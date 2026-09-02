//
//  TapEnvironment.swift
//
//  Everything the event-tap layer READS from whichever process hosts it.
//
//  The tap layer runs in two processes — XKey.app (CGEvent mode) and XKeyIM
//  (the input method). It was originally written against XKey.app's AppDelegate
//  and reached for that host's state through optional providers and mutable
//  singletons. When XKeyIM began hosting the same code, every one of those
//  optionals silently took a default instead of failing: wrong input method,
//  wrong code table, excluded apps ignored, user rules dead, and a per-keystroke
//  AX snapshot on the tap thread that froze typing.
//
//  So: no field here has a default. A host that forgets one does not compile.
//

import Foundation

struct TapEnvironment {
    /// Everything KeyboardEventHandler.applyAllSettings needs: input method, code
    /// table, macro, spell-check, custom consonants, excluded apps, undo.
    let preferences: Preferences

    /// Name of the visible overlay launcher (Spotlight/Raycast/Alfred), or nil.
    /// Left unprovided this returns nil forever, which is not merely "no overlay":
    /// it stops AppBehaviorDetector ever producing an overlay method, so the
    /// injection method is re-detected — a full AX snapshot — on every keystroke.
    let overlayAppName: () -> String?

    /// Whether the user opted into injecting Vietnamese into remote desktop
    /// clients via clipboard paste rather than passing through.
    let remoteDesktopInjectMode: () -> Bool

    /// Master switch for Window Title Rules.
    let windowTitleRulesEnabled: Bool

    /// Vietnamese on/off at the moment the tap arms.
    let vietnameseEnabled: Bool

    /// Ceiling for every AX call the tap thread makes. Without it the system
    /// default (seconds) applies and one hung app is enough for macOS to disable
    /// the tap — the primitive behind every freeze we have chased.
    let axMessagingTimeout: Double

    init(preferences: Preferences,
         overlayAppName: @escaping () -> String?,
         remoteDesktopInjectMode: @escaping () -> Bool,
         windowTitleRulesEnabled: Bool,
         vietnameseEnabled: Bool,
         axMessagingTimeout: Double) {
        self.preferences = preferences
        self.overlayAppName = overlayAppName
        self.remoteDesktopInjectMode = remoteDesktopInjectMode
        self.windowTitleRulesEnabled = windowTitleRulesEnabled
        self.vietnameseEnabled = vietnameseEnabled
        self.axMessagingTimeout = axMessagingTimeout
    }
}

extension TapEnvironment {
    /// The single place that wires an environment into the tap layer. Both hosts
    /// call this and nothing else, so the two can never drift apart by wiring
    /// different subsets — the failure this whole contract exists to end.
    func apply(to handler: KeyboardEventHandler) {
        // Bound every AX call the tap thread makes before anything can make one.
        AXHelper.setGlobalMessagingTimeout(Float(axMessagingTimeout))

        let detector = AppBehaviorDetector.shared
        detector.overlayAppNameProvider = overlayAppName
        detector.remoteDesktopInjectModeProvider = remoteDesktopInjectMode
        detector.windowTitleRulesEnabled = windowTitleRulesEnabled
        detector.loadCustomRules()

        handler.applyAllSettings(
            inputMethod: preferences.inputMethod,
            codeTable: preferences.codeTable,
            modernStyle: preferences.modernStyle,
            spellCheckEnabled: preferences.spellCheckEnabled,
            quickTelexEnabled: preferences.quickTelexEnabled,
            quickStartConsonantEnabled: preferences.quickStartConsonantEnabled,
            quickEndConsonantEnabled: preferences.quickEndConsonantEnabled,
            upperCaseFirstChar: preferences.upperCaseFirstChar,
            capitalizeOnlyAfterSpace: preferences.capitalizeOnlyAfterSpace,
            restoreIfWrongSpelling: preferences.restoreIfWrongSpelling,
            skipRestoreForUppercaseVietnameseAbbreviations: preferences.skipRestoreForUppercaseVietnameseAbbreviations,
            // Empty string (not the stored list) is how applyAllSettings/VietnameseData
            // encode "custom consonants off" — there is no separate enabled flag on the
            // call. Matches AppDelegate.applyPreferences; passing the raw string here
            // would silently turn custom consonants on for users who disabled them.
            customConsonants: preferences.customConsonantEnabled ? preferences.customConsonants : "",
            macroEnabled: preferences.macroEnabled,
            macroInEnglishMode: preferences.macroInEnglishMode,
            autoCapsMacro: preferences.autoCapsMacro,
            addSpaceAfterMacro: preferences.addSpaceAfterMacro,
            yieldMacroToSystemReplacement: preferences.yieldMacroToSystemReplacement,
            smartSwitchEnabled: preferences.smartSwitchEnabled,
            excludedApps: preferences.excludedApps,
            undoTypingEnabled: preferences.undoTypingEnabled
        )
        handler.setVietnamese(vietnameseEnabled)
    }
}
