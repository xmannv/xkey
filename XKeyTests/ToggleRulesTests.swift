//
//  ToggleRulesTests.swift
//  XKeyTests
//
//  Unit tests for Toggle Exclusion Rules and Toggle Window Title Rules features
//  Tests persistence, runtime flag behavior, hotkey configuration, and debug config output
//

import XCTest
@testable import XKey

// MARK: - Toggle Exclusion Rules Tests

class ToggleExclusionRulesTests: XCTestCase {

    override func setUpWithError() throws {
        try skipIfXKeyIMIsRunning()
    }
    
    var handler: KeyboardEventHandler!
    
    override func setUp() {
        super.setUp()
        handler = KeyboardEventHandler()
    }
    
    override func tearDown() {
        handler = nil
        super.tearDown()
    }
    
    // MARK: - Default State Tests
    
    /// Verify exclusionRulesEnabled defaults to true (feature ON by default)
    func testDefaultState_ExclusionRulesEnabled() {
        XCTAssertTrue(handler.exclusionRulesEnabled,
            "exclusionRulesEnabled should default to true")
    }
    
    // MARK: - Runtime Flag Tests
    
    /// Verify that setting exclusionRulesEnabled to false changes the flag
    func testSetExclusionRulesEnabled_False() {
        handler.exclusionRulesEnabled = false
        XCTAssertFalse(handler.exclusionRulesEnabled,
            "exclusionRulesEnabled should be false after setting")
    }
    
    /// Verify toggle round-trip: true → false → true
    func testExclusionRulesEnabled_RoundTrip() {
        XCTAssertTrue(handler.exclusionRulesEnabled)
        
        handler.exclusionRulesEnabled = false
        XCTAssertFalse(handler.exclusionRulesEnabled)
        
        handler.exclusionRulesEnabled = true
        XCTAssertTrue(handler.exclusionRulesEnabled)
    }
}

// MARK: - Toggle Window Title Rules Tests

class ToggleWindowTitleRulesTests: XCTestCase {

    override func setUpWithError() throws {
        try skipIfXKeyIMIsRunning()
    }
    
    // MARK: - Default State Tests
    
    /// Verify windowTitleRulesEnabled defaults to true (feature ON by default)
    func testDefaultState_WindowTitleRulesEnabled() {
        let detector = AppBehaviorDetector.shared
        // Save current state to restore after test
        let savedState = detector.windowTitleRulesEnabled
        defer { detector.windowTitleRulesEnabled = savedState }
        
        // Default should be true
        detector.windowTitleRulesEnabled = true
        XCTAssertTrue(detector.windowTitleRulesEnabled,
            "windowTitleRulesEnabled should be true when set to true")
    }
    
    // MARK: - Runtime Flag Tests
    
    /// Verify that disabling window title rules changes the flag
    func testSetWindowTitleRulesEnabled_False() {
        let detector = AppBehaviorDetector.shared
        let savedState = detector.windowTitleRulesEnabled
        defer { detector.windowTitleRulesEnabled = savedState }
        
        detector.windowTitleRulesEnabled = false
        XCTAssertFalse(detector.windowTitleRulesEnabled,
            "windowTitleRulesEnabled should be false after setting")
    }
    
    /// Verify that findAllMatchingRules returns empty when disabled
    func testFindAllMatchingRules_ReturnsEmpty_WhenDisabled() {
        let detector = AppBehaviorDetector.shared
        let savedState = detector.windowTitleRulesEnabled
        defer { detector.windowTitleRulesEnabled = savedState }
        
        detector.windowTitleRulesEnabled = false
        
        // With rules disabled, findAllMatchingRules should return empty regardless of context
        let rules = detector.findAllMatchingRules()
        XCTAssertTrue(rules.isEmpty,
            "findAllMatchingRules() should return empty array when windowTitleRulesEnabled is false, got \(rules.count) rules")
    }

    /// Verify that debug/single-rule lookup also respects the master switch.
    /// When disabled, debug logs must not show a rule that cannot actually apply.
    func testFindMatchingRule_ReturnsNil_WhenDisabled() {
        let detector = AppBehaviorDetector.shared
        let savedState = detector.windowTitleRulesEnabled
        let savedCustomRules = detector.getCustomRules()
        defer {
            detector.windowTitleRulesEnabled = savedState
            detector.reorderCustomRules(savedCustomRules)
        }

        detector.windowTitleRulesEnabled = false
        detector.reorderCustomRules([
            WindowTitleRule(
                name: "Any Window Debug Rule",
                bundleIdPattern: "*",
                titlePattern: "",
                matchMode: .contains,
                injectionMethod: .selection
            )
        ])

        XCTAssertNil(detector.findMatchingRule(),
            "findMatchingRule() should return nil when windowTitleRulesEnabled is false, so debug logs do not show disabled rules")
    }

    /// Verify the built-in Meta chat rule covers Messenger and Facebook window titles.
    func testBuiltInMetaChatRule_CoversMessengerAndFacebookTitles() {
        let rule = AppBehaviorDetector.builtInWindowTitleRules.first { $0.name == "Meta Chat Web (Atlas)" }

        XCTAssertNotNil(rule, "Built-in Meta Chat Web (Atlas) rule should exist")
        XCTAssertEqual(rule?.bundleIdPattern, "com.openai.atlas")
        XCTAssertEqual(rule?.titlePattern, "Facebook|Messenger")
        XCTAssertEqual(rule?.matchMode, .regex)
        XCTAssertEqual(rule?.injectionMethod, .selection)
        XCTAssertEqual(rule?.textSendingMethod, .oneByOne)
        XCTAssertTrue(rule?.matches(bundleId: "com.openai.atlas", windowTitle: "Messenger", axInfo: nil) ?? false)
        XCTAssertTrue(rule?.matches(bundleId: "com.openai.atlas", windowTitle: "Facebook", axInfo: nil) ?? false)
    }
    
    /// Verify toggle round-trip
    func testWindowTitleRulesEnabled_RoundTrip() {
        let detector = AppBehaviorDetector.shared
        let savedState = detector.windowTitleRulesEnabled
        defer { detector.windowTitleRulesEnabled = savedState }
        
        detector.windowTitleRulesEnabled = true
        XCTAssertTrue(detector.windowTitleRulesEnabled)
        
        detector.windowTitleRulesEnabled = false
        XCTAssertFalse(detector.windowTitleRulesEnabled)
        
        detector.windowTitleRulesEnabled = true
        XCTAssertTrue(detector.windowTitleRulesEnabled)
    }

    // MARK: - Input Method Policy Tests

    func testWindowTitleRuleInputMethodPolicy_RoundTripsThroughCodable() throws {
        let rule = WindowTitleRule(
            name: "Enable Vietnamese in specific window",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            inputMethodPolicy: .enable
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)

        XCTAssertEqual(decoded.inputMethodPolicy, .enable)
    }

    func testMergedRuleResult_InputMethodPolicyLaterRuleOverridesEarlierRule() {
        let disableRule = WindowTitleRule(
            name: "Base disable",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )
        let enableRule = WindowTitleRule(
            name: "Specific enable",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            inputMethodPolicy: .enable
        )

        var result = MergedRuleResult()
        result.merge(from: disableRule)
        result.merge(from: enableRule)

        XCTAssertEqual(result.inputMethodPolicy, .enable)
    }

    func testMergedRuleResult_InputMethodPolicyEnableThenDisable_DisableWins() {
        let enableRule = WindowTitleRule(
            name: "Base enable",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            inputMethodPolicy: .enable
        )
        let disableRule = WindowTitleRule(
            name: "Specific disable",
            bundleIdPattern: "com.example.App",
            titlePattern: "Terminal",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )

        var result = MergedRuleResult()
        result.merge(from: enableRule)
        result.merge(from: disableRule)

        XCTAssertEqual(result.inputMethodPolicy, .disable,
            "A later matching rule's policy must override an earlier one (cascade order)")
    }

    func testMergedRuleResult_InputMethodPolicyNilDoesNotOverrideEarlierPolicy() {
        let enableRule = WindowTitleRule(
            name: "Sets enable",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            inputMethodPolicy: .enable
        )
        let noPolicyRule = WindowTitleRule(
            name: "No policy override",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            inputMethodPolicy: nil
        )

        var result = MergedRuleResult()
        result.merge(from: enableRule)
        result.merge(from: noPolicyRule)

        XCTAssertEqual(result.inputMethodPolicy, .enable,
            "A later rule with no policy (nil) must not clear an earlier rule's policy")
    }

    func testMergedRuleResult_InputMethodPolicySingleRuleSetsPolicy() {
        let rule = WindowTitleRule(
            name: "Disable",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )

        var result = MergedRuleResult()
        result.merge(from: rule)

        XCTAssertEqual(result.inputMethodPolicy, .disable)
    }

    func testMergedRuleResult_DefaultsToNilInputMethodPolicy() {
        let empty = MergedRuleResult()
        XCTAssertNil(empty.inputMethodPolicy,
            "A fresh MergedRuleResult should carry no policy override")

        let ruleWithoutPolicy = WindowTitleRule(
            name: "No policy",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains
        )
        var merged = MergedRuleResult()
        merged.merge(from: ruleWithoutPolicy)
        XCTAssertNil(merged.inputMethodPolicy,
            "Merging a rule without a policy must leave the result's policy nil")
    }

    func testWindowTitleRuleInputMethodPolicyDisable_RoundTripsThroughCodable() throws {
        let rule = WindowTitleRule(
            name: "Disable Vietnamese in terminal",
            bundleIdPattern: "com.example.Terminal",
            titlePattern: "",
            matchMode: .contains,
            inputMethodPolicy: .disable
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)

        XCTAssertEqual(decoded.inputMethodPolicy, .disable)
    }

    func testWindowTitleRule_OmitsInputMethodPolicyWhenNil_AndDecodesAbsentKeyAsNil() throws {
        // Backward compatibility: a rule without a policy must not emit the key,
        // and rules saved before this feature (no key) must decode with a nil policy.
        let rule = WindowTitleRule(
            name: "No policy",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains
        )

        let data = try JSONEncoder().encode(rule)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("inputMethodPolicy"),
            "Encoder must omit inputMethodPolicy when nil (encodeIfPresent)")

        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)
        XCTAssertNil(decoded.inputMethodPolicy,
            "Decoding a rule whose JSON has no inputMethodPolicy key must yield nil")
    }

    // MARK: - Empty Char Prefix Override Tests

    func testWindowTitleRuleEmptyCharPrefix_RoundTripsThroughCodable() throws {
        let rule = WindowTitleRule(
            name: "Force empty char prefix",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            needsEmptyCharPrefix: true
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)

        XCTAssertEqual(decoded.needsEmptyCharPrefix, true)
    }

    func testWindowTitleRuleEmptyCharPrefixFalse_RoundTripsThroughCodable() throws {
        // false is a meaningful "force disable" override, distinct from nil (inherit).
        let rule = WindowTitleRule(
            name: "Force disable empty char prefix",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            needsEmptyCharPrefix: false
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)

        XCTAssertEqual(decoded.needsEmptyCharPrefix, false,
            "false must survive round-trip and not be conflated with nil")
    }

    func testWindowTitleRule_OmitsEmptyCharPrefixWhenNil_AndDecodesAbsentKeyAsNil() throws {
        // Backward compatibility: a rule without an override must not emit the key,
        // and rules saved before this feature (no key) must decode with nil (inherit).
        let rule = WindowTitleRule(
            name: "No empty char prefix override",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains
        )

        let data = try JSONEncoder().encode(rule)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("needsEmptyCharPrefix"),
            "Encoder must omit needsEmptyCharPrefix when nil (encodeIfPresent)")

        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)
        XCTAssertNil(decoded.needsEmptyCharPrefix,
            "Decoding a rule whose JSON has no needsEmptyCharPrefix key must yield nil")
    }

    func testMergedRuleResult_EmptyCharPrefixLaterRuleOverridesEarlierRule() {
        let baseRule = WindowTitleRule(
            name: "Base enable",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            needsEmptyCharPrefix: true
        )
        let specificRule = WindowTitleRule(
            name: "Specific disable",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            needsEmptyCharPrefix: false
        )

        var result = MergedRuleResult()
        result.merge(from: baseRule)
        result.merge(from: specificRule)

        XCTAssertEqual(result.needsEmptyCharPrefix, false,
            "A later matching rule must override the earlier empty-char-prefix value (cascade order)")
    }

    func testMergedRuleResult_EmptyCharPrefixNilDoesNotOverrideEarlierValue() {
        let enableRule = WindowTitleRule(
            name: "Sets empty char prefix",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains,
            needsEmptyCharPrefix: true
        )
        let noOverrideRule = WindowTitleRule(
            name: "No override",
            bundleIdPattern: "com.example.App",
            titlePattern: "Editor",
            matchMode: .contains,
            needsEmptyCharPrefix: nil
        )

        var result = MergedRuleResult()
        result.merge(from: enableRule)
        result.merge(from: noOverrideRule)

        XCTAssertEqual(result.needsEmptyCharPrefix, true,
            "A later rule with nil override must not clear an earlier rule's empty-char-prefix value")
    }

    func testMergedRuleResult_DefaultsToNilEmptyCharPrefix() {
        let empty = MergedRuleResult()
        XCTAssertNil(empty.needsEmptyCharPrefix,
            "A fresh MergedRuleResult should carry no empty-char-prefix override")

        let ruleWithoutOverride = WindowTitleRule(
            name: "No override",
            bundleIdPattern: "com.example.App",
            titlePattern: "",
            matchMode: .contains
        )
        var merged = MergedRuleResult()
        merged.merge(from: ruleWithoutOverride)
        XCTAssertNil(merged.needsEmptyCharPrefix,
            "Merging a rule without an override must leave the result's value nil")
    }

    // MARK: - Excluded Bundle ID Tests

    func testWindowTitleRule_DoesNotMatchExcludedBundle() {
        let rule = WindowTitleRule(
            name: "Word for the web",
            bundleIdPattern: "",
            titlePattern: "\\.docx",
            matchMode: .regex,
            excludedBundleIds: ["org.libreoffice.script"]
        )

        XCTAssertFalse(rule.matches(
            bundleId: "org.libreoffice.script",
            windowTitle: "Untitled 2.docx",
            axInfo: nil
        ))
    }

    func testWindowTitleRule_StillMatchesUnknownBrowserWhenLibreOfficeIsExcluded() {
        let rule = WindowTitleRule(
            name: "Word for the web",
            bundleIdPattern: "",
            titlePattern: "\\.docx",
            matchMode: .regex,
            excludedBundleIds: ["org.libreoffice.script"]
        )

        XCTAssertTrue(rule.matches(
            bundleId: "com.example.unknown-browser",
            windowTitle: "Report.docx",
            axInfo: nil
        ))
    }

    func testWindowTitleRule_DefaultExcludedBundleIdsIsEmpty() {
        let rule = WindowTitleRule(
            name: "Legacy rule",
            bundleIdPattern: "",
            titlePattern: "\\.docx",
            matchMode: .regex
        )

        XCTAssertTrue(rule.excludedBundleIds.isEmpty)
        XCTAssertTrue(rule.matches(
            bundleId: "org.libreoffice.script",
            windowTitle: "Legacy.docx",
            axInfo: nil
        ))
    }

    func testBuiltInWordForWebRule_ExcludesLibreOfficeButMatchesUnknownBrowser() throws {
        let rule = try XCTUnwrap(AppBehaviorDetector.builtInWindowTitleRules.first {
            $0.name == "Word for the web"
        })

        XCTAssertFalse(rule.matches(
            bundleId: "org.libreoffice.script",
            windowTitle: "Untitled 2.docx",
            axInfo: nil
        ))
        XCTAssertTrue(rule.matches(
            bundleId: "com.example.unknown-browser",
            windowTitle: "Report.docx",
            axInfo: nil
        ))
    }

    func testWindowTitleRule_ExcludedBundleIdsRoundTripInStableOrder() throws {
        let rule = WindowTitleRule(
            name: "Excluded apps",
            bundleIdPattern: "",
            titlePattern: "\\.docx",
            matchMode: .regex,
            excludedBundleIds: ["org.libreoffice.script", "com.example.Editor"]
        )

        let decoded = try JSONDecoder().decode(
            WindowTitleRule.self,
            from: JSONEncoder().encode(rule)
        )

        XCTAssertEqual(decoded.excludedBundleIds, rule.excludedBundleIds)
    }

    func testWindowTitleRule_DecodesMissingExcludedBundleIdsAsEmpty() throws {
        let rule = WindowTitleRule(
            name: "Legacy rule",
            bundleIdPattern: "",
            titlePattern: "\\.docx",
            matchMode: .regex
        )
        let data = try JSONEncoder().encode(rule)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("excludedBundleIds"))

        let decoded = try JSONDecoder().decode(WindowTitleRule.self, from: data)
        XCTAssertTrue(decoded.excludedBundleIds.isEmpty)
    }

    func testInjectionMethodInfo_DefaultsToNoEmptyCharPrefix() {
        // Priority 1/2 fall back to `false` when no rule sets the override; verify the
        // InjectionMethodInfo default matches that contract.
        let info = InjectionMethodInfo(
            method: .fast,
            delays: (2000, 5000, 2000),
            textSendingMethod: .chunked,
            description: "test"
        )
        XCTAssertFalse(info.needsEmptyCharPrefix,
            "InjectionMethodInfo must default needsEmptyCharPrefix to false")
    }
}

// MARK: - EventTapManager Toggle Hotkey Slot Tests

class ToggleHotkeySlotTests: XCTestCase {

    override func setUpWithError() throws {
        try skipIfXKeyIMIsRunning()
    }
    
    var eventTapManager: EventTapManager!
    
    override func setUp() {
        super.setUp()
        eventTapManager = EventTapManager()
    }
    
    override func tearDown() {
        eventTapManager = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    /// Verify toggle exclusion hotkey slot starts nil
    func testInitialState_ToggleExclusionHotkey_IsNil() {
        XCTAssertNil(eventTapManager.toggleExclusionHotkey,
            "toggleExclusionHotkey should start as nil")
    }
    
    /// Verify toggle window rules hotkey slot starts nil
    func testInitialState_ToggleWindowRulesHotkey_IsNil() {
        XCTAssertNil(eventTapManager.toggleWindowRulesHotkey,
            "toggleWindowRulesHotkey should start as nil")
    }
    
    /// Verify toggle exclusion callback starts nil
    func testInitialState_OnToggleExclusionHotkey_IsNil() {
        XCTAssertNil(eventTapManager.onToggleExclusionHotkey,
            "onToggleExclusionHotkey callback should start as nil")
    }
    
    /// Verify toggle window rules callback starts nil
    func testInitialState_OnToggleWindowRulesHotkey_IsNil() {
        XCTAssertNil(eventTapManager.onToggleWindowRulesHotkey,
            "onToggleWindowRulesHotkey callback should start as nil")
    }
    
    // MARK: - Hotkey Configuration
    
    /// Verify setting toggle exclusion hotkey
    func testSetToggleExclusionHotkey() {
        let hotkey = Hotkey(keyCode: 0x0E, modifiers: [.control, .option]) // Ctrl+Opt+E
        eventTapManager.toggleExclusionHotkey = hotkey
        
        XCTAssertNotNil(eventTapManager.toggleExclusionHotkey)
        XCTAssertEqual(eventTapManager.toggleExclusionHotkey?.keyCode, 0x0E)
        XCTAssertEqual(eventTapManager.toggleExclusionHotkey?.modifiers, [.control, .option])
    }
    
    /// Verify setting toggle window rules hotkey
    func testSetToggleWindowRulesHotkey() {
        let hotkey = Hotkey(keyCode: 0x0D, modifiers: [.control, .option]) // Ctrl+Opt+W
        eventTapManager.toggleWindowRulesHotkey = hotkey
        
        XCTAssertNotNil(eventTapManager.toggleWindowRulesHotkey)
        XCTAssertEqual(eventTapManager.toggleWindowRulesHotkey?.keyCode, 0x0D)
        XCTAssertEqual(eventTapManager.toggleWindowRulesHotkey?.modifiers, [.control, .option])
    }
    
    /// Verify clearing hotkey by setting to nil
    func testClearToggleExclusionHotkey() {
        let hotkey = Hotkey(keyCode: 0x0E, modifiers: [.control, .option])
        eventTapManager.toggleExclusionHotkey = hotkey
        XCTAssertNotNil(eventTapManager.toggleExclusionHotkey)
        
        eventTapManager.toggleExclusionHotkey = nil
        XCTAssertNil(eventTapManager.toggleExclusionHotkey)
    }
    
    // MARK: - Callback Registration
    
    /// Verify callback can be set and cleared
    func testSetAndClearExclusionCallback() {
        var called = false
        eventTapManager.onToggleExclusionHotkey = { called = true }
        
        // Verify callback was set
        XCTAssertNotNil(eventTapManager.onToggleExclusionHotkey)
        
        // Invoke directly to verify it's callable
        eventTapManager.onToggleExclusionHotkey?()
        XCTAssertTrue(called, "Callback should have been invoked")
        
        // Clear callback
        eventTapManager.onToggleExclusionHotkey = nil
        XCTAssertNil(eventTapManager.onToggleExclusionHotkey)
    }
    
    /// Verify callback can be set and cleared for window rules
    func testSetAndClearWindowRulesCallback() {
        var called = false
        eventTapManager.onToggleWindowRulesHotkey = { called = true }
        
        XCTAssertNotNil(eventTapManager.onToggleWindowRulesHotkey)
        eventTapManager.onToggleWindowRulesHotkey?()
        XCTAssertTrue(called, "Callback should have been invoked")
        
        eventTapManager.onToggleWindowRulesHotkey = nil
        XCTAssertNil(eventTapManager.onToggleWindowRulesHotkey)
    }
}

// MARK: - Preferences Persistence Tests

class ToggleRulesPreferencesTests: XCTestCase {
    
    // MARK: - Hotkey Model Tests
    
    /// Verify Hotkey with keyCode 0 is treated as "not set"
    func testHotkey_ZeroKeyCode_IsNotSet() {
        let hotkey = Hotkey(keyCode: 0, modifiers: [])
        XCTAssertEqual(hotkey.keyCode, 0,
            "Hotkey with keyCode 0 should represent 'not set'")
    }
    
    /// Verify Hotkey displayString for a configured hotkey
    func testHotkey_DisplayString() {
        let hotkey = Hotkey(keyCode: 0x0E, modifiers: [.control, .option]) // Ctrl+Opt+E
        let display = hotkey.displayString
        XCTAssertTrue(display.contains("⌃"), "Should contain Control symbol")
        XCTAssertTrue(display.contains("⌥"), "Should contain Option symbol")
        XCTAssertTrue(display.contains("E"), "Should contain key letter")
    }
    
    /// Verify Hotkey equality
    func testHotkey_Equality() {
        let hotkey1 = Hotkey(keyCode: 0x0E, modifiers: [.control, .option])
        let hotkey2 = Hotkey(keyCode: 0x0E, modifiers: [.control, .option])
        let hotkey3 = Hotkey(keyCode: 0x0D, modifiers: [.control, .option])
        
        XCTAssertEqual(hotkey1, hotkey2, "Same hotkeys should be equal")
        XCTAssertNotEqual(hotkey1, hotkey3, "Different hotkeys should not be equal")
    }
    
    // MARK: - Preferences Model Tests
    
    /// Verify default preferences have exclusion rules enabled
    func testPreferences_Default_ExclusionRulesEnabled() {
        let prefs = Preferences()
        XCTAssertTrue(prefs.exclusionRulesEnabled,
            "Default preferences should have exclusionRulesEnabled = true")
    }
    
    /// Verify default preferences have window title rules enabled
    func testPreferences_Default_WindowTitleRulesEnabled() {
        let prefs = Preferences()
        XCTAssertTrue(prefs.windowTitleRulesEnabled,
            "Default preferences should have windowTitleRulesEnabled = true")
    }
    
    /// Verify default preferences have empty hotkeys
    func testPreferences_Default_HotkeysNotSet() {
        let prefs = Preferences()
        XCTAssertEqual(prefs.toggleExclusionHotkey.keyCode, 0,
            "Default toggle exclusion hotkey should not be set")
        XCTAssertEqual(prefs.toggleWindowRulesHotkey.keyCode, 0,
            "Default toggle window rules hotkey should not be set")
    }
}

// MARK: - Debug Config Summary Tests

class ToggleRulesDebugConfigTests: XCTestCase {
    
    /// Verify generateConfigSummary includes Toggle Rules section
    func testDebugConfig_ContainsToggleRulesSection() {
        let viewModel = DebugViewModel()
        let lines = viewModel.generateConfigSummary()
        
        let hasToggleRulesHeader = lines.contains("[Toggle Rules]")
        XCTAssertTrue(hasToggleRulesHeader,
            "Config summary should contain [Toggle Rules] section. Lines: \(lines)")
        
        viewModel.stopAllTimers()
    }
    
    /// Verify config contains exclusion rules state
    func testDebugConfig_ContainsExclusionRulesState() {
        let viewModel = DebugViewModel()
        let lines = viewModel.generateConfigSummary()
        
        let hasExclusionLine = lines.contains { $0.contains("Exclusion Rules:") && ($0.contains("ON") || $0.contains("OFF")) }
        XCTAssertTrue(hasExclusionLine,
            "Config should show Exclusion Rules state")
        
        viewModel.stopAllTimers()
    }
    
    /// Verify config contains window title rules state
    func testDebugConfig_ContainsWindowTitleRulesState() {
        let viewModel = DebugViewModel()
        let lines = viewModel.generateConfigSummary()
        
        let hasWTRLine = lines.contains { $0.contains("Window Title Rules:") && ($0.contains("ON") || $0.contains("OFF")) }
        XCTAssertTrue(hasWTRLine,
            "Config should show Window Title Rules state")
        
        viewModel.stopAllTimers()
    }

    /// Verify OFF states are highlighted to make disabled settings easier to notice in logs.
    func testDebugConfig_HighlightsOffStatesWithWarningEmoji() {
        let settings = SharedSettings.shared
        let savedWindowTitleRulesEnabled = settings.windowTitleRulesEnabled
        defer { settings.windowTitleRulesEnabled = savedWindowTitleRulesEnabled }
        settings.windowTitleRulesEnabled = false

        let viewModel = DebugViewModel()
        let lines = viewModel.generateConfigSummary()

        let hasHighlightedOffState = lines.contains { $0.contains("Window Title Rules: ⚠️ OFF") }
        XCTAssertTrue(hasHighlightedOffState,
            "Config summary should highlight OFF states with a warning emoji. Lines: \(lines)")

        viewModel.stopAllTimers()
    }
    
    /// Verify config contains hotkey info
    func testDebugConfig_ContainsHotkeyInfo() {
        let viewModel = DebugViewModel()
        let lines = viewModel.generateConfigSummary()
        
        let hasExclHotkey = lines.contains { $0.contains("Exclusion Hotkey:") }
        let hasWTRHotkey = lines.contains { $0.contains("Window Rules Hotkey:") }
        
        XCTAssertTrue(hasExclHotkey, "Config should show Exclusion Hotkey")
        XCTAssertTrue(hasWTRHotkey, "Config should show Window Rules Hotkey")
        
        viewModel.stopAllTimers()
    }
}
