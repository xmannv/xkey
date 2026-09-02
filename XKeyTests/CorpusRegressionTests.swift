//
//  CorpusRegressionTests.swift
//  XKeyTests
//

import XCTest
@testable import XKey

/// Replays a large Telex regression corpus (9,093 valid cases, see
/// telex_test_suite.csv) through VNEngine exactly like a real controller does:
/// letters/digits compose via `processKey`, everything else (space, comma, period,
/// punctuation with no keyCode mapping) is a word boundary, committed via
/// `processWordBreak`. Cases are bucketed by the CSV's `expected_behavior` column.
///
/// FLOORS are this repo's OWN measured baseline, not borrowed from anywhere else.
/// The engine that originally produced this corpus has different semantics
/// (teencode rimes, free-tone-late placement, a bigger English dictionary), so its
/// pass rates don't transfer to XKey. Low numbers here are an honest measurement of
/// that semantic gap, not a defect to "fix" — this task only ratchets: raise a floor
/// when a later change genuinely improves a bucket, never lower one to silence a
/// regression.
///
/// Engine config: plain `VNEngine()`, no extra flags. `vCheckSpelling` and
/// `vRestoreIfWrongSpelling` already default to `1` (see VNEngine.swift, declared next
/// to `vTempOffSpelling = 0`), which is what makes restore-at-boundary reachable at all.
/// Nothing else needed enabling.
final class CorpusRegressionTests: XCTestCase {

    struct Case {
        let input: String
        let expected: String
        let bucket: String
    }

    // Baseline measured 2026-08-25 (8,046 valid cases; see loadCSV/parseCSV).
    // restore_raw re-measured after removing the English-collision force-restore
    // feature (words like "task"/"disk" no longer force-restore): 4051 -> 3776 —
    // an intentional drop from that removal, not a regression. The former
    // ambiguous_needs_context bucket (1,047 rows) existed solely to exercise that
    // feature and was deleted from the CSV along with it.
    static let floors: [String: Int] = [
        "transform": 400,
        "keep_as_typed": 355,
        "restore_raw": 3776,
        "cancel_keep_composed": 66,
    ]

    func testCorpusBuckets() throws {
        let cases = try Self.loadCSV()
        let engine = VNEngine()
        var pass = [String: Int](), total = [String: Int]()
        for c in cases {
            total[c.bucket, default: 0] += 1
            let out = Self.replay(c.input, engine: engine)
            if Self.matches(out, c.expected) { pass[c.bucket, default: 0] += 1 }
        }
        for bucket in Self.floors.keys.sorted() {
            let floor = Self.floors[bucket]!
            print("CORPUS \(bucket): \(pass[bucket] ?? 0)/\(total[bucket] ?? 0)")
            XCTAssertGreaterThanOrEqual(pass[bucket] ?? 0, floor, "bucket \(bucket) regressed below floor \(floor)")
        }
    }

    // MARK: - Replay

    /// Accept an exact match, or any "/"-separated style-variant the corpus lists as
    /// equally correct (e.g. "hóa / hoá" — both tone-placement styles are valid).
    private static func matches(_ output: String, _ expected: String) -> Bool {
        if output == expected { return true }
        return expected.components(separatedBy: " / ").contains(output)
    }

    /// Replays `input` through `engine` (reset first) and returns the fully committed
    /// text. Letters/digits compose via `processKey`. Every other character is a word
    /// boundary: commit whatever is composed so far via `processWordBreak`, then append
    /// the boundary character itself literally — mirroring the same "non-letter is a
    /// boundary" rule the corpus's own driving harness used, refined
    /// to use `VNEngine.isWordBreak` so Telex's '[' / ']' horn keys still compose instead
    /// of being wrongly treated as a boundary (they aren't a word break in Telex/Adaptive
    /// — see VNEngine.isWordBreak). A trailing `processWordBreak(" ")` flushes the last
    /// composed word, same as a real word followed by a space.
    private static func replay(_ input: String, engine: VNEngine) -> String {
        engine.reset()
        var out = ""
        for ch in input {
            if let kc = VietnameseData.keyCode(for: ch), !VNEngine.isWordBreak(character: ch, inputMethod: .telex) {
                _ = engine.processKey(character: ch, keyCode: kc, isUppercase: ch.isUppercase)
            } else {
                out += commitWord(engine, boundary: ch)
                out.append(ch)
            }
        }
        out += commitWord(engine, boundary: " ")
        return out
    }

    /// Commits whatever is composed in `engine` at a word boundary. Returns the plain
    /// composed word when no restore fired (`getCurrentWord()` before the boundary), or
    /// the raw restored keystrokes when it did (English-collision / invalid-spelling
    /// restore — the same result `boundary.newCharacters` carries in the
    /// English-collision restore test).
    private static func commitWord(_ engine: VNEngine, boundary: Character) -> String {
        let wordBefore = engine.getCurrentWord()
        let boundaryResult = engine.processWordBreak(character: boundary)
        let emitted = boundaryResult.newCharacters.map { $0.unicode(codeTable: .unicode) }.joined()
        guard !emitted.isEmpty else { return wordBefore }
        // Restore re-appends the boundary char after the raw keystrokes (see
        // convertHookStateToResult's vRestore branch) — strip it, it isn't part of the
        // committed word.
        return emitted.hasSuffix(String(boundary)) ? String(emitted.dropLast()) : emitted
    }

    // MARK: - CSV loading

    private static func loadCSV() throws -> [Case] {
        let url = try XCTUnwrap(
            Bundle(for: CorpusRegressionTests.self).url(forResource: "telex_test_suite", withExtension: "csv"),
            "telex_test_suite.csv missing from XKeyTests bundle")
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(text)
        guard let header = rows.first,
              let inputIdx = header.firstIndex(of: "input"),
              let expectedIdx = header.firstIndex(of: "expected_output"),
              let behaviorIdx = header.firstIndex(of: "expected_behavior") else {
            XCTFail("telex_test_suite.csv missing expected columns")
            return []
        }
        let known: Set<String> = ["transform", "restore_raw", "keep_as_typed",
                                   "cancel_keep_composed"]
        return rows.dropFirst().compactMap { fields in
            guard fields.count > max(inputIdx, expectedIdx, behaviorIdx),
                  known.contains(fields[behaviorIdx]) else { return nil }
            return Case(input: fields[inputIdx], expected: fields[expectedIdx], bucket: fields[behaviorIdx])
        }
    }

    /// Minimal RFC4180 CSV parser: handles quoted fields containing commas, embedded
    /// newlines, and doubled-quote ("") escapes — the corpus's `notes` column uses all
    /// three. CRLF and bare LF row terminators are both accepted.
    ///
    /// Walks `unicodeScalars`, not `Character`s: Swift's `Character` collapses a "\r\n"
    /// pair into a single extended grapheme cluster, so a per-`Character` switch would
    /// never match a bare "\r" or "\n" case on this CRLF-terminated file — every row
    /// would silently merge into one. Working at the scalar level keeps "\r" and "\n"
    /// as two distinct comparisons.
    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.unicodeScalars.append(c)
                i += 1
                continue
            }
            switch c {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field); field = ""
            case "\r":
                break // ignore; the following "\n" (or a lone "\r") ends the row
            case "\n":
                row.append(field); field = ""
                rows.append(row); row = []
            default:
                field.unicodeScalars.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
