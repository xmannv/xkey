import Foundation

struct AppContext: Equatable {
    let bundleIdentifier: String?
    let windowTitle: String?
    let overlayName: String?
    let resolvedInputMethodPolicy: InputMethodPolicy?
    let resolvedTargetInputSourceId: String?
    let hasResolvedWindowTitleRules: Bool
    /// False for a context that only refines the app the user is already in (a focus,
    /// title, click or detection pass). Smart Switch restores an app's language when the
    /// user enters it; re-running it on every refinement would undo a change made in place.
    let appliesSmartSwitch: Bool

    init(bundleIdentifier: String?,
         windowTitle: String?,
         overlayName: String?,
         resolvedInputMethodPolicy: InputMethodPolicy? = nil,
         resolvedTargetInputSourceId: String? = nil,
         hasResolvedWindowTitleRules: Bool = false,
         appliesSmartSwitch: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.overlayName = overlayName
        self.resolvedInputMethodPolicy = resolvedInputMethodPolicy
        self.resolvedTargetInputSourceId = resolvedTargetInputSourceId
        self.hasResolvedWindowTitleRules = hasResolvedWindowTitleRules
        self.appliesSmartSwitch = appliesSmartSwitch
    }
}

enum AppPolicyDecision: Equatable {
    case keepCurrentLanguage
    case overrideVietnamese(Bool)
    case restoreVietnamese(Bool)
    case disableTransformation
}

/// What a Window Title Rule's target input source asks the host to do.
enum InputSourceRuleAction: Equatable {
    case select(String)
    case restorePreRuleSource
    case none
}

struct AppContextCacheDecision: Equatable {
    let useCached: Bool
    let shouldRefresh: Bool
}

protocol AppPolicySmartSwitchStore: AnyObject {
    func vietnameseEnabled(for bundleIdentifier: String) -> Bool?
    func saveVietnameseEnabled(_ enabled: Bool, for bundleIdentifier: String)
}

extension SmartSwitchManager: AppPolicySmartSwitchStore {
    func vietnameseEnabled(for bundleIdentifier: String) -> Bool? {
        switch getAppLanguage(bundleId: bundleIdentifier, currentLanguage: 0) {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    func saveVietnameseEnabled(_ enabled: Bool, for bundleIdentifier: String) {
        setAndSaveAppLanguage(bundleId: bundleIdentifier, language: enabled ? 1 : 0)
    }
}

final class AppPolicyRuntime {
    func reevaluateAfterWindowTitleRulesChange(
        context: AppContext?,
        currentVietnameseEnabled: Bool,
        preferences: RuntimePreferences,
        apply: (AppPolicyDecision) -> Void,
        invalidateCache: () -> Void,
        refresh: () -> Void
    ) {
        if let context {
            // A refinement: the user toggled rules in the window they are already in.
            let provisionalContext = AppContext(
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle,
                overlayName: context.overlayName,
                appliesSmartSwitch: false
            )
            apply(evaluate(context: provisionalContext,
                           currentVietnameseEnabled: currentVietnameseEnabled,
                           preferences: preferences))
        }
        invalidateCache()
        refresh()
    }

    static func cacheDecision(
        cachedWindowTitle: String?,
        liveWindowTitle: String?,
        age: TimeInterval
    ) -> AppContextCacheDecision {
        if let liveWindowTitle, liveWindowTitle != cachedWindowTitle {
            return AppContextCacheDecision(useCached: false, shouldRefresh: true)
        }
        return AppContextCacheDecision(useCached: true, shouldRefresh: age >= 0.25)
    }

    private let smartSwitchStore: AppPolicySmartSwitchStore
    private let windowTitleRules: () -> [WindowTitleRule]

    init(smartSwitchStore: AppPolicySmartSwitchStore,
         windowTitleRules: @escaping () -> [WindowTitleRule]) {
        self.smartSwitchStore = smartSwitchStore
        self.windowTitleRules = windowTitleRules
    }

    func evaluate(
        context: AppContext,
        currentVietnameseEnabled: Bool,
        preferences: RuntimePreferences
    ) -> AppPolicyDecision {
        let bundleIdentifier = effectiveBundleIdentifier(for: context)

        if preferences.exclusionRulesEnabled,
           context.overlayName == nil,
           let bundleIdentifier,
           preferences.excludedApps.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return .disableTransformation
        }

        if preferences.windowTitleRulesEnabled,
           let bundleIdentifier,
           let policy = context.hasResolvedWindowTitleRules
               ? context.resolvedInputMethodPolicy
               : matchingInputMethodPolicy(
                   bundleIdentifier: bundleIdentifier,
                   windowTitle: context.windowTitle ?? ""
               ) {
            return .overrideVietnamese(policy == .enable)
        }

        guard preferences.engineSettings.smartSwitchEnabled,
              context.appliesSmartSwitch,
              let bundleIdentifier else {
            return .keepCurrentLanguage
        }

        if let saved = smartSwitchStore.vietnameseEnabled(for: bundleIdentifier) {
            return saved == currentVietnameseEnabled
                ? .keepCurrentLanguage
                : .restoreVietnamese(saved)
        }

        smartSwitchStore.saveVietnameseEnabled(
            currentVietnameseEnabled,
            for: bundleIdentifier
        )
        return .keepCurrentLanguage
    }

    func saveCurrentLanguage(
        _ enabled: Bool,
        context: AppContext,
        preferences: RuntimePreferences
    ) {
        guard preferences.engineSettings.smartSwitchEnabled,
              let bundleIdentifier = effectiveBundleIdentifier(for: context) else { return }
        smartSwitchStore.saveVietnameseEnabled(enabled, for: bundleIdentifier)
    }

    func inputSourceRuleAction(context: AppContext,
                               windowTitleRulesEnabled: Bool) -> InputSourceRuleAction {
        guard context.overlayName == nil else { return .none }
        let target: String?
        if windowTitleRulesEnabled, context.hasResolvedWindowTitleRules {
            target = context.resolvedTargetInputSourceId
        } else if windowTitleRulesEnabled {
            target = windowTitleRules()
                .filter { $0.isEnabled && !$0.hasAXPatterns }
                .filter {
                    $0.matches(bundleId: context.bundleIdentifier ?? "",
                               windowTitle: context.windowTitle ?? "",
                               axInfo: nil)
                }
                .compactMap(\.targetInputSourceId)
                .last
        } else {
            target = nil
        }
        if let target { return .select(target) }
        // Only a context that knows the window title can tell that no rule covers the
        // window. An entry has none yet: restoring there flips the source out and back
        // once the refinement matches the title.
        return context.hasResolvedWindowTitleRules ? .restorePreRuleSource : .none
    }

    private func effectiveBundleIdentifier(for context: AppContext) -> String? {
        if let overlayName = context.overlayName {
            return OverlayAppDetector.bundleId(forOverlayName: overlayName)
        }
        return context.bundleIdentifier
    }

    private func matchingInputMethodPolicy(
        bundleIdentifier: String,
        windowTitle: String
    ) -> InputMethodPolicy? {
        windowTitleRules()
            .filter { $0.isEnabled && !$0.hasAXPatterns }
            .filter { $0.matches(bundleId: bundleIdentifier, windowTitle: windowTitle, axInfo: nil) }
            .compactMap(\.inputMethodPolicy)
            .last
    }
}
