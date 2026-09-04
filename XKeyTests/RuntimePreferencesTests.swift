import XCTest
@testable import XKey

final class RuntimePreferencesTests: XCTestCase {
    func testMapsEveryRuntimePreferenceFromPreferencesAndHostValues() {
        var preferences = Preferences()
        preferences.inputMethod = .vni
        preferences.codeTable = .unicodeCompound
        preferences.modernStyle = true
        preferences.spellCheckEnabled = true
        preferences.quickTelexEnabled = false
        preferences.quickStartConsonantEnabled = true
        preferences.quickEndConsonantEnabled = true
        preferences.upperCaseFirstChar = true
        preferences.capitalizeOnlyAfterSpace = false
        preferences.restoreIfWrongSpelling = false
        preferences.skipRestoreForUppercaseVietnameseAbbreviations = true
        preferences.customConsonantEnabled = true
        preferences.customConsonants = "Z,F"
        preferences.macroEnabled = true
        preferences.macroInEnglishMode = true
        preferences.autoCapsMacro = true
        preferences.addSpaceAfterMacro = true
        preferences.yieldMacroToSystemReplacement = true
        preferences.smartSwitchEnabled = false
        preferences.exclusionRulesEnabled = false
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: "com.example.Editor", appName: "Editor")
        ]
        preferences.undoTypingEnabled = true

        let snapshot = RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: false,
            windowTitleRulesEnabled: false,
            remoteDesktopInjectMode: true
        )

        XCTAssertEqual(snapshot.engineSettings.inputMethod, .vni)
        XCTAssertEqual(snapshot.engineSettings.codeTable, .unicodeCompound)
        XCTAssertTrue(snapshot.engineSettings.modernStyle)
        XCTAssertTrue(snapshot.engineSettings.spellCheckEnabled)
        XCTAssertFalse(snapshot.engineSettings.quickTelexEnabled)
        XCTAssertTrue(snapshot.engineSettings.quickStartConsonantEnabled)
        XCTAssertTrue(snapshot.engineSettings.quickEndConsonantEnabled)
        XCTAssertTrue(snapshot.engineSettings.upperCaseFirstChar)
        XCTAssertFalse(snapshot.engineSettings.capitalizeOnlyAfterSpace)
        XCTAssertFalse(snapshot.engineSettings.restoreIfWrongSpelling)
        XCTAssertTrue(snapshot.engineSettings.skipRestoreForUppercaseVietnameseAbbreviations)
        XCTAssertEqual(snapshot.engineSettings.customConsonants,
                       VietnameseData.parseCustomConsonants("Z,F"))
        XCTAssertTrue(snapshot.engineSettings.macroEnabled)
        XCTAssertTrue(snapshot.engineSettings.macroInEnglishMode)
        XCTAssertTrue(snapshot.engineSettings.autoCapsMacro)
        XCTAssertTrue(snapshot.engineSettings.addSpaceAfterMacro)
        XCTAssertFalse(snapshot.engineSettings.smartSwitchEnabled)

        XCTAssertFalse(snapshot.vietnameseEnabled)
        XCTAssertTrue(snapshot.yieldMacroToSystemReplacement)
        XCTAssertFalse(snapshot.windowTitleRulesEnabled)
        XCTAssertFalse(snapshot.exclusionRulesEnabled)
        XCTAssertEqual(snapshot.excludedApps, preferences.excludedApps)
        XCTAssertTrue(snapshot.undoTypingEnabled)
        XCTAssertTrue(snapshot.remoteDesktopInjectMode)
    }

    func testDisabledCustomConsonantsMapToEmptyEngineSet() {
        var preferences = Preferences()
        preferences.customConsonantEnabled = false
        preferences.customConsonants = "Z,F,W,J"

        let snapshot = RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: true,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        )

        XCTAssertTrue(snapshot.engineSettings.customConsonants.isEmpty)
    }

    func testHandlerApplySynchronizesLanguageExclusionsAndMacroManager() throws {
        var preferences = Preferences()
        preferences.autoCapsMacro = true
        preferences.yieldMacroToSystemReplacement = false
        preferences.exclusionRulesEnabled = false
        preferences.excludedApps = [
            ExcludedApp(bundleIdentifier: "com.example.Editor", appName: "Editor")
        ]
        let snapshot = RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: false,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        )
        let macroData = try JSONSerialization.data(withJSONObject: [
            ["text": "xruntime", "content": "expanded", "isEnabled": true],
            ["text": "xdisabled", "content": "not loaded", "isEnabled": false],
        ])
        let previousMacroManager = VNEngine().macroManager
        VNEngine.setSharedMacroManager(MacroManager())
        defer {
            VNEngine.setSharedMacroManager(previousMacroManager)
            XCTAssertTrue(VNEngine().macroManager === previousMacroManager)
        }
        let session = InputSession(preferences: snapshot, macroDataProvider: { macroData })
        let handler = KeyboardEventHandler(session: session)
        let macroManager = handler.getMacroManager()
        handler.apply(snapshot)

        XCTAssertEqual(handler.engine.vLanguage, 0)
        XCTAssertEqual(handler.excludedApps, preferences.excludedApps)
        XCTAssertFalse(handler.exclusionRulesEnabled)
        XCTAssertNotNil(macroManager.findMacro(key: Array("XRUNTIME".unicodeScalars.map(\.value))))
        XCTAssertNil(macroManager.findMacro(key: Array("XDISABLED".unicodeScalars.map(\.value))))

        preferences.yieldMacroToSystemReplacement = true
        handler.apply(RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: false,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        ))
        macroManager.setSystemReplacementShortcuts(["xruntime"])
        XCTAssertNil(macroManager.findMacro(key: Array("XRUNTIME".unicodeScalars.map(\.value))))
    }

    func testHandlerApplyPreservesBufferWhenVietnameseStateIsUnchanged() {
        let handler = KeyboardEventHandler()
        handler.setVietnamese(true)
        XCTAssertEqual(handler.engine.vLanguage, 1)
        _ = handler.engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        XCTAssertEqual(handler.engine.getCurrentWord(), "a")

        handler.apply(RuntimePreferences(
            preferences: Preferences(),
            vietnameseEnabled: true,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        ))

        XCTAssertEqual(handler.engine.vLanguage, 1)
        XCTAssertEqual(handler.engine.getCurrentWord(), "a")
    }

    func testHandlerApplyTransitionsVietnameseState() {
        let handler = KeyboardEventHandler()
        _ = handler.engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)

        handler.apply(RuntimePreferences(
            preferences: Preferences(),
            vietnameseEnabled: false,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        ))
        XCTAssertEqual(handler.engine.vLanguage, 0)
        XCTAssertTrue(handler.engine.buffer.isEmpty)

        handler.apply(RuntimePreferences(
            preferences: Preferences(),
            vietnameseEnabled: true,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        ))
        XCTAssertEqual(handler.engine.vLanguage, 1)
    }
}
