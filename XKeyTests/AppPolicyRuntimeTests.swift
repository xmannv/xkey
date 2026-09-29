import XCTest
@testable import XKey

final class AppPolicyRuntimeTests: XCTestCase {
    func testWindowTitleRulesHotkeyAppliesCachedTitlePolicyBeforeAsyncRefresh() {
        let rule = WindowTitleRule(
            name: "English terminal",
            bundleIdPattern: "com.example.Editor",
            titlePattern: "Terminal",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )
        let runtime = makeRuntime(rules: [rule])
        let handler = KeyboardEventHandler()
        handler.setVietnamese(true)
        var languageSeenByRefresh: Int?

        runtime.reevaluateAfterWindowTitleRulesChange(
            context: AppContext(bundleIdentifier: "com.example.Editor",
                                windowTitle: "Project — Terminal",
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true),
            currentVietnameseEnabled: true,
            preferences: snapshot(),
            apply: {
                handler.applyAppPolicyDecision($0, currentVietnameseEnabled: true)
            },
            invalidateCache: {},
            refresh: { languageSeenByRefresh = handler.engine.vLanguage }
        )

        XCTAssertEqual(languageSeenByRefresh, 0)
        XCTAssertTrue(handler.durableVietnameseEnabled)
    }

    func testExpiredUnchangedContextRemainsUsableWhileRefreshing() {
        XCTAssertEqual(
            AppPolicyRuntime.cacheDecision(
                cachedWindowTitle: "Editor",
                liveWindowTitle: "Editor",
                age: 0.3
            ),
            AppContextCacheDecision(useCached: true, shouldRefresh: true)
        )
    }

    func testChangedLiveTitleInvalidatesCachedContextBeforeProcessing() {
        XCTAssertEqual(
            AppPolicyRuntime.cacheDecision(
                cachedWindowTitle: "Editor",
                liveWindowTitle: "Terminal",
                age: 0.1
            ),
            AppContextCacheDecision(useCached: false, shouldRefresh: true)
        )
    }

    func testExcludedAppDisablesTransformation() {
        var preferences = Preferences()
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: "com.example.Blocked", appName: "Blocked")
        ]
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.Blocked", windowTitle: nil, overlayName: nil),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .disableTransformation)
    }

    func testDisabledExclusionRulesIgnoreExcludedApps() {
        var preferences = Preferences()
        preferences.exclusionRulesEnabled = false
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: "com.example.Blocked", appName: "Blocked")
        ]

        XCTAssertEqual(makeRuntime().evaluate(
            context: AppContext(bundleIdentifier: "com.example.Blocked", windowTitle: nil, overlayName: nil),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .keepCurrentLanguage)
    }

    func testMatchingWindowTitleRuleAppliesConfiguredState() {
        let rule = WindowTitleRule(
            name: "English terminal",
            bundleIdPattern: "com.example.Editor",
            titlePattern: "Terminal",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )
        let runtime = makeRuntime(rules: [rule])

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor", windowTitle: "Project — Terminal", overlayName: nil),
            currentVietnameseEnabled: true,
            preferences: snapshot()
        ), .overrideVietnamese(false))
    }

    func testWindowRuleOverrideDoesNotReplaceDurableHandlerLanguage() {
        let handler = KeyboardEventHandler()
        handler.setVietnamese(true)

        handler.applyAppPolicyDecision(.overrideVietnamese(false),
                                       currentVietnameseEnabled: true)
        XCTAssertTrue(handler.durableVietnameseEnabled)
        XCTAssertEqual(handler.engine.vLanguage, 0)

        handler.applyAppPolicyDecision(.keepCurrentLanguage,
                                       currentVietnameseEnabled: true)
        XCTAssertTrue(handler.durableVietnameseEnabled)
        XCTAssertEqual(handler.engine.vLanguage, 1)
    }

    func testResolvedAXWindowTitlePolicyAppliesConfiguredState() {
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(
                bundleIdentifier: "com.example.Editor",
                windowTitle: "Document",
                overlayName: nil,
                resolvedInputMethodPolicy: .disable,
                resolvedTargetInputSourceId: "com.apple.keylayout.ABC",
                hasResolvedWindowTitleRules: true
            ),
            currentVietnameseEnabled: true,
            preferences: snapshot()
        ), .overrideVietnamese(false))
    }

    func testResolvedNilTitleKeepsCurrentLanguageWhenAXIsUnavailable() {
        XCTAssertEqual(makeRuntime().evaluate(
            context: AppContext(
                bundleIdentifier: "com.example.Editor",
                windowTitle: nil,
                overlayName: nil,
                hasResolvedWindowTitleRules: true
            ),
            currentVietnameseEnabled: true,
            preferences: snapshot()
        ), .keepCurrentLanguage)
    }

    func testExplicitLanguageChangeUpdatesSmartSwitchBeforeNextEvaluation() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore(languages: ["com.example.Editor": false])
        let runtime = makeRuntime(store: store)
        let context = AppContext(bundleIdentifier: "com.example.Editor", windowTitle: nil, overlayName: nil)

        runtime.saveCurrentLanguage(true, context: context, preferences: snapshot(preferences))

        XCTAssertEqual(runtime.evaluate(
            context: context,
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .keepCurrentLanguage)
        XCTAssertEqual(store.saved, ["com.example.Editor": true])
    }

    func testDisabledWindowTitleRulesIgnoreMatches() {
        let rule = WindowTitleRule(
            name: "Vietnamese terminal",
            bundleIdPattern: "com.example.Editor",
            titlePattern: "Terminal",
            matchMode: .contains,
            inputMethodPolicy: .enable
        )
        let runtime = makeRuntime(rules: [rule])

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor", windowTitle: "Terminal", overlayName: nil),
            currentVietnameseEnabled: false,
            preferences: snapshot(windowTitleRulesEnabled: false)
        ), .keepCurrentLanguage)
    }

    func testKnownSmartSwitchAppRestoresSavedLanguage() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore(languages: ["com.example.Editor": true])
        let runtime = makeRuntime(store: store)

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor", windowTitle: nil, overlayName: nil),
            currentVietnameseEnabled: false,
            preferences: snapshot(preferences)
        ), .restoreVietnamese(true))
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testUnknownSmartSwitchAppSavesCurrentLanguage() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore()
        let runtime = makeRuntime(store: store)

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.New", windowTitle: nil, overlayName: nil),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .keepCurrentLanguage)
        XCTAssertEqual(store.saved, ["com.example.New": true])
    }

    func testOverlayBundleUsesSamePolicy() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: "com.example.Blocked", appName: "Blocked")
        ]
        let store = FakeSmartSwitchStore(languages: ["com.apple.Spotlight": true])
        let runtime = makeRuntime(store: store)

        XCTAssertEqual(runtime.evaluate(
            context: AppContext(bundleIdentifier: "com.example.Blocked", windowTitle: nil, overlayName: "Spotlight"),
            currentVietnameseEnabled: false,
            preferences: snapshot(preferences)
        ), .restoreVietnamese(true))
    }

    func testUnknownOverlayDoesNotUseUnderlyingAppPolicy() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore(languages: ["com.example.Editor": false])

        XCTAssertEqual(makeRuntime(store: store).evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor", windowTitle: nil, overlayName: "Unknown Launcher"),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .keepCurrentLanguage)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testProcessHostDoesNotChangeResult() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let appStore = FakeSmartSwitchStore(languages: ["com.example.Editor": false])
        let inputMethodStore = FakeSmartSwitchStore(languages: ["com.example.Editor": false])
        let context = AppContext(bundleIdentifier: "com.example.Editor", windowTitle: "Document", overlayName: nil)

        let appResult = makeRuntime(store: appStore).evaluate(
            context: context,
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        )
        let inputMethodResult = makeRuntime(store: inputMethodStore).evaluate(
            context: context,
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        )

        XCTAssertEqual(appResult, inputMethodResult)
    }

    func testRefinementKeepsTheLanguageTheUserSetInPlace() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore(languages: ["com.example.Editor": false])

        XCTAssertEqual(makeRuntime(store: store).evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor",
                                windowTitle: "Document",
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        ), .keepCurrentLanguage)
    }

    func testRefinementDoesNotRecordAnAppItNeverEntered() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore()

        _ = makeRuntime(store: store).evaluate(
            context: AppContext(bundleIdentifier: "com.example.New",
                                windowTitle: nil,
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences)
        )

        XCTAssertTrue(store.saved.isEmpty)
    }

    func testRefinementStillAppliesWindowTitlePolicy() {
        XCTAssertEqual(makeRuntime().evaluate(
            context: AppContext(bundleIdentifier: "com.example.Editor",
                                windowTitle: "Document",
                                overlayName: nil,
                                resolvedInputMethodPolicy: .disable,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            currentVietnameseEnabled: true,
            preferences: snapshot()
        ), .overrideVietnamese(false))
    }

    /// Toggling Window Title Rules re-evaluates the window the user is already in. The
    /// provisional context must not restore an app's language the way entering it does.
    func testWindowTitleRulesToggleDoesNotReenterTheApp() {
        var preferences = Preferences()
        preferences.smartSwitchEnabled = true
        let store = FakeSmartSwitchStore(languages: ["com.example.Editor": false])
        var applied: [AppPolicyDecision] = []

        makeRuntime(store: store).reevaluateAfterWindowTitleRulesChange(
            context: AppContext(bundleIdentifier: "com.example.Editor",
                                windowTitle: "Document",
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            currentVietnameseEnabled: true,
            preferences: snapshot(preferences),
            apply: { applied.append($0) },
            invalidateCache: {},
            refresh: {}
        )

        XCTAssertEqual(applied, [.keepCurrentLanguage])
    }

    // MARK: - Input-source rules

    /// An entry has no window title yet. It cannot tell that no rule covers the window,
    /// so it must leave the rule-switched source alone; restoring the pre-rule source
    /// there flips it out and back once the refinement matches the title.
    func testEntryWithoutTitleKeepsTheRuleSwitchedSource() {
        let runtime = makeRuntime(rules: [sheetsToABC])

        XCTAssertEqual(runtime.inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.google.Chrome",
                                windowTitle: nil,
                                overlayName: nil),
            windowTitleRulesEnabled: true
        ), .none)
    }

    func testRefinementWithNoMatchingRuleRestoresThePreRuleSource() {
        XCTAssertEqual(makeRuntime(rules: [sheetsToABC]).inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.google.Chrome",
                                windowTitle: "Inbox",
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            windowTitleRulesEnabled: true
        ), .restorePreRuleSource)
    }

    func testRefinementUsesTheTargetResolvedWithItsSnapshot() {
        XCTAssertEqual(makeRuntime().inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.google.Chrome",
                                windowTitle: "Budget - Sheets",
                                overlayName: nil,
                                resolvedTargetInputSourceId: "com.apple.keylayout.ABC",
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            windowTitleRulesEnabled: true
        ), .select("com.apple.keylayout.ABC"))
    }

    /// A rule with no title pattern covers the whole app, so an entry can apply it early.
    func testEntryAppliesAnAppWideRule() {
        let appWide = WindowTitleRule(name: "Terminal is English",
                                      bundleIdPattern: "com.apple.Terminal",
                                      titlePattern: "",
                                      matchMode: .contains,
                                      targetInputSourceId: "com.apple.keylayout.ABC")

        XCTAssertEqual(makeRuntime(rules: [appWide]).inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.apple.Terminal",
                                windowTitle: nil,
                                overlayName: nil),
            windowTitleRulesEnabled: true
        ), .select("com.apple.keylayout.ABC"))
    }

    func testDisabledRulesRestoreThePreRuleSourceOnceTheWindowIsKnown() {
        XCTAssertEqual(makeRuntime(rules: [sheetsToABC]).inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.google.Chrome",
                                windowTitle: "Budget - Sheets",
                                overlayName: nil,
                                hasResolvedWindowTitleRules: true,
                                appliesSmartSwitch: false),
            windowTitleRulesEnabled: false
        ), .restorePreRuleSource)
    }

    func testOverlayLeavesTheInputSourceAlone() {
        XCTAssertEqual(makeRuntime(rules: [sheetsToABC]).inputSourceRuleAction(
            context: AppContext(bundleIdentifier: "com.google.Chrome",
                                windowTitle: nil,
                                overlayName: "Spotlight"),
            windowTitleRulesEnabled: true
        ), .none)
    }

    private var sheetsToABC: WindowTitleRule {
        WindowTitleRule(name: "Sheets is English",
                        bundleIdPattern: "com.google.Chrome",
                        titlePattern: "Sheets",
                        matchMode: .contains,
                        targetInputSourceId: "com.apple.keylayout.ABC")
    }

    /// A Smart Switch restore sets the language once. It must not pin it: the user's next
    /// toggle has to reach the typing path, not just the menu bar.
    func testRestoredLanguageYieldsToTheNextToggle() throws {
        let handler = KeyboardEventHandler()
        let event = try keyDown()
        try skipUnlessTheTapPathIsOpen(handler, event)

        handler.applyAppPolicyDecision(.restoreVietnamese(false), currentVietnameseEnabled: true)
        handler.setVietnamese(true)
        handler.engine.vLanguage = 0

        XCTAssertTrue(handler.shouldProcessEvent(event, type: .keyDown),
                      "the toggle back to Vietnamese must be typed, not just shown")
        XCTAssertEqual(handler.engine.vLanguage, 1)
    }

    func testDisabledInputSourceBlocksTypingUntilTheUserLeavesIt() throws {
        let handler = KeyboardEventHandler()
        let event = try keyDown()
        try skipUnlessTheTapPathIsOpen(handler, event)

        handler.inputSourceEnabled = false
        XCTAssertFalse(handler.shouldProcessEvent(event, type: .keyDown),
                       "a source XKey is configured off for must not be transformed")

        handler.inputSourceEnabled = true
        XCTAssertTrue(handler.shouldProcessEvent(event, type: .keyDown),
                      "leaving that source must not leave typing blocked")
    }

    func testLeavingADisabledInputSourceKeepsTheWindowTitleOverride() throws {
        let handler = KeyboardEventHandler()
        let event = try keyDown()
        try skipUnlessTheTapPathIsOpen(handler, event)

        handler.setVietnamese(false)
        handler.applyAppPolicyDecision(.overrideVietnamese(true), currentVietnameseEnabled: false)
        handler.inputSourceEnabled = false
        _ = handler.shouldProcessEvent(event, type: .keyDown)
        handler.inputSourceEnabled = true
        handler.engine.vLanguage = 0

        XCTAssertTrue(handler.shouldProcessEvent(event, type: .keyDown))
        XCTAssertEqual(handler.engine.vLanguage, 1,
                       "the window-title rule still covers this window after the round trip")
    }

    private func keyDown() throws -> CGEvent {
        try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true))
    }

    /// The handler also yields to a live XKeyIM tap and to an excluded frontmost app,
    /// both of which belong to the machine running the tests, not to these tests.
    private func skipUnlessTheTapPathIsOpen(_ handler: KeyboardEventHandler,
                                            _ event: CGEvent) throws {
        handler.setVietnamese(true)
        try XCTSkipUnless(handler.shouldProcessEvent(event, type: .keyDown),
                          "the tap path is closed in this environment (a live XKeyIM tap owns input, or the frontmost app is excluded)")
    }

    private func makeRuntime(
        store: FakeSmartSwitchStore = FakeSmartSwitchStore(),
        rules: [WindowTitleRule] = []
    ) -> AppPolicyRuntime {
        AppPolicyRuntime(smartSwitchStore: store, windowTitleRules: { rules })
    }

    private func snapshot(
        _ preferences: Preferences = Preferences(),
        windowTitleRulesEnabled: Bool = true
    ) -> RuntimePreferences {
        RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: true,
            windowTitleRulesEnabled: windowTitleRulesEnabled,
            remoteDesktopInjectMode: false
        )
    }
}

private final class FakeSmartSwitchStore: AppPolicySmartSwitchStore {
    var languages: [String: Bool]
    private(set) var saved: [String: Bool] = [:]

    init(languages: [String: Bool] = [:]) {
        self.languages = languages
    }

    func vietnameseEnabled(for bundleIdentifier: String) -> Bool? {
        languages[bundleIdentifier]
    }

    func saveVietnameseEnabled(_ enabled: Bool, for bundleIdentifier: String) {
        languages[bundleIdentifier] = enabled
        saved[bundleIdentifier] = enabled
    }
}

/// Where Smart Switch is decided. It must not ride on an AX pass: any newer pass
/// supersedes the one in flight (the tap's detection request on the first keystroke, a
/// click's focus check), and in Electron apps, whose AX round-trips run up to the
/// messaging timeout, the user nearly always types or clicks before that pass lands.
///
/// Not in AXPassOffMainThreadTests, which skips while XKeyIM runs: nothing here writes
/// the App Group store.
final class SmartSwitchEntryTests: XCTestCase {

    private var source: TapEventSource!
    private var published: [AppContext] = []

    override func setUp() {
        super.setUp()
        source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.onAppContext = { [weak self] in self?.published.append($0) }
    }

    override func tearDown() {
        source.stop()
        source = nil
        let detector = OverlayAppDetector.shared
        detector.axReaderForTesting = nil
        dismissOverlay()
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        AppBehaviorDetector.shared.clearInjectionMethodFallback()
        super.tearDown()
    }

    func testStartEntersTheFrontmostApp() {
        source.start()

        XCTAssertEqual(published.first?.bundleIdentifier,
                       NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        XCTAssertEqual(published.first?.appliesSmartSwitch, true)
    }

    func testActivationEntersTheAppBeforeAnyAXPass() {
        source.start()
        published.removeAll()

        postActivation()

        // No run-loop turn has passed, so nothing from axPassQueue can have landed.
        XCTAssertEqual(published.map(\.bundleIdentifier),
                       [NSRunningApplication.current.bundleIdentifier])
        XCTAssertEqual(published.first?.appliesSmartSwitch, true)
        XCTAssertEqual(published.first?.hasResolvedWindowTitleRules, false)
    }

    func testTheActivationAXPassOnlyRefines() {
        source.start()
        published.removeAll()

        postActivation()
        waitUntil("the app-switch pass landed") { self.published.count >= 2 }

        XCTAssertEqual(published.dropFirst().map(\.appliesSmartSwitch).filter { $0 }, [],
                       "a pass must not re-run Smart Switch for an app the user is already in")
    }

    func testAnInjectionDetectionPassPublishesWhatItRead() {
        source.start()
        published.removeAll()

        AppBehaviorDetector.shared.scheduleInjectionMethodDetection?(0)
        waitUntil("the detection pass landed") { !self.published.isEmpty }

        XCTAssertEqual(published.first?.appliesSmartSwitch, false)
        XCTAssertEqual(published.first?.hasResolvedWindowTitleRules, true,
                       "the pass that supersedes the app-switch pass must carry its window-title policy")
    }

    func testClosingAnOverlayEntersTheUnderlyingAppBeforeAnyAXPass() throws {
        source.start()
        let overlayChanged = try XCTUnwrap(OverlayAppDetector.shared.onOverlayVisibilityChanged)
        overlayChanged(true, "Spotlight")
        published.removeAll()

        overlayChanged(false, "Spotlight")

        XCTAssertEqual(published.count, 1)
        XCTAssertNil(published.first?.overlayName)
        XCTAssertEqual(published.first?.bundleIdentifier,
                       NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        XCTAssertEqual(published.first?.appliesSmartSwitch, true)
    }

    /// A pass that lands while Spotlight is open describes Spotlight. Published as the
    /// app underneath, it would apply that app's exclusion or window rule to what the
    /// user types into the launcher.
    func testARefinementWhileAnOverlayIsOpenDescribesTheOverlay() throws {
        let detector = OverlayAppDetector.shared
        // Scripted so the detector's 0.5s dismissal poll keeps finding it.
        detector.axReaderForTesting = { "Spotlight" }
        detector.armProbe()
        let found = try XCTUnwrap(detector.beginProbe())
        detector.finishProbe(found, overlayName: "Spotlight")

        source.start()
        published.removeAll()

        AppBehaviorDetector.shared.scheduleInjectionMethodDetection?(0)
        waitUntil("the detection pass landed") { !self.published.isEmpty }

        XCTAssertEqual(published.first?.overlayName, "Spotlight")
        XCTAssertEqual(published.first?.appliesSmartSwitch, false)
    }

    private func postActivation() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )
    }

    /// Leave the shared detector with nothing visible and nothing armed.
    private func dismissOverlay() {
        let detector = OverlayAppDetector.shared
        detector.onOverlayVisibilityChanged = nil
        detector.onProbeArmed = nil
        detector.onOverlayReadNeeded = nil
        guard detector.lastKnownOverlayVisible else { return }
        detector.armProbe()
        guard let gone = detector.beginProbe() else { return }
        detector.finishProbe(gone, overlayName: nil)
    }

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 10,
                           condition: @escaping () -> Bool) {
        let met = expectation(description: description)
        let poll = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            guard condition() else { return }
            timer.invalidate()
            met.fulfill()
        }
        wait(for: [met], timeout: timeout)
        poll.invalidate()
    }
}
