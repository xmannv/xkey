//
//  CharacterInjector.swift
//  XKey
//
//  Injects Vietnamese characters into the system
//

import Cocoa
import Carbon

class CharacterInjector {
    
    // MARK: - Properties
    
    private var eventSource: CGEventSource?
    private var isFirstWord: Bool = true  // Track if we're typing the first word
    private var keystrokeCount: Int = 0   // Track number of keystrokes in current word
    
    // Debug callback
    var debugCallback: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }
    
    // MARK: - Word Tracking
    
    /// Reset first word flag (call when space/enter is pressed)
    func resetFirstWord() {
        isFirstWord = false
        debugCallback?("Reset first word: isFirstWord=false")
    }
    
    /// Mark as new input session (call when cursor moves or new field focused)
    func markNewSession() {
        isFirstWord = true
        keystrokeCount = 0
        debugCallback?("New session: isFirstWord=true, keystrokeCount=0")
    }
    
    /// Reset keystroke count for new word (call when space/enter is pressed)
    func resetKeystrokeCount() {
        keystrokeCount = 0
        debugCallback?("Reset keystroke count: keystrokeCount=0")
    }
    
    /// Increment keystroke count (call after each keystroke)
    func incrementKeystroke() {
        keystrokeCount += 1
        debugCallback?("Keystroke count: \(keystrokeCount)")
    }
    
    // MARK: - Public Methods

    /// Send backspace key presses with optional autocomplete fix
    func sendBackspaces(count: Int, codeTable: CodeTable, proxy: CGEventTapProxy, fixAutocomplete: Bool = false) {
        // For Chrome: handle duplicate first character issue
        // Only the first character gets duplicated (Chrome receives both original and injected)
        // Subsequent characters work normally
        // Chrome fix: Disabled for now due to conflicts between address bar and text fields
        // Address bar and text fields behave differently, making it hard to fix both
        // Users should disable Vietnamese input when typing in Chrome address bar
        // or use the search box instead
        if fixAutocomplete && isChromiumBrowser() {
            // Just send normal backspaces
            for _ in 0..<count {
                sendBackspace(codeTable: codeTable, proxy: proxy)
            }
            return
        }
        
        guard count > 0 else { return }
        
        if fixAutocomplete {
            // For other apps, send empty character first, then increase backspace count
            sendEmptyCharacter(proxy: proxy)
            for _ in 0..<(count + 1) {
                sendBackspace(codeTable: codeTable, proxy: proxy)
            }
        } else {
            // Normal backspace without autocomplete fix
            for _ in 0..<count {
                sendBackspace(codeTable: codeTable, proxy: proxy)
            }
        }
    }


    
    /// Send Vietnamese characters
    func sendCharacters(_ characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        debugCallback?("sendCharacters: count=\(characters.count)")
        
        for (index, character) in characters.enumerated() {
            let unicodeString = character.unicode(codeTable: codeTable)
            debugCallback?("  [\(index)]: Sending '\(unicodeString)' (Unicode: \(unicodeString.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")))")
            sendString(unicodeString, proxy: proxy)
        }
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

    /// Send a string of characters
    func sendString(_ string: String, proxy: CGEventTapProxy) {
        for char in string.unicodeScalars {
            sendUnicodeCharacter(char, proxy: proxy)
        }
    }
    
    // MARK: - Private Methods

    private func sendBackspace(codeTable: CodeTable, proxy: CGEventTapProxy) {
        let deleteKeyCode: CGKeyCode = 0x33 // Delete/Backspace key

        // For VNI and Unicode Compound, some characters require double backspace
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1

        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy)
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
    
    /// Check if currently focused element is Chrome address bar
    private func isChromeAddressBar() -> Bool {
        guard isChromiumBrowser() else {
            return false
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return false
        }
        
        let element = focusedElement as! AXUIElement
        
        // Get role of focused element
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let roleString = role as? String else {
            return false
        }
        
        // Get subrole if available
        var subrole: CFTypeRef?
        let hasSubrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success
        let subroleString = subrole as? String
        
        // Get description if available
        var description: CFTypeRef?
        let hasDescription = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) == .success
        let descriptionString = description as? String
        
        // Get identifier if available
        var identifier: CFTypeRef?
        let hasIdentifier = AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifier) == .success
        let identifierString = identifier as? String
        
        debugCallback?("      [AX] Role: \(roleString)")
        if let subroleString = subroleString {
            debugCallback?("      [AX] Subrole: \(subroleString)")
        }
        if let descriptionString = descriptionString {
            debugCallback?("      [AX] Description: \(descriptionString)")
        }
        if let identifierString = identifierString {
            debugCallback?("      [AX] Identifier: \(identifierString)")
        }
        
        // Chrome address bar typically has:
        // - Role: AXTextField
        // - Subrole: AXSearchField or contains "address" in description
        // - Or identifier contains "omnibox"
        
        if roleString == kAXTextFieldRole as String {
            // Check subrole
            if let subroleString = subroleString, subroleString == "AXSearchField" {
                debugCallback?("  [AX] Detected address bar (AXSearchField)")
                return true
            }
            
            // Check description
            if let descriptionString = descriptionString?.lowercased(),
               descriptionString.contains("address") || descriptionString.contains("url") {
                debugCallback?("  [AX] Detected address bar (description)")
                return true
            }
            
            // Check identifier
            if let identifierString = identifierString?.lowercased(),
               identifierString.contains("omnibox") || identifierString.contains("address") {
                debugCallback?("  [AX] Detected address bar (identifier)")
                return true
            }
        }
        
        return false
    }
    
    /// Check if we're in Chrome address bar (for special handling)
    func isInChromeAddressBar() -> Bool {
        return isChromeAddressBar()
    }
    
    /// Get current keystroke count (for Chrome address bar detection)
    func getKeystrokeCount() -> Int {
        return keystrokeCount
    }
    
    /// Check and fix duplicate BEFORE backspace (Chrome address bar fix ONLY)
    func checkAndFixChromeAddressBarDuplicate(proxy: CGEventTapProxy) {
        let isAddressBar = isChromeAddressBar()
        
        debugCallback?("    → Chrome fix check: isAddressBar=\(isAddressBar), isFirstWord=\(isFirstWord), keystrokeCount=\(keystrokeCount)")
        
        // Only apply fix for Chrome ADDRESS BAR, not content area
        guard isAddressBar else {
            debugCallback?("    → Chrome fix: Not address bar, skipping")
            return
        }
        
        // Only apply fix for FIRST WORD ONLY, starting from keystroke 2
        // Chrome address bar duplicates characters in the first word only
        // Subsequent words work normally
        guard isFirstWord && keystrokeCount >= 2 else {
            debugCallback?("    → Chrome fix: Wrong timing (need isFirstWord=true, keystrokeCount>=2)")
            return
        }
        
        debugCallback?("    → ✓ Chrome address bar fix: Applying fix at keystroke \(keystrokeCount) (FIRST WORD)")
        
        // Chrome duplicates injected characters in the first word
        // For each keystroke after the first, we need to remove the duplicate
        // Example:
        // - Keystroke 1: "m" → Chrome has "mm" (original + injected)
        // - Keystroke 2: "o" → Need to remove 1 duplicate "m" first
        // - Keystroke 3: "a" → Need to remove 1 duplicate from previous injection
        
        debugCallback?("    → ✓ Chrome fix: Sending backspace to remove duplicate")
        sendKeyPress(0x33, proxy: proxy) // Backspace to remove duplicate
        usleep(2000) // 2ms delay after cleanup
        
        debugCallback?("    → ✓ Chrome fix: Duplicate removed")
    }
}

