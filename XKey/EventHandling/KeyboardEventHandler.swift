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
    
    @Published var fixAutocomplete: Bool = true {
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
    
    @Published var tempOffSpellingEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var tempOffEngineEnabled: Bool = false {
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

        // Set up engine logging
        self.engine.logCallback = { [weak self] message in
            self?.debugLogCallback?("🔧 Engine: \(message)")
        }
        
        // Set up injector debug logging
        self.injector.debugCallback = { [weak self] message in
            self?.debugLogCallback?("💉 Injector: \(message)")
        }
        
        // Share managers with VNEngine
        VNEngine.setSharedMacroManager(macroManager)
        VNEngine.setSharedSmartSwitchManager(smartSwitchManager)

        // Macro manager logging disabled for cleaner output
        // macroManager.logCallback = { [weak self] message in
        //     self?.debugLogCallback?("📦 Macro: \(message)")
        // }
        
        // Load macro data from UserDefaults
        loadMacrosFromUserDefaults()
        
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
        loadMacrosFromUserDefaults()
        
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
    
    private func loadMacrosFromUserDefaults() {
        let userDefaultsKey = "XKey.Macros"
        
        // Clear existing macros first to avoid duplicates
        macroManager.clearAll()
        
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
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
    
    // MARK: - EventTapDelegate
    
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        // Check if current app is in excluded list
        if isCurrentAppExcluded() {
            return false
        }

        // Check if we should process in English mode (for macro support)
        let shouldProcessInEnglishMode = !isVietnameseEnabled && macroEnabled && macroInEnglishMode

        // Only process key down events when Vietnamese is enabled OR macro in English mode is enabled
        guard isVietnameseEnabled || shouldProcessInEnglishMode else {
            return false
        }

        // Only process key down events
        guard type == .keyDown else {
            return false
        }

        // Handle Ctrl key for temp off spelling
        if event.isControlPressed && tempOffSpellingEnabled {
            // Temporarily disable spell checking when Ctrl is pressed
            engine.vTempOffSpelling = 1
        } else {
            engine.vTempOffSpelling = 0
        }

        // Handle Option key for temp off engine
        if event.isOptionPressed && tempOffEngineEnabled {
            // Temporarily disable engine when Option is pressed
            engine.reset()
            injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state
            return false
        }

        // Don't process if Command is pressed
        if event.isCommandPressed {
            engine.reset()
            // Cmd + Arrow keys move cursor, so mark as mid-sentence
            // This prevents Forward Delete from deleting text on the right
            let keyCode = event.keyCode
            let cursorMovementKeys: [CGKeyCode] = [0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79] // Arrow keys, Home, End, Page Up/Down
            let isCursorMovement = cursorMovementKeys.contains(keyCode)
            injector.markNewSession(cursorMoved: isCursorMovement)
            return false
        }

        // Don't process if Option is pressed and tempOffEngine is NOT enabled
        if event.isOptionPressed && !tempOffEngineEnabled {
            engine.reset()
            injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state
            return false
        }

        // If only Ctrl is pressed and tempOffSpelling is NOT enabled, skip processing
        if event.isControlPressed && !tempOffSpellingEnabled {
            engine.reset()
            injector.markNewSession(preserveMidSentence: true)  // Preserve mid-sentence state
            return false
        }

        return true
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
            engine.reset()
            injector.markNewSession(cursorMoved: true)  // Mark that cursor was moved
            return event
        }

        // Handle Tab key - reset engine and mid-sentence flag (new field)
        if keyCode == 0x30 { // Tab
            engine.reset()
            injector.markNewSession(cursorMoved: false)  // New field, not mid-sentence
            return event
        }

        // Handle Escape key - undo typing if enabled
        if keyCode == 0x35 { // Escape
            // Only handle undo if setting is enabled
            if undoTypingEnabled {
                // Check if undo is available
                if engine.canUndoTyping() {
                    let result = engine.undoTyping()

                    if result.shouldConsume {
                        // Use synchronized injection to replace Vietnamese text with raw keystrokes
                        injector.injectSync(
                            backspaceCount: result.backspaceCount,
                            characters: result.newCharacters,
                            codeTable: codeTable,
                            proxy: proxy,
                            fixAutocomplete: false
                        )

                        // Mark new session after undo, preserve mid-sentence state
                        injector.markNewSession(preserveMidSentence: true)

                        return nil  // Consume the event
                    }
                }
            }

            // Pass through if undo not enabled or nothing to undo
            return event
        }

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
            let result = engine.processWordBreak(character: character)
            
            // Check if macro was found and replaced
            if result.shouldConsume {
                // Send backspaces
                if result.backspaceCount > 0 {
                    injector.sendBackspaces(
                        count: result.backspaceCount,
                        codeTable: codeTable,
                        proxy: proxy,
                        fixAutocomplete: engine.settings.fixAutocomplete
                    )
                }
                
                // Send macro replacement characters
                if !result.newCharacters.isEmpty {
                    injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
                }
                
                // Send the word break character (space, etc.) after macro
                // Don't consume - let it pass through
            }
            // NOTE: Do NOT reset mid-sentence flag on Enter/Return
            // When user presses Enter in the middle of text (e.g., line 2 of 3 lines),
            // there's still text on the right side. If we reset isTypingMidSentence,
            // Forward Delete will incorrectly delete that text when adding diacritics.
            // The mid-sentence flag should only be reset when:
            // - User clicks mouse (handled by resetWithCursorMoved)
            // - User tabs to new field (handled above)
            // - User starts typing in a completely new context
            
            return event
        }

        // In English mode with macro, only accumulate macro keys without Vietnamese processing
        if isEnglishModeWithMacro {
            engine.addKeyToMacroBuffer(keyCode: engineKeyCode, isCaps: isUppercase)
            return event  // Pass through without Vietnamese processing
        }

        // Wait for any pending injection to complete before processing next keystroke
        // Uses semaphore synchronization to prevent race conditions
        injector.waitForInjectionComplete()

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
                proxy: proxy,
                fixAutocomplete: engine.settings.fixAutocomplete
            )

            // Consume original event
            return nil
        }

        // Pass through
        return event
    }
    
    // MARK: - Special Key Handling

    private func handleBackspace(event: CGEvent, proxy: CGEventTapProxy) -> CGEvent? {
        // In English mode with macro, only update macro buffer
        let isEnglishModeWithMacro = !isVietnameseEnabled && macroEnabled && macroInEnglishMode
        if isEnglishModeWithMacro {
            engine.updateMacroBufferOnBackspace()
            return event  // Pass through
        }

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
        // Base word break characters
        // IMPORTANT: All special characters that can be part of macros must be included here
        // so they go through processWordBreak which correctly handles CAPS_MASK for macro matching.
        // This includes shifted number keys (@, #, $, etc.) and other punctuation.
        var wordBreaks: Set<Character> = [
            // Whitespace and basic punctuation
            " ", ",", ".", "!", "?", ";", ":",
            "\n", "\r", "\t",
            // Brackets and parentheses
            "(", ")", "{", "}", "<", ">",
            // Slashes
            "/", "\\", "|",
            // Shifted number keys - commonly used in macros
            "@", "#", "$", "%", "^", "&", "*",
            // Other special characters
            "~", "`", "-", "_", "=", "+",
            "'", "\""
        ]
        
        // For Telex input method, [ and ] are special keys (ơ and ư), not word breaks
        // For Simple Telex 1 & 2, [ and ] are word breaks
        if inputMethod != .telex {
            wordBreaks.insert("[")
            wordBreaks.insert("]")
        }
        
        return wordBreaks.contains(character)
    }
    
    // MARK: - Settings Update
    
    private func updateEngineSettings() {
        var settings = VNEngine.EngineSettings()
        settings.inputMethod = inputMethod
        settings.codeTable = codeTable
        settings.modernStyle = modernStyle
        settings.spellCheckEnabled = spellCheckEnabled
        settings.fixAutocomplete = fixAutocomplete
        
        // Advanced features
        settings.quickTelexEnabled = quickTelexEnabled
        settings.quickStartConsonantEnabled = quickStartConsonantEnabled
        settings.quickEndConsonantEnabled = quickEndConsonantEnabled
        settings.upperCaseFirstChar = upperCaseFirstChar
        settings.restoreIfWrongSpelling = restoreIfWrongSpelling
        settings.allowConsonantZFWJ = allowConsonantZFWJ
        settings.freeMarking = freeMarkEnabled
        settings.tempOffSpellingEnabled = tempOffSpellingEnabled
        settings.tempOffEngineEnabled = tempOffEngineEnabled
        
        // Macro settings
        settings.macroEnabled = macroEnabled
        settings.macroInEnglishMode = macroInEnglishMode
        settings.autoCapsMacro = autoCapsMacro
        
        // Smart switch
        settings.smartSwitchEnabled = smartSwitchEnabled
        
        engine.updateSettings(settings)
        
        // Update macro manager
        macroManager.setCodeTable(codeTable.rawValue)
        macroManager.setAutoCapsMacro(autoCapsMacro)
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
        injector.markNewSession()  // Mark as new input session
        injector.clearMethodCache()  // Clear injection method cache
    }
    
    /// Reset engine and mark that cursor was moved (by mouse click or arrow keys)
    /// This disables autocomplete fix to avoid deleting text on the right of cursor
    func resetWithCursorMoved() {
        engine.reset()
        injector.markNewSession(cursorMoved: true)  // Mark that cursor was moved
        injector.clearMethodCache()  // Clear injection method cache
    }

    /// Reset engine when app switches
    /// Assumes user will likely click into middle of text, so enables mid-sentence mode
    /// This prevents Forward Delete from deleting text on the right of cursor
    func resetForAppSwitch() {
        engine.reset()
        injector.markNewSession(cursorMoved: true)  // Assume typing mid-sentence after app switch
        injector.clearMethodCache()
    }

    // MARK: - Excluded Apps Check
    
    /// Check if the current frontmost app is in the excluded list
    private func isCurrentAppExcluded() -> Bool {
        guard !excludedApps.isEmpty else { return false }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return excludedApps.contains { $0.bundleIdentifier == bundleId }
    }
    
    /// Check if a specific bundle identifier is excluded
    func isAppExcluded(bundleIdentifier: String) -> Bool {
        return excludedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

