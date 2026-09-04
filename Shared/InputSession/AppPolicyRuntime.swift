import Foundation

struct AppContext: Equatable {
    let bundleIdentifier: String?
    let windowTitle: String?
    let overlayName: String?
    let resolvedInputMethodPolicy: InputMethodPolicy?
    let resolvedTargetInputSourceId: String?
    let hasResolvedWindowTitleRules: Bool

    init(bundleIdentifier: String?,
         windowTitle: String?,
         overlayName: String?,
         resolvedInputMethodPolicy: InputMethodPolicy? = nil,
         resolvedTargetInputSourceId: String? = nil,
         hasResolvedWindowTitleRules: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.overlayName = overlayName
        self.resolvedInputMethodPolicy = resolvedInputMethodPolicy
        self.resolvedTargetInputSourceId = resolvedTargetInputSourceId
        self.hasResolvedWindowTitleRules = hasResolvedWindowTitleRules
    }
}

enum AppPolicyDecision: Equatable {
    case keepCurrentLanguage
    case overrideVietnamese(Bool)
    case restoreVietnamese(Bool)
    case disableTransformation
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
            let provisionalContext = AppContext(
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle,
                overlayName: context.overlayName
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
