//
//  VNEngineAdaptiveTests.swift
//  XKeyTests
//
//  Tests for the Adaptive input method (Telex + VNI auto-accept).
//

import XCTest
@testable import XKey

class VNEngineAdaptiveTests: XCTestCase {

    var engine: VNEngine!

    override func setUp() {
        super.setUp()
        engine = VNEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Task 1: enum + settings round-trip

    func testAdaptiveEnumExists() {
        XCTAssertEqual(InputMethod.adaptive.rawValue, 4)
        XCTAssertFalse(InputMethod.adaptive.displayName.isEmpty)
        XCTAssertTrue(InputMethod.allCases.contains(.adaptive))
    }

    func testAdaptiveSettingsRoundTrip() {
        var settings = engine.settings
        settings.inputMethod = .adaptive
        engine.updateSettings(settings)

        XCTAssertTrue(engine.vAdaptiveEnabled, "vAdaptiveEnabled should be set for .adaptive")
        XCTAssertEqual(engine.vInputType, 0, "base vInputType should default to Telex (0)")
        XCTAssertEqual(engine.settings.inputMethod, .adaptive, "reverse mapping should return .adaptive")
    }

    func testNonAdaptiveClearsFlag() {
        var settings = engine.settings
        settings.inputMethod = .adaptive
        engine.updateSettings(settings)
        XCTAssertTrue(engine.vAdaptiveEnabled)

        settings.inputMethod = .vni
        engine.updateSettings(settings)
        XCTAssertFalse(engine.vAdaptiveEnabled, "switching to VNI must clear vAdaptiveEnabled")
        XCTAssertEqual(engine.vInputType, 1)
        XCTAssertEqual(engine.settings.inputMethod, .vni)
    }

    // MARK: - Task 2: dual-typing produces the same Vietnamese output

    /// Helper: type a sequence of (character, keyCode) in adaptive mode and return the word.
    private func typeAdaptive(_ keys: [(Character, UInt16)]) -> String {
        engine.reset()
        engine.vAdaptiveEnabled = true
        engine.vInputType = 0
        for (ch, code) in keys {
            _ = engine.processKey(character: ch, keyCode: code, isUppercase: false)
        }
        return engine.getCurrentWord()
    }

    func testAdaptive_AcuteTone_BothWays() {
        // Telex: a + s  →  á
        XCTAssertEqual(typeAdaptive([("a", VietnameseData.KEY_A), ("s", VietnameseData.KEY_S)]), "á")
        // VNI: a + 1  →  á
        XCTAssertEqual(typeAdaptive([("a", VietnameseData.KEY_A), ("1", VietnameseData.KEY_1)]), "á")
    }

    func testAdaptive_Circumflex_BothWays() {
        // Telex: a + a  →  â
        XCTAssertEqual(typeAdaptive([("a", VietnameseData.KEY_A), ("a", VietnameseData.KEY_A)]), "â")
        // VNI: a + 6  →  â
        XCTAssertEqual(typeAdaptive([("a", VietnameseData.KEY_A), ("6", VietnameseData.KEY_6)]), "â")
    }

    func testAdaptive_Horn_U_BothWays() {
        // Telex: u + w  →  ư
        XCTAssertEqual(typeAdaptive([("u", VietnameseData.KEY_U), ("w", VietnameseData.KEY_W)]), "ư")
        // VNI: u + 7  →  ư
        XCTAssertEqual(typeAdaptive([("u", VietnameseData.KEY_U), ("7", VietnameseData.KEY_7)]), "ư")
    }

    func testAdaptive_Dee_BothWays() {
        // Telex: d + d  →  đ
        XCTAssertEqual(typeAdaptive([("d", VietnameseData.KEY_D), ("d", VietnameseData.KEY_D)]), "đ")
        // VNI: d + 9  →  đ
        XCTAssertEqual(typeAdaptive([("d", VietnameseData.KEY_D), ("9", VietnameseData.KEY_9)]), "đ")
    }

    // MARK: - Task 3: static gatekeepers accept adaptive keys

    func testAdaptive_DigitIsSpecialKey() {
        // Letters are always special; the point is digits must be special in adaptive.
        XCTAssertTrue(VNEngine.isVietnameseSpecialKey(character: "1", inputMethod: .adaptive))
        XCTAssertTrue(VNEngine.isVietnameseSpecialKey(character: "9", inputMethod: .adaptive))
        // Telex modifier letters too:
        XCTAssertTrue(VNEngine.isVietnameseSpecialKey(character: "s", inputMethod: .adaptive))
        // Brackets are Telex standalone input → special in adaptive:
        XCTAssertTrue(VNEngine.isVietnameseSpecialKey(character: "[", inputMethod: .adaptive))
        XCTAssertTrue(VNEngine.isVietnameseSpecialKey(character: "]", inputMethod: .adaptive))
    }

    func testAdaptive_BracketIsNotWordBreak() {
        // In Telex, [ and ] are NOT word breaks (they produce ơ/ư). Same for adaptive.
        XCTAssertFalse(VNEngine.isWordBreak(character: "[", inputMethod: .adaptive))
        XCTAssertFalse(VNEngine.isWordBreak(character: "]", inputMethod: .adaptive))
        // Space is always a word break:
        XCTAssertTrue(VNEngine.isWordBreak(character: " ", inputMethod: .adaptive))
    }

    // MARK: - Task 4: alphanumeric / English tokens stay literal

    func testAdaptive_CovidStaysLiteral() {
        let word = typeAdaptive([
            ("c", VietnameseData.KEY_C), ("o", VietnameseData.KEY_O), ("v", VietnameseData.KEY_V),
            ("i", VietnameseData.KEY_I), ("d", VietnameseData.KEY_D),
            ("1", VietnameseData.KEY_1), ("9", VietnameseData.KEY_9)
        ])
        XCTAssertEqual(word, "covid19", "non-Vietnamese token must not get VNI tones")
    }

    func testAdaptive_Mp3StaysLiteral() {
        let word = typeAdaptive([
            ("m", VietnameseData.KEY_M), ("p", VietnameseData.KEY_P), ("3", VietnameseData.KEY_3)
        ])
        XCTAssertEqual(word, "mp3", "all-consonant + digit token must not be modified")
    }

    func testAdaptive_ValidVietnameseDigitStillWorks() {
        // Sanity: a valid syllable + VNI digit still gets the tone (gate must not over-block).
        // v + i + 1 → ví
        XCTAssertEqual(typeAdaptive([
            ("v", VietnameseData.KEY_V), ("i", VietnameseData.KEY_I), ("1", VietnameseData.KEY_1)
        ]), "ví")
    }

    // MARK: - Task 5: full equivalence matrix + commit/backspace

    func testAdaptive_EquivalenceMatrix() {
        // (expected, telexKeys, vniKeys) — each pair must produce `expected` in adaptive mode.
        let cases: [(String, [(Character, UInt16)], [(Character, UInt16)])] = [
            ("á", [("a", VietnameseData.KEY_A), ("s", VietnameseData.KEY_S)],
                  [("a", VietnameseData.KEY_A), ("1", VietnameseData.KEY_1)]),
            ("à", [("a", VietnameseData.KEY_A), ("f", VietnameseData.KEY_F)],
                  [("a", VietnameseData.KEY_A), ("2", VietnameseData.KEY_2)]),
            ("â", [("a", VietnameseData.KEY_A), ("a", VietnameseData.KEY_A)],
                  [("a", VietnameseData.KEY_A), ("6", VietnameseData.KEY_6)]),
            ("ê", [("e", VietnameseData.KEY_E), ("e", VietnameseData.KEY_E)],
                  [("e", VietnameseData.KEY_E), ("6", VietnameseData.KEY_6)]),
            ("ô", [("o", VietnameseData.KEY_O), ("o", VietnameseData.KEY_O)],
                  [("o", VietnameseData.KEY_O), ("6", VietnameseData.KEY_6)]),
            ("ơ", [("o", VietnameseData.KEY_O), ("w", VietnameseData.KEY_W)],
                  [("o", VietnameseData.KEY_O), ("7", VietnameseData.KEY_7)]),
            ("ư", [("u", VietnameseData.KEY_U), ("w", VietnameseData.KEY_W)],
                  [("u", VietnameseData.KEY_U), ("7", VietnameseData.KEY_7)]),
            ("ă", [("a", VietnameseData.KEY_A), ("w", VietnameseData.KEY_W)],
                  [("a", VietnameseData.KEY_A), ("8", VietnameseData.KEY_8)]),
            ("đ", [("d", VietnameseData.KEY_D), ("d", VietnameseData.KEY_D)],
                  [("d", VietnameseData.KEY_D), ("9", VietnameseData.KEY_9)]),
        ]
        for (expected, telex, vni) in cases {
            XCTAssertEqual(typeAdaptive(telex), expected, "Telex path for \(expected)")
            XCTAssertEqual(typeAdaptive(vni), expected, "VNI path for \(expected)")
        }
    }

    func testAdaptive_WordBreakCommitsThenNewWord() {
        engine.reset()
        engine.vAdaptiveEnabled = true
        engine.vInputType = 0
        // Type "á" via VNI, commit with space, then start a fresh word via Telex.
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        XCTAssertEqual(engine.getCurrentWord(), "á")
        _ = engine.processWordBreak(character: " ")
        // New word "ô" via Telex
        _ = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        _ = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        XCTAssertEqual(engine.getCurrentWord(), "ô")
    }

    func testAdaptive_BackspaceClearsComposedChar() {
        engine.reset()
        engine.vAdaptiveEnabled = true
        engine.vInputType = 0
        // "á" via VNI a+1, then backspace removes the tone-bearing char.
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        XCTAssertEqual(engine.getCurrentWord(), "á")
        _ = engine.processBackspace()
        XCTAssertEqual(engine.getCurrentWord(), "", "backspace should clear the single composed char")
    }
}
