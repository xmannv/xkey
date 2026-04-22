//
//  EventTapManager.swift
//  XKey
//
//  Manages CGEventTap for intercepting keyboard events
//

import Cocoa
import Carbon
import IOKit

class EventTapManager {

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = false
    private var isSuspended = false  // Track suspension state for IMKit mode
    private var isHotkeyRecording = false  // Track if hotkey recording is in progress
    
    // Multi-user session tracking
    // When another macOS user session is active (Fast User Switching),
    // the HID-level event tap still fires for the inactive session.
    // This flag prevents intercepting events that belong to other sessions.
    var isSessionOnConsole = true
    var sessionObservers: [Any] = []

    weak var delegate: EventTapDelegate?
    var debugLogCallback: ((String) -> Void)?
    
    // Toggle hotkey configuration
    var toggleHotkey: Hotkey?
    var onToggleHotkey: (() -> Void)?
    
    // Toolbar hotkey configuration (for temp off toolbar)
    var toolbarHotkey: Hotkey?
    var onToolbarHotkey: (() -> Void)?

    // Convert tool hotkey configuration
    var convertToolHotkey: Hotkey?
    var onConvertToolHotkey: (() -> Void)?

    // Undo typing hotkey configuration
    // Returns true if event should be consumed (undo was performed)
    var undoTypingHotkey: Hotkey?
    var onUndoTypingHotkey: (() -> Bool)?
    
    // Translation hotkey configuration
    var translationHotkey: Hotkey?
    var onTranslationHotkey: (() -> Void)?
    
    // Translate to source language hotkey configuration
    var translateToSourceHotkey: Hotkey?
    var onTranslateToSourceHotkey: (() -> Void)?
    
    // Debug hotkey configuration
    var debugHotkey: Hotkey?
    var onDebugHotkey: (() -> Void)?
    
    // Toggle exclusion rules hotkey configuration
    var toggleExclusionHotkey: Hotkey?
    var onToggleExclusionHotkey: (() -> Void)?
    
    // Toggle window title rules hotkey configuration
    var toggleWindowRulesHotkey: Hotkey?
    var onToggleWindowRulesHotkey: (() -> Void)?
    
    // Modifier-only hotkey tracking (for toggle hotkey)
    private var modifierOnlyState: ModifierOnlyState = ModifierOnlyState()
    
    // Modifier-only hotkey tracking (for undo typing hotkey)
    private var undoModifierOnlyState: ModifierOnlyState = ModifierOnlyState()
    
    private struct ModifierOnlyState {
        var currentModifiers: ModifierFlags = []
        var targetModifiersReached: Bool = false  // True when all required modifiers were pressed
        var hasTriggered: Bool = false
    }
    
    // MARK: - Delegate Protocol

    protocol EventTapDelegate: AnyObject {
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
    
    // MARK: - Initialization
    
    init() {
        // Observe hotkey recording state to suspend hotkey processing
        NotificationCenter.default.addObserver(
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
        NotificationCenter.default.removeObserver(self)
        stop()
    }
    
    // MARK: - Public Methods
    
    func start() throws {
        guard !isEnabled else {
            throw EventTapError.alreadyRunning
        }

        // Check accessibility permission
        guard checkAccessibilityPermission() else {
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
        
        // Callback closure for event tap
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
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
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        // Create event tap - try HID level first, fallback to session
        // HID level intercepts events BEFORE session level, providing better timing
        // and avoiding keystroke "swallowing" issues in terminals
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        )
        
        if tap != nil {
            debugLogCallback?("Event tap created at HID level")
        } else {
            // Fallback to session level
            debugLogCallback?("HID tap failed, trying session level...")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
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

        // Create run loop source
        debugLogCallback?("Creating run loop source...")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            debugLogCallback?("Failed to create run loop source")
            eventTap = nil
            throw EventTapError.creationFailed
        }

        // Add to current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // Enable the event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLogCallback?("Event tap enabled")

        isEnabled = true
        debugLogCallback?("Event tap fully started!")
    }

    func stop() {
        guard isEnabled else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            // CFRelease not needed in modern Swift - ARC handles it
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            // CFRelease not needed in modern Swift - ARC handles it
            runLoopSource = nil
        }
        
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

    /// Resume event tap (when leaving IMKit mode)
    func resume() {
        guard isEnabled else { return }

        isSuspended = false
        debugLogCallback?("Event tap resumed (IMKit inactive)")
    }

    // MARK: - Event Callback
    
    private func eventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap disabled event FIRST — unconditionally, regardless of session state.
        // If the system auto-disables our tap (timeout/user input), we must re-enable it
        // even when off-console, otherwise XKey will stop working when the user returns.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
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
            debugLogCallback?(" → Skipping XKey-injected event (marker detected)")
            // Also print directly for debugging
            debugLogCallback?("MARKER SKIP: type=\(type.rawValue), keyCode=\(event.getIntegerValueField(.keyboardEventKeycode))")
            return Unmanaged.passUnretained(event)
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

        // Check for toggle hotkey FIRST (before delegate processing)
        // This ensures the hotkey is consumed and doesn't reach other apps
        if let hotkey = toggleHotkey {
            // Handle modifier-only hotkey (e.g., Ctrl+Shift)
            if hotkey.isModifierOnly {
                if type == .flagsChanged {
                    let eventModifiers = ModifierFlags(from: event.flags)
                    
                    debugLogCallback?(" → flagsChanged: eventModifiers=\(eventModifiers.rawValue), hotkey.modifiers=\(hotkey.modifiers.rawValue)")
                    
                    // Check if all required modifiers are currently pressed
                    // Use "contains" to allow for additional modifiers like CapsLock
                    // Include .function for Fn key support
                    let hasAllRequiredModifiers = hotkey.modifiers.isSubset(of: eventModifiers) &&
                                                   eventModifiers.intersection([.control, .shift, .option, .command, .function]) == hotkey.modifiers
                    
                    if hasAllRequiredModifiers {
                        // All required modifiers are pressed
                        if !modifierOnlyState.targetModifiersReached {
                            modifierOnlyState.targetModifiersReached = true
                            modifierOnlyState.hasTriggered = false
                            debugLogCallback?(" → Target modifiers REACHED: \(hotkey.displayString)")
                        }
                        modifierOnlyState.currentModifiers = eventModifiers
                    } else {
                        // Modifiers changed
                        if modifierOnlyState.targetModifiersReached && !modifierOnlyState.hasTriggered {
                            // Was holding target modifiers, now released - TRIGGER!
                            modifierOnlyState.hasTriggered = true
                            debugLogCallback?(" → MODIFIER-ONLY HOTKEY TRIGGERED on release: \(hotkey.displayString)")
                            DispatchQueue.main.async { [weak self] in
                                self?.onToggleHotkey?()
                            }
                        }
                        // Reset state
                        modifierOnlyState.targetModifiersReached = false
                        modifierOnlyState.currentModifiers = eventModifiers
                    }
                } else if type == .keyDown {
                    // If user presses any key while holding modifiers, cancel the modifier-only hotkey
                    if modifierOnlyState.targetModifiersReached {
                        debugLogCallback?(" → Key pressed while holding modifiers - canceling modifier-only hotkey")
                        modifierOnlyState.targetModifiersReached = false
                        modifierOnlyState.hasTriggered = true  // Prevent trigger on release
                    }
                }
                // Don't consume flagsChanged events - let them pass through
            } else {
                // Handle regular hotkey (e.g., Cmd+Shift+V)
                if type == .keyDown {
                    let eventModifiers = ModifierFlags(from: event.flags)
                    if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                        debugLogCallback?(" → TOGGLE HOTKEY DETECTED - consuming event")
                        // Call toggle callback on main thread
                        DispatchQueue.main.async { [weak self] in
                            self?.onToggleHotkey?()
                        }
                        // Consume the event completely - don't pass to other apps
                        return nil
                    }
                }
            }
        }
        
        // Check for toolbar hotkey (for temp off toolbar)
        // Skip if user is recording a new hotkey (so they can re-record the same hotkey)
        if let hotkey = toolbarHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOOLBAR HOTKEY DETECTED - consuming event")
                // Call toolbar callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onToolbarHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check for convert tool hotkey
        // Skip if user is recording a new hotkey (so they can re-record the same hotkey)
        if let hotkey = convertToolHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?("  → CONVERT TOOL HOTKEY DETECTED - consuming event")
                // Call convert tool callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onConvertToolHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check for translation hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = translationHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TRANSLATION HOTKEY DETECTED - consuming event (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                // Call translation callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onTranslationHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check for translate-to-source hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = translateToSourceHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TRANSLATE-TO-SOURCE HOTKEY DETECTED - consuming event (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                // Call callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onTranslateToSourceHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check for debug hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = debugHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            // Compare only relevant modifiers (ignore CapsLock etc.)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → DEBUG HOTKEY DETECTED - consuming event (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                // Call debug callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onDebugHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check for toggle exclusion rules hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = toggleExclusionHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOGGLE EXCLUSION HOTKEY DETECTED - consuming event (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                DispatchQueue.main.async { [weak self] in
                    self?.onToggleExclusionHotkey?()
                }
                return nil
            }
        }

        // Check for toggle window title rules hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = toggleWindowRulesHotkey, type == .keyDown, !isHotkeyRecording {
            let eventModifiers = ModifierFlags(from: event.flags)
            let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
            if event.keyCode == hotkey.keyCode && relevantModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOGGLE WINDOW RULES HOTKEY DETECTED - consuming event (keyCode=\(event.keyCode), mods=\(relevantModifiers.rawValue))")
                DispatchQueue.main.async { [weak self] in
                    self?.onToggleWindowRulesHotkey?()
                }
                return nil
            }
        }

        // Check for undo typing hotkey
        // Skip if user is recording a new hotkey
        if let hotkey = undoTypingHotkey, !isHotkeyRecording {
            if hotkey.isModifierOnly {
                // Handle modifier-only undo hotkey (e.g., Ctrl+Shift)
                if type == .flagsChanged {
                    let eventModifiers = ModifierFlags(from: event.flags)
                    
                    // Check if all required modifiers are currently pressed
                    let hasAllRequiredModifiers = hotkey.modifiers.isSubset(of: eventModifiers) &&
                                                   eventModifiers.intersection([.control, .shift, .option, .command, .function]) == hotkey.modifiers
                    
                    if hasAllRequiredModifiers {
                        // All required modifiers are pressed
                        if !undoModifierOnlyState.targetModifiersReached {
                            undoModifierOnlyState.targetModifiersReached = true
                            undoModifierOnlyState.hasTriggered = false
                            debugLogCallback?(" → Undo target modifiers REACHED: \(hotkey.displayString)")
                        }
                        undoModifierOnlyState.currentModifiers = eventModifiers
                    } else {
                        // Modifiers changed (released)
                        if undoModifierOnlyState.targetModifiersReached && !undoModifierOnlyState.hasTriggered {
                            // Was holding target modifiers, now released - TRIGGER!
                            debugLogCallback?(" → UNDO MODIFIER-ONLY HOTKEY TRIGGERED on release: \(hotkey.displayString)")
                            // Call callback synchronously and check result
                            if let callback = onUndoTypingHotkey, callback() {
                                undoModifierOnlyState.hasTriggered = true
                                debugLogCallback?(" → Undo performed successfully")
                            } else {
                                debugLogCallback?(" → Nothing to undo, pass through")
                            }
                        }
                        // Reset state
                        undoModifierOnlyState.targetModifiersReached = false
                        undoModifierOnlyState.currentModifiers = eventModifiers
                    }
                } else if type == .keyDown {
                    // If user presses any key while holding modifiers, cancel the modifier-only hotkey
                    if undoModifierOnlyState.targetModifiersReached {
                        debugLogCallback?(" → Key pressed while holding modifiers - canceling undo modifier-only hotkey")
                        undoModifierOnlyState.targetModifiersReached = false
                        undoModifierOnlyState.hasTriggered = true  // Prevent trigger on release
                    }
                }
                // Don't consume flagsChanged events - let them pass through
            } else {
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
                        // Call callback synchronously and check result
                        if let callback = onUndoTypingHotkey, callback() {
                            debugLogCallback?(" → Undo performed - consuming event")
                            return nil  // Consume the event
                        }
                        debugLogCallback?(" → Nothing to undo - pass through")
                        // Fall through to delegate processing
                    }
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
    
    // MARK: - Permission Check
    
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
    
    // MARK: - Secure Input Detection
    
    /// Check if macOS Secure Input mode is active.
    ///
    /// When Secure Input is ON (typically enabled by password managers like 1Password,
    /// Terminal, or browser password fields), macOS blocks ALL CGEvent taps from
    /// receiving keyDown/keyUp events. Only flagsChanged (modifier keys) pass through.
    /// This makes XKey and ALL third-party input methods completely non-functional.
    ///
    /// Uses IOKit IOConsoleUsers (same source as `ioreg`) instead of
    /// CGSessionCopyCurrentDictionary, which can return the wrong PID.
    ///
    /// - Returns: Tuple with (isSecure, pid of app holding it, app name)
    func checkSecureInput() -> (isSecure: Bool, pid: pid_t?, appName: String?) {
        // Read IOConsoleUsers from IOKit registry (same data source as `ioreg -l | grep SecureInput`)
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return (false, nil, nil) }
        defer { IOObjectRelease(root) }
        
        guard let ref = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return (false, nil, nil)
        }
        
        let consoleUsers = ref.takeRetainedValue()
        guard let users = consoleUsers as? [[String: Any]] else {
            return (false, nil, nil)
        }
        
        // Find the current session's Secure Input PID
        for user in users {
            // Only check sessions that are on console (active)
            guard let onConsole = user["kCGSSessionOnConsoleKey"] as? Bool,
                  onConsole else { continue }
            
            guard let securePIDValue = user["kCGSSessionSecureInputPID"] as? Int,
                  securePIDValue != 0 else { continue }
            
            let securePID = pid_t(securePIDValue)
            
            // Resolve app name from PID
            let app = NSRunningApplication(processIdentifier: securePID)
            let appName = app?.localizedName ?? app?.bundleIdentifier ?? "PID \(securePID)"
            
            return (true, securePID, appName)
        }
        
        return (false, nil, nil)
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

