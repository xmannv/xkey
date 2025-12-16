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
    private var isEnabled = false

    weak var delegate: EventTapDelegate?
    var debugLogCallback: ((String) -> Void)?
    
    // Toggle hotkey configuration
    var toggleHotkey: Hotkey?
    var onToggleHotkey: (() -> Void)?
    
    // MARK: - Delegate Protocol

    protocol EventTapDelegate: AnyObject {
        func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool
        func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent?
    }
    
    // MARK: - Errors
    
    enum EventTapError: Error {
        case creationFailed
        case accessibilityPermissionDenied
        case alreadyRunning
        case notRunning
    }
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    func start() throws {
        debugLogCallback?("🚀 EventTapManager.start() called")

        guard !isEnabled else {
            debugLogCallback?("  ❌ Already running")
            throw EventTapError.alreadyRunning
        }

        // Check accessibility permission
        guard checkAccessibilityPermission() else {
            debugLogCallback?("  ❌ No accessibility permission")
            throw EventTapError.accessibilityPermissionDenied
        }
        debugLogCallback?("  ✅ Accessibility permission OK")

        // Create event mask for keyboard events
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        debugLogCallback?("  📊 Event mask: \(eventMask)")
        
        // Create event tap
        debugLogCallback?("  🔧 Creating event tap...")
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
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
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLogCallback?("  ❌ Failed to create event tap!")
            throw EventTapError.creationFailed
        }
        debugLogCallback?("  ✅ Event tap created")
        
        eventTap = tap

        // Create run loop source
        debugLogCallback?("  🔄 Creating run loop source...")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            debugLogCallback?("  ❌ Failed to create run loop source")
            eventTap = nil
            throw EventTapError.creationFailed
        }
        debugLogCallback?("  ✅ Run loop source created")

        // Add to current run loop
        debugLogCallback?("  🔄 Adding to run loop...")
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        debugLogCallback?("  ✅ Added to run loop")

        // Enable the event tap
        debugLogCallback?("  ⚡ Enabling event tap...")
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLogCallback?("  ✅ Event tap enabled")

        isEnabled = true
        debugLogCallback?("✅ Event tap fully started!")
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
        
        debugLogCallback?("⏹️ Event tap stopped")
    }
    
    func restart() throws {
        stop()
        try start()
    }
    
    // MARK: - Event Callback
    
    private func eventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        debugLogCallback?("EventTapManager.eventCallback: type=\(type.rawValue), delegate=\(delegate != nil)")

        // Handle tap disabled event
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Check for toggle hotkey FIRST (before delegate processing)
        // This ensures the hotkey is consumed and doesn't reach other apps
        if type == .keyDown, let hotkey = toggleHotkey {
            let eventModifiers = ModifierFlags(from: event.flags)
            if event.keyCode == hotkey.keyCode && eventModifiers == hotkey.modifiers {
                debugLogCallback?("  → TOGGLE HOTKEY DETECTED - consuming event")
                // Call toggle callback on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.onToggleHotkey?()
                }
                // Consume the event completely - don't pass to other apps
                return nil
            }
        }

        // Check if delegate wants to process this event
        guard let delegate = delegate else {
            debugLogCallback?("  → No delegate!")
            return Unmanaged.passUnretained(event)
        }

        debugLogCallback?("  → Calling shouldProcessEvent...")
        guard delegate.shouldProcessEvent(event, type: type) else {
            debugLogCallback?("  → shouldProcessEvent returned false")
            return Unmanaged.passUnretained(event)
        }

        debugLogCallback?("  → Calling processKeyEvent...")
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
}

// MARK: - ModifierFlags Helper

extension ModifierFlags {
    init(from cgFlags: CGEventFlags) {
        var flags = ModifierFlags()
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        self = flags
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
}

