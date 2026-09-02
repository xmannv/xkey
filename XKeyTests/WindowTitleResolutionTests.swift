//
//  WindowTitleResolutionTests.swift
//  XKeyTests
//
//  A window title that AX has already been asked for must never be asked for
//  again — not even when the answer was nil.
//
//  Rule matching used to read `focusedInfo?.windowTitle ?? getCurrentWindowTitle()`,
//  which cannot tell "we asked and AX said nothing" apart from "nobody has asked".
//  A snapshot resolves its title to nil exactly when the AX cascade fails, and on a
//  slow app that means it timed out — so the fallback re-ran the same up-to-six
//  round-trip cascade, on the main thread, at up to the AX messaging timeout each.
//  These tests pin the distinction: `windowTitleWasResolved` says which case a
//  snapshot is in, and only "nobody has asked" may reach for a live query.
//

import XCTest
@testable import XKey

final class WindowTitleResolutionTests: XCTestCase {

    private typealias Info = AppBehaviorDetector.FocusedElementInfo

    /// Counts the live window-title cascades (`getCurrentWindowTitle`) a detection pass
    /// runs. Both overrides also make the tests independent of the test host's own
    /// frontmost app and Accessibility permission.
    private final class CountingDetector: AppBehaviorDetector {
        private(set) var liveWindowTitleQueries = 0
        var stubbedBundleId: String? = "com.operasoftware.Opera"
        var stubbedWindowTitle: String? = "Live Title"

        override func getCurrentBundleId() -> String? {
            return stubbedBundleId
        }

        override func getCurrentWindowTitle() -> String? {
            liveWindowTitleQueries += 1
            return stubbedWindowTitle
        }
    }

    private func makeDetector() -> CountingDetector {
        let detector = CountingDetector()
        detector.windowTitleRulesEnabled = true
        return detector
    }

    // MARK: - The distinction itself

    /// `empty` is built with no windowTitleProvider, so its title is resolved-to-nil by
    /// construction. That is what makes it the exact shape of the bug, and it needs no
    /// Accessibility permission to reproduce.
    func testEmptyInfoHasAResolvedNilWindowTitle() {
        XCTAssertTrue(Info.empty.windowTitleWasResolved)
        XCTAssertNil(Info.empty.windowTitle)
    }

    func testUnresolvedSnapshotReportsItsTitleAsUnresolved() {
        let info = Info(element: nil,
                        role: nil, subrole: nil, description: nil,
                        identifier: nil, roleDescription: nil,
                        windowTitleProvider: { "Snapshot Title" })
        XCTAssertFalse(info.windowTitleWasResolved)
        XCTAssertEqual(info.windowTitle, "Snapshot Title")
        XCTAssertTrue(info.windowTitleWasResolved, "resolving must record that it happened")
    }

    // MARK: - Rule matching

    /// The regression this whole change exists for: a snapshot whose title resolved to
    /// nil must not send rule matching back into a fresh AX cascade.
    func testRuleMatchingTrustsAResolvedNilTitle() {
        let detector = makeDetector()

        _ = detector.findAllMatchingRules(focusedInfo: Info.empty)

        XCTAssertEqual(detector.liveWindowTitleQueries, 0,
                       "a title that already resolved to nil must be trusted, not re-queried")
    }

    /// The control: with no snapshot at all nobody has asked yet, so the live query is
    /// still the right answer — and still happens. Without this, the test above would
    /// also pass on a build that never queries the title at all.
    func testRuleMatchingStillQueriesLiveWhenThereIsNoSnapshot() {
        let detector = makeDetector()

        _ = detector.findAllMatchingRules()

        XCTAssertEqual(detector.liveWindowTitleQueries, 1,
                       "with nothing resolved, the live cascade is the only source of the title")
    }

    /// A snapshot that has not resolved its title yet resolves through the snapshot, so
    /// the value is cached there for the rest of the pass — never through a live query
    /// whose result nothing would remember.
    func testUnresolvedSnapshotResolvesThroughTheSnapshotNotLive() {
        let detector = makeDetector()
        var providerCalls = 0
        let info = Info(element: nil,
                        role: nil, subrole: nil, description: nil,
                        identifier: nil, roleDescription: nil,
                        windowTitleProvider: { providerCalls += 1; return "Snapshot Title" })

        _ = detector.findAllMatchingRules(focusedInfo: info)
        _ = detector.findAllMatchingRules(focusedInfo: info)

        XCTAssertEqual(detector.liveWindowTitleQueries, 0)
        XCTAssertEqual(providerCalls, 1, "the snapshot resolves once and keeps the answer")
    }

    // MARK: - Opera Speed Dial (the other consumer of a resolved title)

    /// Speed Dial has no focused element, so it is detected from the window title alone.
    /// A title the caller already resolved must be the one it reads.
    func testOperaSpeedDialUsesTheResolvedTitle() {
        let detector = makeDetector()
        let info = Info(element: nil,
                        role: nil, subrole: nil, description: nil,
                        identifier: nil, roleDescription: nil,
                        windowTitle: "Speed Dial")

        XCTAssertTrue(detector.isAddressBar(info: info, bundleId: "com.operasoftware.Opera"))
        XCTAssertEqual(detector.liveWindowTitleQueries, 0)
    }

    func testOperaSpeedDialTrustsAResolvedNilTitle() {
        let detector = makeDetector()
        detector.stubbedWindowTitle = "Speed Dial"

        XCTAssertFalse(detector.isAddressBar(info: Info.empty, bundleId: "com.operasoftware.Opera"),
                       "a resolved nil title is an answer: it is not the Speed Dial title")
        XCTAssertEqual(detector.liveWindowTitleQueries, 0)
    }

    // MARK: - The snapshot taken when nothing is focused

    /// `getFocusedElementInfo()` returns `withoutFocusedElement()` rather than `empty`
    /// when AX reports nothing focused, precisely so that trusting a resolved nil does
    /// not blind the title-only detectors. It carries no element attributes but its
    /// title is still resolvable.
    func testWithoutFocusedElementCarriesNoElementButAResolvableTitle() {
        let info = Info.withoutFocusedElement()

        XCTAssertNil(info.element)
        XCTAssertNil(info.role)
        XCTAssertFalse(info.windowTitleWasResolved,
                       "the title must be resolvable, not resolved-to-nil by construction")
    }
}
