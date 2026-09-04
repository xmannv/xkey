import XCTest
@testable import XKey

final class InputSessionTests: XCTestCase {
    private var macroManager: MacroManager!
    private var previousMacroManager: MacroManager!

    override func setUp() {
        super.setUp()
        previousMacroManager = VNEngine().macroManager
        macroManager = MacroManager()
        VNEngine.setSharedMacroManager(macroManager)
    }

    override func tearDown() {
        VNEngine.setSharedMacroManager(previousMacroManager)
        macroManager = nil
        previousMacroManager = nil
        super.tearDown()
    }

    func testOrdinaryKeyPassesThroughWhileEngineTracksWord() {
        let session = makeSession()

        XCTAssertEqual(session.handle(key("a", VietnameseData.KEY_A)), .passThrough)
        XCTAssertEqual(session.engine.getCurrentWord(), "a")
    }

    func testCharacterRemapsNonUSPhysicalKeyCodeForEngineProcessing() {
        let session = makeSession()

        XCTAssertEqual(session.handle(key("a", VietnameseData.KEY_Q)), .passThrough)
        XCTAssertEqual(session.engine.getCurrentWord(), "a")
    }

    func testTelexToneAndMarkSequenceProducesReplacement() {
        let session = makeSession()

        type("thuw", into: session)
        let action = session.handle(key("r", VietnameseData.KEY_R))

        XCTAssertEqual(action, .replace(backspaces: 1, text: "ử"))
        XCTAssertEqual(session.engine.getCurrentWord(), "thử")
    }

    func testRepeatedTelexMarkRestoresRawSpelling() {
        let session = makeSession()

        XCTAssertEqual(session.handle(key("a", VietnameseData.KEY_A)), .passThrough)
        XCTAssertEqual(session.handle(key("s", VietnameseData.KEY_S)),
                       .replace(backspaces: 1, text: "á"))
        XCTAssertEqual(session.handle(key("s", VietnameseData.KEY_S)),
                       .replace(backspaces: 1,
                                characters: [VNCharacter(vowel: .a),
                                             VNCharacter(character: "s")],
                                codeTable: .unicode))
        XCTAssertEqual(session.engine.getCurrentWord(), "as")
    }

    func testRepeatedNonDeleteInvalidatesCompositionBeforeUndoOrBoundary() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.undoTypingEnabled = true
        let session = makeSession(preferences: preferences)
        type("thuwr", into: session)
        XCTAssertEqual(session.engine.getCurrentWord(), "thử")

        let repeatedKey = InputEvent(kind: .keyDown,
                                     keyCode: VietnameseData.KEY_A,
                                     characters: "a",
                                     modifiers: [],
                                     isRepeat: true)
        XCTAssertEqual(session.handle(repeatedKey), .passThrough)

        XCTAssertEqual(session.engine.index, 0)
        XCTAssertEqual(session.handle(InputEvent(kind: .undo,
                                                 keyCode: nil,
                                                 characters: nil,
                                                 modifiers: [],
                                                 isRepeat: false)), .passThrough)
        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)), .passThrough)
    }

    func testInvalidSpellingRestoresOriginalKeystrokesAtWordBoundary() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = true
        preferences.restoreIfWrongSpelling = true
        let session = makeSession(preferences: preferences)
        var checkedWords: [String] = []
        session.engine.spellCheckVerdictOverride = { word in
            checkedWords.append(word)
            return false
        }
        type("xyr", into: session)
        XCTAssertEqual(session.engine.getCurrentWord(), "xỷ")

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)),
                       .replace(backspaces: 2,
                                characters: [VNCharacter(consonant: .x),
                                             VNCharacter(vowel: .y),
                                             VNCharacter(consonant: .r),
                                             VNCharacter(character: " ")],
                                codeTable: .unicode))
        XCTAssertEqual(checkedWords, ["xỷ"])
        XCTAssertEqual(session.engine.index, 0)
        XCTAssertEqual(session.engine.spaceCount, 1)
    }

    func testDisabledSessionSpellCheckDoesNotUsePersistedGlobalSetting() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        let session = makeSession(preferences: preferences)
        var checkedWords: [String] = []
        session.engine.spellCheckVerdictOverride = { word in
            checkedWords.append(word)
            return false
        }

        XCTAssertTrue(session.engine.checkWordSpelling(word: "xỷ"))
        XCTAssertTrue(checkedWords.isEmpty)
    }

    func testValidSpellingVerdictKeepsComposedWordAtBoundary() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = true
        preferences.restoreIfWrongSpelling = true
        let session = makeSession(preferences: preferences)
        session.engine.spellCheckVerdictOverride = { _ in true }
        type("xyr", into: session)

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)), .passThrough)
        XCTAssertEqual(session.engine.index, 0)
        XCTAssertEqual(session.engine.spaceCount, 1)
    }

    func testBackspaceUsesEngineAndPassesPhysicalDeleteThrough() {
        let session = makeSession()
        type("aa", into: session)

        XCTAssertEqual(session.handle(key("\u{8}", VietnameseData.KEY_DELETE)), .passThrough)
        XCTAssertEqual(session.engine.getCurrentWord(), "")
    }

    func testBackspaceAfterSpaceRestoresPreviousWordForContinuedTyping() {
        let session = makeSession()
        type("thu", into: session)
        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)), .passThrough)

        XCTAssertEqual(session.handle(key("\u{8}", VietnameseData.KEY_DELETE)), .passThrough)
        XCTAssertEqual(session.engine.getCurrentWord(), "thu")
    }

    func testSpaceAndEnterAreWordBoundaries() {
        let session = makeSession()
        type("thu", into: session)

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)), .passThrough)
        XCTAssertEqual(session.engine.index, 0)
        XCTAssertEqual(session.engine.spaceCount, 1)

        type("xin", into: session)
        XCTAssertEqual(session.handle(key("\n", VietnameseData.KEY_RETURN)), .passThrough)
        XCTAssertEqual(session.engine.index, 0)
        XCTAssertEqual(session.engine.spaceCount, 0)
    }

    func testCommandFlagsChangedCommitsPendingTextAndResetsEngine() {
        let session = makeSession()
        type("thu", into: session)

        let action = session.handle(InputEvent(
            kind: .flagsChanged,
            keyCode: nil,
            characters: nil,
            modifiers: [.command],
            isRepeat: false
        ))

        XCTAssertEqual(action, .commit(text: "thu"))
        XCTAssertEqual(session.engine.index, 0)
    }

    func testModifierKeyDownResetsPendingState() {
        let session = makeSession()
        type("thu", into: session)

        let action = session.handle(InputEvent(
            kind: .keyDown,
            keyCode: VietnameseData.KEY_A,
            characters: "a",
            modifiers: [.control],
            isRepeat: false
        ))

        XCTAssertEqual(action, .reset)
        XCTAssertEqual(session.engine.index, 0)
    }

    func testFocusChangeAndExplicitResetClearEngine() {
        let session = makeSession()
        type("thu", into: session)

        XCTAssertEqual(session.handle(InputEvent(
            kind: .focusChanged,
            keyCode: nil,
            characters: nil,
            modifiers: [],
            isRepeat: false
        )), .reset)
        XCTAssertEqual(session.engine.index, 0)

        type("xin", into: session)
        XCTAssertEqual(session.handle(InputEvent(
            kind: .reset,
            keyCode: nil,
            characters: nil,
            modifiers: [],
            isRepeat: false
        )), .reset)
        XCTAssertEqual(session.engine.index, 0)
    }

    func testVietnameseDisabledPassesThroughWithoutBuffering() {
        let session = makeSession(vietnameseEnabled: false)

        XCTAssertEqual(session.handle(key("a", VietnameseData.KEY_A)), .passThrough)
        XCTAssertEqual(session.engine.index, 0)
    }

    func testVietnameseDisabledCommandsPassThroughWithoutMutatingPendingEngineState() {
        let events: [(String, InputEvent)] = [
            ("Command-A", InputEvent(kind: .keyDown,
                                     keyCode: VietnameseData.KEY_A,
                                     characters: "a",
                                     modifiers: [.command],
                                     isRepeat: false)),
            ("Left arrow", InputEvent(kind: .keyDown,
                                      keyCode: VietnameseData.KEY_LEFT,
                                      characters: nil,
                                      modifiers: [],
                                      isRepeat: false)),
            ("Tab", InputEvent(kind: .keyDown,
                               keyCode: VietnameseData.KEY_TAB,
                               characters: "\t",
                               modifiers: [],
                               isRepeat: false)),
            ("Command flagsChanged", InputEvent(kind: .flagsChanged,
                                                keyCode: nil,
                                                characters: nil,
                                                modifiers: [.command],
                                                isRepeat: false)),
        ]

        for (name, event) in events {
            let session = makeSession(vietnameseEnabled: false)
            _ = session.engine.processKey(character: "a",
                                          keyCode: VietnameseData.KEY_A,
                                          isUppercase: false)

            XCTAssertEqual(session.handle(event), .passThrough, name)
            XCTAssertEqual(session.engine.getCurrentWord(), "a", name)
        }
    }

    func testVietnameseDisabledStillProcessesEnglishMacrosWhenEnabled() {
        XCTAssertTrue(macroManager.addMacro(text: "bb", content: "bạn bè"))
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.macroEnabled = true
        preferences.macroInEnglishMode = true
        let session = makeSession(preferences: preferences, vietnameseEnabled: false)

        type("bb", into: session)

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)),
                       .replace(backspaces: 2, text: "bạn bè"))
    }

    func testApplyReappliesEngineSettingsWithoutResettingPendingWord() {
        let session = makeSession()
        type("a", into: session)

        var preferences = Preferences()
        preferences.inputMethod = .vni
        preferences.spellCheckEnabled = false
        session.apply(runtimePreferences(preferences: preferences))

        XCTAssertEqual(session.preferences.engineSettings.inputMethod, .vni)
        XCTAssertEqual(session.engine.settings.inputMethod, .vni)
        XCTAssertEqual(session.engine.settings.spellCheckEnabled, false)
        XCTAssertEqual(session.engine.getCurrentWord(), "a")
    }

    func testMacroCompletionProducesReplacementAction() {
        XCTAssertTrue(macroManager.addMacro(text: "bb", content: "bạn bè"))
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.macroEnabled = true
        let session = makeSession(preferences: preferences)

        type("bb", into: session)

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)),
                       .replace(backspaces: 2, text: "bạn bè"))
    }

    func testInitAndApplyReloadEnabledPersistedMacrosIntoSameManager() throws {
        let first = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","text":"aa","content":"first","isEnabled":true},
         {"id":"00000000-0000-0000-0000-000000000002","text":"off","content":"disabled","isEnabled":false}]
        """.utf8)
        var persistedData = first
        let session = InputSession(preferences: runtimePreferences(preferences: Preferences()),
                                   macroDataProvider: { persistedData })

        XCTAssertTrue(session.engine.macroManager === macroManager)
        XCTAssertTrue(macroManager.hasMacro(text: "aa"))
        XCTAssertFalse(macroManager.hasMacro(text: "off"))

        persistedData = Data("""
        [{"id":"00000000-0000-0000-0000-000000000003","text":"bb","content":"second","isEnabled":true}]
        """.utf8)
        session.apply(runtimePreferences(preferences: Preferences()))

        XCTAssertFalse(macroManager.hasMacro(text: "aa"))
        XCTAssertTrue(macroManager.hasMacro(text: "bb"))
    }

    func testCharacterRemapsNonUSPhysicalKeyCodeForMacroBuffer() {
        XCTAssertTrue(macroManager.addMacro(text: "ab", content: "alpha beta"))
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.macroEnabled = true
        let session = makeSession(preferences: preferences)

        _ = session.handle(key("a", VietnameseData.KEY_Q))
        _ = session.handle(key("b", VietnameseData.KEY_B))

        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)),
                       .replace(backspaces: 2, text: "alpha beta"))
    }

    func testApplyReappliesSystemReplacementYieldPolicy() {
        XCTAssertTrue(macroManager.addMacro(text: "bb", content: "bạn bè"))
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.macroEnabled = true
        preferences.yieldMacroToSystemReplacement = false
        let session = makeSession(preferences: preferences)

        type("bb", into: session)
        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)),
                       .replace(backspaces: 2, text: "bạn bè"))

        preferences.yieldMacroToSystemReplacement = true
        session.apply(runtimePreferences(preferences: preferences))
        macroManager.setSystemReplacementShortcuts(["bb"])
        type("bb", into: session)
        XCTAssertEqual(session.handle(key(" ", VietnameseData.KEY_SPACE)), .passThrough)
    }

    func testUndoProducesRawKeystrokeReplacement() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.undoTypingEnabled = true
        let session = makeSession(preferences: preferences)
        type("tieesng", into: session)

        let action = session.handle(InputEvent(
            kind: .undo,
            keyCode: nil,
            characters: nil,
            modifiers: [],
            isRepeat: false
        ))

        XCTAssertEqual(action, .replace(backspaces: 5, text: "tieesng"))
        XCTAssertEqual(session.engine.index, 0)
    }

    private func makeSession(preferences: Preferences = Preferences(),
                             vietnameseEnabled: Bool = true) -> InputSession {
        InputSession(preferences: runtimePreferences(
            preferences: preferences,
            vietnameseEnabled: vietnameseEnabled
        ), macroDataProvider: { nil })
    }

    private func runtimePreferences(preferences: Preferences,
                                    vietnameseEnabled: Bool = true) -> RuntimePreferences {
        RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: vietnameseEnabled,
            windowTitleRulesEnabled: false,
            remoteDesktopInjectMode: false
        )
    }

    private func key(_ character: Character, _ keyCode: UInt16) -> InputEvent {
        InputEvent(
            kind: .keyDown,
            keyCode: keyCode,
            characters: String(character),
            modifiers: [],
            isRepeat: false
        )
    }

    private func type(_ text: String, into session: InputSession) {
        for character in text {
            guard let keyCode = VietnameseData.characterToKeyCodeMap[Character(character.lowercased())] else {
                XCTFail("Missing key code for \(character)")
                return
            }
            _ = session.handle(key(character, keyCode))
        }
    }
}
