//
//  FocusedElementInfoLazyTests.swift
//  XKeyTests
//
//  Tests for lazy AXDOMIdentifier/AXDOMClassList loading in FocusedElementInfo
//  and the role gates guarding DOM-attribute queries in address bar detection.
//  These guarantee the Gmail-freeze fix does not regress existing detection:
//  - Notion code block, Chromium/Firefox address bars, rules with AX patterns
//    must still see DOM attributes when they ask for them.
//  - Hot-path consumers (signature) must never fire the lazy renderer query.
//

import XCTest
@testable import XKey

class FocusedElementInfoLazyTests: XCTestCase {

    private typealias Info = AppBehaviorDetector.FocusedElementInfo

    /// Reference-type counter so provider closures can record fires after makeInfo returns
    private final class Counter {
        var count = 0
    }

    /// Build an info with counting DOM providers
    private func makeInfo(
        role: String? = nil,
        subrole: String? = nil,
        description: String? = nil,
        identifier: String? = nil,
        domIdentifier: String? = nil,
        domClasses: [String]? = nil,
        domIdCounter: Counter? = nil,
        domClassesCounter: Counter? = nil
    ) -> Info {
        return Info(
            element: nil,
            role: role,
            subrole: subrole,
            description: description,
            identifier: identifier,
            roleDescription: nil,
            domIdentifierProvider: domIdCounter.map { counter in
                { counter.count += 1; return domIdentifier }
            },
            domClassesProvider: domClassesCounter.map { counter in
                { counter.count += 1; return domClasses }
            }
        )
    }

    // MARK: - Lazy semantics

    func testDOMProvidersNotFiredOnInit() {
        let idCounter = Counter()
        let classCounter = Counter()
        _ = makeInfo(role: "AXTextArea",
                     domIdentifier: "x", domClasses: ["a"],
                     domIdCounter: idCounter, domClassesCounter: classCounter)
        XCTAssertEqual(idCounter.count, 0)
        XCTAssertEqual(classCounter.count, 0)
    }

    func testSignatureDoesNotFireDOMIdentifierQuery() {
        let idCounter = Counter()
        let info = makeInfo(role: "AXTextArea", description: "Message Body",
                            domIdentifier: "compose-1",
                            domIdCounter: idCounter)
        let sig = info.signature
        XCTAssertEqual(idCounter.count, 0, "signature must never fire the lazy DOM query")
        XCTAssertFalse(sig.contains("dom:"))
        XCTAssertTrue(sig.contains("AXTextArea"))
        XCTAssertTrue(sig.contains("desc:Message Body"))
    }

    func testSignatureIncludesDOMIdentifierAfterLoaded() {
        let idCounter = Counter()
        let info = makeInfo(role: "AXTextField",
                            domIdentifier: "urlbar-input",
                            domIdCounter: idCounter)
        XCTAssertEqual(info.domIdentifier, "urlbar-input")
        XCTAssertEqual(idCounter.count, 1)
        XCTAssertTrue(info.signature.contains("dom:urlbar-input"))
        XCTAssertEqual(idCounter.count, 1, "signature must reuse the cached value")
    }

    func testDOMClassesFiredOnceAndCached() {
        let classCounter = Counter()
        let info = makeInfo(domClasses: ["Am", "LW-avf"], domClassesCounter: classCounter)
        XCTAssertEqual(info.domClasses, ["Am", "LW-avf"])
        XCTAssertEqual(info.domClasses, ["Am", "LW-avf"])
        XCTAssertEqual(classCounter.count, 1)
    }

    func testNilProviderResultIsCachedNotRetried() {
        let classCounter = Counter()
        let info = makeInfo(domClasses: nil, domClassesCounter: classCounter)
        XCTAssertNil(info.domClasses)
        XCTAssertNil(info.domClasses)
        XCTAssertEqual(classCounter.count, 1, "nil result must be cached, not re-queried")
    }

    func testDirectValuesBypassProviders() {
        let info = Info(
            element: nil,
            role: "AXTextArea", subrole: nil, description: nil,
            identifier: nil, domIdentifier: "direct-id", domClasses: ["direct-class"],
            roleDescription: nil
        )
        XCTAssertEqual(info.domIdentifier, "direct-id")
        XCTAssertEqual(info.domClasses, ["direct-class"])
        XCTAssertTrue(info.signature.contains("dom:direct-id"))
    }

    // MARK: - Chromium address bar gate

    func testChromiumAddressBarByDescriptionDoesNotFireDOMQuery() {
        let classCounter = Counter()
        let info = makeInfo(role: "AXTextField", description: "Address and search bar",
                            domClasses: ["OmniboxViewViews"], domClassesCounter: classCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isChromiumAddressBar(info: info))
        XCTAssertEqual(classCounter.count, 0)
    }

    func testChromiumAddressBarDOMFallbackForNativeTextField() {
        let classCounter = Counter()
        // Localized browser UI: description doesn't match, DOM class fallback must work
        let info = makeInfo(role: "AXTextField", description: "Thanh địa chỉ và tìm kiếm",
                            domClasses: ["OmniboxViewViews"], domClassesCounter: classCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isChromiumAddressBar(info: info))
        XCTAssertEqual(classCounter.count, 1)
    }

    func testChromiumAddressBarSkipsDOMQueryForWebContent() {
        let classCounter = Counter()
        // Gmail body: AXTextArea — never the omnibox, must not fire the renderer query
        let info = makeInfo(role: "AXTextArea", description: "Message Body",
                            domClasses: ["Am", "LW-avf"], domClassesCounter: classCounter)
        XCTAssertFalse(AppBehaviorDetector.shared.isChromiumAddressBar(info: info))
        XCTAssertEqual(classCounter.count, 0)
    }

    func testChromiumAddressBarTextFieldWithoutOmniboxClasses() {
        let classCounter = Counter()
        let info = makeInfo(role: "AXTextField", description: "Search",
                            domClasses: ["SomeOtherView"], domClassesCounter: classCounter)
        XCTAssertFalse(AppBehaviorDetector.shared.isChromiumAddressBar(info: info))
        XCTAssertEqual(classCounter.count, 1)
    }

    // MARK: - Firefox-style address bar gate

    func testFirefoxAddressBarByIdentifierDoesNotFireDOMQuery() {
        let idCounter = Counter()
        let info = makeInfo(role: "AXTextField", identifier: "urlbar-input",
                            domIdentifier: "urlbar-input", domIdCounter: idCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isFirefoxStyleAddressBar(info: info))
        XCTAssertEqual(idCounter.count, 0)
    }

    func testFirefoxAddressBarByDescriptionDoesNotFireDOMQuery() {
        let idCounter = Counter()
        let info = makeInfo(role: "AXTextField",
                            description: "Search with Google or enter address",
                            domIdentifier: "urlbar-input", domIdCounter: idCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isFirefoxStyleAddressBar(info: info))
        XCTAssertEqual(idCounter.count, 0)
    }

    func testFirefoxAddressBarByDOMIdForNativeTextField() {
        let idCounter = Counter()
        // Localized Firefox UI: identifier/description miss, DOM ID must still match
        let info = makeInfo(role: "AXTextField", description: "Tìm kiếm hoặc nhập địa chỉ",
                            domIdentifier: "urlbar-input", domIdCounter: idCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isFirefoxStyleAddressBar(info: info))
        XCTAssertEqual(idCounter.count, 1)
    }

    func testFirefoxAddressBarSkipsDOMQueryForWebContent() {
        let idCounter = Counter()
        let info = makeInfo(role: "AXGroup", description: "editor",
                            domIdentifier: "urlbar-input", domIdCounter: idCounter)
        XCTAssertFalse(AppBehaviorDetector.shared.isFirefoxStyleAddressBar(info: info))
        XCTAssertEqual(idCounter.count, 0)
    }

    // MARK: - Notion code block (bundle-gated caller, direct read)

    func testNotionCodeBlockStillReadsDOMClasses() {
        let classCounter = Counter()
        let info = makeInfo(role: "AXTextArea",
                            domClasses: ["content-editable-leaf-rtl", "notranslate"],
                            domClassesCounter: classCounter)
        XCTAssertTrue(AppBehaviorDetector.shared.isNotionCodeBlock(info: info))
        XCTAssertEqual(classCounter.count, 1)
    }

    // MARK: - Window Title Rules with AX patterns

    func testRuleWithDOMClassPatternFiresLazyQueryAndMatches() {
        let classCounter = Counter()
        let info = makeInfo(role: "AXTextArea",
                            domClasses: ["Am", "LW-avf"], domClassesCounter: classCounter)
        let rule = WindowTitleRule(
            name: "Test DOM rule",
            bundleIdPattern: "com.google.Chrome",
            titlePattern: "",
            matchMode: .contains,
            axDOMClassList: ["LW-avf"]
        )
        XCTAssertTrue(rule.matches(bundleId: "com.google.Chrome", windowTitle: "Gmail", axInfo: info))
        XCTAssertEqual(classCounter.count, 1, "rules with AX patterns must still read DOM classes")
    }

    func testTitleOnlyRuleDoesNotFireDOMQuery() {
        let idCounter = Counter()
        let classCounter = Counter()
        let info = makeInfo(role: "AXTextArea",
                            domIdentifier: "x", domClasses: ["y"],
                            domIdCounter: idCounter, domClassesCounter: classCounter)
        let rule = WindowTitleRule(
            name: "Title only",
            bundleIdPattern: "",
            titlePattern: "Google Docs",
            matchMode: .contains
        )
        XCTAssertTrue(rule.matches(bundleId: "com.google.Chrome", windowTitle: "Google Docs", axInfo: info))
        XCTAssertEqual(classCounter.count, 0)
        XCTAssertEqual(idCounter.count, 0)
    }
}
