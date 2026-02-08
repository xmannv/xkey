//
//  AdvancedInjectionMethods.swift
//  XKey
//
//  Advanced injection methods for special apps
//  These methods are ready to be integrated when needed
//

import Cocoa
import Carbon

// MARK: - Advanced Injection Methods (Library)
// These are additional injection methods that can be activated for specific apps
// Currently not integrated into the main injection flow

/// Advanced injection utilities for special cases
/// - selectAll: For apps with aggressive autocomplete (Arc browser)
/// - axDirect: For apps where synthetic keyboard events don't work (Spotlight, Firefox)
class AdvancedInjectionMethods {
    
    static let shared = AdvancedInjectionMethods()

    /// Event marker for XKey-injected events
    private let kEventMarker: Int64 = 0x584B4559  // "XKEY" in hex

    /// Session buffer for selectAll method - tracks full text typed in session
    private var sessionBuffer: String = ""

    /// Debug callback for logging
    var debugCallback: ((String) -> Void)?

    private init() {}
    
    // MARK: - Session Buffer Management
    
    /// Update session buffer with new composed text
    /// Called before injection to track full session text
    func updateSessionBuffer(backspace: Int, newText: String) {
        if backspace > 0 && sessionBuffer.count >= backspace {
            sessionBuffer.removeLast(backspace)
        }
        sessionBuffer.append(newText)
    }
    
    /// Clear session buffer (call on focus change, submit, etc.)
    func clearSessionBuffer() {
        sessionBuffer = ""
    }
    
    /// Set session buffer to specific value (for restoring after paste, etc.)
    func setSessionBuffer(_ text: String) {
        sessionBuffer = text
    }
    
    /// Get current session buffer
    func getSessionBuffer() -> String {
        return sessionBuffer
    }
    
    // MARK: - Select All Injection
    // For apps with aggressive autocomplete (Arc browser)
    // Instead of backspace + text, this method:
    // 1. Selects all text (Cmd+Home + Shift+Cmd+End)
    // 2. Types the full session buffer to replace
    
    /// Select All injection: Select all text then type full session buffer
    /// Used for apps with aggressive autocomplete (Arc, Spotlight on macOS 13)
    /// Session buffer tracks ALL text typed in this session, not just current word
    ///
    /// - Parameter proxy: Event tap proxy for posting events
    func injectViaSelectAll(proxy: CGEventTapProxy) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        
        // Get full session buffer (all text typed in this session)
        let fullText = sessionBuffer
        guard !fullText.isEmpty else { return }
        
        // Select all using Cmd+Left (home) + Shift+Cmd+Right (select to end)
        // This works better in Arc browser than Cmd+A
        let leftArrowKeyCode: CGKeyCode = CGKeyCode(VietnameseData.KEY_LEFT)
        let rightArrowKeyCode: CGKeyCode = CGKeyCode(VietnameseData.KEY_RIGHT)
        
        // Cmd+Left = Home
        postKey(leftArrowKeyCode, source: source, flags: .maskCommand, proxy: proxy)
        usleep(5000)
        
        // Shift+Cmd+Right = Select to end
        postKey(rightArrowKeyCode, source: source, flags: [.maskCommand, .maskShift], proxy: proxy)
        usleep(5000)
        
        // Type full session buffer (replaces all selected text)
        postText(fullText, source: source, proxy: proxy)
    }
    
    // MARK: - AX Direct Injection
    // For apps where synthetic keyboard events don't work (Spotlight, Firefox)
    // Uses Accessibility API to directly manipulate text field value
    
    /// AX API injection: Directly manipulate text field via Accessibility API
    /// Used for Spotlight/Arc where synthetic keyboard events are unreliable due to autocomplete
    ///
    /// - Parameters:
    ///   - bs: Number of characters to backspace
    ///   - text: Replacement text to insert
    /// - Returns: true if successful, false if caller should fallback to synthetic events
    func injectViaAX(bs: Int, text: String) -> Bool {
        // Get focused element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let ref = focusedRef else {
            debugCallback?("[AX] No focused element")
            return false
        }
        let axEl = ref as! AXUIElement
        
        // Read current text value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &valueRef) == .success else {
            debugCallback?("[AX] No value attribute")
            return false
        }
        let fullText = (valueRef as? String) ?? ""
        
        // Read cursor position and selection
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axEl, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let axRange = rangeRef else {
            debugCallback?("[AX] No selected text range")
            return false
        }
        var range = CFRange()
        guard AXValueGetValue(axRange as! AXValue, .cfRange, &range), range.location >= 0 else {
            debugCallback?("[AX] Invalid range")
            return false
        }
        
        let cursor = range.location
        let selection = range.length
        
        // Handle autocomplete: when selection > 0, text after cursor is autocomplete suggestion
        // Example: "a|rc://chrome-urls" where "|" is cursor, "rc://..." is selected suggestion
        let userText = (selection > 0 && cursor <= fullText.count)
            ? String(fullText.prefix(cursor))
            : fullText
        
        // Calculate replacement: delete `bs` chars before cursor, insert `text`
        let deleteStart = max(0, cursor - bs)
        let prefix = String(userText.prefix(deleteStart))
        let suffix = String(userText.dropFirst(cursor))
        let newText = (prefix + text + suffix).precomposedStringWithCanonicalMapping
        
        // Write new value
        guard AXUIElementSetAttributeValue(axEl, kAXValueAttribute as CFString, newText as CFTypeRef) == .success else {
            debugCallback?("[AX] Write failed")
            return false
        }
        
        // Update cursor to end of inserted text
        var newCursor = CFRange(location: deleteStart + text.count, length: 0)
        if let newRange = AXValueCreate(.cfRange, &newCursor) {
            AXUIElementSetAttributeValue(axEl, kAXSelectedTextRangeAttribute as CFString, newRange)
        }

        debugCallback?("[AX] Success: bs=\(bs), text=\(text)")
        return true
    }
    
    /// Try AX injection with retries, fallback to callback if all fail
    /// Spotlight can be busy searching, causing AX API to fail temporarily
    ///
    /// - Parameters:
    ///   - bs: Number of characters to backspace
    ///   - text: Replacement text to insert
    ///   - fallback: Closure to call if AX injection fails
    /// - Note: NOT YET INTEGRATED - Ready for future use
    func injectViaAXWithFallback(bs: Int, text: String, fallback: () -> Void) {
        // Try AX API up to 3 times (Spotlight might be busy)
        for attempt in 0..<3 {
            if attempt > 0 {
                usleep(5000)  // 5ms delay before retry
            }
            if injectViaAX(bs: bs, text: text) {
                return  // Success!
            }
        }
        
        // All AX attempts failed - call fallback
        debugCallback?("[AX] Fallback to synthetic events")
        fallback()
    }
    
    // MARK: - Private Helpers
    
    /// Post a single key press event
    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource, flags: CGEventFlags = [], proxy: CGEventTapProxy? = nil) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        
        keyDown.setIntegerValueField(.eventSourceUserData, value: kEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kEventMarker)
        
        if !flags.isEmpty {
            keyDown.flags = flags
            keyUp.flags = flags
        }
        
        if let proxy = proxy {
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
        } else {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
    }
    
    /// Post text in chunks (CGEvent has 20-char limit)
    private func postText(_ text: String, source: CGEventSource, delay: UInt32 = 0, proxy: CGEventTapProxy? = nil) {
        let utf16 = Array(text.utf16)
        var offset = 0
        let chunkSize = 20
        
        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { break }
            
            keyDown.setIntegerValueField(.eventSourceUserData, value: kEventMarker)
            keyUp.setIntegerValueField(.eventSourceUserData, value: kEventMarker)
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            
            if let proxy = proxy {
                keyDown.tapPostEvent(proxy)
                keyUp.tapPostEvent(proxy)
            } else {
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
            }
            
            if delay > 0 { usleep(delay) }
            offset = end
        }
    }
}

// MARK: - Usage Example
/*
 
 To integrate selectAll method:
 1. Add `.selectAll` to InjectionMethod enum in AppBehaviorDetector.swift
 2. Configure apps that need it in detectMethodForBundleId()
 3. In CharacterInjector.injectSync(), add case for .selectAll:
 
    case .selectAll:
        AdvancedInjectionMethods.shared.updateSessionBuffer(backspace: backspaceCount, newText: charPreview)
        AdvancedInjectionMethods.shared.injectViaSelectAll(proxy: proxy)
 
 To integrate axDirect method:
 1. Add `.axDirect` to InjectionMethod enum in AppBehaviorDetector.swift
 2. Configure apps that need it (Spotlight, Firefox, Arc)
 3. In CharacterInjector.injectSync(), add case for .axDirect:
 
    case .axDirect:
        AdvancedInjectionMethods.shared.injectViaAXWithFallback(bs: backspaceCount, text: charPreview) {
            // Fallback to autocomplete method
            injectViaAutocompleteInternal(count: backspaceCount, delays: delays, proxy: proxy)
            sendTextChunkedInternal(charPreview, delay: delays.text, proxy: proxy, useDirectPost: false)
        }
 
 */
