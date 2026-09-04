//
//  KeystrokePerfTests.swift
//  XKeyTests
//

import XCTest
@testable import XKey

/// Per-keystroke latency gate for VNEngine.processKey.
/// RATCHET RULE: when the engine gets faster, LOWER the
/// ceiling; never raise it to silence a red build. CI retries the whole
/// process 3× and fails only if all 3 exceed the ceiling (noisy runners).
///
/// Deployment target is macOS 12, but `ContinuousClock` needs macOS 13+ — every
/// machine that actually runs this test (CI, dev Macs) is well past that, so
/// gating the whole class on availability is safe and avoids a manual clock.
@available(macOS 13.0, *)
final class KeystrokePerfTests: XCTestCase {
    // Ceiling = 3x min-of-5, measured on Release config, 2026-08-25, sha de17609.
    // Runs (us/keystroke): 2.336, 2.269, 2.217, 2.195, 2.293 — min 2.194775 x 3 = 6.584, rounded up.
    static let ceilingMicros: Double = 6.6

    func testKeystrokeLatency() throws {
        #if DEBUG
        throw XCTSkip("perf gate runs in Release configuration only")
        #else
        let word = Array("truowngf ")
        var best = Double.infinity
        for _ in 0..<5 {
            let engine = VNEngine()
            engine.spellCheckVerdictOverride = { _ in true }
            let n = 20_000
            let t0 = ContinuousClock.now
            for i in 0..<n {
                let ch = word[i % word.count]
                if ch == " " {
                    // Space has no keyCode mapping (VietnameseData.keyCode(for:) only
                    // covers letters/digits) — it's the word-boundary keystroke, routed
                    // via processWordBreak exactly like CorpusRegressionTests.replay(_:)
                    // does for non-letter characters. This also measures the boundary
                    // cost (restore/spell-check path), not just plain composition.
                    _ = engine.processWordBreak(character: ch)
                } else {
                    _ = engine.processKey(character: ch,
                                          keyCode: CGKeyCode(VietnameseData.keyCode(for: ch) ?? 0),
                                          isUppercase: false)
                }
            }
            // Duration.components is (seconds, attoseconds-of-the-fractional-part), NOT
            // total attoseconds — reading .attoseconds alone silently drops whole seconds
            // elapsed. Combine both components to get a correct microsecond figure.
            let elapsed = (ContinuousClock.now - t0).components
            let us = (Double(elapsed.seconds) * 1_000_000 + Double(elapsed.attoseconds) / 1_000_000_000_000) / Double(n)
            best = min(best, us)
        }
        print("KeystrokePerf: us/keystroke=\(best)")
        XCTAssertLessThanOrEqual(best, Self.ceilingMicros)
        #endif
    }
}
