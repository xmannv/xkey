//
//  ScreenSimulationTests.swift
//  XKeyTests
//
//  Screen == engine invariant harness. A dumb client-side screen model applies
//  VNEngine.ProcessResult exactly like a compliant real client (AXDirectInjector /
//  synthetic events), then asserts screen.text == engine.getCurrentWord() after
//  EVERY keystroke. Any divergence is the class of bug that produced the Firefox
//  "dịch" → "diịch" desync (diff said one thing, engine believed another).
//

import XCTest
@testable import XKey

final class ScreenSimulationTests: XCTestCase {
    /// Dumb screen model: applies ProcessResult exactly like a compliant client.
    /// Invariant: after EVERY keystroke, screen text == engine.getCurrentWord().
    /// Any divergence is the class of bug that produced Firefox "dịch"→"diịch".
    struct Screen {
        var text = ""
        mutating func apply(_ r: VNEngine.ProcessResult, keyChar: Character, engineOutput: String) {
            if r.shouldConsume {
                if r.backspaceCount > 0 { text.removeLast(min(r.backspaceCount, text.count)) }
                text += engineOutput   // converted from r.newCharacters
            } else {
                text.append(keyChar)
            }
        }
    }

    // Key sequences grouped by the classes the regression corpus covers:
    // ươ propagation, qu/gi onset, stop coda, cancel gesture (double key), English, case.
    static let corpus: [String] = [
        "truowngf", "nguowfi", "dduowngf", "queen", "gioongs", "vieejt",
        "hoas", "hoaf", "toans", "bawns", "batj", "bawtj",
        "aa", "aaa", "ss", "dd", "ddd", "w", "ww",
        "google", "his", "windows", "javascript",
        "Vieejt", "TRUOWNGF",
    ]

    /// Real conversion APIs (verified in repo):
    /// - char → keyCode: `VietnameseData.keyCode(for: ch)` (VietnameseData.swift:686)
    /// - VNCharacter → String: `$0.unicode(codeTable: .unicode)` (pattern from
    ///   KeyboardEventHandler.swift:273-275)
    private func emit(_ r: VNEngine.ProcessResult) -> String {
        r.newCharacters.map { $0.unicode(codeTable: .unicode) }.joined()
    }

    /// Types `seq` key-by-key into a fresh engine/screen pair and asserts the
    /// invariant after every key. Shared by the corpus test and the minimal
    /// known-desync repro below.
    private func assertInvariant(typing seq: String) {
        let engine = VNEngine()
        var screen = Screen()
        for ch in seq {
            let r = engine.processKey(character: ch,
                                      keyCode: CGKeyCode(VietnameseData.keyCode(for: ch) ?? 0),
                                      isUppercase: ch.isUppercase)
            screen.apply(r, keyChar: ch, engineOutput: emit(r))
            XCTAssertEqual(screen.text, engine.getCurrentWord(),
                           "diverged typing '\(seq)' at '\(ch)'")
        }
    }

    func testScreenTracksEngineOnCorpus() {
        for word in Self.corpus {
            assertInvariant(typing: word)
        }
    }

    /// Known desync: the 'w' key after a 2-vowel run whose ư/ơ horn-attach the
    /// engine's internal validity check rejects returns
    /// (shouldConsume: false, backspaceCount: 2, newCharacters: ["i","a"]) — a
    /// phantom no-op revert that a compliant client (which only applies
    /// backspaceCount/newCharacters when shouldConsume is true, per the
    /// contract documented in this file's Screen.apply) never sees. The
    /// client appends 'w' verbatim → screen becomes "iaw", but the engine's
    /// buffer silently stayed "ia" (backspace-2 + reinsert "ia" cancels out
    /// internally). Traced with debug prints on the minimal 3-key sequence
    /// "i","a","w" — a known engine bug, fix tracked as follow-up (out of scope here).
    func testKnownDesync_wAfterRejectedHornAttach() {
        XCTExpectFailure("known engine diff bug: w after rejected horn attach — see testKnownDesync_wAfterRejectedHornAttach") {
            assertInvariant(typing: "iaw")
        }
    }

    /// Deterministic LCG — no Date/Random so failures replay exactly.
    struct LCG { var s: UInt64
        mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int(s >> 33) % n } }

    /// One recorded divergence: screen.text != engine.getCurrentWord() right
    /// after processing `key`. Captures the causing ProcessResult's fields so
    /// known vs. new desyncs can be told apart precisely, not just by string
    /// diffing screen/engine.
    private struct Divergence {
        let seq: String
        let key: Character
        let screen: String
        let engineWord: String
        let shouldConsume: Bool
        let backspaceCount: Int
        let newCharCount: Int
    }

    /// Known root cause (see testKnownDesync_wAfterRejectedHornAttach): the
    /// 'w' key after a vowel run whose horn-attach (ư/ơ) the
    /// engine's internal validity check rejects returns a ProcessResult with
    /// shouldConsume=false but a non-zero backspaceCount/newCharacters (a
    /// phantom no-op revert never applied by a compliant client, since
    /// Screen.apply only reads those fields when shouldConsume is true).
    private func isKnownDesync(_ d: Divergence) -> Bool {
        d.key == "w" && !d.shouldConsume && d.backspaceCount > 0 && d.newCharCount > 0
    }

    func testScreenTracksEngineFuzz() {
        // Fixed seed 0x5EED, 2000 iterations: no Date/Random so failures replay
        // exactly. Does NOT assert per-key — instead collects every divergence,
        // then classifies known vs. unknown below. Once a word's screen and
        // engine have diverged, every following key in that word trivially
        // stays diverged too (same root cause, not new evidence), so only the
        // FIRST divergence per iteration is recorded.
        var divergences: [Divergence] = []
        let keys = Array("aeiouydtsfrxjwbcghklmnpq")
        var rng = LCG(s: 0x5EED)
        for _ in 0..<2000 {
            let engine = VNEngine()
            var screen = Screen()
            var typed = ""
            let len = 2 + rng.next(9)
            keyLoop: for _ in 0..<len {
                let ch = keys[rng.next(keys.count)]
                typed.append(ch)
                let r = engine.processKey(character: ch,
                                          keyCode: CGKeyCode(VietnameseData.keyCode(for: ch) ?? 0),
                                          isUppercase: false)
                screen.apply(r, keyChar: ch, engineOutput: emit(r))
                let engineWord = engine.getCurrentWord()
                if screen.text != engineWord {
                    divergences.append(Divergence(seq: typed, key: ch, screen: screen.text, engineWord: engineWord,
                                                  shouldConsume: r.shouldConsume, backspaceCount: r.backspaceCount,
                                                  newCharCount: r.newCharacters.count))
                    break keyLoop
                }
            }
        }

        let known = divergences.filter(isKnownDesync)
        let unknown = divergences.filter { !isKnownDesync($0) }

        // Live gate: a NEW desync pattern (not matching the known 'w'
        // phantom-revert shape) fails the test for real — this is what
        // actually protects against regressions, unlike a blanket
        // XCTExpectFailure over the whole loop would.
        XCTAssertTrue(unknown.isEmpty,
                      "NEW desync patterns: \(unknown.prefix(5).map { "'\($0.seq)' at '\($0.key)': screen='\($0.screen)' engine='\($0.engineWord)'" })")

        // Known-bug visibility: stays failing (forcing cleanup) once the
        // engine fix lands and `known` becomes empty — XCTExpectFailure's
        // strict mode reports an unmatched-expectation failure when the
        // inner assertion stops failing.
        XCTExpectFailure("known engine diff bug: w after rejected horn attach — see testKnownDesync_wAfterRejectedHornAttach") {
            XCTAssertTrue(known.isEmpty,
                          "known desyncs: \(known.prefix(5).map { "'\($0.seq)' at '\($0.key)': screen='\($0.screen)' engine='\($0.engineWord)'" })")
        }
    }
}
