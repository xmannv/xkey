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
    
    // Managers
    private let macroManager = MacroManager()
    private let smartSwitchManager = SmartSwitchManager()
    
    // MARK: - Initialization
    
    init() {
        self.engine = VNEngine()
        self.injector = CharacterInjector()

        // Set up engine logging
        self.engine.logCallback = { [weak self] message in
            #if DEBUG
            self?.debugLogCallback?("🔧 Engine: \(message)")
            #endif
        }
        
        // Set up injector debug logging
        self.injector.debugCallback = { [weak self] message in
            #if DEBUG
            self?.debugLogCallback?("💉 Injector: \(message)")
            #endif
        }
        
        // Share managers with VNEngine
        VNEngine.setSharedMacroManager(macroManager)
        VNEngine.setSharedSmartSwitchManager(smartSwitchManager)
        
        // Load macro data from UserDefaults
        loadMacrosFromUserDefaults()
    }
    
    // MARK: - Macro Data Loading
    
    private func loadMacrosFromUserDefaults() {
        let userDefaultsKey = "XKey.Macros"
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let macros = try? JSONDecoder().decode([MacroItemData].self, from: data) {
            for macro in macros {
                _ = macroManager.addMacro(text: macro.text, content: macro.content)
            }
            #if DEBUG
            debugLogCallback?("📦 Loaded \(macros.count) macros from UserDefaults")
            #endif
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
        if !isVietnameseEnabled {
            engine.reset()
        }
        #if DEBUG
        debugLogCallback?("Vietnamese input: \(isVietnameseEnabled ? "ON" : "OFF")")
        #endif
    }
    
    func setVietnamese(_ enabled: Bool) {
        isVietnameseEnabled = enabled
        if !enabled {
            engine.reset()
        }
    }
    
    // MARK: - EventTapDelegate
    
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        debugLogCallback?("shouldProcessEvent: enabled=\(isVietnameseEnabled), type=\(type.rawValue)")

        // Only process key down events when Vietnamese is enabled
        guard isVietnameseEnabled else {
            debugLogCallback?("  → Vietnamese DISABLED")
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
            injector.markNewSession()  // Mark as new input session
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

        // Get character and key code
        // Use charactersIgnoringModifiers for the base character (for input processing)
        // But check the ACTUAL character (with modifiers) to determine if it's uppercase
        guard let charactersIgnoringModifiers = event.charactersIgnoringModifiers,
              let character = charactersIgnoringModifiers.first else {
            return event
        }

        let keyCode = event.keyCode
        
        // Determine uppercase by checking the ACTUAL character (with Shift/Caps Lock applied)
        // This is more reliable than checking event flags
        let actualCharacters = event.characters ?? ""
        let actualCharacter = actualCharacters.first ?? character
        let isUppercase = actualCharacter.isUppercase

        debugLogCallback?("KEY: '\(character)' code=\(keyCode)")

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
            debugLogCallback?("  → CURSOR MOVEMENT - reset engine")
            engine.reset()
            injector.markNewSession()
            return event
        }

        // Handle special keys
        if keyCode == 0x33 { // Delete/Backspace
            debugLogCallback?("  → BACKSPACE")
            return handleBackspace(event: event, proxy: proxy)
        }

        if isWordBreakKey(character) {
            debugLogCallback?("  → WORD BREAK - checking macro first")
            let result = engine.processWordBreak(character: character)
            
            // Check if macro was found and replaced
            if result.shouldConsume {
                debugLogCallback?("  → MACRO FOUND! bs=\(result.backspaceCount) chars=\(result.newCharacters.count)")
                
                // Send backspaces
                if result.backspaceCount > 0 {
                    debugLogCallback?("    → Send \(result.backspaceCount) backspaces")
                    injector.sendBackspaces(
                        count: result.backspaceCount,
                        codeTable: codeTable,
                        proxy: proxy,
                        fixAutocomplete: engine.settings.fixAutocomplete
                    )
                }
                
                // Send macro replacement characters
                if !result.newCharacters.isEmpty {
                    let chars = result.newCharacters.map { $0.unicode(codeTable: codeTable) }.joined()
                    debugLogCallback?("    → Inject macro: \(chars)")
                    injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
                }
                
                // Send the word break character (space, etc.) after macro
                // Don't consume - let it pass through
            }
            
            injector.resetFirstWord()  // Mark that we're no longer on first word
            injector.resetKeystrokeCount()  // Reset keystroke count for next word
            return event
        }

        // Process through engine
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

            // Chrome address bar fix: Check for duplicates BEFORE sending backspaces
            // Only applies to Chrome address bar, not content area
            debugLogCallback?("  → Calling Chrome address bar fix...")
            injector.checkAndFixChromeAddressBarDuplicate(proxy: proxy)
            debugLogCallback?("  → Chrome fix done")

            // Send backspaces with autocomplete fix
            if result.backspaceCount > 0 {
                debugLogCallback?("    → Send \(result.backspaceCount) backspaces")
                injector.sendBackspaces(
                    count: result.backspaceCount,
                    codeTable: codeTable,
                    proxy: proxy,
                    fixAutocomplete: engine.settings.fixAutocomplete
                )
            }

            // Send new characters
            if !result.newCharacters.isEmpty {
                let chars = result.newCharacters.map { $0.unicode(codeTable: codeTable) }.joined()
                debugLogCallback?("    → Inject: \(chars)")

                // Debug: Log each character
                for (index, char) in result.newCharacters.enumerated() {
                    let unicode = char.unicode(codeTable: codeTable)
                    let unicodeHex = unicode.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")
                    debugLogCallback?("      [\(index)]: '\(unicode)' (\(unicodeHex))")
                }

                injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
            }

            // Consume original event
            return nil
        }

        // Pass through
        debugLogCallback?("  → PASS THROUGH")
        return event
    }
    
    // MARK: - Special Key Handling

    private func handleBackspace(event: CGEvent, proxy: CGEventTapProxy) -> CGEvent? {
        let result = engine.processBackspace()

        debugLogCallback?("  → Backspace result: shouldConsume=\(result.shouldConsume), bs=\(result.backspaceCount), chars=\(result.newCharacters.count)")

        if result.shouldConsume {
            // Send backspaces
            if result.backspaceCount > 0 {
                debugLogCallback?("    → Send \(result.backspaceCount) backspaces")
                injector.sendBackspaces(count: result.backspaceCount, codeTable: codeTable, proxy: proxy)
            }

            // Send new characters
            if !result.newCharacters.isEmpty {
                debugLogCallback?("    → Inject: \(result.newCharacters.count) chars")
                // Log each character being injected
                for (index, char) in result.newCharacters.enumerated() {
                    let unicode = char.unicode(codeTable: codeTable)
                    debugLogCallback?("      [\(index)]: '\(unicode)' (U+\(String(format: "%04X", unicode.unicodeScalars.first?.value ?? 0)))")
                }
                injector.sendCharacters(result.newCharacters, codeTable: codeTable, proxy: proxy)
            }

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
        
        #if DEBUG
        debugLogCallback?("✅ updateEngineSettings: inputMethod=\(inputMethod.displayName), vInputType=\(engine.vInputType), vAllowConsonantZFWJ=\(engine.vAllowConsonantZFWJ)")
        #endif
        
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
    }
}

