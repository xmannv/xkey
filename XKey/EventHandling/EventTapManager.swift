//
//  EventTapManager.swift
//  XKey
//
//  Manages CGEventTap for intercepting keyboard events
//

import Cocoa
import Carbon

class EventTapManager {

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sessionEventTap: CFMachPort?       // Secondary tap for remote desktop input (always-on)
    private var sessionRunLoopSource: CFRunLoopSource?
    private var isEnabled = false
    private var isHIDTapActive = false             // True if primary tap is at HID level
    private var isSuspended = false  // Track suspension state for IMKit mode
    private var isHotkeyRecording = false  // Track if hotkey recording is in progress

    // Session tap creation parameters — populated in start(), consumed by createSessionTapIfNeeded().
    // All access happens on the main thread (start()/stop() are invoked on main).
    private var sessionEventTapCallback: CGEventTapCallBack?
    private var sessionEventTapUserInfo: UnsafeMutableRawPointer?
    private var sessionEventTapMask: CGEventMask = 0
    private var remoteDesktopActivationObserver: NSObjectProtocol?

    /// Token for the block-based hotkey-recording notification observer.
    /// Stored so deinit can remove it explicitly (block observers ignore
    /// `removeObserver(self)`).
    private var hotkeyRecordingObserver: NSObjectProtocol?

    // Bundle IDs of remote desktop apps: see `RemoteDesktopBundleIds.all` in
    // Shared/AppBehaviorDetector.swift (single source of truth).
    
    // Multi-user session tracking
    // When another macOS user session is active (Fast User Switching),
    // the HID-level event tap still fires for the inactive session.
    // This flag prevents intercepting events that belong to other sessions.
    var isSessionOnConsole = true
    var sessionObservers: [Any] = []

    weak var delegate: EventTapDelegate?
    var debugLogCallback: ((String) -> Void)?
    var eventPermissionCheck: (() -> Bool)?
    var onEventTapPermissionLost: (() -> Void)?
    var onHostCommand: ((HostCommand, CGEvent, CGEventTapProxy) -> HostCommandResult)?
    
    // Toggle hotkey configuration
    var toggleHotkey: Hotkey?
    
    // Toolbar hotkey configuration (for temp off toolbar)
    var toolbarHotkey: Hotkey?

    // Convert tool hotkey configuration
    var convertToolHotkey: Hotkey?

    // Undo typing hotkey configuration
    var undoTypingHotkey: Hotkey?
    
    // Translation hotkey configuration
    var translationHotkey: Hotkey?
    
    // Translate to source language hotkey configuration
    var translateToSourceHotkey: Hotkey?
    
    // Debug hotkey configuration
    var debugHotkey: Hotkey?
    
    // Toggle exclusion rules hotkey configuration
    var toggleExclusionHotkey: Hotkey?
    
    // Toggle window title rules hotkey configuration
    var toggleWindowRulesHotkey: Hotkey?
    
    private var modifierOnlyCommandResolver = ModifierOnlyHostCommandResolver()
    
    // MARK: - Method Reprobe Chords

    /// Cmd-chord keycodes that move browser focus into chrome-UI text fields:
    /// L (0x25) / T (0x11) / N (0x2D) → omnibox, F (0x03) / K (0x28) → find or
    /// search field. Only these arm the injection-method reprobe — broader
    /// chords (Cmd+C/V/W/R…) don't move focus there and would only add AX cost
    /// and sample transitional AX states (e.g. tab teardown after Cmd+W).
    static let focusMovingChordKeyCodes: Set<Int64> = [0x25, 0x11, 0x2D, 0x03, 0x28]

    // MARK: - Delegate Protocol

    protocol EventTapDelegate: AnyObject {
        /// Blocks only while a previously queued direct-post injection is still running.
        /// Called at the tap boundary before physical keyDown/flagsChanged events can pass through.
        func waitForPendingInjection()
        func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool
        func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent?
        
        /// Called when the user session becomes active again after a Fast User Switch.
        /// Implementors should reset any stale engine state (word buffer, etc.)
        /// since the buffer may have accumulated phantom data while off-console.
        func sessionDidBecomeActive()
    }
    
    
    // MARK: - Errors
    
    enum EventTapError: Error {
        case creationFailed
        case accessibilityPermissionDenied
        case alreadyRunning
        case notRunning
    }

    enum DisabledTapRecoveryAction: Equatable {
        case reenable
        case stop
    }

    static func disabledTapRecoveryAction(
        hasEventPermission: Bool
    ) -> DisabledTapRecoveryAction {
        hasEventPermission ? .reenable : .stop
    }
    
    // MARK: - Initialization
    
    init() {
        // Observe hotkey recording state to suspend hotkey processing.
        // Block-based observer returns a token that MUST be stored for later removal —
        // NotificationCenter.removeObserver(self) only removes selector-based observers.
        hotkeyRecordingObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isRecording = notification.userInfo?["isRecording"] as? Bool {
                self?.isHotkeyRecording = isRecording
                self?.debugLogCallback?("🎹 Hotkey recording: \(isRecording ? "STARTED" : "STOPPED")")
            }
        }

        // Setup multi-user session monitoring
        setupSessionMonitoring()
    }

    deinit {
        removeSessionMonitoring()
        if let obs = hotkeyRecordingObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        stop()
    }
    
    // MARK: - Public Methods
    
    func start() throws {
        guard !isEnabled else {
            throw EventTapError.alreadyRunning
        }

        // Check accessibility permission
        guard hasEventTapPermission() else {
            debugLogCallback?("No accessibility permission")
            throw EventTapError.accessibilityPermissionDenied
        }
        debugLogCallback?("Accessibility permission OK")

        // Create event mask for keyboard events
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        debugLogCallback?("Event mask: \(eventMask)")
        
        // HID tap callback - marks events before passing through
        let hidCallback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

            // Call event callback with proxy and handle nil (consume event)
            if let result = manager.eventCallback(proxy: proxy, type: type, event: event) {
                return result
            } else {
                // Return nil to consume the event
                return nil
            }
        }
        
        // Session tap callback - processes events NOT seen by HID tap (remote desktop input)
        let sessionCallback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

            if let result = manager.sessionEventCallback(proxy: proxy, type: type, event: event) {
                return result
            } else {
                return nil
            }
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        // Create event tap - try HID level first, fallback to session
        // HID level intercepts events BEFORE session level, providing better timing
        // and avoiding keystroke "swallowing" issues in terminals
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hidCallback,
            userInfo: userInfo
        )
        
        if tap != nil {
            isHIDTapActive = true
            debugLogCallback?("Event tap created at HID level")
        } else {
            // Fallback to session level (no dual tap needed in this case)
            isHIDTapActive = false
            debugLogCallback?("HID tap failed, trying session level...")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: hidCallback,
                userInfo: userInfo
            )
            if tap != nil {
                debugLogCallback?("Event tap created at session level")
            }
        }
        
        guard let tap = tap else {
            debugLogCallback?("Failed to create event tap!")
            throw EventTapError.creationFailed
        }
        
        eventTap = tap

        // Create run loop source for primary tap
        debugLogCallback?("Creating run loop source...")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            debugLogCallback?("Failed to create run loop source")
            eventTap = nil
            throw EventTapError.creationFailed
        }

        // Add to current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // Enable the primary event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLogCallback?("Primary event tap enabled")

        // DUAL TAP: session-level tap captures keyboard events from remote desktop daemons
        // that bypass the HID-level tap.
        //
        // Two modes:
        // - isRemoteDesktopTarget=true (machine B being remoted into): always-on tailAppend.
        //   Daemon events arrive at session level; tap stays active regardless of frontmost app.
        // - isRemoteDesktopTarget=false (default, machine A): lazy — tap created only while
        //   a remote desktop client is frontmost, destroyed on app switch. Prevents timing
        //   interference with Chromium apps (Notion code block, Kiro CLI) during local use.
        sessionEventTapCallback = sessionCallback
        sessionEventTapUserInfo = userInfo
        sessionEventTapMask = eventMask
        if SharedSettings.shared.isRemoteDesktopTarget {
            createSessionTapIfNeeded()
        } else {
            setupRemoteDesktopActivationHook()
            updateSessionTapForFrontmostApp()
        }

        isEnabled = true
        debugLogCallback?("Event tap fully started!")
    }

    func stop() {
        guard isEnabled else { return }

        // Stop primary tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        // Stop session tap
        destroySessionTapIfExists()
        removeRemoteDesktopActivationHook()

        // Clear cached session tap creation params
        sessionEventTapCallback = nil
        sessionEventTapUserInfo = nil
        sessionEventTapMask = 0

        isHIDTapActive = false
        isEnabled = false

        debugLogCallback?("Event tap stopped")
    }
    
    func restart() throws {
        stop()
        try start()
    }

    /// Suspend event tap temporarily (for IMKit mode)
    func suspend() {
        guard isEnabled else { return }

        isSuspended = true
        debugLogCallback?("Event tap suspended (IMKit active)")
    }

    func suspendAndDrainPendingInjection() {
        suspend()
        delegate?.waitForPendingInjection()
    }

    /// Resume event tap (when leaving IMKit mode)
    func resume() {
        guard isEnabled else { return }

        isSuspended = false
        debugLogCallback?("Event tap resumed (IMKit inactive)")
    }

    // MARK: - Event Callback

    private func routeHostCommand(_ command: HostCommand,
                                  event: CGEvent,
                                  proxy: CGEventTapProxy) -> HostCommandResult {
        guard let onHostCommand else {
            debugLogCallback?("Host command unavailable: \(command.rawValue)")
            return .unavailable
        }
        return onHostCommand(command, event, proxy)
    }

    private func additionalHostCommand(for event: CGEvent) -> HostCommand? {
        let eventModifiers = ModifierFlags(from: event.flags)
        let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
        let bindings: [(Hotkey?, HostCommand, Bool)] = [
            (toolbarHotkey, .showToolbar, true),
            (convertToolHotkey, .showConvertTool, true),
            (translationHotkey, .showTranslation, false),
            (translateToSourceHotkey, .translateToSource, false),
            (debugHotkey, .showDebugWindow, false),
            (toggleExclusionHotkey, .toggleExclusionRules, false),
            (toggleWindowRulesHotkey, .toggleWindowTitleRules, false),
            (undoTypingHotkey, .undoTyping, false),
        ]
        for (hotkey, command, requiresExactModifiers) in bindings {
            guard let hotkey, !hotkey.isModifierOnly else { continue }
            let modifiers = requiresExactModifiers ? eventModifiers : relevantModifiers
            if event.keyCode == hotkey.keyCode, modifiers == hotkey.modifiers {
                return command
            }
        }
        return nil
    }

    private func modifierOnlyHostCommandBindings() -> [(hotkey: Hotkey, command: HostCommand)] {
        var bindings: [(hotkey: Hotkey, command: HostCommand)] = []
        if let toggleHotkey, toggleHotkey.isModifierOnly {
            bindings.append((toggleHotkey, .toggleVietnamese))
        }
        if !isHotkeyRecording,
           let undoTypingHotkey,
           undoTypingHotkey.isModifierOnly {
            bindings.append((undoTypingHotkey, .undoTyping))
        }
        return bindings
    }

    private func routeModifierOnlyHostCommand(
        type: CGEventType,
        event: CGEvent,
        proxy: CGEventTapProxy
    ) {
        if type == .flagsChanged {
            if let command = modifierOnlyCommandResolver.update(
                modifiers: ModifierFlags(from: event.flags),
                bindings: modifierOnlyHostCommandBindings()
            ) {
                _ = routeHostCommand(command, event: event, proxy: proxy)
            }
        } else if type == .keyDown {
            modifierOnlyCommandResolver.cancel()
        }
    }
    
    private func eventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events before session state. A timeout is recoverable, but
        // a revoked permission must fail open: repeatedly re-enabling a no-longer-authorized
        // tap can block physical input until this process exits.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            switch Self.disabledTapRecoveryAction(hasEventPermission: hasEventTapPermission()) {
            case .reenable:
                if let tap = eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            case .stop:
                if let tap = eventTap {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.stop()
                    self.onEventTapPermissionLost?()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // CRITICAL: Multi-user session guard
        // When another macOS user is active via Fast User Switching,
        // the HID-level event tap still receives their keystrokes.
        // We must pass them through untouched to avoid:
        // - Consuming/swallowing keystrokes meant for the other user
        // - XKey hotkeys firing in the wrong session
        // - Vietnamese processing injecting text into our (inactive) session
        if !isSessionOnConsole {
            return Unmanaged.passUnretained(event)
        }
        
        // IMPORTANT: If suspended (IMKit mode active), pass ALL events through
        // This allows IMKit to receive and handle keyboard events
        if isSuspended {
            return Unmanaged.passUnretained(event)
        }

        // CRITICAL: Skip events injected by XKey itself
        // This prevents re-processing of backspaces/text we inject, which causes
        // race conditions and duplicate diacritics in terminal apps
        if event.getIntegerValueField(.eventSourceUserData) == kXKeyEventMarker {
            return Unmanaged.passUnretained(event)
        }

        // DUAL TAP: Mark this event as seen by HID tap
        // The session tap checks for this marker to avoid double-processing.
        // Events from remote desktop never pass through HID tap, so they won't have this marker
        // and will be processed by the session tap instead.
        // Only mark when dual tap is active (HID primary + session secondary)
        if isHIDTapActive {
            event.setIntegerValueField(.eventSourceUserData, value: kXKeyHIDSeenMarker)
        }

        // Preserve ordering with queued slow direct-post injection before any physical
        // keyDown/modifier event can trigger a shortcut, change focus, or insert text.
        // Keep keyUp on its existing zero-delay path for spring-loaded Adobe tools.
        if type != .keyUp {
            delegate?.waitForPendingInjection()
        }

        // CRITICAL FIX: Pass through keyUp events IMMEDIATELY with zero delay
        // This fixes spring-loaded tools in Adobe apps (Illustrator, Photoshop, etc.)
        // where holding Z/Space temporarily activates Zoom/Hand tool.
        // These apps require precise keyUp timing to release the tool.
        // On low-RAM systems, the processing delay through multiple checks below
        // can cause keyUp to arrive too late, leaving mouse in drag state.
        // Since XKey only processes keyDown for Vietnamese input, keyUp can bypass safely.
        if type == .keyUp {
            return Unmanaged.passUnretained(event)
        }

        // CRITICAL FIX: Pass through key repeat events IMMEDIATELY
        // Key repeat events occur when user holds a key (spring-loaded tools in Adobe apps)
        // These must bypass ALL checks (hotkeys, delegate) to avoid any delay
        // Only the first keyDown needs processing for Vietnamese input
        //
        // EXCEPTION: Backspace repeat MUST reach delegate for engine buffer sync!
        // When user holds Backspace, each repeat deletes a character on screen.
        // The engine must process each deletion to keep its buffer synchronized,
        // otherwise Vietnamese input (e.g., Telex ] and [ keys) breaks after hold-backspace.
        if type == .keyDown && event.isKeyRepeat {
            if event.keyCode != VietnameseData.KEY_DELETE {
                return Unmanaged.passUnretained(event)
            }
            // Fall through for backspace repeat - delegate needs to process each deletion
        }

        debugLogCallback?("EventTapManager.eventCallback: type=\(type.rawValue), delegate=\(delegate != nil)")
        routeModifierOnlyHostCommand(type: type, event: event, proxy: proxy)

        // Check for toggle hotkey FIRST (before delegate processing)
        // This ensures the hotkey is consumed and doesn't reach other apps
        if let hotkey = toggleHotkey, !hotkey.isModifierOnly, type == .keyDown {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?(" → TOGGLE HOTKEY DETECTED")
                let result = routeHostCommand(.toggleVietnamese, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }
        
        // Check for toolbar hotkey (for temp off toolbar)
        // Skip if user is recording a new hotkey (so they can re-record the same hotkey)
        if let hotkey = toolbarHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOOLBAR HOTKEY DETECTED")
                let result = routeHostCommand(.showToolbar, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for convert tool hotkey
        // Skip if user is recording a new hotkey (so they can re-record the same hotkey)
        if let hotkey = convertToolHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?("  → CONVERT TOOL HOTKEY DETECTED")
                let result = routeHostCommand(.showConvertTool, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for translation hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = translationHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TRANSLATION HOTKEY DETECTED (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                let result = routeHostCommand(.showTranslation, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for translate-to-source hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = translateToSourceHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TRANSLATE-TO-SOURCE HOTKEY DETECTED (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                let result = routeHostCommand(.translateToSource, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for debug hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = debugHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → DEBUG HOTKEY DETECTED (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                let result = routeHostCommand(.showDebugWindow, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for toggle exclusion rules hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = toggleExclusionHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOGGLE EXCLUSION HOTKEY DETECTED (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                let result = routeHostCommand(.toggleExclusionRules, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for toggle window title rules hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = toggleWindowRulesHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOGGLE WINDOW RULES HOTKEY DETECTED (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                let result = routeHostCommand(.toggleWindowTitleRules, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        // Check for undo typing hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = undoTypingHotkey, !isHotkeyRecording, !hotkey.isModifierOnly {
                // Handle regular undo hotkey (e.g., Esc or any key+modifiers)
                if type == .keyDown {
                    let eventModifiers = ModifierFlags(from: event.flags)
                    // For Esc key (keyCode 0x35), modifiers should be empty
                    // For other keys, check both keyCode and modifiers
                    let modifiersMatch = hotkey.modifiers.isEmpty ? 
                        eventModifiers.intersection([.control, .shift, .option, .command]).isEmpty :
                        eventModifiers == hotkey.modifiers
                    
                    if event.keyCode == hotkey.keyCode && modifiersMatch {
                        debugLogCallback?(" → UNDO TYPING HOTKEY DETECTED: \(hotkey.displayString)")
                        let result = routeHostCommand(.undoTyping, event: event, proxy: proxy)
                        if result.shouldConsumeEvent {
                            debugLogCallback?(" → Undo performed - consuming event")
                            return nil  // Consume the event
                        }
                        debugLogCallback?(" → Nothing to undo - pass through")
                        // Fall through to delegate processing
                    }
                }
        }

        // MARK: Overlay Probe Arming
        // Arm overlay detection probe when events suggest overlay state may change.
        // This runs BEFORE delegate processing so the probe is ready for
        // isOverlayAppVisible() calls within KeyboardEventHandler.
        if type == .flagsChanged {
            // Modifier key changed — potential overlay open (Cmd+Space etc.)
            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskControl) ||
               flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
                OverlayAppDetector.shared.armProbe()
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 0x35 || keyCode == 0x24 || keyCode == 0x4C { // Esc, Return, or Keypad Enter — potential overlay close
                // Deferred: CGEventTap fires BEFORE the app processes the key,
                // so immediate probe would still see overlay as focused.
                OverlayAppDetector.shared.armProbeDeferred()
            } else if event.flags.contains(.maskCommand) {
                // keyDown with Cmd — potential overlay shortcut (Cmd+Space, Cmd+K, etc.)
                OverlayAppDetector.shared.armProbe()
                // Focus-moving chords (Cmd+L/T/N/F/K) can land focus in a
                // browser address bar before async detection — arm a one-shot
                // injection-method reprobe for the next plain keystroke.
                if EventTapManager.focusMovingChordKeyCodes.contains(keyCode) {
                    AppBehaviorDetector.shared.armMethodReprobe()
                }
            }
        }

        // Check if delegate wants to process this event
        guard let delegate = delegate else {
            debugLogCallback?(" → No delegate!")
            return Unmanaged.passUnretained(event)
        }

        debugLogCallback?(" → Calling shouldProcessEvent...")
        guard delegate.shouldProcessEvent(event, type: type) else {
            debugLogCallback?(" → shouldProcessEvent returned false")
            return Unmanaged.passUnretained(event)
        }

        debugLogCallback?(" → Calling processKeyEvent...")
        // Process event through delegate with proxy
        if let processedEvent = delegate.processKeyEvent(event, type: type, proxy: proxy) {
            return Unmanaged.passUnretained(processedEvent)
        }

        // Consume event by returning nil
        return nil
    }
    
    // MARK: - Session Event Callback (Dual Tap - Remote Desktop Input)
    
    /// Secondary event callback for session-level tap.
    /// Only processes events NOT seen by the HID tap (i.e., events from remote desktop connections).
    /// This enables Vietnamese input when the machine is being remoted into.
    private func sessionEventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled event - re-enable session tap
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let sTap = sessionEventTap {
                CGEvent.tapEnable(tap: sTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Multi-user session guard (same as HID tap)
        if !isSessionOnConsole {
            return Unmanaged.passUnretained(event)
        }
        
        // If suspended (IMKit mode), pass through
        if isSuspended {
            return Unmanaged.passUnretained(event)
        }
        
        // Skip events injected by XKey itself
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == kXKeyEventMarker {
            return Unmanaged.passUnretained(event)
        }
        
        // CRITICAL: Skip events already seen by HID tap (deduplication)
        // Local keyboard events pass through HID tap first and get marked.
        // Only events from remote desktop (virtual input) lack this marker.
        if userData == kXKeyHIDSeenMarker {
            // Restore clean state before passing to downstream apps/utilities
            // This prevents kXKeyHIDSeenMarker from leaking to other keyboard tools
            event.setIntegerValueField(.eventSourceUserData, value: 0)
            return Unmanaged.passUnretained(event)
        }

        // Remote physical input bypasses the HID tap, so apply the same ordering barrier
        // here. XKey-injected events were filtered above and cannot wait on themselves.
        if type != .keyUp {
            delegate?.waitForPendingInjection()
        }
        
        // --- From here, we're processing a remote desktop event ---
        debugLogCallback?("[SessionTap] Processing remote desktop event: type=\(type.rawValue), keyCode=\(event.getIntegerValueField(.keyboardEventKeycode))")
        
        // Pass through keyUp events (XKey only processes keyDown)
        if type == .keyUp {
            return Unmanaged.passUnretained(event)
        }
        
        // Pass through key repeat (except backspace for buffer sync)
        if type == .keyDown && event.isKeyRepeat {
            if event.keyCode != VietnameseData.KEY_DELETE {
                return Unmanaged.passUnretained(event)
            }
        }
        routeModifierOnlyHostCommand(type: type, event: event, proxy: proxy)
        
        // Check for toggle hotkey (allow remote users to toggle Vietnamese)
        if let hotkey = toggleHotkey, !hotkey.isModifierOnly, type == .keyDown {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                let result = routeHostCommand(.toggleVietnamese, event: event, proxy: proxy)
                return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
            }
        }

        if type == .keyDown,
           !isHotkeyRecording,
           let command = additionalHostCommand(for: event) {
            let result = routeHostCommand(command, event: event, proxy: proxy)
            if result.shouldConsumeEvent { return nil }
            if command != .undoTyping {
                return Unmanaged.passUnretained(event)
                }
        }
        
        // Overlay probe arming (same as HID tap)
        if type == .flagsChanged {
            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskControl) ||
               flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
                OverlayAppDetector.shared.armProbe()
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 0x35 || keyCode == 0x24 || keyCode == 0x4C {
                OverlayAppDetector.shared.armProbeDeferred()
            } else if event.flags.contains(.maskCommand) {
                OverlayAppDetector.shared.armProbe()
                if EventTapManager.focusMovingChordKeyCodes.contains(keyCode) {
                    AppBehaviorDetector.shared.armMethodReprobe()
                }
            }
        }

        // Delegate processing (Vietnamese input engine)
        guard let delegate = delegate else {
            return Unmanaged.passUnretained(event)
        }
        
        guard delegate.shouldProcessEvent(event, type: type) else {
            return Unmanaged.passUnretained(event)
        }
        
        if let processedEvent = delegate.processKeyEvent(event, type: type, proxy: proxy) {
            return Unmanaged.passUnretained(processedEvent)
        }
        
        // Consume event
        return nil
    }
    
    // MARK: - Permission Check

    private func hasEventTapPermission() -> Bool {
        eventPermissionCheck?() ?? checkAccessibilityPermission()
    }
    
    func checkAccessibilityPermission() -> Bool {
        // Don't prompt - just check silently
        // We handle our own permission UI in AppDelegate
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermission() {
        // This function is kept for compatibility but we don't use it
        // We handle permission requests through our custom dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Status
    
    var isRunning: Bool {
        return isEnabled
    }
    
    // MARK: - Multi-User Session Monitoring
    
    /// Setup observers for macOS Fast User Switching (multi-user sessions).
    ///
    /// Problem: When XKey uses `.cghidEventTap` (HID level), the event tap intercepts
    /// ALL keyboard events system-wide, including those from other user sessions.
    /// This causes XKey to "steal" keystrokes from other users and inject Vietnamese
    /// text into the wrong session.
    ///
    /// Solution: Listen for session activation/deactivation notifications and set a cached
    /// flag that the event callback checks (O(1) boolean comparison) before processing.
    /// Both reads (event callback) and writes (notification handlers) occur on the main
    /// thread, so no synchronization is needed.
    private func setupSessionMonitoring() {
        // Check initial session state
        isSessionOnConsole = checkSessionOnConsole()
        debugLogCallback?("🖥️ Initial session state: \(isSessionOnConsole ? "on-console" : "off-console")")
        
        // Listen for session deactivation (user switches AWAY from this session)
        let resignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isSessionOnConsole = false
            self.debugLogCallback?("🖥️ Session resigned active — event tap passthrough enabled (multi-user switch)")
        }
        sessionObservers.append(resignObserver)
        
        // Listen for session activation (user switches BACK to this session)
        let becomeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isSessionOnConsole = true
            self.debugLogCallback?("🖥️ Session became active — event tap processing resumed")
            
            // Reset engine state when returning to this session.
            // The engine buffer may be stale (accumulated ghost keystrokes while
            // events passed through another user's session).
            // Notifying the delegate ensures a clean slate for Vietnamese input.
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.sessionDidBecomeActive()
            }
        }
        sessionObservers.append(becomeObserver)
    }
    
    /// Remove session monitoring observers
    private func removeSessionMonitoring() {
        for observer in sessionObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        sessionObservers.removeAll()
    }

    // MARK: - Session Tap (Remote Desktop)
    //
    // The session-level event tap captures keyboard events injected at session level
    // by remote desktop server daemons (RustDesk, Jump Desktop, TeamViewer, etc.).
    // These events bypass the HID-level primary tap and are only visible here.
    // Local keyboard events reach both taps; the HIDSeenMarker deduplicates them.
    //
    // Two activation strategies (controlled by isRemoteDesktopTarget preference):
    // - Remote target mode (machine B): always-on at .tailAppendEventTap
    // - Default mode (machine A): lazy, only while remote desktop client is frontmost

    /// Register NSWorkspace observer for frontmost-app-based lazy session tap activation.
    /// Used in default mode (isRemoteDesktopTarget=false). Not called when remote target mode is on.
    private func setupRemoteDesktopActivationHook() {
        let center = NSWorkspace.shared.notificationCenter
        remoteDesktopActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateSessionTapForFrontmostApp()
        }
    }

    /// Tear down NSWorkspace observer.
    private func removeRemoteDesktopActivationHook() {
        if let obs = remoteDesktopActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            remoteDesktopActivationObserver = nil
        }
    }

    /// Reconcile session tap state based on frontmost app.
    /// Called on app-activation events and once at startup. Main thread only.
    private func updateSessionTapForFrontmostApp() {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        let isRemote = RemoteDesktopBundleIds.all.contains(bundleId)
        if isRemote {
            createSessionTapIfNeeded()
        } else {
            destroySessionTapIfExists()
        }
    }

    /// Install the session-level secondary tap (if not already installed).
    /// Only meaningful when the primary tap is at HID level.
    /// Must be called on the main thread.
    private func createSessionTapIfNeeded() {
        guard isHIDTapActive else { return }
        guard sessionEventTap == nil else { return }
        guard let callback = sessionEventTapCallback,
              let userInfo = sessionEventTapUserInfo else { return }

        guard let sTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: sessionEventTapMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            debugLogCallback?("⚠️ Session tap creation failed")
            return
        }

        guard let runLoop = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, sTap, 0) else {
            // Run loop source creation failed — invalidate the orphaned tap so it doesn't leak
            debugLogCallback?("⚠️ Session tap run loop source creation failed")
            CFMachPortInvalidate(sTap)
            return
        }

        sessionEventTap = sTap
        sessionRunLoopSource = runLoop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoop, .commonModes)
        CGEvent.tapEnable(tap: sTap, enable: true)
        debugLogCallback?("🌐 Session tap created (always-on, tailAppend)")
    }

    /// Tear down the session-level secondary tap if installed.
    /// Idempotent: safe to call multiple times. Must be invoked on the main thread.
    private func destroySessionTapIfExists() {
        guard sessionEventTap != nil || sessionRunLoopSource != nil else { return }

        if let sSource = sessionRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), sSource, .commonModes)
            sessionRunLoopSource = nil
        }
        if let sTap = sessionEventTap {
            CGEvent.tapEnable(tap: sTap, enable: false)
            CFMachPortInvalidate(sTap)
            sessionEventTap = nil
        }
        debugLogCallback?("🌐 Session tap destroyed")
    }
    
    /// Check if current session is the active console session
    /// (only called once at init, not on every keystroke)
    private func checkSessionOnConsole() -> Bool {
        guard let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            // Can't determine session state — assume on-console (safe default for single-user)
            return true
        }
        // kCGSessionOnConsoleKey indicates if this session owns the console
        return sessionDict[kCGSessionOnConsoleKey as String] as? Bool ?? true
    }
}

// MARK: - Default Delegate Implementations

extension EventTapManager.EventTapDelegate {
    /// Default no-op for delegates without asynchronous injection.
    func waitForPendingInjection() {}

    /// Default no-op: conformers only override if they need session-aware reset
    func sessionDidBecomeActive() {}
}

// MARK: - ModifierFlags Helper

extension ModifierFlags {
    init(from cgFlags: CGEventFlags) {
        var flags = ModifierFlags()
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskSecondaryFn) { flags.insert(.function) }
        self = flags
    }
    
    /// Check if this set is a subset of another set
    func isSubset(of other: ModifierFlags) -> Bool {
        return self.intersection(other) == self
    }
}

// MARK: - Event Helper Extensions

extension CGEvent {
    
    /// Get the character from keyboard event
    var characters: String? {
        guard let nsEvent = NSEvent(cgEvent: self) else {
            return nil
        }
        return nsEvent.characters
    }
    
    /// Get the character ignoring modifiers
    var charactersIgnoringModifiers: String? {
        guard let nsEvent = NSEvent(cgEvent: self) else {
            return nil
        }
        return nsEvent.charactersIgnoringModifiers
    }
    
    /// Get the key code
    var keyCode: UInt16 {
        return UInt16(getIntegerValueField(.keyboardEventKeycode))
    }
    
    /// Check if Shift key is pressed
    var isShiftPressed: Bool {
        return flags.contains(.maskShift)
    }
    
    /// Check if Command key is pressed
    var isCommandPressed: Bool {
        return flags.contains(.maskCommand)
    }
    
    /// Check if Control key is pressed
    var isControlPressed: Bool {
        return flags.contains(.maskControl)
    }
    
    /// Check if Option/Alt key is pressed
    var isOptionPressed: Bool {
        return flags.contains(.maskAlternate)
    }
    
    /// Check if Caps Lock is on
    var isCapsLockOn: Bool {
        return flags.contains(.maskAlphaShift)
    }
    
    /// Check if any modifier key is pressed (except Shift and Caps Lock)
    var hasOtherModifiers: Bool {
        return isCommandPressed || isControlPressed || isOptionPressed
    }

    /// Check if this is a key repeat event (key being held down)
    /// Key repeat events occur when user holds a key - used for shortcuts like holding Z for Zoom in Adobe apps
    /// Returns true if this keyDown is an auto-repeat, false for initial key press
    var isKeyRepeat: Bool {
        return getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}
