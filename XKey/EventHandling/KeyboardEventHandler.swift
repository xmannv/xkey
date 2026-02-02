//
//  KeyboardEventHandler.swift
//  XKey
//
//  Handles keyboard events and coordinates between engine and injector
//

import Cocoa
import Combine

class KeyboardEventHandler: EventTapManager.EventTapDelegate {
    
    // MARK: - Properties

    let engine: VNEngine  // Made public for debug access
    private let injector: CharacterInjector
    private var isVietnameseEnabled = true

    // Debug logging callback
    var debugLogCallback: ((String) -> Void)?
    
    /// Enable verbose engine logging (causes lag when enabled!)
    /// Only turn on for debugging specific issues
    var verboseEngineLogging: Bool = false
    
    /// Flag to skip updateEngineSettings() during batch updates
    /// This prevents multiple redundant engine updates when applying all settings at once
    private var isBatchUpdating = false

    // Settings
    @Published var inputMethod: InputMethod = .telex {
        didSet { updateEngineSettings() }
    }
    
    @Published var codeTable: CodeTable = .unicode {
        didSet { updateEngineSettings() }
    }
    
    @Published var modernStyle: Bool = true {
        didSet { updateEngineSettings() }
    }
    
    @Published var spellCheckEnabled: Bool = true {
        didSet { updateEngineSettings() }
    }
    

    
    // Advanced features
    @Published var quickTelexEnabled: Bool = true {
        didSet { updateEngineSettings() }
    }
    
    @Published var quickStartConsonantEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var quickEndConsonantEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var upperCaseFirstChar: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var restoreIfWrongSpelling: Bool = true {
        didSet { updateEngineSettings() }
    }
    

    
    @Published var allowConsonantZFWJ: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var freeMarkEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    // Macro settings
    @Published var macroEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var macroInEnglishMode: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var autoCapsMacro: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var addSpaceAfterMacro: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    // Smart switch
    @Published var smartSwitchEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    // Excluded apps
    @Published var excludedApps: [ExcludedApp] = []

    // Undo typing with Esc key
    @Published var undoTypingEnabled: Bool = false

    // Managers
    private let macroManager = MacroManager()
    private let smartSwitchManager = SmartSwitchManager()
    
    // MARK: - Initialization
    
    init() {
        self.engine = VNEngine()
        self.injector = CharacterInjector()

        // Set up engine logging (only logs when verboseEngineLogging is enabled)
        self.engine.logCallback = { [weak self] message in
            guard let self = self, self.verboseEngineLogging else { return }
            self.debugLogCallback?("Engine: \(message)")
        }
        
        // Set up injector debug logging (only logs when verboseEngineLogging is enabled)
        self.injector.debugCallback = { [weak self] message in
            guard let self = self, self.verboseEngineLogging else { return }
            self.debugLogCallback?("Injector: \(message)")
        }

        // Share managers with VNEngine

        VNEngine.setSharedMacroManager(macroManager)
        VNEngine.setSharedSmartSwitchManager(smartSwitchManager)

        // Macro manager logging disabled for cleaner output
        // macroManager.logCallback = { [weak self] message in
        //     self?.debugLogCallback?("📦 Macro: \(message)")
        // }
        
        // Load macro data from plist
        loadMacrosFromPlist()
        
        // Load smart switch data from file
        loadSmartSwitchData()
        
        // Listen for macro changes from UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMacrosDidChange),
            name: .macrosDidChange,
            object: nil
        )
        

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleMacrosDidChange() {
        loadMacrosFromPlist()
        
        // Reset engine to clear buffer when macros change
        // This prevents stale buffer from interfering with new macro matching
        engine.reset()
        injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state when macros change
    }
    
    // MARK: - Smart Switch Data Loading
    
    private func loadSmartSwitchData() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let xkeyDir = appSupport.appendingPathComponent("XKey")
        let path = xkeyDir.appendingPathComponent("smart_switch.json").path

        _ = smartSwitchManager.loadFromFile(path: path)
    }
    
    // MARK: - Macro Data Loading
    
    private func loadMacrosFromPlist() {
        // Clear existing macros first to avoid duplicates
        macroManager.clearAll()
        
        if let data = SharedSettings.shared.getMacrosData(),
           let macros = try? JSONDecoder().decode([MacroItemData].self, from: data) {
            for macro in macros {
                _ = macroManager.addMacro(text: macro.text, content: macro.content)
            }
        }
    }
    
    /// Simple struct for decoding macro data
    private struct MacroItemData: Codable {
        let id: UUID
        let text: String
        let content: String
    }
    
    // MARK: - Debug (removed - now using print statements)
    
    // MARK: - Vietnamese Toggle
    
    func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        // Update engine's vLanguage to match
        engine.vLanguage = isVietnameseEnabled ? 1 : 0
        if !isVietnameseEnabled {
            engine.reset()
        }
    }
    
    func setVietnamese(_ enabled: Bool) {
        isVietnameseEnabled = enabled
        // Update engine's vLanguage to match
        engine.vLanguage = enabled ? 1 : 0
        if !enabled {
            engine.reset()
        }
    }
    
    // MARK: - Undo Typing
    
    /// Perform undo typing operation when triggered by EventTapManager hotkey callback
    /// Returns true if undo was performed (event should be consumed), false otherwise
    func performUndoTyping() -> Bool {
        guard undoTypingEnabled else { return false }
        guard engine.canUndoTyping() else { return false }
        
        let result = engine.undoTyping()
        guard result.shouldConsume else { return false }
        
        // Build the replacement text
        var replacementText = ""
        for vnChar in result.newCharacters {
            replacementText += vnChar.unicode(codeTable: codeTable)
        }
        
        debugLogCallback?("🔙 Undo typing: backspaces=\(result.backspaceCount), text=\"\(replacementText)\"")
        
        // Use privateState to isolate from system event state (same as CharacterInjector)
        guard let source = CGEventSource(stateID: .privateState) else {
            debugLogCallback?("🔙 Failed to create event source")
            return false
        }
        
        // Step 1: Send backspaces
        if result.backspaceCount > 0 {
            for i in 0..<result.backspaceCount {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                    keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    keyDown.post(tap: .cgSessionEventTap)
                    keyUp.post(tap: .cgSessionEventTap)
                    debugLogCallback?("🔙   Backspace \(i + 1)/\(result.backspaceCount)")
                }
                // Small delay between backspaces
                usleep(3000)  // 3ms
            }
            // Wait after backspaces
            usleep(10000)  // 10ms
        }
        
        // Step 2: Send replacement characters
        if !replacementText.isEmpty {
            // Send text in one chunk using keyboardSetUnicodeString
            var utf16Chars = Array(replacementText.utf16)
            
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
                keyUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
                
                keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
                
                debugLogCallback?("🔙   Sent text: \"\(replacementText)\"")
            }
        }
        
        // Mark new session after undo, preserve mid-sentence state
        injector.markNewSession(preserveMidSentence: true)
        
        return true
    }
    
    // MARK: - EventTapDelegate
    
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        // Check if current app is in excluded list
        if isCurrentAppExcluded() {
            return false
        }
        
        // Check if injection method is passthrough - bypass all Vietnamese processing
        // This is checked BEFORE Vietnamese mode check because passthrough applies regardless
        let confirmedMethod = AppBehaviorDetector.shared.getConfirmedInjectionMethod()
        if confirmedMethod.method == .passthrough {
            return false
        }

        // CRITICAL: Skip processing for key repeat events (key being held down)
        // This fixes issues with spring-loaded tools in apps like Adobe Illustrator:
        // - Holding Z for Zoom tool, Space for Hand tool
        // - Key repeat events should pass through immediately without any delay
        // - Only the first keyDown is processed for potential Vietnamese conversion
        // - This prevents timing issues where keyUp arrives before delayed repeat keyDowns
        if type == .keyDown && event.isKeyRepeat {
            return false
        }

        // Check if we should process in English mode (for macro support)
        let shouldProcessInEnglishMode = !isVietnameseEnabled && macroEnabled && macroInEnglishMode

        // Only process key down events when Vietnamese is enabled OR macro in English mode is enabled
        guard isVietnameseEnabled || shouldProcessInEnglishMode else {
            return false
        }

        // For keyDown events, check modifier keys and skip processing if pressed
        // IMPORTANT: Only reset engine for keyDown events, NOT for flagsChanged events
        // For flagsChanged (modifier-only hotkeys like Ctrl+Shift for undo), we don't want
        // to reset the engine because that would clear the undo buffer
        if type == .keyDown {
            // Count active modifiers (excluding Shift for letter uppercase)
            let hasCommand = event.isCommandPressed
            let hasControl = event.isControlPressed
            let hasOption = event.isOptionPressed
            let hasShift = event.flags.contains(.maskShift)
            
            // Calculate number of modifiers pressed
            let modifierCount = (hasCommand ? 1 : 0) + (hasControl ? 1 : 0) + 
                               (hasOption ? 1 : 0) + (hasShift ? 1 : 0)
            
            // Reset engine if there's a key combination:
            // 1. Cmd/Ctrl/Alt + any key (common shortcuts like Cmd+Z, Ctrl+K, Alt+Arrow)
            // 2. 2+ modifiers pressed (like Ctrl+Shift, Cmd+Shift+Z, etc.)
            //
            // This handles all hotkey patterns consistently:
            // - Cmd+C/V/X (copy/paste/cut)
            // - Cmd+Z (undo) - text changes
            // - Cmd+Arrow (word/line navigation)
            // - Ctrl+K (delete line in some editors)
            // - Alt+Arrow (word navigation)
            // - Ctrl+Shift+* (various custom hotkeys)
            //
            // Shift alone with letter is NOT reset (for uppercase typing)
            let hasModifierCombo = hasCommand || hasControl || hasOption || modifierCount >= 2
            
            if hasModifierCombo {
                // Check if this is a cursor movement key
                let keyCode = event.keyCode
                let cursorMovementKeys: [CGKeyCode] = [0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79] // Arrow keys, Home, End, Page Up/Down
                let isCursorMovement = cursorMovementKeys.contains(keyCode)
                
                if isCursorMovement {
                    // CRITICAL FIX: Use resetWithCursorMoved() to properly set the flag
                    // This ensures history is cleared and restore logic is skipped
                    // Previously, engine.reset() was called which didn't set cursorMovedSinceReset
                    engine.resetWithCursorMoved()
                    injector.markNewSession(cursorMoved: true)
                } else {
                    // Other combos (Cmd+C/V/Z, Ctrl+K, etc.) → preserve mid-sentence state
                    // These don't move cursor position, so keep existing flag value
                    engine.reset()
                    injector.markNewSession(preserveMidSentence: true)
                }
                return false
            }
        }



        return true
    }
    
    // Helper to get timestamp for debug logging
    private func getTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent? {
        guard type == .keyDown else {
            return event
        }

        // Get physical key code
        let keyCode = event.keyCode

        // Handle special keys BEFORE qwertyCharacter mapping
        // These keys need special handling and don't need character conversion

        // Handle Backspace/Delete
        if keyCode == 0x33 {
            debugLogCallback?("[\(getTimestamp())] ⌫ BACKSPACE received (keyCode=0x33)")
            return handleBackspace(event: event, proxy: proxy)
        }

        // Handle cursor movement keys - reset engine as focus might have changed
        let cursorMovementKeys: [CGKeyCode] = [
            0x7B, // Left Arrow
            0x7C, // Right Arrow
            0x7D, // Down Arrow
            0x7E, // Up Arrow
            0x73, // Home
            0x77, // End
            0x74, // Page Up
            0x79  // Page Down
        ]

        if cursorMovementKeys.contains(keyCode) {
            let keyName: String
            switch keyCode {
            case 0x7B: keyName = "←"
            case 0x7C: keyName = "→"
            case 0x7D: keyName = "↓"
            case 0x7E: keyName = "↑"
            case 0x73: keyName = "Home"
            case 0x77: keyName = "End"
            case 0x74: keyName = "PgUp"
            case 0x79: keyName = "PgDn"
            default: keyName = "?"
            }
            debugLogCallback?("[\(getTimestamp())] \(keyName) Arrow/Nav key received (keyCode=0x\(String(format: "%02X", keyCode)))")
            engine.resetWithCursorMoved()  // Use new method that sets cursor moved flag
            injector.markNewSession(cursorMoved: true)  // Mark that cursor was moved
            return event
        }

        // Handle Tab key - reset engine but preserve mid-sentence state
        // Tab adds indentation/whitespace, it doesn't move to a new field
        // When user types Enter + Tab (e.g., starting a new indented line in code),
        // they may still have text on the right side. Forward Delete must be blocked.
        // NOTE: Only real field switches (like Tab in a form) should reset mid-sentence,
        // but we can't distinguish that from regular Tab, so preserve state to be safe.
        if keyCode == 0x30 { // Tab
            engine.reset()
            injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state
            return event
        }

        // NOTE: Escape key undo is now handled by EventTapManager (via undoTypingHotkey)
        // This allows both default Esc and custom hotkeys (like Ctrl+Shift) to work consistently
        // through the same code path (performUndoTyping callback)

        // Handle Forward Delete (Fn+Delete)
        if keyCode == 0x75 { // Forward Delete
            engine.reset()
            injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state after Forward Delete
            return event  // Pass through
        }

        // CRITICAL: Get character directly from the event
        // When using Input Sources like Swiss French, macOS already handles the layout conversion
        // The character we receive is what the user expects to type
        // For example, with Swiss French QWERTZ:
        //   - User presses physical 'Z' key (where Y is on QWERTZ)
        //   - macOS sends: keyCode=0x10 (QWERTY Y position), character='z' (Swiss French mapping)
        //   - We should use character='z' for Telex processing

        // Get character from event (respects current Input Source)
        guard let characters = event.characters,
              let character = characters.first else {
            return event
        }

        // Determine if Shift/CapsLock is pressed
        let hasShiftModifier = event.flags.contains(.maskShift)
        let hasCapsLock = event.flags.contains(.maskAlphaShift)

        // Determine if uppercase:
        // - For letters: Shift XOR Caps Lock (standard behavior)
        // - For non-letters: use the character as-is
        let isLetter = character.isLetter
        let isUppercase = isLetter ? (hasShiftModifier != hasCapsLock) : character.isUppercase

        // Convert character to QWERTY keyCode for engine processing
        // Engine expects keyCode based on QWERTY layout (e.g., 'z' → 0x06)
        // This ensures Vietnamese processing works correctly regardless of Input Source
        let engineKeyCode: CGKeyCode
        if let convertedKeyCode = KeyCodeToCharacter.keyCode(forCharacter: character) {
            engineKeyCode = convertedKeyCode
        } else {
            // Fallback to physical keyCode if character not found in mapping
            engineKeyCode = keyCode
        }

        // Check if we're in English mode with macro support
        let isEnglishModeWithMacro = !isVietnameseEnabled && macroEnabled && macroInEnglishMode

        if isWordBreakKey(character) {
            // Log word break key
            let keyName: String
            switch character {
            case " ": keyName = "SPACE"
            case "\n", "\r": keyName = "ENTER"
            default: keyName = "'\(character)'"
            }
            debugLogCallback?("[\(getTimestamp())] \(keyName) Word-break received (index=\(engine.index), spaceCount=\(engine.spaceCount))")
            
            // IMPORTANT: Check if engine has buffer OR macroKey before processing word break
            // If engine buffer is empty (index == 0) AND no macroKey, it means:
            // 1. User just started typing, OR
            // 2. Editor autocompleted characters (e.g., ":d" → emoji)
            // In both cases, we should NOT process word break with spell check
            // because it would restore/delete the autocompleted text
            //
            // HOWEVER, if macroKey has content (even with index == 0), we still need to
            // call processWordBreak to trigger macro replacement. This happens when user
            // types a macro ending with a special character like "you@" - after typing "@",
            // the index is reset to 0 but macroKey still has [y, o, u, @].
            //
            // ALSO, if the character could be part of a macro (like "@", "!", etc.),
            // we should call processWordBreak to add it to macroKey, even if buffer is empty.
            // This supports macros starting with special characters like "@gmail" → "email@gmail.com".
            let hasMacroKey = macroEnabled && !engine.hookState.macroKey.isEmpty
            
            // Check if this is a non-space character that could be part of a macro
            // These characters should be added to macroKey via processWordBreak
            let isMacroableChar = macroEnabled && character != " " && 
                ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", 
                 "~", "`", "-", "_", "=", "+", "{", "}", "|", ":", "\"", 
                 "<", ">", "?", ";", "'", ",", ".", "/", "\\", "[", "]"].contains(character)
            
            if engine.index > 0 || hasMacroKey || isMacroableChar {
                // Engine has buffer OR pending macro OR macroable character - process word break
                let result = engine.processWordBreak(character: character)
                
                // Check if macro was found and replaced, or restore happened
                if result.shouldConsume {
                    // Send backspaces
                    if result.backspaceCount > 0 {
                        injector.sendBackspaces(
                            count: result.backspaceCount,
                            codeTable: codeTable,
                            proxy: proxy
                        )
                    }
                    
                    // Send replacement characters (includes the space character for restore/macro)
                    if !result.newCharacters.isEmpty {
                        injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
                    }
                    
                    // IMPORTANT: When restore or macro replacement happens, the space character
                    // is already included in result.newCharacters. We must consume the event
                    // to prevent a double space from being inserted.
                    return nil
                }
            } else {
                // No buffer, no macroKey, and not a macroable character
                // Just reset engine and let word break pass through
                // This prevents restoring autocompleted text (like emojis)
                engine.reset()
            }
            
            // CRITICAL FIX: When Enter/Return is pressed, set isTypingMidSentence = true
            // After inserting a newline, cursor will be at the start of a new line.
            // If there are any lines below, Forward Delete would pull up the next line.
            // By setting isTypingMidSentence = true, we prevent Forward Delete from being sent.
            // This is essential for multi-line editing scenarios like:
            // - User is at end of line 1 of 3 lines, presses Enter to create new line
            // - New line is between line 1 and old line 2
            // - When typing Vietnamese on new line, Forward Delete must be blocked
            if character == "\n" || character == "\r" {
                injector.markNewSession(cursorMoved: true)  // Treat Enter as cursor movement
            }
            
            return event
        }

        // In English mode with macro, only accumulate macro keys without Vietnamese processing
        if isEnglishModeWithMacro {
            engine.addKeyToMacroBuffer(keyCode: engineKeyCode, isCaps: isUppercase)
            return event  // Pass through without Vietnamese processing
        }

        // Wait for any pending injection to complete before processing next keystroke
        // Uses semaphore synchronization to prevent race conditions
        let waitStart = CFAbsoluteTimeGetCurrent()
        injector.waitForInjectionComplete()
        let waitTime = (CFAbsoluteTimeGetCurrent() - waitStart) * 1000
        if waitTime > 1.0 {
            debugLogCallback?("[\(getTimestamp())] ⏱ Waited \(String(format: "%.1f", waitTime))ms for previous injection")
        }

        // Process through engine (Vietnamese mode)
        let result = engine.processKey(
            character: character,
            keyCode: engineKeyCode,
            isUppercase: isUppercase
        )

        if result.shouldConsume {
            // Use synchronized injection (backspace + text in one atomic operation)
            // This prevents race conditions in terminals where next keystroke arrives
            // between backspace and text injection
            injector.injectSync(
                backspaceCount: result.backspaceCount,
                characters: result.newCharacters,
                codeTable: codeTable,
                proxy: proxy
            )

            // Consume original event
            return nil
        }


        // Pass through - engine may have buffered this character
        // If editor autocompletes it (e.g., \":d\" → emoji), the word break handler
        // will check engine.index and skip processing to avoid deleting the autocompleted text
        return event
    }
    
    // MARK: - Special Key Handling

    private func handleBackspace(event: CGEvent, proxy: CGEventTapProxy) -> CGEvent? {
        // In English mode with macro, only update macro buffer
        let isEnglishModeWithMacro = !isVietnameseEnabled && macroEnabled && macroInEnglishMode
        if isEnglishModeWithMacro {
            debugLogCallback?("[\(getTimestamp())] ⌫ Backspace in English+Macro mode - pass through")
            engine.updateMacroBufferOnBackspace()
            return event  // Pass through
        }

        // Wait for injection before processing backspace
        let waitStart = CFAbsoluteTimeGetCurrent()
        injector.waitForInjectionComplete()
        let waitTime = (CFAbsoluteTimeGetCurrent() - waitStart) * 1000
        if waitTime > 1.0 {
            debugLogCallback?("[\(getTimestamp())] ⏱ Backspace waited \(String(format: "%.1f", waitTime))ms for injection")
        }
        
        debugLogCallback?("[\(getTimestamp())] ⌫ Processing backspace (index=\(engine.index), spaceCount=\(engine.spaceCount))")
        let result = engine.processBackspace()

        if result.shouldConsume {
            // Use synchronized injection
            injector.injectSync(
                backspaceCount: result.backspaceCount,
                characters: result.newCharacters,
                codeTable: codeTable,
                proxy: proxy
            )

            return nil
        }

        return event
    }
    
    private func isWordBreakKey(_ character: Character) -> Bool {
        // Use centralized logic from VNEngine to ensure consistency with XKeyIM
        return VNEngine.isWordBreak(character: character, inputMethod: inputMethod)
    }
    
    // MARK: - Settings Update
    
    private func updateEngineSettings() {
        // Skip if we're in batch update mode (prevents 16+ redundant updates)
        guard !isBatchUpdating else { return }
        
        var settings = VNEngine.EngineSettings()
        settings.inputMethod = inputMethod
        settings.codeTable = codeTable
        settings.modernStyle = modernStyle
        settings.spellCheckEnabled = spellCheckEnabled
        
        // Advanced features
        settings.quickTelexEnabled = quickTelexEnabled
        settings.quickStartConsonantEnabled = quickStartConsonantEnabled
        settings.quickEndConsonantEnabled = quickEndConsonantEnabled
        settings.upperCaseFirstChar = upperCaseFirstChar
        settings.restoreIfWrongSpelling = restoreIfWrongSpelling

        settings.allowConsonantZFWJ = allowConsonantZFWJ
        settings.freeMarking = freeMarkEnabled
        
        // Macro settings
        settings.macroEnabled = macroEnabled
        settings.macroInEnglishMode = macroInEnglishMode
        settings.autoCapsMacro = autoCapsMacro
        settings.addSpaceAfterMacro = addSpaceAfterMacro
        
        // Smart switch
        settings.smartSwitchEnabled = smartSwitchEnabled
        
        engine.updateSettings(settings)
        
        // Debug: Log spell check setting sync
        debugLogCallback?("⚙️ Settings sync: spellCheckEnabled=\(spellCheckEnabled) → vCheckSpelling=\(engine.vCheckSpelling)")
        
        // Update macro manager
        macroManager.setCodeTable(codeTable.rawValue)
        macroManager.setAutoCapsMacro(autoCapsMacro)
    }
    
    /// Apply all settings at once (batch update) - only calls updateEngineSettings() once at the end
    /// This prevents multiple redundant log messages when applying preferences at startup
    func applyAllSettings(
        inputMethod: InputMethod,
        codeTable: CodeTable,
        modernStyle: Bool,
        spellCheckEnabled: Bool,
        quickTelexEnabled: Bool,
        quickStartConsonantEnabled: Bool,
        quickEndConsonantEnabled: Bool,
        upperCaseFirstChar: Bool,
        restoreIfWrongSpelling: Bool,
        allowConsonantZFWJ: Bool,
        freeMarkEnabled: Bool,
        macroEnabled: Bool,
        macroInEnglishMode: Bool,
        autoCapsMacro: Bool,
        addSpaceAfterMacro: Bool,
        smartSwitchEnabled: Bool,
        excludedApps: [ExcludedApp],
        undoTypingEnabled: Bool
    ) {
        // Enable batch mode to skip individual updateEngineSettings() calls
        isBatchUpdating = true
        
        // Set all properties (didSet won't trigger updateEngineSettings due to flag)
        self.inputMethod = inputMethod
        self.codeTable = codeTable
        self.modernStyle = modernStyle
        self.spellCheckEnabled = spellCheckEnabled
        self.quickTelexEnabled = quickTelexEnabled
        self.quickStartConsonantEnabled = quickStartConsonantEnabled
        self.quickEndConsonantEnabled = quickEndConsonantEnabled
        self.upperCaseFirstChar = upperCaseFirstChar
        self.restoreIfWrongSpelling = restoreIfWrongSpelling
        self.allowConsonantZFWJ = allowConsonantZFWJ
        self.freeMarkEnabled = freeMarkEnabled
        self.macroEnabled = macroEnabled
        self.macroInEnglishMode = macroInEnglishMode
        self.autoCapsMacro = autoCapsMacro
        self.addSpaceAfterMacro = addSpaceAfterMacro
        self.smartSwitchEnabled = smartSwitchEnabled
        self.excludedApps = excludedApps
        self.undoTypingEnabled = undoTypingEnabled
        
        // Disable batch mode
        isBatchUpdating = false
        
        // Now call updateEngineSettings() once
        updateEngineSettings()
    }
    
    // MARK: - Macro Management

    func getMacroManager() -> MacroManager {
        return macroManager
    }

    func getSmartSwitchManager() -> SmartSwitchManager {
        return smartSwitchManager
    }
    
    // MARK: - Reset
    
    func reset() {
        engine.reset()
        injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state to avoid Forward Delete in wrong context
        injector.clearMethodCache()  // Clear injection method cache
    }
    
    /// Reset engine and mark that cursor was moved (by mouse click or arrow keys)
    /// This disables autocomplete fix to avoid deleting text on the right of cursor
    /// Also sets engine flag to skip restore logic (user may be editing mid-word)
    func resetWithCursorMoved() {
        engine.resetWithCursorMoved()  // Use new method that sets cursor moved flag
        injector.markNewSession(cursorMoved: true)  // Mark that cursor was moved
        injector.clearMethodCache()  // Clear injection method cache
    }

    /// Reset engine when app switches
    /// Assumes user will likely click into middle of text, so enables mid-sentence mode
    /// This prevents Forward Delete from deleting text on the right of cursor
    func resetForAppSwitch() {
        engine.resetWithCursorMoved()  // Use new method that sets cursor moved flag
        injector.markNewSession(cursorMoved: true)  // Assume typing mid-sentence after app switch
        injector.clearMethodCache()
    }

    /// Reset mid-sentence flag only (without resetting engine)
    /// Used when clicking into overlay app (Spotlight/Raycast/Alfred) with empty input field
    /// Since the field is empty, Forward Delete is safe (nothing to delete on right)
    func resetMidSentenceFlag() {
        injector.resetMidSentenceFlag()
    }

    // MARK: - Excluded Apps Check
    
    /// Apps that should always pass through all keys (remote devices handle input)
    private static let passthroughApps: Set<String> = [
        "com.apple.ScreenContinuity"  // iPhone Mirroring - iOS device handles text input
    ]
    
    /// Check if the current frontmost app is in the excluded list
    /// IMPORTANT: Overlay apps (Spotlight, Raycast, Alfred) are NEVER excluded,
    /// even when the underlying app is in the excluded list.
    /// This allows Vietnamese typing in overlays regardless of the excluded app beneath.
    private func isCurrentAppExcluded() -> Bool {
        // PRIORITY 1: Check if overlay app is active (Spotlight, Raycast, Alfred)
        // Overlay apps use floating panels that don't become frontmostApplication,
        // so NSWorkspace.shared.frontmostApplication would return the excluded app underneath.
        // We must check overlay visibility FIRST to avoid blocking Vietnamese in overlays.
        if OverlayAppDetector.shared.isOverlayAppVisible() {
            return false  // Overlay apps are never excluded - allow Vietnamese typing
        }
        
        // PRIORITY 2: Check frontmost application for regular apps
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        // Always exclude passthrough apps (iPhone Mirroring, etc.)
        if Self.passthroughApps.contains(bundleId) {
            return true
        }
        
        // Check user-defined excluded apps
        guard !excludedApps.isEmpty else { return false }
        return excludedApps.contains { $0.bundleIdentifier == bundleId }
    }
    
    /// Check if a specific bundle identifier is excluded
    func isAppExcluded(bundleIdentifier: String) -> Bool {
        return excludedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

