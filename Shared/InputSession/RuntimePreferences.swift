//
//  RuntimePreferences.swift
//  XKey
//
//  Immutable settings snapshot shared by every input runtime.
//

import Foundation

struct RuntimePreferences {
    let engineSettings: VNEngine.EngineSettings
    let vietnameseEnabled: Bool
    let yieldMacroToSystemReplacement: Bool
    let windowTitleRulesEnabled: Bool
    let exclusionRulesEnabled: Bool
    let excludedApps: [ExcludedApp]
    let undoTypingEnabled: Bool
    let remoteDesktopInjectMode: Bool

    init(preferences: Preferences,
         vietnameseEnabled: Bool,
         windowTitleRulesEnabled: Bool,
         remoteDesktopInjectMode: Bool) {
        var engineSettings = VNEngine.EngineSettings()
        engineSettings.inputMethod = preferences.inputMethod
        engineSettings.codeTable = preferences.codeTable
        engineSettings.modernStyle = preferences.modernStyle
        engineSettings.spellCheckEnabled = preferences.spellCheckEnabled
        engineSettings.quickTelexEnabled = preferences.quickTelexEnabled
        engineSettings.quickStartConsonantEnabled = preferences.quickStartConsonantEnabled
        engineSettings.quickEndConsonantEnabled = preferences.quickEndConsonantEnabled
        engineSettings.upperCaseFirstChar = preferences.upperCaseFirstChar
        engineSettings.capitalizeOnlyAfterSpace = preferences.capitalizeOnlyAfterSpace
        engineSettings.restoreIfWrongSpelling = preferences.restoreIfWrongSpelling
        engineSettings.skipRestoreForUppercaseVietnameseAbbreviations = preferences.skipRestoreForUppercaseVietnameseAbbreviations
        let customConsonants = preferences.customConsonantEnabled ? preferences.customConsonants : ""
        engineSettings.customConsonants = VietnameseData.parseCustomConsonants(customConsonants)
        engineSettings.macroEnabled = preferences.macroEnabled
        engineSettings.macroInEnglishMode = preferences.macroInEnglishMode
        engineSettings.autoCapsMacro = preferences.autoCapsMacro
        engineSettings.addSpaceAfterMacro = preferences.addSpaceAfterMacro
        engineSettings.smartSwitchEnabled = preferences.smartSwitchEnabled

        self.engineSettings = engineSettings
        self.vietnameseEnabled = vietnameseEnabled
        self.yieldMacroToSystemReplacement = preferences.yieldMacroToSystemReplacement
        self.windowTitleRulesEnabled = windowTitleRulesEnabled
        self.exclusionRulesEnabled = preferences.exclusionRulesEnabled
        self.excludedApps = preferences.excludedApps
        self.undoTypingEnabled = preferences.undoTypingEnabled
        self.remoteDesktopInjectMode = remoteDesktopInjectMode
    }

    private init(engineSettings: VNEngine.EngineSettings,
                 vietnameseEnabled: Bool,
                 yieldMacroToSystemReplacement: Bool,
                 windowTitleRulesEnabled: Bool,
                 exclusionRulesEnabled: Bool,
                 excludedApps: [ExcludedApp],
                 undoTypingEnabled: Bool,
                 remoteDesktopInjectMode: Bool) {
        self.engineSettings = engineSettings
        self.vietnameseEnabled = vietnameseEnabled
        self.yieldMacroToSystemReplacement = yieldMacroToSystemReplacement
        self.windowTitleRulesEnabled = windowTitleRulesEnabled
        self.exclusionRulesEnabled = exclusionRulesEnabled
        self.excludedApps = excludedApps
        self.undoTypingEnabled = undoTypingEnabled
        self.remoteDesktopInjectMode = remoteDesktopInjectMode
    }

    func replacingRuntimeOverrides(
        engineSettings: VNEngine.EngineSettings,
        yieldMacroToSystemReplacement: Bool,
        undoTypingEnabled: Bool
    ) -> RuntimePreferences {
        RuntimePreferences(
            engineSettings: engineSettings,
            vietnameseEnabled: vietnameseEnabled,
            yieldMacroToSystemReplacement: yieldMacroToSystemReplacement,
            windowTitleRulesEnabled: windowTitleRulesEnabled,
            exclusionRulesEnabled: exclusionRulesEnabled,
            excludedApps: excludedApps,
            undoTypingEnabled: undoTypingEnabled,
            remoteDesktopInjectMode: remoteDesktopInjectMode
        )
    }
}
