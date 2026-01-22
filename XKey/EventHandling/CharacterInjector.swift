//
//  CharacterInjector.swift
//  XKey
//
//  Injects Vietnamese characters into the system
//

import Cocoa
import Carbon

// MARK: - Event Marker
// Used to identify events injected by XKey - prevents re-processing by event tap
// This is critical for avoiding race conditions in terminal apps
let kXKeyEventMarker: Int64 = 0x584B4559  // "XKEY" in hex

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
    
    // Debug callback
    var debugCallback: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Use .privateState to isolate injected events from system event state
        eventSource = CGEventSource(stateID: .privateState)
    }
    /// Mark as new input session (call when cursor moves or new field focused)
    /// - Parameters:
    ///   - cursorMoved: true if cursor was moved by user (mouse click or arrow keys)
    ///   - preserveMidSentence: if true, keep current isTypingMidSentence value (for Escape undo, Forward Delete, etc.)
    func markNewSession(cursorMoved: Bool = false, preserveMidSentence: Bool = false) {
        if !preserveMidSentence {
            isTypingMidSentence = cursorMoved  // If cursor moved, we're likely typing in middle of text
        }
        debugCallback?("New session: isTypingMidSentence=\(isTypingMidSentence), cursorMoved=\(cursorMoved), preserved=\(preserveMidSentence)")
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
    func injectSync(backspaceCount: Int, characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        // Acquire semaphore for entire injection operation
        injectionSemaphore.wait()
        defer { injectionSemaphore.signal() }
        
        // Create NEW event source for each injection
        // This ensures each injection has independent state, avoiding potential race conditions
        eventSource = CGEventSource(stateID: .privateState)
        
        let methodInfo = detectInjectionMethod()
        let method = methodInfo.method
        let delays = methodInfo.delays
        let textSendingMethod = methodInfo.textSendingMethod
        
        // For slow method (terminals), use direct post and use post(tap: .cgSessionEventTap) without proxy for injectViaBackspace
        // With HID level event tap, new event source per injection, and proper markers,
        // direct post should work correctly now
        let useDirectPost = (method == .slow)

        // Build preview of characters to inject
        let charPreview = characters.map { $0.unicode(codeTable: codeTable) }.joined()
        debugCallback?("Inject: bs=\(backspaceCount), chars=\(characters.count), text=\"\(charPreview)\", method=\(method), textMode=\(textSendingMethod)")

        // Step 1: Send backspaces
        if backspaceCount > 0 {
            switch method {
            case .selection:
                debugCallback?("    → Selection method: Shift+Left × \(backspaceCount)")
                injectViaSelectionInternal(count: backspaceCount, delays: delays, proxy: proxy)

            case .autocomplete:
                // For autocomplete method, Forward Delete is ALWAYS needed to clear browser autosuggestions
                // However, we must skip it when typing mid-sentence or when AX detects text after cursor
                // Note: We use shouldSendForwardDeleteForAutocomplete() which ignores fixAutocomplete setting
                let shouldForwardDelete = shouldSendForwardDeleteForAutocomplete()
                debugCallback?("    → Autocomplete method: Forward Delete + backspaces (skipFwdDel=\(!shouldForwardDelete))")
                injectViaAutocompleteInternal(count: backspaceCount, delays: delays, proxy: proxy, skipForwardDelete: !shouldForwardDelete)

            case .axDirect:
                // AX Direct: Use Accessibility API to manipulate text directly
                // Used for Firefox-based browsers content area where keyboard events don't work well
                debugCallback?("    → AX Direct method: bs=\(backspaceCount), text=\"\(charPreview)\"")
                // Forward debug callback to AdvancedInjectionMethods
                AdvancedInjectionMethods.shared.debugCallback = debugCallback
                AdvancedInjectionMethods.shared.injectViaAXWithFallback(bs: backspaceCount, text: charPreview) {
                    // Fallback to selection method if AX fails
                    self.debugCallback?("    → AX failed, fallback to selection")
                    self.injectViaSelectionInternal(count: backspaceCount, delays: delays, proxy: proxy)
                    self.sendTextChunkedInternal(charPreview, delay: delays.text, proxy: proxy, useDirectPost: false)
                }
                // AX Direct handles both backspace and text insertion (or fallback does), so skip Step 2
                debugCallback?("injectSync: complete (AX Direct)")
                return

            case .slow, .fast:
                debugCallback?("    → Backspace method: delays=\(delays), directPost=\(useDirectPost)")
                // Forward Delete is only used for .autocomplete method
                // For slow/fast methods, just send backspaces
                
                // SPECIAL CASE: Microsoft Office (Excel/Word/PowerPoint)
                // Send Forward Delete before backspaces to clear AutoComplete suggestions
                // Forward Delete clears any highlighted suggestion text after cursor
                // Note: We use Forward Delete instead of Escape because:
                // - Escape in Excel CANCELS the entire edit session (loses all typed content)
                // - Forward Delete only clears text after cursor (the suggestion)
                //
                // IMPORTANT: Only send Forward Delete when there's NO real text after cursor.
                // If user clicked into middle of existing text, Forward Delete would delete
                // real characters. AutoComplete suggestions are not counted as "real text" by AX API.
                let isMicrosoftOffice = AppBehaviorDetector.shared.detect() == .microsoftOffice
                if isMicrosoftOffice && backspaceCount > 0 {
                    // Check if there's real text after cursor using Accessibility API
                    let hasRealTextAfter = hasTextAfterCursor() ?? false
                    if !hasRealTextAfter {
                        debugCallback?("    → MS Office: sending Forward Delete to clear AutoComplete")
                        sendForwardDelete(proxy: proxy)
                        usleep(2000)  // 2ms delay after Forward Delete
                    } else {
                        debugCallback?("    → MS Office: skipping Forward Delete (real text after cursor)")
                    }
                }

                // Send backspaces immediately, then waits AFTER all backspaces are sent
                for i in 0..<backspaceCount {
                    sendBackspaceKey(codeTable: codeTable, proxy: proxy, useDirectPost: useDirectPost)
                    usleep(delays.backspace)
                    debugCallback?("    → Backspace \(i + 1)/\(backspaceCount)")
                }
                // Wait after all backspaces
                if backspaceCount > 0 {
                    usleep(delays.wait)
                    debugCallback?("    → Post-backspace wait: \(delays.wait)µs")
                }
            
            case .passthrough:
                // Passthrough should never reach here - it's filtered at shouldProcessEvent level
                // But if it does, just return without doing anything
                debugCallback?("    → Passthrough mode - no injection needed")
                return
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
            
            // Use text sending method from rule/detection
            switch textSendingMethod {
            case .oneByOne:
                debugCallback?("    → Text mode: one-by-one, directPost=\(useDirectPost)")
                sendTextOneByOneInternal(fullString, delay: delays.text, proxy: proxy, useDirectPost: useDirectPost)
            case .chunked:
                debugCallback?("    → Text mode: chunked, directPost=\(useDirectPost)")
                sendTextChunkedInternal(fullString, delay: delays.text, proxy: proxy, useDirectPost: useDirectPost)
            }
        }
        
        // Settle time
        let settleTime: UInt32 = (method == .slow) ? 20000 : 5000
        usleep(settleTime)
        
        debugCallback?("injectSync: complete")
    }
    
    /// Internal: Send backspace key (no semaphore)
    private func sendBackspaceKey(codeTable: CodeTable, proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        let deleteKeyCode: CGKeyCode = 0x33
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1
        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy, useDirectPost: useDirectPost)
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
    /// - Parameter skipForwardDelete: if true, skip sending Forward Delete (e.g., when typing mid-sentence)
    private func injectViaAutocompleteInternal(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy, skipForwardDelete: Bool = false) {
        if !skipForwardDelete {
            sendForwardDelete(proxy: proxy)
            usleep(3000)
        } else {
            debugCallback?("    → Skipped Forward Delete (mid-sentence)")
        }
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
    /// Special handling for newline/tab: splits text and sends as key events
    private func sendTextChunkedInternal(_ text: String, delay: UInt32, proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        debugCallback?("    → Sending text chunked: '\(text)' (handling special chars), direct=\(useDirectPost)")
        
        // Split text into segments by newline and tab
        // Each segment is either: normal text, newline, or tab
        var segments: [(type: SegmentType, content: String)] = []
        var currentSegment = ""
        
        for char in text {
            if char == "\n" || char == "\r" {
                if !currentSegment.isEmpty {
                    segments.append((.text, currentSegment))
                    currentSegment = ""
                }
                segments.append((.newline, ""))
            } else if char == "\t" {
                if !currentSegment.isEmpty {
                    segments.append((.text, currentSegment))
                    currentSegment = ""
                }
                segments.append((.tab, ""))
            } else {
                currentSegment.append(char)
            }
        }
        if !currentSegment.isEmpty {
            segments.append((.text, currentSegment))
        }
        
        // Send each segment
        for (segmentIndex, segment) in segments.enumerated() {
            switch segment.type {
            case .newline:
                debugCallback?("    → Sending newline (Return key)")
                sendReturnKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                
            case .tab:
                debugCallback?("    → Sending tab (Tab key)")
                sendTabKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                
            case .text:
                // Send text in chunks
                let utf16 = Array(segment.content.utf16)
                var offset = 0
                let chunkSize = 20
                
                while offset < utf16.count {
                    let end = min(offset + chunkSize, utf16.count)
                    var chunk = Array(utf16[offset..<end])
                    
                    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                        break
                    }
                    
                    keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    
                    // Mark as XKey-injected event to prevent re-processing by event tap
                    keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    
                    // For slow method (terminals), post directly to session event tap
                    if useDirectPost {
                        keyDown.post(tap: .cgSessionEventTap)
                        keyUp.post(tap: .cgSessionEventTap)
                    } else {
                        keyDown.tapPostEvent(proxy)
                        keyUp.tapPostEvent(proxy)
                    }
                    
                    debugCallback?("    → Sent chunk [\(offset)..<\(end)]: \(chunk.count) chars")
                    
                    if delay > 0 && end < utf16.count {
                        usleep(delay)
                    }
                    
                    offset = end
                }
            }
            
            // Add delay between segments
            if delay > 0 && segmentIndex < segments.count - 1 {
                usleep(delay)
            }
        }
    }
    
    /// Segment type for chunked text sending
    private enum SegmentType {
        case text
        case newline
        case tab
    }
    
    /// Internal: Send text one character at a time (for Safari/Google Docs compatibility)
    /// Some apps don't handle multiple Unicode characters in a single CGEvent properly
    /// Special handling for newline: sends Return key (0x24) instead of Unicode \n
    private func sendTextOneByOneInternal(_ text: String, delay: UInt32, proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        debugCallback?("    → Sending text one-by-one: '\(text)' (\(text.count) chars), direct=\(useDirectPost)")
        
        for (index, char) in text.enumerated() {
            // Special handling for newline - send Return key instead
            if char == "\n" || char == "\r" {
                debugCallback?("    → Sent char [\(index)]: newline (Return key)")
                sendReturnKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                if delay > 0 && index < text.count - 1 {
                    usleep(delay)
                }
                continue
            }
            
            // Special handling for tab - send Tab key instead
            if char == "\t" {
                debugCallback?("    → Sent char [\(index)]: tab (Tab key)")
                sendTabKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                if delay > 0 && index < text.count - 1 {
                    usleep(delay)
                }
                continue
            }
            
            var utf16 = Array(String(char).utf16)
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                break
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            
            // Mark as XKey-injected event to prevent re-processing by event tap
            keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            
            // For slow method (terminals), post directly to session event tap
            if useDirectPost {
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
            } else {
                keyDown.tapPostEvent(proxy)
                keyUp.tapPostEvent(proxy)
            }
            
            debugCallback?("    → Sent char [\(index)]: '\(char)'")
            
            // Add delay between characters (except after last one)
            if delay > 0 && index < text.count - 1 {
                usleep(delay)
            }
        }
    }
    
    /// Internal: Send Return key (for newline in macros)
    private func sendReturnKeyInternal(proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        let returnKeyCode: CGKeyCode = 0x24  // Return key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }
        
        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        
        if useDirectPost {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        } else {
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
        }
    }
    
    /// Internal: Send Tab key (for tab in macros)
    private func sendTabKeyInternal(proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        let tabKeyCode: CGKeyCode = 0x30  // Tab key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: tabKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: tabKeyCode, keyDown: false) else {
            return
        }
        
        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        
        if useDirectPost {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        } else {
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
        }
    }
    
    // MARK: - Public Methods

    /// Send backspace key presses
    /// Uses adaptive delays based on detected app type (Terminal/JetBrains/etc.)
    /// Synchronized with semaphore to prevent race conditions
    /// Note: Forward Delete is only used for .autocomplete method (Firefox, Spotlight, Raycast, Alfred)
    func sendBackspaces(count: Int, codeTable: CodeTable, proxy: CGEventTapProxy) {
        guard count > 0 else { return }

        // Begin synchronized injection
        beginInjection()
        defer { endInjection() }

        // Detect injection method for current app
        let methodInfo = detectInjectionMethod()
        let method = methodInfo.method
        let delays = methodInfo.delays

        debugCallback?("sendBackspaces: count=\(count), method=\(method), isTypingMidSentence=\(isTypingMidSentence)")

        switch method {
        case .selection:
            // Selection method: Shift+Left to select, then type replacement
            debugCallback?("    → Selection method: Shift+Left × \(count)")
            injectViaSelection(count: count, delays: delays, proxy: proxy)

        case .autocomplete:
            // Autocomplete method: Forward Delete to clear suggestion, then backspaces
            // This is the ONLY case where Forward Delete is used
            debugCallback?("    → Autocomplete method: Forward Delete + backspaces")
            injectViaAutocomplete(count: count, delays: delays, proxy: proxy)

        case .axDirect:
            // AX Direct method: For backspace-only, fall back to selection method
            // (AX API needs both backspace count AND replacement text to work properly)
            debugCallback?("    → AX Direct (backspace-only): fallback to selection × \(count)")
            injectViaSelection(count: count, delays: delays, proxy: proxy)

        case .slow:
            // Slow method for Terminal/JetBrains: higher delays between keystrokes
            // No Forward Delete - it's not needed for terminals
            debugCallback?("    → Slow method (Terminal/IDE): delays=\(delays)")
            injectViaBackspace(count: count, codeTable: codeTable, delays: delays, proxy: proxy)

        case .fast:
            // Fast method: minimal delays, no Forward Delete
            debugCallback?("    → Fast method (normal)")
            injectViaBackspace(count: count, codeTable: codeTable, delays: delays, proxy: proxy)
        
        case .passthrough:
            // Passthrough should never reach here - no injection needed
            debugCallback?("    → Passthrough mode - no backspaces needed")
            return
        }
    }
    
    // MARK: - Injection Methods (Terminal/JetBrains compatible)
    
    /// Standard backspace injection with configurable delays
    private func injectViaBackspace(count: Int, codeTable: CodeTable, delays: InjectionDelays, proxy: CGEventTapProxy) {
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
    /// Respects isTypingMidSentence flag to avoid deleting text when cursor is in middle
    private func injectViaAutocomplete(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        // Only send Forward Delete if not typing mid-sentence
        // When cursor is at end of text, Forward Delete clears autocomplete suggestion
        // When cursor is in middle of text, Forward Delete would delete real characters
        if !isTypingMidSentence {
            sendForwardDelete(proxy: proxy)
            usleep(3000)
        } else {
            debugCallback?("    → Skipped Forward Delete (mid-sentence)")
        }
        
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
        let methodInfo = detectInjectionMethod()
        let method = methodInfo.method
        let delays = methodInfo.delays
        let textSendingMethod = methodInfo.textSendingMethod
        
        debugCallback?("sendCharacters: count=\(characters.count), method=\(method), textMode=\(textSendingMethod)")
        
        // Build full string from characters
        var fullString = ""
        for (index, character) in characters.enumerated() {
            let unicodeString = character.unicode(codeTable: codeTable)
            fullString += unicodeString
            debugCallback?("  [\(index)]: '\(unicodeString)' (Unicode: \(unicodeString.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")))")
        }
        
        // Send text using configured method
        switch textSendingMethod {
        case .oneByOne:
            sendTextOneByOne(fullString, delay: delays.text, proxy: proxy)
        case .chunked:
            sendTextChunked(fullString, delay: delays.text, proxy: proxy)
        }
        
        // Settle time: adaptive based on method
        // Reduced from 20ms to 8ms for slow apps thanks to semaphore sync
        let settleTime: UInt32 = (method == .slow) ? 8000 : 3000
        usleep(settleTime)
    }

    
    /// Get text (word) before cursor until space
    /// Used for spell checking when engine loses context (e.g., after backspace into previous word)
    func getTextBeforeCursor() -> String? {
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
    /// Check if macro is a standalone word (not part of a larger word)
    /// Simple logic: 
    ///   - Character BEFORE macro text must be: space/newline/start of text
    ///   - Character AFTER cursor must be: space/newline/end of text
    /// Returns: true if standalone, false if part of word, nil if AX not supported
    func isMacroStandalone(macroLength: Int) -> Bool? {
        // Skip if macroLength is invalid
        guard macroLength > 0 else { return nil }
        
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil  // AX not supported, silently return nil
        }

        let element = focusedElement as! AXUIElement

        // Get selected text range (cursor position)
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil  // AX not supported
        }

        var rangeValue = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRange as! AXValue, .cfRange, &rangeValue) else {
            return nil  // AX not supported
        }

        let cursorPosition = rangeValue.location

        // Get total text length
        var numberOfCharacters: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numberOfCharacters) == .success,
              let totalLength = numberOfCharacters as? Int else {
            return nil  // AX not supported
        }

        // Position right before macro text
        let positionBeforeMacro = cursorPosition - macroLength
        
        // --- Check character BEFORE macro ---
        var charBeforeOK = false
        if positionBeforeMacro <= 0 {
            // Macro is at start of text → OK
            charBeforeOK = true
        } else {
            // Read character at position (positionBeforeMacro - 1)
            let readPos = positionBeforeMacro - 1
            let readRange = CFRange(location: readPos, length: 1)
            var readRangeValue = readRange
            if let axRange = AXValueCreate(.cfRange, &readRangeValue) {
                var text: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &text) == .success,
                   let charString = text as? String, let char = charString.first {
                    charBeforeOK = char.isWhitespace || char.isNewline
                }
            }
        }

        // --- Check character AFTER cursor ---
        var charAfterOK = false
        if cursorPosition >= totalLength {
            // Cursor at end of text → OK
            charAfterOK = true
        } else {
            // Read character at cursor position
            let readRange = CFRange(location: cursorPosition, length: 1)
            var readRangeValue = readRange
            if let axRange = AXValueCreate(.cfRange, &readRangeValue) {
                var text: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &text) == .success,
                   let charString = text as? String, let char = charString.first {
                    charAfterOK = char.isWhitespace || char.isNewline
                }
            }
        }

        let isStandalone = charBeforeOK && charAfterOK
        
        // Only log result when it matters (not standalone = will skip macro)
        if !isStandalone {
            debugCallback?("  [AX] Macro not standalone: charBeforeOK=\(charBeforeOK), charAfterOK=\(charAfterOK)")
        }
        
        return isStandalone
    }
    
    /// Get length of text before cursor using Accessibility API
    private func getTextLengthBeforeCursor() -> Int? {
        return getTextBeforeCursor()?.count
    }

    /// Check if there is text after cursor using Accessibility API
    /// Returns: true if there's text after cursor, false if at end of text, nil if AX not supported
    private func hasTextAfterCursor() -> Bool? {
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugCallback?("  [AX] hasTextAfterCursor: Failed to get focused element")
            return nil  // AX not supported
        }

        let element = focusedElement as! AXUIElement

        // Get selected text range (cursor position)
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            debugCallback?("  [AX] hasTextAfterCursor: Failed to get selected range")
            return nil  // AX not supported
        }

        // Extract cursor position AND selection length
        var rangeValue = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRange as! AXValue, .cfRange, &rangeValue) else {
            debugCallback?("  [AX] hasTextAfterCursor: Failed to extract range value")
            return nil  // AX not supported
        }

        let cursorPosition = rangeValue.location
        let selectionLength = rangeValue.length

        // Get total text length
        var numberOfCharacters: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numberOfCharacters) == .success,
              let totalLength = numberOfCharacters as? Int else {
            debugCallback?("  [AX] hasTextAfterCursor: Failed to get total length")
            return nil  // AX not supported
        }

        // If there's a selection (highlighted text), it's likely AutoComplete suggestion
        // In this case, we consider it as "no real text after cursor" because
        // the selected text will be replaced when user continues typing
        let hasRealTextAfter = cursorPosition + selectionLength < totalLength
        debugCallback?("  [AX] hasTextAfterCursor: cursor=\(cursorPosition), selection=\(selectionLength), total=\(totalLength), hasRealTextAfter=\(hasRealTextAfter)")

        return hasRealTextAfter
    }
    
    /// Check if there is a non-whitespace character immediately after cursor
    /// Returns: the character if exists and is not whitespace (cursor is mid-word),
    ///          nil if at end of text, followed by whitespace, or AX not supported
    /// This is used for context-aware macro checking
    func getCharacterAfterCursor() -> Character? {
        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        // Get selected text range (cursor position)
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to get selected range")
            return nil
        }

        var rangeValue = CFRange(location: 0, length: 0)
        guard AXValueGetValue(selectedRange as! AXValue, .cfRange, &rangeValue) else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to extract range value")
            return nil
        }

        let cursorPosition = rangeValue.location
        let selectionLength = rangeValue.length

        // Get total text length
        var numberOfCharacters: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &numberOfCharacters) == .success,
              let totalLength = numberOfCharacters as? Int else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to get total length")
            return nil
        }

        // Check if there's text after cursor (accounting for selection)
        let positionAfterCursor = cursorPosition + selectionLength
        guard positionAfterCursor < totalLength else {
            debugCallback?("  [AX] getCharacterAfterCursor: At end of text")
            return nil
        }

        // Read 1 character after cursor
        let readRange = CFRange(location: positionAfterCursor, length: 1)
        var readRangeValue = readRange
        guard let axRange = AXValueCreate(.cfRange, &readRangeValue) else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to create AXValue")
            return nil
        }

        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &text
        ) == .success else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to read text")
            return nil
        }

        guard let charString = text as? String, let char = charString.first else {
            debugCallback?("  [AX] getCharacterAfterCursor: Text is empty")
            return nil
        }

        debugCallback?("  [AX] getCharacterAfterCursor: char='\(char)' isWhitespace=\(char.isWhitespace)")

        // Return nil if it's whitespace (word boundary)
        if char.isWhitespace || char.isNewline {
            return nil
        }

        return char
    }



    /// Determine if Forward Delete should be sent for autocomplete method (Firefox/Safari address bar)
    /// Unlike shouldSendForwardDelete(), this doesn't check fixAutocomplete setting
    /// because autocomplete method ALWAYS needs Forward Delete to clear browser autosuggestions
    /// Only skips Forward Delete if:
    /// 1. Typing mid-sentence (cursor was moved)
    /// 2. AX API confirms text after cursor
    private func shouldSendForwardDeleteForAutocomplete() -> Bool {
        // Don't send if we know cursor was moved (typing mid-sentence)
        if isTypingMidSentence {
            debugCallback?("  [FwdDel-AC] Skipped: isTypingMidSentence=true")
            return false
        }

        // Check via Accessibility API if there's text after cursor
        if let hasTextAfter = hasTextAfterCursor() {
            if hasTextAfter {
                debugCallback?("  [FwdDel-AC] Skipped: AX detected text after cursor")
                return false
            } else {
                debugCallback?("  [FwdDel-AC] Allowed: AX confirmed no text after cursor")
                return true
            }
        }

        // AX not supported - ALLOW Forward Delete
        // Same reasoning as shouldSendForwardDelete(): isTypingMidSentence was already checked.
        // If user hasn't pressed Enter, clicked, or moved cursor, Forward Delete is safe.
        debugCallback?("  [FwdDel-AC] Allowed: AX not supported, but isTypingMidSentence=false")
        return true
    }

    /// Send a string of characters (legacy method, sends one char at a time)
    func sendString(_ string: String, proxy: CGEventTapProxy) {
        for char in string.unicodeScalars {
            sendUnicodeCharacter(char, proxy: proxy)
        }
    }
    
    /// Send text in chunks (up to 20 chars per CGEvent) for better performance
    /// CGEvent has a 20-character limit per keyboardSetUnicodeString call
    /// Special handling for newline/tab: splits text and sends as key events
    private func sendTextChunked(_ text: String, delay: UInt32, proxy: CGEventTapProxy) {
        // Use the internal version with useDirectPost = false
        sendTextChunkedInternal(text, delay: delay, proxy: proxy, useDirectPost: false)
    }
    
    /// Send text one character at a time (for Safari/Google Docs compatibility)
    /// Some apps don't handle multiple Unicode characters in a single CGEvent properly
    /// Special handling for newline/tab: sends key events instead of Unicode
    private func sendTextOneByOne(_ text: String, delay: UInt32, proxy: CGEventTapProxy) {
        // Use the internal version with useDirectPost = false
        sendTextOneByOneInternal(text, delay: delay, proxy: proxy, useDirectPost: false)
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

    private func sendKeyPress(_ keyCode: CGKeyCode, proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }

        // Create key down event
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            // Mark as XKey-injected event to prevent re-processing by event tap
            keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            
            // For slow method (terminals), post directly to session event tap
            // This avoids race conditions where tapPostEvent can cause timing issues
            if useDirectPost {
                keyDown.post(tap: .cgSessionEventTap)
            } else {
                keyDown.tapPostEvent(proxy)
            }
        }

        // Create key up event
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            // Mark as XKey-injected event to prevent re-processing by event tap
            keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            
            if useDirectPost {
                keyUp.post(tap: .cgSessionEventTap)
            } else {
                keyUp.tapPostEvent(proxy)
            }
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

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

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
        
        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        
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
        
        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        
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
        
        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        
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

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

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

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

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
    

    // MARK: - Injection Method Detection
    
    /// Get injection method for current context
    /// Uses confirmed method from AppBehaviorDetector (set on mouse click/app switch)
    /// This avoids repeated AX API calls and timing issues
    func detectInjectionMethod() -> InjectionMethodInfo {
        // Use AppBehaviorDetector's confirmed method (Single Source of Truth)
        let methodInfo = AppBehaviorDetector.shared.getConfirmedInjectionMethod()
        
        debugCallback?("🌟 detectMethod: \(methodInfo.description) → \(methodInfo.method), textMode=\(methodInfo.textSendingMethod)")
        
        return methodInfo
    }
    
    /// Clear method cache (call when app changes)
    /// Delegates to AppBehaviorDetector which manages the confirmed method
    func clearMethodCache() {
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        AppBehaviorDetector.shared.clearCache()
    }
}

