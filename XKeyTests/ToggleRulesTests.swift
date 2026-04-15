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
}

// MARK: - EventTapManager Toggle Hotkey Slot Tests

class ToggleHotkeySlotTests: XCTestCase {
    
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
