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
    
    // Undo typing key (single key, no modifiers)
    var undoTypingKeyCode: UInt16?
    
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
        injector.markNewSession()
    }
    
    // MARK: - Smart Switch Data Loading
    
    private func loadSmartSwitchData() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let xkeyDir = appSupport.appendingPathComponent("XKey")
        let path = xkeyDir.appendingPathComponent("smart_switch.json").path
        
        if smartSwitchManager.loadFromFile(path: path) {
            let apps = smartSwitchManager.getAllApps()
            debugLogCallback?("📦 Loaded \(apps.count) app language settings from file")
        }
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
        debugLogCallback?("Vietnamese input: \(isVietnameseEnabled ? "ON" : "OFF"), vLanguage=\(engine.vLanguage)")
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
        debugLogCallback?("shouldProcessEvent: enabled=\(isVietnameseEnabled), macroInEnglish=\(macroInEnglishMode), macroEnabled=\(macroEnabled), type=\(type.rawValue)")

        // Check if current app is in excluded list
        if isCurrentAppExcluded() {
            debugLogCallback?("  → Current app is EXCLUDED")
            return false
        }
        
        // Check if we should process in English mode (for macro support)
        let shouldProcessInEnglishMode = !isVietnameseEnabled && macroEnabled && macroInEnglishMode
        
        // Only process key down events when Vietnamese is enabled OR macro in English mode is enabled
        guard isVietnameseEnabled || shouldProcessInEnglishMode else {
            debugLogCallback?("  → Vietnamese DISABLED and macro in English mode OFF")
            return false
        }

        // Only process key down events
        guard type == .keyDown else {
            debugLogCallback?("  → Not keyDown (type=\(type.rawValue))")
            return false
        }

        // Handle Ctrl key for temp off spelling
        if event.isControlPressed && tempOffSpellingEnabled {
            // Temporarily disable spell checking when Ctrl is pressed
            engine.vTempOffSpelling = 1
            debugLogCallback?("  → Ctrl pressed - temp off spelling")
        } else {
            engine.vTempOffSpelling = 0
        }
        
        // Handle Option key for temp off engine
        if event.isOptionPressed && tempOffEngineEnabled {
            // Temporarily disable engine when Option is pressed
            debugLogCallback?("  → Option pressed - temp off engine")
            engine.reset()
            injector.markNewSession()
            return false
        }

        // Don't process if Command is pressed
        if event.isCommandPressed {
            debugLogCallback?("  → Has Cmd modifier")
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
            debugLogCallback?("  → Option pressed but tempOffEngine disabled")
            engine.reset()
            injector.markNewSession()
            return false
        }
        
        // If only Ctrl is pressed and tempOffSpelling is NOT enabled, skip processing
        if event.isControlPressed && !tempOffSpellingEnabled {
            debugLogCallback?("  → Ctrl pressed but tempOffSpelling disabled")
            engine.reset()
            injector.markNewSession()
            return false
        }

        debugLogCallback?("  → OK, will process")
        return true
    }
    
    func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent? {
        guard type == .keyDown else {
            return event
        }

        // Get physical key code
        let keyCode = event.keyCode
        
        // IMPORTANT: Convert physical keyCode to QWERTY character
        // This ensures Vietnamese typing works on non-QWERTY layouts (QWERTZ, AZERTY, etc.)
        // We cannot use event.charactersIgnoringModifiers because it returns the character
        // based on the current keyboard layout, not the physical key position
        // For example, on QWERTZ: physical key at position 0x06 (Z on QWERTY) returns 'y'
        
        // Determine if Shift is pressed (for uppercase and special characters)
        let hasShiftModifier = event.flags.contains(.maskShift)
        let hasCapsLock = event.flags.contains(.maskAlphaShift)
        
        // Get QWERTY character from physical key position
        guard let qwertyCharacter = KeyCodeToCharacter.qwertyCharacter(keyCode: keyCode, withShift: hasShiftModifier) else {
            // Not a printable character or not mapped
            return event
        }
        
        // Determine if uppercase:
        // - For letters: Shift XOR Caps Lock (standard behavior)
        // - For special characters: use Shift flag
        let isLetter = qwertyCharacter.isLetter
        let isUppercase = isLetter ? (hasShiftModifier != hasCapsLock) : hasShiftModifier
        
        // Use the QWERTY character for processing
        let character = qwertyCharacter

        debugLogCallback?("KEY: '\(character)' code=\(keyCode) (QWERTY)")

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
            debugLogCallback?("  → CURSOR MOVEMENT - reset engine, mark mid-sentence")
            engine.reset()
            injector.markNewSession(cursorMoved: true)  // Mark that cursor was moved
            return event
        }
        
        // Handle Tab key - reset engine and mid-sentence flag (new field)
        if keyCode == 0x30 { // Tab
            debugLogCallback?("  → TAB - reset engine, new field")
            engine.reset()
            injector.markNewSession(cursorMoved: false)  // New field, not mid-sentence
            return event
        }
        
        // Handle undo typing key (single key, no modifiers)
        // Only trigger if there's something to undo in the engine buffer
        if let undoKeyCode = undoTypingKeyCode, keyCode == undoKeyCode {
            // Check if NO modifiers are pressed (pure single key)
            let hasNoModifiers = !event.isCommandPressed && !event.isControlPressed && !event.isOptionPressed
            
            if hasNoModifiers && engine.canUndoTyping() {
                debugLogCallback?("  → UNDO TYPING KEY - performing undo")
                let result = engine.undoTyping()
                
                if result.shouldConsume {
                    // Send backspaces
                    if result.backspaceCount > 0 {
                        injector.sendBackspaces(
                            count: result.backspaceCount,
                            codeTable: codeTable,
                            proxy: proxy,
                            fixAutocomplete: false
                        )
                    }
                    
                    // Send original characters
                    if !result.newCharacters.isEmpty {
                        injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
                    }
                    
                    injector.markNewSession()
                    return nil  // Consume the event
                }
            }
            // If nothing to undo, fall through to normal processing
        }

        // Handle special keys
        if keyCode == 0x33 { // Delete/Backspace
            debugLogCallback?("  → BACKSPACE")
            return handleBackspace(event: event, proxy: proxy)
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
            
            injector.resetFirstWord()  // Mark that we're no longer on first word
            injector.resetKeystrokeCount()  // Reset keystroke count for next word
            
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
            engine.addKeyToMacroBuffer(keyCode: keyCode, isCaps: isUppercase)
            return event  // Pass through without Vietnamese processing
        }

        // Wait for any pending injection to complete before processing next keystroke
        // Uses semaphore synchronization to prevent race conditions
        injector.waitForInjectionComplete()
        
        // Process through engine (Vietnamese mode)
        debugLogCallback?("  → Calling engine.processKey('\(character)')...")
        let result = engine.processKey(
            character: character,
            keyCode: keyCode,
            isUppercase: isUppercase
        )
        debugLogCallback?("  → Engine returned: shouldConsume=\(result.shouldConsume), bs=\(result.backspaceCount), chars=\(result.newCharacters.count)")
        
        // Increment keystroke count for Chrome duplicate detection
        if result.shouldConsume {
            injector.incrementKeystroke()
        }

        // Handle result
        if result.shouldConsume {
            debugLogCallback?("  → CONSUME: bs=\(result.backspaceCount) chars=\(result.newCharacters.count)")

            // Chrome address bar fix: Check for duplicates BEFORE injection
            debugLogCallback?("  → Calling Chrome address bar fix...")
            injector.checkAndFixChromeAddressBarDuplicate(proxy: proxy)
            debugLogCallback?("  → Chrome fix done")

            // Debug log
            if !result.newCharacters.isEmpty {
                let chars = result.newCharacters.map { $0.unicode(codeTable: codeTable) }.joined()
                debugLogCallback?("    → Inject: \(chars)")
                for (index, char) in result.newCharacters.enumerated() {
                    let unicode = char.unicode(codeTable: codeTable)
                    let unicodeHex = unicode.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")
                    debugLogCallback?("      [\(index)]: '\(unicode)' (\(unicodeHex))")
                }
            }

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
        debugLogCallback?("  → PASS THROUGH")
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

        debugLogCallback?("  → Backspace result: shouldConsume=\(result.shouldConsume), bs=\(result.backspaceCount), chars=\(result.newCharacters.count)")

        if result.shouldConsume {
            debugLogCallback?("    → Inject: bs=\(result.backspaceCount), chars=\(result.newCharacters.count)")
            
            // Log each character being injected
            for (index, char) in result.newCharacters.enumerated() {
                let unicode = char.unicode(codeTable: codeTable)
                debugLogCallback?("      [\(index)]: '\(unicode)' (U+\(String(format: "%04X", unicode.unicodeScalars.first?.value ?? 0)))")
            }
            
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
        var wordBreaks: Set<Character> = [
            " ", ",", ".", "!", "?", ";", ":",
            "\n", "\r", "\t", "(", ")",
            "{", "}", "<", ">", "/", "\\", "|"
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

