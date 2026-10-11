//
//  ServicesProviderTests.swift
//  XKeyTests
//
//  Covers the shared add-to-user-dictionary pipeline (UserDictionaryService)
//  and the NSServices entry point (ServicesProvider) that feeds it.
//

import XCTest
@testable import XKey

class ServicesProviderTests: XCTestCase {

    // MARK: - extractWords (shared pipeline)

    func testExtractWordsSplitsOnWhitespaceAndNewlines() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: "xin chào"), ["xin", "chào"])
        XCTAssertEqual(UserDictionaryService.extractWords(from: "một\nhai\tba"), ["một", "hai", "ba"])
    }

    func testExtractWordsStripsEdgePunctuation() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: "hello, (world)!"), ["hello", "world"])
        XCTAssertEqual(UserDictionaryService.extractWords(from: "\"đẹp\"…"), ["đẹp"])
    }

    func testExtractWordsKeepsInternalApostrophesAndHyphens() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: "don't state-of-the-art"),
                       ["don't", "state-of-the-art"])
    }

    func testExtractWordsLowercases() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: "XKey"), ["xkey"])
    }

    func testExtractWordsDedupesCaseInsensitivePreservingOrder() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: "Word word WORD other"),
                       ["word", "other"])
    }

    func testExtractWordsEmptyInput() {
        XCTAssertEqual(UserDictionaryService.extractWords(from: ""), [])
        XCTAssertEqual(UserDictionaryService.extractWords(from: "   \n\t  "), [])
        XCTAssertEqual(UserDictionaryService.extractWords(from: "— … ,"), [])
    }

    func testExtractWordsCapsResultAtMaxWords() {
        let many = (1...200).map { "w\($0)" }.joined(separator: " ")
        let words = UserDictionaryService.extractWords(from: many)
        XCTAssertEqual(words.count, UserDictionaryService.maxWords)
        XCTAssertEqual(words.first, "w1")
    }

    /// A selection longer than the input cap can cut the last token mid-word —
    /// the truncated fragment must be dropped, not stored.
    func testExtractWordsFromSelectionDropsTruncatedTailWord() {
        let text = "first " + String(repeating: "z", count: UserDictionaryService.maxInputLength)
        XCTAssertEqual(UserDictionaryService.extractWords(fromSelection: text), ["first"])
    }

    /// …but a token that ends exactly at the cap boundary is kept.
    func testExtractWordsFromSelectionKeepsWordEndingAtCapBoundary() {
        let tail = String(repeating: "z", count: UserDictionaryService.maxInputLength - "first ".count)
        let text = "first " + tail + " extra"
        XCTAssertEqual(UserDictionaryService.extractWords(fromSelection: text), ["first", tail])
    }

    /// An over-cap selection that yields zero words must not crash (the
    /// truncated-tail drop has nothing to drop).
    func testExtractWordsFromSelectionEmptyResultSurvivesTruncationCheck() {
        let text = String(repeating: "…", count: UserDictionaryService.maxInputLength + 1)
        XCTAssertEqual(UserDictionaryService.extractWords(fromSelection: text), [])
    }

    // MARK: - addWords (shared pipeline)

    /// addWords splits the requested words into newly-added vs already-present,
    /// and only the new ones reach the dictionary.
    func testAddWordsReportsAddedVsExisting() {
        let word = "udsvcaddword"
        // Clean slate
        SharedSettings.shared.removeUserDictionaryWord(word)
        defer { SharedSettings.shared.removeUserDictionaryWord(word) }

        // First pass: word is new.
        let first = UserDictionaryService.shared.addWords([word])
        XCTAssertEqual(first.added, [word])
        XCTAssertEqual(first.alreadyPresent, [])
        XCTAssertTrue(SharedSettings.shared.isWordInUserDictionary(word))

        // Second pass: same word is now a duplicate, nothing new is written.
        let second = UserDictionaryService.shared.addWords([word])
        XCTAssertEqual(second.added, [])
        XCTAssertEqual(second.alreadyPresent, [word])
    }

    /// Callers may pass unnormalized input — addWords applies the same
    /// lowercase+trim normalization as addUserDictionaryWord.
    func testAddWordsNormalizesInput() {
        let word = "udsvcnormword"
        SharedSettings.shared.removeUserDictionaryWord(word)
        defer { SharedSettings.shared.removeUserDictionaryWord(word) }

        let result = UserDictionaryService.shared.addWords(["  UDSvcNormWord  "])
        XCTAssertEqual(result.added, [word])
        XCTAssertTrue(SharedSettings.shared.isWordInUserDictionary(word))
        XCTAssertFalse(SharedSettings.shared.getUserDictionaryWords().contains("  UDSvcNormWord  "))
    }

    // MARK: - preview (shared formatting)

    func testPreviewJoinsAndOverflows() {
        XCTAssertEqual(UserDictionaryService.preview(of: ["a", "b"], limit: 5), "a, b")
        let six = ["a", "b", "c", "d", "e", "f"]
        XCTAssertTrue(UserDictionaryService.preview(of: six, limit: 3).hasPrefix("a, b, c"))
    }

    // MARK: - Service entry point

    /// Invoke the real NSServices entry point with a pasteboard carrying
    /// NSStringPboardType, the same way the system delivers a selection.
    func testServiceEntryPointAddsWordsToUserDictionary() throws {
        let wordA = "svcptestalpha"
        let wordB = "svcptestbeta"
        // Clean slate in case a previous run left them behind
        SharedSettings.shared.removeUserDictionaryWord(wordA)
        SharedSettings.shared.removeUserDictionaryWord(wordB)
        defer {
            SharedSettings.shared.removeUserDictionaryWord(wordA)
            SharedSettings.shared.removeUserDictionaryWord(wordB)
        }

        let pboard = NSPasteboard(name: NSPasteboard.Name("svc-entry-test"))
        pboard.clearContents()
        XCTAssertTrue(pboard.setString("\(wordA), \(wordB).", forType: .string))

        var serviceError: NSString?
        ServicesProvider.shared.addToUserDictionary(
            pboard, userData: nil, error: &serviceError
        )
        XCTAssertNil(serviceError)

        // The handler defers the dictionary write to the main queue.
        let deadline = Date(timeIntervalSinceNow: 3)
        var found = false
        while Date() < deadline && !found {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            found = SharedSettings.shared.isWordInUserDictionary(wordA)
                && SharedSettings.shared.isWordInUserDictionary(wordB)
        }
        XCTAssertTrue(found, "service should add both extracted words to the user dictionary")
    }

    /// An empty pasteboard must report an error and write nothing.
    func testServiceEntryPointRejectsEmptyPasteboard() throws {
        let pboard = NSPasteboard(name: NSPasteboard.Name("svc-entry-empty"))
        pboard.clearContents()

        var serviceError: NSString?
        ServicesProvider.shared.addToUserDictionary(
            pboard, userData: nil, error: &serviceError
        )
        XCTAssertNotNil(serviceError)
    }

    // MARK: - Services menu enable state

    private func withScratchSuite(_ body: (UserDefaults, String) -> Void) {
        let suite = "svc-enable-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults, suite)
        defaults.removePersistentDomain(forName: suite)
    }

    /// A disabled `NSServicesStatus` entry must be flipped back to enabled.
    func testEnsureServiceMenuEnabledFixesDisabledEntry() {
        withScratchSuite { defaults, suite in
            let key = "com.codetay.XKey - XKey: Add to Personal Dictionary - addToUserDictionary"
            defaults.set([
                key: [
                    "enabled_context_menu": false,
                    "enabled_services_menu": false,
                    "presentation_modes": ["ContextMenu": false, "ServicesMenu": false],
                    // A user-assigned service shortcut — must survive the fix.
                    "key_equivalent": "@~d",
                ],
                "other.app - Some Service - doThing": [
                    "enabled_context_menu": false,
                    "enabled_services_menu": false,
                ],
            ], forKey: "NSServicesStatus")

            ServicesProvider.shared.ensureServiceMenuEnabled(
                bundleID: "com.codetay.XKey", suiteName: suite
            )

            let status = defaults.dictionary(forKey: "NSServicesStatus") as? [String: [String: Any]]
            let fixed = status?[key]
            XCTAssertEqual(fixed?["enabled_context_menu"] as? Bool, true)
            XCTAssertEqual(fixed?["enabled_services_menu"] as? Bool, true)
            let modes = fixed?["presentation_modes"] as? [String: Bool]
            XCTAssertEqual(modes?["ContextMenu"], true)
            XCTAssertEqual(modes?["ServicesMenu"], true)
            XCTAssertEqual(fixed?["key_equivalent"] as? String, "@~d")

            // Other apps' entries must be untouched.
            let other = status?["other.app - Some Service - doThing"]
            XCTAssertEqual(other?["enabled_context_menu"] as? Bool, false)
        }
    }

    /// An already-enabled entry must be left alone (no rewrite needed).
    func testEnsureServiceMenuEnabledLeavesEnabledEntryAlone() {
        withScratchSuite { defaults, suite in
            let key = "com.codetay.XKey - XKey: Test - addToUserDictionary"
            let enabled: [String: Any] = [
                "enabled_context_menu": true,
                "enabled_services_menu": true,
                "presentation_modes": ["ContextMenu": true, "ServicesMenu": true],
            ]
            defaults.set([key: enabled], forKey: "NSServicesStatus")

            ServicesProvider.shared.ensureServiceMenuEnabled(
                bundleID: "com.codetay.XKey", suiteName: suite
            )

            let status = defaults.dictionary(forKey: "NSServicesStatus") as? [String: [String: Any]]
            XCTAssertEqual(status?[key]?["enabled_context_menu"] as? Bool, true)
        }
    }
}
