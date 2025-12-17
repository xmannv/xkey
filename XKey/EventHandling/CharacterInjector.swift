//
//  CharacterInjector.swift
//  XKey
//
//  Injects Vietnamese characters into the system
//

import Cocoa
import Carbon

// MARK: - Injection Method

/// Injection method for different app types
/// Adaptive delays for Terminal/JetBrains/Electron compatibility
enum InjectionMethod {
    case fast           // Default: backspace + text with minimal delays
    case slow           // Terminals/IDEs: backspace + text with higher delays
    case selection      // Browser address bars: Shift+Left select + type replacement
    case autocomplete   // Spotlight: Forward Delete + backspace + text
}

/// Injection delays in microseconds (backspace, wait, text)
typealias InjectionDelays = (backspace: UInt32, wait: UInt32, text: UInt32)

class CharacterInjector {
    
    // MARK: - Properties
    
    private var eventSource: CGEventSource?
    private var isFirstWord: Bool = true  // Track if we're typing the first word
    private var keystrokeCount: Int = 0   // Track number of keystrokes in current word
    private var isTypingMidSentence: Bool = false  // Track if user moved cursor (typing in middle of text)
    private var lastInjectionTime: UInt64 = 0  // Track when last character was injected (mach_absolute_time)
    private static let injectionCooldownNs: UInt64 = 15_000_000  // 15ms cooldown between injections
    
    // Cached injection method to avoid repeated detection
    private var cachedMethod: InjectionMethod?
    private var cachedDelays: InjectionDelays?
    private var cachedBundleId: String?
    
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
    /// - Parameter cursorMoved: true if cursor was moved by user (mouse click or arrow keys)
    func markNewSession(cursorMoved: Bool = false) {
        isFirstWord = true
        keystrokeCount = 0
        isTypingMidSentence = cursorMoved  // If cursor moved, we're likely typing in middle of text
        debugCallback?("New session: isFirstWord=true, keystrokeCount=0, isTypingMidSentence=\(cursorMoved)")
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
    
    /// Wait for injection cooldown if needed (call BEFORE processing next keystroke)
    /// This prevents race condition where backspace arrives before previous injection is rendered
    func waitForInjectionCooldown() {
        guard lastInjectionTime > 0 else { return }
        
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let currentTime = mach_absolute_time()
        let elapsedTicks = currentTime - lastInjectionTime
        let elapsedNs = elapsedTicks * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        
        if elapsedNs < CharacterInjector.injectionCooldownNs {
            let remainingNs = CharacterInjector.injectionCooldownNs - elapsedNs
            let remainingUs = UInt32(remainingNs / 1000)
            debugCallback?("    → Injection cooldown: waiting \(remainingUs)µs")
            usleep(remainingUs)
        }
    }
    
    // MARK: - Public Methods

    /// Send backspace key presses with optional autocomplete fix
    /// Uses adaptive delays based on detected app type (Terminal/JetBrains/etc.)
    func sendBackspaces(count: Int, codeTable: CodeTable, proxy: CGEventTapProxy, fixAutocomplete: Bool = false) {
        guard count > 0 else { return }
        
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
    func sendCharacters(_ characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        guard !characters.isEmpty else { return }
        
        // Get injection method and delays
        let (method, delays) = detectInjectionMethod()
        
        debugCallback?("sendCharacters: count=\(characters.count), method=\(method)")
        
        for (index, character) in characters.enumerated() {
            let unicodeString = character.unicode(codeTable: codeTable)
            debugCallback?("  [\(index)]: Sending '\(unicodeString)' (Unicode: \(unicodeString.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")))")
            sendString(unicodeString, proxy: proxy)
            
            // Add delay between characters for slow apps (Terminal/JetBrains)
            if method == .slow && index < characters.count - 1 {
                usleep(delays.text)
            }
        }
        
        // Settle time: longer for slow apps to ensure text is rendered
        let settleTime: UInt32 = (method == .slow) ? 40000 : 5000  // 40ms for slow (Terminal), 5ms for fast
        usleep(settleTime)
        
        // Record injection time for cooldown tracking
        lastInjectionTime = mach_absolute_time()
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
    
    // MARK: - Injection Method Detection
    
    /// Detect injection method based on frontmost app and focused element
    /// Uses adaptive delays for Terminal/JetBrains/Electron compatibility
    func detectInjectionMethod() -> (InjectionMethod, InjectionDelays) {
        // Get focused element and its owning app
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        var role: String?
        var bundleId: String?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            
            // Get role
            var roleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, kAXRoleAttribute as CFString, &roleVal)
            role = roleVal as? String
            
            // Get owning app's bundle ID
            var pid: pid_t = 0
            if AXUIElementGetPid(axEl, &pid) == .success {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    bundleId = app.bundleIdentifier
                }
            }
        }
        
        // Fallback to frontmost app
        if bundleId == nil {
            bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        
        guard let bundleId = bundleId else {
            return (.fast, (200, 800, 500))
        }
        
        // Cache check - avoid repeated detection for same app
        if bundleId == cachedBundleId, let method = cachedMethod, let delays = cachedDelays {
            debugCallback?("    → detectMethod (cached): \(bundleId) → \(method)")
            return (method, delays)
        }
        
        cachedBundleId = bundleId
        
        debugCallback?("    → detectMethod: \(bundleId) role=\(role ?? "nil")")
        
        // Selection method for autocomplete UI elements (ComboBox, SearchField)
        if role == "AXComboBox" {
            debugCallback?("    → Method: selection (ComboBox)")
            cachedMethod = .selection
            cachedDelays = (1000, 3000, 2000)
            return (.selection, (1000, 3000, 2000))
        }
        if role == "AXSearchField" {
            debugCallback?("    → Method: selection (SearchField)")
            cachedMethod = .selection
            cachedDelays = (1000, 3000, 2000)
            return (.selection, (1000, 3000, 2000))
        }
        
        // Spotlight - use autocomplete method
        if bundleId == "com.apple.Spotlight" {
            debugCallback?("    → Method: autocomplete (Spotlight)")
            cachedMethod = .autocomplete
            cachedDelays = (1000, 3000, 1000)
            return (.autocomplete, (1000, 3000, 1000))
        }
        
        // Browser address bars (AXTextField with autocomplete)
        let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
                        "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox", 
                        "com.operasoftware.Opera", "com.vivaldi.Vivaldi"]
        if browsers.contains(bundleId) && role == "AXTextField" {
            debugCallback?("    → Method: selection (browser address bar)")
            cachedMethod = .selection
            cachedDelays = (1000, 3000, 2000)
            return (.selection, (1000, 3000, 2000))
        }
        
        // JetBrains IDEs - TextField uses selection, others use slow with higher delays
        if bundleId.hasPrefix("com.jetbrains") {
            if role == "AXTextField" {
                debugCallback?("    → Method: selection (JetBrains TextField)")
                cachedMethod = .selection
                cachedDelays = (1000, 3000, 2000)
                return (.selection, (1000, 3000, 2000))
            }
            debugCallback?("    → Method: slow (JetBrains IDE)")
            cachedMethod = .slow
            // Higher delays for JetBrains: 6ms backspace, 15ms wait, 6ms text
            cachedDelays = (6000, 15000, 6000)
            return (.slow, (6000, 15000, 6000))
        }
        
        // Microsoft Office apps
        if bundleId == "com.microsoft.Excel" || bundleId == "com.microsoft.Word" {
            debugCallback?("    → Method: selection (Microsoft Office)")
            cachedMethod = .selection
            cachedDelays = (1000, 3000, 2000)
            return (.selection, (1000, 3000, 2000))
        }
        
        // Terminal apps - high delays for reliability (Warp, iTerm2, etc.)
        let terminals = [
            // Terminals
            "com.apple.Terminal", "com.googlecode.iterm2", "io.alacritty",
            "com.github.wez.wezterm", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty", "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio",
            "com.termius-dmg.mac"
        ]
        if terminals.contains(bundleId) {
            debugCallback?("    → Method: slow (Terminal)")
            cachedMethod = .slow
            // High delays for terminal reliability: 12ms backspace, 30ms wait, 12ms text
            cachedDelays = (12000, 30000, 12000)
            return (.slow, (12000, 30000, 12000))
        }
        
        // Default: fast with safe delays
        debugCallback?("    → Method: fast (default)")
        cachedMethod = .fast
        cachedDelays = (1000, 3000, 1500)
        return (.fast, (1000, 3000, 1500))
    }
    
    /// Clear cached injection method (call when app changes)
    func clearMethodCache() {
        cachedMethod = nil
        cachedDelays = nil
        cachedBundleId = nil
    }
}

