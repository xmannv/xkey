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
