import Foundation

/// Owns normalized typing state and decisions. Host injection, app policy,
/// accessibility, and marked-text presentation remain transport concerns.
final class InputSession {
    let engine: VNEngine
    private(set) var preferences: RuntimePreferences
    private var effectiveVietnameseEnabled: Bool
    private let macroDataProvider: () -> Data?

    init(engine: VNEngine = VNEngine(),
         preferences: RuntimePreferences,
         macroDataProvider: @escaping () -> Data? = { SharedSettings.shared.getMacrosData() }) {
        self.engine = engine
        self.preferences = preferences
        self.effectiveVietnameseEnabled = preferences.vietnameseEnabled
        self.macroDataProvider = macroDataProvider
        reloadMacros()
        applyEngineSettings(preferences)
        engine.vLanguage = preferences.vietnameseEnabled ? 1 : 0
    }

    func apply(_ preferences: RuntimePreferences) {
        let languageChanged = self.preferences.vietnameseEnabled != preferences.vietnameseEnabled
        self.preferences = preferences
        effectiveVietnameseEnabled = preferences.vietnameseEnabled
        reloadMacros()
        applyEngineSettings(preferences)
        engine.vLanguage = preferences.vietnameseEnabled ? 1 : 0
        if languageChanged {
            engine.reset()
        }
    }

    func handle(_ event: InputEvent) -> InputAction {
        switch event.kind {
        case .reset:
            reset()
            return .reset
        case .focusChanged:
            engine.resetWithCursorMoved()
            return .reset
        case .flagsChanged:
            guard processesNormalizedTypingEvents else { return .passThrough }
            return handleFlagsChanged(event)
        case .undo:
            return handleUndo()
        case .keyDown:
            guard processesNormalizedTypingEvents else { return .passThrough }
            return handleKeyDown(event)
        }
    }

    func reset() {
        engine.reset()
    }

    func reloadMacros() {
        guard let data = macroDataProvider(),
              let macros = try? JSONDecoder().decode([PersistedMacro].self, from: data)
        else { return }

        let manager = engine.macroManager
        manager.clearAll()
        for macro in macros where macro.isEnabled {
            _ = manager.addMacro(text: macro.text, content: macro.content)
        }
    }

    func setEffectiveVietnameseEnabled(_ enabled: Bool) {
        effectiveVietnameseEnabled = enabled
        engine.vLanguage = enabled ? 1 : 0
    }

    func update(engineSettings: VNEngine.EngineSettings,
                yieldMacroToSystemReplacement: Bool,
                undoTypingEnabled: Bool) {
        preferences = preferences.replacingRuntimeOverrides(
            engineSettings: engineSettings,
            yieldMacroToSystemReplacement: yieldMacroToSystemReplacement,
            undoTypingEnabled: undoTypingEnabled
        )
        applyEngineSettings(preferences)
    }

    private func applyEngineSettings(_ preferences: RuntimePreferences) {
        let settings = preferences.engineSettings
        engine.updateSettings(settings)
        engine.macroManager.setCodeTable(settings.codeTable.rawValue)
        engine.macroManager.setAutoCapsMacro(settings.autoCapsMacro)
        engine.macroManager.setYieldToSystemReplacement(preferences.yieldMacroToSystemReplacement)
    }

    private func handleFlagsChanged(_ event: InputEvent) -> InputAction {
        guard event.modifiers.contains(.command) || event.modifiers.contains(.control) else {
            return .passThrough
        }

        let pendingText = engine.getCurrentWord()
        engine.reset()
        return pendingText.isEmpty ? .reset : .commit(text: pendingText)
    }

    private var processesNormalizedTypingEvents: Bool {
        effectiveVietnameseEnabled
            || (preferences.engineSettings.macroEnabled
                && preferences.engineSettings.macroInEnglishMode)
    }

    private func handleUndo() -> InputAction {
        guard preferences.undoTypingEnabled, engine.canUndoTyping() else {
            return .passThrough
        }
        return action(for: engine.undoTyping())
    }

    private func handleKeyDown(_ event: InputEvent) -> InputAction {
        guard let keyCode = event.keyCode else { return .passThrough }

        if event.isRepeat && keyCode != VietnameseData.KEY_DELETE {
            // Adapters should filter unsupported repeats. If one reaches the core,
            // invalidate composition so the pass-through key cannot desync the buffer.
            engine.resetWithCursorMoved()
            return .passThrough
        }

        if hasResettingModifierCombination(event.modifiers) {
            if VietnameseData.cursorMovementKeys.contains(keyCode) {
                engine.resetWithCursorMoved()
            } else {
                engine.reset()
            }
            return .reset
        }

        if keyCode == VietnameseData.KEY_DELETE {
            return handleBackspace()
        }

        if VietnameseData.cursorMovementKeys.contains(keyCode) {
            engine.resetWithCursorMoved()
            return .reset
        }

        if keyCode == VietnameseData.KEY_TAB || keyCode == VietnameseData.KEY_FORWARD_DELETE {
            engine.reset()
            return .reset
        }

        guard let character = event.characters?.first else { return .passThrough }

        let englishMacroMode = !effectiveVietnameseEnabled
            && preferences.engineSettings.macroEnabled
            && preferences.engineSettings.macroInEnglishMode

        guard effectiveVietnameseEnabled || englishMacroMode else {
            return .passThrough
        }

        if VNEngine.isWordBreak(character: character,
                                inputMethod: preferences.engineSettings.inputMethod) {
            return handleWordBreak(character)
        }

        let isUppercase = uppercaseState(for: character, modifiers: event.modifiers)
        let engineKeyCode = KeyCodeToCharacter.keyCode(forCharacter: character) ?? keyCode
        if englishMacroMode {
            engine.addKeyToMacroBuffer(keyCode: engineKeyCode, isCaps: isUppercase)
            return .passThrough
        }

        return action(for: engine.processKey(
            character: character,
            keyCode: engineKeyCode,
            isUppercase: isUppercase
        ))
    }

    private func handleBackspace() -> InputAction {
        let englishMacroMode = !effectiveVietnameseEnabled
            && preferences.engineSettings.macroEnabled
            && preferences.engineSettings.macroInEnglishMode
        if englishMacroMode {
            engine.updateMacroBufferOnBackspace()
            return .passThrough
        }
        guard effectiveVietnameseEnabled else { return .passThrough }
        return action(for: engine.processBackspace())
    }

    private func handleWordBreak(_ character: Character) -> InputAction {
        let macroEnabled = preferences.engineSettings.macroEnabled
        let hasMacroKey = macroEnabled && !engine.hookState.macroKey.isEmpty
        let isMacroableCharacter = macroEnabled
            && character != " "
            && Self.macroableCharacters.contains(character)

        guard engine.index > 0 || hasMacroKey || isMacroableCharacter else {
            engine.updateUpperCaseStatus(character: character)
            engine.reset()
            return .passThrough
        }

        return action(for: engine.processWordBreak(character: character))
    }

    private func action(for result: VNEngine.ProcessResult) -> InputAction {
        guard result.shouldConsume else { return .passThrough }
        if result.backspaceCount == 0 && result.newCharacters.isEmpty {
            return .consume
        }
        return .replace(backspaces: result.backspaceCount,
                        characters: result.newCharacters,
                        codeTable: preferences.engineSettings.codeTable)
    }

    private func hasResettingModifierCombination(_ modifiers: InputModifiers) -> Bool {
        let significant = modifiers.intersection([.command, .control, .option, .shift])
        return significant.contains(.command)
            || significant.contains(.control)
            || significant.contains(.option)
            || significant.rawValue.nonzeroBitCount >= 2
    }

    private func uppercaseState(for character: Character,
                                modifiers: InputModifiers) -> Bool {
        if character.isLetter || character == "[" || character == "]" {
            return modifiers.contains(.shift) != modifiers.contains(.capsLock)
        }
        return character.isUppercase
    }

    private static let macroableCharacters: Set<Character> = [
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
        "~", "`", "-", "_", "=", "+", "{", "}", "|", ":", "\"",
        "<", ">", "?", ";", "'", ",", ".", "/", "\\", "[", "]",
    ]

    private struct PersistedMacro: Decodable {
        let text: String
        let content: String
        let isEnabled: Bool

        private enum CodingKeys: String, CodingKey {
            case text, content, isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            content = try container.decode(String.self, forKey: .content)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }
    }
}
