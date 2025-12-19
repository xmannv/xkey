//
//  CharacterInjector.swift
//  XKey
//
//  Injects Vietnamese characters into the system
//

import Cocoa
import Carbon

// MARK: - Injection Method
// NOTE: InjectionMethod, InjectionDelays, and InjectionMethodInfo are defined in
// Shared/AppBehaviorDetector.swift (Single Source of Truth)

class CharacterInjector {
    
    // MARK: - Properties
    
    private var eventSource: CGEventSource?
    private var isTypingMidSentence: Bool = false  // Track if user moved cursor (typing in middle of text)
    
    /// Semaphore to ensure injection completes before next keystroke is processed
    /// This prevents race conditions where backspace arrives before previous injection is rendered
    private let injectionSemaphore = DispatchSemaphore(value: 1)
    
    // Cached injection method to avoid repeated detection
    private var cachedMethod: InjectionMethod?
    private var cachedDelays: InjectionDelays?
    private var cachedBundleId: String?
    
    // Debug callback
    var debugCallback: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Use .privateState to isolate injected events from system event state
        eventSource = CGEventSource(stateID: .privateState)
    }
    /// Mark as new input session (call when cursor moves or new field focused)
    /// - Parameter cursorMoved: true if cursor was moved by user (mouse click or arrow keys)
    func markNewSession(cursorMoved: Bool = false) {
        isTypingMidSentence = cursorMoved  // If cursor moved, we're likely typing in middle of text
        debugCallback?("New session: isTypingMidSentence=\(cursorMoved)")
    }
    
    /// Check if currently typing in middle of sentence (cursor was moved)
    func getIsTypingMidSentence() -> Bool {
        return isTypingMidSentence
    }
    
    /// Reset mid-sentence flag (call when starting fresh input, e.g., new text field)
    func resetMidSentenceFlag() {
        isTypingMidSentence = false
        debugCallback?("Reset mid-sentence flag: isTypingMidSentence=false")
    }
    /// Wait for previous injection to complete (call BEFORE processing next keystroke)
    /// Uses semaphore to ensure 100% synchronization (better than cooldown timer)
    func waitForInjectionComplete() {
        debugCallback?("    → Waiting for previous injection to complete...")
        injectionSemaphore.wait()
        injectionSemaphore.signal()
        debugCallback?("    → Previous injection complete, proceeding")
    }
    
    /// Begin injection (call at start of injection)
    private func beginInjection() {
        injectionSemaphore.wait()
    }
    
    /// End injection (call at end of injection)
    private func endInjection() {
        injectionSemaphore.signal()
    }
    
    // MARK: - Synchronized Injection
    
    /// Inject text replacement synchronously - backspaces + new text in one atomic operation
    /// This prevents race conditions where next keystroke arrives between backspace and text injection
    func injectSync(backspaceCount: Int, characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy, fixAutocomplete: Bool = false) {
        // Acquire semaphore for entire injection operation
        injectionSemaphore.wait()
        defer { injectionSemaphore.signal() }
        
        let (method, delays) = detectInjectionMethod()
        debugCallback?("injectSync: bs=\(backspaceCount), chars=\(characters.count), method=\(method)")
        
        // IMPORTANT: Disable autocomplete fix when typing in middle of sentence
        let shouldFixAutocomplete = fixAutocomplete && !isTypingMidSentence
        
        // Step 1: Send backspaces
        if backspaceCount > 0 {
            switch method {
            case .selection:
                debugCallback?("    → Selection method: Shift+Left × \(backspaceCount)")
                injectViaSelectionInternal(count: backspaceCount, delays: delays, proxy: proxy)
                
            case .autocomplete:
                debugCallback?("    → Autocomplete method: Forward Delete + backspaces")
                injectViaAutocompleteInternal(count: backspaceCount, delays: delays, proxy: proxy)
                
            case .slow, .fast:
                debugCallback?("    → Backspace method: delays=\(delays)")
                if shouldFixAutocomplete {
                    sendForwardDelete(proxy: proxy)
                    usleep(3000)
                }
                for i in 0..<backspaceCount {
                    sendBackspaceKey(codeTable: codeTable, proxy: proxy)
                    usleep(delays.backspace)
                    debugCallback?("    → Backspace \(i + 1)/\(backspaceCount)")
                }
                if backspaceCount > 0 {
                    usleep(delays.wait)
                }
            }
        }
        
        // Step 2: Send new characters
        if !characters.isEmpty {
            var fullString = ""
            for (index, character) in characters.enumerated() {
                let unicodeString = character.unicode(codeTable: codeTable)
                fullString += unicodeString
                debugCallback?("  [\(index)]: '\(unicodeString)'")
            }
            
            // Send text using chunking
            sendTextChunkedInternal(fullString, delay: delays.text, proxy: proxy)
        }
        
        // Settle time
        let settleTime: UInt32 = (method == .slow) ? 20000 : 5000
        usleep(settleTime)
        
        debugCallback?("injectSync: complete")
    }
    
    /// Internal: Send backspace key (no semaphore)
    private func sendBackspaceKey(codeTable: CodeTable, proxy: CGEventTapProxy) {
        let deleteKeyCode: CGKeyCode = 0x33
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1
        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy)
            usleep(1000)
        }
    }
    
    /// Internal: Selection injection (no semaphore)
    private func injectViaSelectionInternal(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        for i in 0..<count {
            sendShiftLeftArrow(proxy: proxy)
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Shift+Left \(i + 1)/\(count)")
        }
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 3000)
        }
    }
    
    /// Internal: Autocomplete injection (no semaphore)
    private func injectViaAutocompleteInternal(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        sendForwardDelete(proxy: proxy)
        usleep(3000)
        for i in 0..<count {
            sendKeyPress(0x33, proxy: proxy)
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Backspace \(i + 1)/\(count)")
        }
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 5000)
        }
    }
    
    /// Internal: Send text chunked (no semaphore)
    private func sendTextChunkedInternal(_ text: String, delay: UInt32, proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }
        
        let utf16 = Array(text.utf16)
        var offset = 0
        let chunkSize = 20
        
        debugCallback?("    → Sending text chunked: '\(text)' (\(utf16.count) UTF-16 units)")
        
        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                break
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
            
            debugCallback?("    → Sent chunk [\(offset)..<\(end)]: \(chunk.count) chars")
            
            if delay > 0 && end < utf16.count {
                usleep(delay)
            }
            
            offset = end
        }
    }
    
    // MARK: - Public Methods

    /// Send backspace key presses with optional autocomplete fix
    /// Uses adaptive delays based on detected app type (Terminal/JetBrains/etc.)
    /// Synchronized with semaphore to prevent race conditions
    func sendBackspaces(count: Int, codeTable: CodeTable, proxy: CGEventTapProxy, fixAutocomplete: Bool = false) {
        guard count > 0 else { return }
        
        // Begin synchronized injection
        beginInjection()
        defer { endInjection() }
        
        // Detect injection method for current app
        let (method, delays) = detectInjectionMethod()
        
        debugCallback?("sendBackspaces: count=\(count), method=\(method), fixAutocomplete=\(fixAutocomplete), isTypingMidSentence=\(isTypingMidSentence)")
        
        // IMPORTANT: Disable autocomplete fix when typing in middle of sentence
        // Forward Delete would delete text to the right of cursor, which is wrong!
        let shouldFixAutocomplete = fixAutocomplete && !isTypingMidSentence
        
        switch method {
        case .selection:
            // Selection method: Shift+Left to select, then type replacement
            debugCallback?("    → Selection method: Shift+Left × \(count)")
            injectViaSelection(count: count, delays: delays, proxy: proxy)
            
        case .autocomplete:
            // Autocomplete method: Forward Delete to clear suggestion, then backspaces
            debugCallback?("    → Autocomplete method: Forward Delete + backspaces")
            injectViaAutocomplete(count: count, delays: delays, proxy: proxy)
            
        case .slow:
            // Slow method for Terminal/JetBrains: higher delays between keystrokes
            debugCallback?("    → Slow method (Terminal/IDE): delays=\(delays)")
            injectViaBackspace(count: count, codeTable: codeTable, delays: delays, proxy: proxy, fixAutocomplete: shouldFixAutocomplete)
            
        case .fast:
            // Fast method: minimal delays
            if shouldFixAutocomplete {
                debugCallback?("    → Fast method with autocomplete fix")
                sendForwardDelete(proxy: proxy)
                usleep(3000)
                injectViaBackspace(count: count, codeTable: codeTable, delays: delays, proxy: proxy, fixAutocomplete: false)
            } else if isTypingMidSentence {
                debugCallback?("    → Fast method (mid-sentence)")
                injectViaBackspace(count: count, codeTable: codeTable, delays: (delays.backspace, delays.wait, delays.text), proxy: proxy, fixAutocomplete: false)
            } else {
                debugCallback?("    → Fast method (normal)")
                injectViaBackspace(count: count, codeTable: codeTable, delays: delays, proxy: proxy, fixAutocomplete: false)
            }
        }
    }
    
    // MARK: - Injection Methods (Terminal/JetBrains compatible)
    
    /// Standard backspace injection with configurable delays
    private func injectViaBackspace(count: Int, codeTable: CodeTable, delays: InjectionDelays, proxy: CGEventTapProxy, fixAutocomplete: Bool) {
        if fixAutocomplete {
            sendForwardDelete(proxy: proxy)
            usleep(3000)
        }
        
        for i in 0..<count {
            sendBackspace(codeTable: codeTable, proxy: proxy)
            usleep(delays.backspace)
            debugCallback?("    → Backspace \(i + 1)/\(count)")
        }
        
        if count > 0 {
            usleep(delays.wait)
        }
    }
    
    /// Selection injection: Shift+Left to select characters
    private func injectViaSelection(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        for i in 0..<count {
            sendShiftLeftArrow(proxy: proxy)
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Shift+Left \(i + 1)/\(count)")
        }
        
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 3000)
        }
    }
    
    /// Autocomplete injection: Forward Delete to clear suggestion, then backspaces
    private func injectViaAutocomplete(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        // Forward Delete clears auto-selected suggestion
        sendForwardDelete(proxy: proxy)
        usleep(3000)
        
        // Backspaces remove typed characters
        for i in 0..<count {
            sendKeyPress(0x33, proxy: proxy)  // Backspace
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Backspace \(i + 1)/\(count)")
        }
        
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 5000)
        }
    }


    
    /// Send Vietnamese characters with adaptive delays for Terminal/JetBrains
    /// Uses text chunking (up to 20 chars per CGEvent) for better performance
    /// Synchronized with semaphore to prevent race conditions
    func sendCharacters(_ characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        guard !characters.isEmpty else { return }
        
        // Begin synchronized injection
        beginInjection()
        defer { endInjection() }
        
        // Get injection method and delays
        let (method, delays) = detectInjectionMethod()
        
        debugCallback?("sendCharacters: count=\(characters.count), method=\(method)")
        
        // Build full string from characters
        var fullString = ""
        for (index, character) in characters.enumerated() {
            let unicodeString = character.unicode(codeTable: codeTable)
            fullString += unicodeString
            debugCallback?("  [\(index)]: '\(unicodeString)' (Unicode: \(unicodeString.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")))")
        }
        
        // Send text using chunking (20 chars per CGEvent - macOS limit)
        sendTextChunked(fullString, delay: delays.text, proxy: proxy)
        
        // Settle time: adaptive based on method
        // Reduced from 20ms to 8ms for slow apps thanks to semaphore sync
        let settleTime: UInt32 = (method == .slow) ? 8000 : 3000
        usleep(settleTime)
    }

    
    /// Get text before cursor until space (for debugging)
    private func getTextBeforeCursor() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugCallback?("  [AX] Failed to get focused element")
            return nil
        }
        
        let element = focusedElement as! AXUIElement
        
        // Get selected text range
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            debugCallback?("  [AX] Failed to get selected range")
            return nil
        }
        
        // Extract cursor position
        var rangeValue = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRange as! AXValue, .cfRange, &rangeValue) else {
            debugCallback?("  [AX] Failed to extract range value")
            return nil
        }
        
        let cursorPosition = rangeValue.location
        debugCallback?("  [AX] Cursor position: \(cursorPosition)")
        
        // Read text from start to cursor (max 50 chars)
        let readLength = min(cursorPosition, 50)
        let readRange = CFRange(location: max(0, cursorPosition - readLength), length: readLength)
        var readRangeValue = readRange
        guard let axRange = AXValueCreate(.cfRange, &readRangeValue) else {
            debugCallback?("  [AX] Failed to create AXValue")
            return nil
        }
        
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &text
        ) == .success else {
            debugCallback?("  [AX] Failed to read text")
            return nil
        }
        
        guard let fullText = text as? String else {
            debugCallback?("  [AX] Text is not a string")
            return nil
        }
        
        // Extract last word (from last space/newline to end)
        let components = fullText.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        let lastWord = components.last ?? ""
        
        debugCallback?("  [AX] Full text: '\(fullText)'")
        debugCallback?("  [AX] Last word: '\(lastWord)' (length: \(lastWord.count))")
        
        return lastWord
    }
    
    /// Get length of text before cursor using Accessibility API
    private func getTextLengthBeforeCursor() -> Int? {
        return getTextBeforeCursor()?.count
    }

    /// Send a string of characters (legacy method, sends one char at a time)
    func sendString(_ string: String, proxy: CGEventTapProxy) {
        for char in string.unicodeScalars {
            sendUnicodeCharacter(char, proxy: proxy)
        }
    }
    
    /// Send text in chunks (up to 20 chars per CGEvent) for better performance
    /// CGEvent has a 20-character limit per keyboardSetUnicodeString call
    private func sendTextChunked(_ text: String, delay: UInt32, proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }
        
        let utf16 = Array(text.utf16)
        var offset = 0
        let chunkSize = 20  // CGEvent limit
        
        debugCallback?("    → Sending text chunked: '\(text)' (\(utf16.count) UTF-16 units)")
        
        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                break
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
            
            debugCallback?("    → Sent chunk [\(offset)..<\(end)]: \(chunk.count) chars")
            
            if delay > 0 && end < utf16.count {
                usleep(delay)
            }
            
            offset = end
        }
    }
    
    // MARK: - Private Methods

    private func sendBackspace(codeTable: CodeTable, proxy: CGEventTapProxy) {
        let deleteKeyCode: CGKeyCode = 0x33 // Delete/Backspace key

        // For VNI and Unicode Compound, some characters require double backspace
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1

        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy)
            // Add small delay for apps like Spotlight that need time to process backspace
            usleep(1000) // 1ms delay between backspaces
        }
    }

    private func sendKeyPress(_ keyCode: CGKeyCode, proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }

        // Create key down event
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.tapPostEvent(proxy)
        }

        // Create key up event
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.tapPostEvent(proxy)
        }
    }
    
    private func sendUnicodeCharacter(_ char: UnicodeScalar, proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }

        // Create keyboard events with Unicode character
        // Use CGEventCreateKeyboardEvent with virtualKey 0 for Unicode input
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        // Convert UnicodeScalar to UTF-16 (UniChar array)
        let unicodeString = String(char)
        var utf16Chars = Array(unicodeString.utf16)

        // Use the official keyboardSetUnicodeString instance method (Swift 3+ API)
        // This is the same method used by OpenKey
        keyDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
        keyUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)

        // Post events using tapPostEvent
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
    }

    // MARK: - Autocomplete Fix Methods
    
    /// Send Right Arrow key to move cursor to end (deselect autocomplete in Spotlight)
    private func sendRightArrow(proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }
        
        let rightArrowKeyCode: CGKeyCode = 0x7C  // Right Arrow key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
        
        debugCallback?("    → Sent Right Arrow to deselect autocomplete")
    }
    
    /// Send Forward Delete (Fn+Delete) to delete text after cursor (clear autocomplete suggestion)
    private func sendForwardDelete(proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }
        
        // Forward Delete key code is 0x75 (117)
        let forwardDeleteKeyCode: CGKeyCode = 0x75
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: forwardDeleteKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: forwardDeleteKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
        
        debugCallback?("    → Sent Forward Delete to clear autocomplete suggestion")
    }
    
    /// Send Escape key to dismiss autocomplete suggestions (for Spotlight)
    private func sendEscapeKey(proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }
        
        let escapeKeyCode: CGKeyCode = 0x35  // Escape key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
        
        debugCallback?("    → Sent Escape key to dismiss autocomplete")
    }

    /// Send empty character to fix autocomplete (U+202F - Narrow No-Break Space)
    private func sendEmptyCharacter(proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }

        let emptyChar: UInt16 = 0x202F  // Narrow No-Break Space

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        var chars = [emptyChar]
        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)

        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
    }

    /// Send Shift+Left Arrow to select text (for Chromium browsers)
    private func sendShiftLeftArrow(proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }

        let leftArrowKeyCode: CGKeyCode = 0x7B  // Left Arrow key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKeyCode, keyDown: false) else {
            return
        }

        // Add Shift modifier
        keyDown.flags.insert(.maskShift)
        keyUp.flags.insert(.maskShift)

        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
    }

    /// Check if current frontmost app is a Chromium-based browser
    private func isChromiumBrowser() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let chromiumBrowsers = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Dev",
            "com.microsoft.edgemac.Beta"
        ]

        return chromiumBrowsers.contains(frontApp.bundleIdentifier ?? "")
    }
    
    /// Check if current focused element is in Spotlight
    private func isSpotlight() -> Bool {
        // Method 1: Check frontmost app (works for some cases)
        // Method 1: Check frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let bundleId = frontApp.bundleIdentifier ?? "unknown"
            debugCallback?("    → isSpotlight: frontmostApp = \(bundleId)")
            if bundleId == "com.apple.Spotlight" {
                debugCallback?("    → isSpotlight: Detected via frontmostApplication")
                return true
            }
        }
        
        // Method 2: Check if Spotlight process is active and has a window
        // Spotlight runs as a separate process when opened with Cmd+Space
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if app.bundleIdentifier == "com.apple.Spotlight" && app.isActive {
                debugCallback?("    → isSpotlight: Detected active Spotlight process")
                return true
            }
        }
        
        // Method 3: Check menu bar ownership - Spotlight takes over menu bar when active
        // When Spotlight is open, the menu bar shows "Spotlight" in the app menu
        if let menuBarOwner = NSWorkspace.shared.menuBarOwningApplication {
            let bundleId = menuBarOwner.bundleIdentifier ?? "unknown"
            debugCallback?("    → isSpotlight: menuBarOwner = \(bundleId)")
            if bundleId == "com.apple.Spotlight" {
                debugCallback?("    → isSpotlight: Detected via menuBarOwningApplication")
                return true
            }
        }
        
        // Method 4: Use Accessibility API to check focused element's app
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success {
            let element = focusedElement as! AXUIElement
            
            // Get the process ID of the focused element
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    let bundleId = app.bundleIdentifier ?? "unknown"
                    let appName = app.localizedName ?? "unknown"
                    debugCallback?("    → isSpotlight: Focused element app = \(appName) (\(bundleId))")
                    
                    if bundleId == "com.apple.Spotlight" {
                        return true
                    }
                }
            }
        } else {
            debugCallback?("    → isSpotlight: Failed to get focused element (AX API)")
        }
        
        debugCallback?("    → isSpotlight: Not Spotlight")
        return false
    }
    // MARK: - Injection Method Detection
    
    /// Detect injection method based on frontmost app and focused element
    /// Uses AppBehaviorDetector for centralized app detection
    func detectInjectionMethod() -> (InjectionMethod, InjectionDelays) {
        // Use AppBehaviorDetector (Single Source of Truth)
        let methodInfo = AppBehaviorDetector.shared.detectInjectionMethod()
        
        debugCallback?("    → detectMethod: \(methodInfo.description) → \(methodInfo.method)")
        
        // Update local cache for compatibility
        cachedMethod = methodInfo.method
        cachedDelays = methodInfo.delays
        
        return (methodInfo.method, methodInfo.delays)
    }
    
    /// Clear cached injection method (call when app changes)
    func clearMethodCache() {
        cachedMethod = nil
        cachedDelays = nil
        cachedBundleId = nil
        // Also clear AppBehaviorDetector cache
        AppBehaviorDetector.shared.clearCache()
    }
}

