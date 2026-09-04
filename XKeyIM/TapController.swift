//
//  TapController.swift
//  XKeyIM
//
//  Owns XKeyIM's CGEventTap. When armed, the tap does all the typing (exactly the
//  path XKey.app uses) and XKeyIMController becomes a pass-through pipe. Without
//  event listen/post permission the tap never arms and XKeyIM falls back to marked text.
//

import Cocoa
import ApplicationServices

private struct TapHostCommandContext {
    let event: CGEvent
    let proxy: CGEventTapProxy
}

final class TapController {

    struct EventPermissionStatus {
        let canListen: Bool
        let canPost: Bool

        var isGranted: Bool { canListen && canPost }
    }

    static let shared = TapController()

    private var manager: EventTapManager?
    private var handler: KeyboardEventHandler?
    private var activation = IMEActivation()
    private var secureInputTimer: Timer?
    private lazy var secureInputRuntime = SecureInputHostRuntime(
        monitor: SecureInputMonitor(
            detector: SystemSecureInputDetector(),
            capabilities: .xkeyIM,
            presenter: SecureInputOverlay.shared,
            ownsPresentation: { [weak self] in self?.activation.isActive == true },
            presentationEnabled: { SharedSettings.shared.vietnameseEnabled },
            onTransition: { transition in
                switch transition {
                case .becameActive(let observation), .holderChanged(let observation):
                    IMKitDebugger.shared.log(
                        "Secure Input enabled by \(observation.holderAppName)",
                        category: "TAP"
                    )
                case .becameInactive:
                    IMKitDebugger.shared.log("Secure Input disabled", category: "TAP")
                }
            }
        )
    )

    /// App-switch handling, AX focus/title monitoring, the mouse-click monitor,
    /// and the overlay callback — the same machinery XKey.app hosts via
    /// AppDelegate. Constructed fresh on every arm() and released in disarm()/
    /// shutdown() rather than cached like `manager`/`handler`: it is cheap to
    /// rebuild and this keeps its AXObserver/NSWorkspace registrations scoped
    /// exactly to "tap is armed", with no separate suspend state to track.
    private var tapEventSource: TapEventSource?
    private var lastAppContext: AppContext?
    private let appContextQueue = DispatchQueue(label: "com.codetay.XKeyIM.app-policy-context",
                                                qos: .userInitiated)
    private var appContextGeneration: UInt64 = 0
    private var resolvingBundleIdentifier: String?
    private var appContextCallbacks: [(AppContext) -> Void] = []
    private var lastAppContextRefreshAt: TimeInterval = 0

    /// Observes settings changes for as long as the tap is armed. Registered in arm()
    /// and removed in disarm()/shutdown(), symmetrically with tapEventSource.
    private var settingsObserver: NSObjectProtocol?
    private lazy var hostCommandRouter = HostCommandRouter<TapHostCommandContext>(
        capabilities: .xkeyIM,
        handler: { [weak self] command, context in
            self?.handleHostCommand(command, context: context) ?? .unavailable
        },
        log: { message in IMKitDebugger.shared.log(message, category: "TAP") }
    )

    /// The sender tag SharedSettings.notifySettingsChanged() puts in the distributed
    /// notification's `object`, so the observer can tell this process's own writes from
    /// XKey.app's.
    /// ponytail: the format is duplicated from SharedSettings, which keeps the tag
    /// private; replace this with an accessor there once that file is free to change.
    /// Drifting apart only costs back the redundant rebuild this avoids.
    private static let settingsProcessTag = "xkey-\(ProcessInfo.processInfo.processIdentifier)"

    /// True while the tap owns the keyboard. Read by XKeyIMController on every
    /// keystroke, so it must stay a plain stored-property read.
    private(set) var isArmed = false

    private enum HandoffState {
        case idle
        case waiting(InputOwnershipHandoffRequest, deadline: TimeInterval)
        case failed
    }

    private var handoffState: HandoffState = .idle
    private var activeHandoffRequest: InputOwnershipHandoffRequest?
    private lazy var handoffCoordinator = InputOwnershipHandoffCoordinator(
        store: SharedSettings.shared,
        processChecker: SystemInputOwnershipProcessChecker()
    )
    private static let handoffTimeout: TimeInterval = 0.5
    private static let handoffPollInterval: TimeInterval = 0.01

    var blocksIMKitProcessingForHandoff: Bool {
        switch handoffState {
        case .waiting, .failed: return true
        case .idle: return false
        }
    }

    private init() {}

    // MARK: - Permission

    /// Ground truth for "may I post and listen to events?". `AXIsProcessTrusted()`
    /// answers a broader question; these two are the specific permissions a tap
    /// needs, and they are what CGEventTapCreate is actually gated on.
    static func eventPermissionStatus() -> EventPermissionStatus {
        EventPermissionStatus(
            canListen: CGPreflightListenEventAccess(),
            canPost: CGPreflightPostEventAccess()
        )
    }

    static func hasEventPermission() -> Bool {
        eventPermissionStatus().isGranted
    }

    // MARK: - IME lifecycle

    /// Set by reconcile() when arming or disarming actually changed the channel.
    /// XKeyIMController reads and clears it to finish the word in progress — the
    /// two channels track a word differently, so carrying one across the switch
    /// leaves the engine describing text the new channel never wrote.
    private(set) var channelDidChange = false

    func consumeChannelChange() -> Bool {
        defer { channelDidChange = false }
        return channelDidChange
    }

    func imeDidActivate(isSelected: Bool) {
        activation.activate(isSelected: isSelected)
        reconcile()
        if !isArmed {
            invalidateAppContext()
        }
        refreshAppContext(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        updateSecureInputMonitoring()
    }

    func imeDidDeactivate(stillSelected: Bool) {
        activation.deactivate(stillSelected: stillSelected)
        reconcile()
        if !activation.isActive {
            invalidateAppContext()
        }
        updateSecureInputMonitoring()
    }

    func inputSourceChanged(isXKeyIM: Bool) {
        activation.selectionChanged(isXKeyIM: isXKeyIM)
        reconcile()
        updateSecureInputMonitoring()
    }

    /// Keeps KeyboardEventHandler's frontmost-app cache fresh. Without this its
    /// exclusion check falls back to a live NSWorkspace query on every keystroke.
    func noteFrontmostApp(bundleId: String?) {
        handler?.noteFrontmostApp(bundleId: bundleId)
    }

    /// Push the shared on/off state into the tap's handler, which caches it.
    func applyVietnameseEnabled(_ enabled: Bool) {
        handler?.setVietnamese(enabled)
        updateSecureInputMonitoring()
    }

    func appContext(bundleIdentifier: String?) -> AppContext {
        resolvedAppContext(bundleIdentifier: bundleIdentifier, onResolved: nil)
            ?? AppContext(bundleIdentifier: bundleIdentifier,
                          windowTitle: Self.windowTitle(for: bundleIdentifier),
                          overlayName: Self.overlayName(for: bundleIdentifier))
    }

    /// Returns nil while the off-main AX snapshot is pending. Callers must not
    /// transform that event using a stale/default policy; `onResolved` installs the
    /// policy before a later event is processed.
    func resolvedAppContext(
        bundleIdentifier: String?,
        onResolved: ((AppContext) -> Void)?
    ) -> AppContext? {
        if isArmed,
           let lastAppContext,
           lastAppContext.bundleIdentifier == bundleIdentifier {
            if lastAppContext.overlayName == nil
                || OverlayAppDetector.shared.getVisibleOverlayAppName() == lastAppContext.overlayName {
                return lastAppContext
            }
        }
        if let lastAppContext,
           lastAppContext.overlayName == nil,
           lastAppContext.bundleIdentifier == bundleIdentifier {
            let liveTitle = Self.windowTitle(for: bundleIdentifier)
            let cacheDecision = AppPolicyRuntime.cacheDecision(
                cachedWindowTitle: lastAppContext.windowTitle,
                liveWindowTitle: liveTitle,
                age: ProcessInfo.processInfo.systemUptime - lastAppContextRefreshAt
            )
            if !cacheDecision.useCached {
                invalidateAppContext()
            } else {
                if cacheDecision.shouldRefresh {
                    refreshAppContext(bundleIdentifier: bundleIdentifier)
                }
                return lastAppContext
            }
        }
        if resolvingBundleIdentifier != nil,
           resolvingBundleIdentifier != bundleIdentifier {
            appContextCallbacks.removeAll()
        }
        if let onResolved {
            appContextCallbacks.append(onResolved)
        }
        refreshAppContext(bundleIdentifier: bundleIdentifier)
        return nil
    }

    private func invalidateAppContext() {
        appContextGeneration &+= 1
        lastAppContext = nil
        resolvingBundleIdentifier = nil
        appContextCallbacks.removeAll()
    }

    private func refreshAppContext(bundleIdentifier: String?) {
        guard !isArmed else { return }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let resolvedBundleIdentifier = bundleIdentifier ?? frontApp?.bundleIdentifier
        guard resolvingBundleIdentifier != resolvedBundleIdentifier else { return }
        resolvingBundleIdentifier = resolvedBundleIdentifier
        appContextGeneration &+= 1
        let generation = appContextGeneration
        let appElement = frontApp.map { AXUIElementCreateApplication($0.processIdentifier) }

        appContextQueue.async { [weak self] in
            let focusedInfo: AppBehaviorDetector.FocusedElementInfo
            if let element = AXHelper.getFocusedElement() {
                focusedInfo = .from(element, appElement: appElement)
            } else {
                focusedInfo = .withoutFocusedElement(appElement: appElement)
            }
            focusedInfo.materialise(bundleId: resolvedBundleIdentifier, includingCaret: false)

            DispatchQueue.main.async {
                guard let self else { return }
                guard !self.isArmed, generation == self.appContextGeneration else { return }
                let resolvedTitle = focusedInfo.windowTitle
                    ?? Self.windowTitle(for: resolvedBundleIdentifier)
                let matchingInfo: AppBehaviorDetector.FocusedElementInfo
                if focusedInfo.windowTitle == nil, let resolvedTitle {
                    matchingInfo = AppBehaviorDetector.FocusedElementInfo(
                        element: focusedInfo.element,
                        role: focusedInfo.role,
                        subrole: focusedInfo.subrole,
                        description: focusedInfo.description,
                        identifier: focusedInfo.identifier,
                        domIdentifier: focusedInfo.domIdentifier,
                        domClasses: focusedInfo.domClasses,
                        roleDescription: focusedInfo.roleDescription,
                        windowTitle: resolvedTitle
                    )
                } else {
                    matchingInfo = focusedInfo
                }
                let rules = AppBehaviorDetector.shared.getMergedRuleResult(focusedInfo: matchingInfo)
                let context = AppContext(
                    bundleIdentifier: resolvedBundleIdentifier,
                    windowTitle: resolvedTitle,
                    overlayName: Self.overlayName(for: resolvedBundleIdentifier),
                    resolvedInputMethodPolicy: rules.inputMethodPolicy,
                    resolvedTargetInputSourceId: rules.targetInputSourceId,
                    hasResolvedWindowTitleRules: true
                )
                self.lastAppContext = context
                self.lastAppContextRefreshAt = ProcessInfo.processInfo.systemUptime
                self.resolvingBundleIdentifier = nil
                let callbacks = self.appContextCallbacks
                self.appContextCallbacks.removeAll()
                callbacks.forEach { $0(context) }
            }
        }
    }

    /// Non-AX fallback for title-only rules. Window names may be unavailable under
    /// privacy restrictions; that is a resolved nil and falls back to global policy.
    private static func windowTitle(for bundleIdentifier: String?) -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else { return nil }
        return windows.first {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }?[kCGWindowName as String] as? String
    }

    private static func overlayName(for bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.apple.Spotlight": return "Spotlight"
        case "com.raycast.macos": return "Raycast"
        case "com.runningwithcrayons.Alfred", "com.runningwithcrayons.Alfred-3": return "Alfred"
        default: return nil
        }
    }

    @discardableResult
    func evaluateSecureInput() -> Bool {
        secureInputRuntime.evaluateMarkedTextInput()
    }

    // MARK: - Arming

    private func reconcile() {
        let shouldArm = activation.isActive && Self.hasEventPermission()
        let was = isArmed
        if shouldArm { arm() } else { disarm() }
        if isArmed != was { channelDidChange = true }
    }

    /// Wire host state into the tap layer through the same contract XKey.app uses, so
    /// the two hosts can never again drift apart by wiring different subsets — this is
    /// what previously left XKeyIM's tap running with the silent defaults for input
    /// method, code table, excluded apps and Window Title Rules, and with no AX timeout
    /// ceiling (the Raycast/Spotlight freeze).
    ///
    /// Read fresh on every call rather than cached: XKey.app's Settings window can write
    /// to the shared App Group at any time this process is alive, so any value read once
    /// would go stale for the rest of the process's life.
    private func applyEnvironment(to handler: KeyboardEventHandler) {
        let tapPreferences = SharedSettings.shared.loadPreferences()
        let environment = TapEnvironment(
            preferences: tapPreferences,
            overlayAppName: { OverlayAppDetector.shared.getVisibleOverlayAppName() },
            remoteDesktopInjectMode: { SharedSettings.shared.remoteDesktopInjectMode },
            windowTitleRulesEnabled: tapPreferences.windowTitleRulesEnabled,
            vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
            axMessagingTimeout: 0.25
        )
        environment.apply(to: handler)
        configureHotkeys(tapPreferences)
    }

    private func configureHotkeys(_ preferences: Preferences) {
        guard let manager else { return }
        manager.toggleHotkey = preferences.toggleHotkey
        manager.undoTypingHotkey = preferences.undoTypingEnabled
            ? (preferences.undoTypingHotkey
                ?? Hotkey(keyCode: VietnameseData.KEY_ESC, modifiers: []))
            : nil
        manager.toggleExclusionHotkey = preferences.toggleExclusionHotkey.keyCode == 0
            ? nil : preferences.toggleExclusionHotkey
        manager.toggleWindowRulesHotkey = preferences.toggleWindowRulesHotkey.keyCode == 0
            ? nil : preferences.toggleWindowRulesHotkey

        manager.toolbarHotkey = preferences.tempOffToolbarHotkey.keyCode == 0
            ? nil : preferences.tempOffToolbarHotkey
        manager.convertToolHotkey = preferences.convertToolHotkey.keyCode == 0
            ? nil : preferences.convertToolHotkey
        manager.translationHotkey = preferences.translationEnabled
            && preferences.translationHotkey.keyCode != 0
            ? preferences.translationHotkey : nil
        manager.translateToSourceHotkey = preferences.translationEnabled
            && preferences.translateToSourceHotkey.keyCode != 0
            ? preferences.translateToSourceHotkey : nil
        manager.debugHotkey = preferences.debugHotkey.keyCode == 0
            ? nil : preferences.debugHotkey
    }

    private func handleHostCommand(_ command: HostCommand,
                                   context: TapHostCommandContext) -> HostCommandResult {
        guard let handler else { return .unavailable }
        switch command {
        case .toggleVietnamese:
            let enabled = !SharedSettings.shared.vietnameseEnabled
            let preferences = SharedSettings.shared.loadPreferences()
            let runtimePreferences = RuntimePreferences(
                preferences: preferences,
                vietnameseEnabled: enabled,
                windowTitleRulesEnabled: preferences.windowTitleRulesEnabled,
                remoteDesktopInjectMode: preferences.remoteDesktopInjectMode
            )
            let runtime = AppPolicyRuntime(
                smartSwitchStore: handler.engine.smartSwitchManager,
                windowTitleRules: { AppBehaviorDetector.shared.getCustomRules() }
            )
            runtime.saveCurrentLanguage(
                enabled,
                context: lastAppContext ?? appContext(
                    bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                ),
                preferences: runtimePreferences
            )
            SharedSettings.shared.vietnameseEnabled = enabled
            applyVietnameseEnabled(enabled)
            if SharedSettings.shared.beepOnToggle { NSSound.beep() }
            return .handled
        case .undoTyping:
            return handler.performUndoTyping(event: context.event, proxy: context.proxy)
                ? .handled : .unavailable
        case .toggleExclusionRules:
            let enabled = !SharedSettings.shared.exclusionRulesEnabled
            SharedSettings.shared.exclusionRulesEnabled = enabled
            handler.exclusionRulesEnabled = enabled
            AppBehaviorDetector.shared.setConfirmedInjectionMethod(
                AppBehaviorDetector.shared.detectInjectionMethod()
            )
            if SharedSettings.shared.beepOnToggle { NSSound.beep() }
            return .handled
        case .toggleWindowTitleRules:
            let enabled = !SharedSettings.shared.windowTitleRulesEnabled
            SharedSettings.shared.windowTitleRulesEnabled = enabled
            AppBehaviorDetector.shared.windowTitleRulesEnabled = enabled
            AppBehaviorDetector.shared.setConfirmedInjectionMethod(
                AppBehaviorDetector.shared.detectInjectionMethod()
            )
            let preferences = SharedSettings.shared.loadPreferences()
            let runtimePreferences = RuntimePreferences(
                preferences: preferences,
                vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
                windowTitleRulesEnabled: enabled,
                remoteDesktopInjectMode: preferences.remoteDesktopInjectMode
            )
            let runtime = AppPolicyRuntime(
                smartSwitchStore: handler.engine.smartSwitchManager,
                windowTitleRules: { AppBehaviorDetector.shared.getCustomRules() }
            )
            runtime.reevaluateAfterWindowTitleRulesChange(
                context: lastAppContext,
                currentVietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
                preferences: runtimePreferences,
                apply: { [weak handler] decision in
                    handler?.applyAppPolicyDecision(
                        decision,
                        currentVietnameseEnabled: SharedSettings.shared.vietnameseEnabled
                    )
                    if case .restoreVietnamese(let enabled) = decision {
                        SharedSettings.shared.vietnameseEnabled = enabled
                    }
                },
                invalidateCache: { [weak self] in self?.invalidateAppContext() },
                refresh: { [weak self] in self?.tapEventSource?.handleFocusCheck() }
            )
            if SharedSettings.shared.beepOnToggle { NSSound.beep() }
            return .handled
        case .showTranslation, .translateToSource, .showConvertTool,
             .showSettings, .showDebugWindow, .showToolbar:
            return .unsupported
        }
    }

    private func arm() {
        guard !isArmed else { return }
        guard case .idle = handoffState else { return }

        let handler = self.handler ?? KeyboardEventHandler()
        self.handler = handler
        handler.noteFrontmostApp(bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        let manager = self.manager ?? EventTapManager()
        manager.delegate = handler
        manager.eventPermissionCheck = { Self.hasEventPermission() }
        manager.onEventTapPermissionLost = { [weak self] in
            self?.disarm()
        }
        manager.onHostCommand = { [weak self] command, event, proxy in
            guard let self else { return .unavailable }
            return self.hostCommandRouter.route(
                command,
                context: TapHostCommandContext(event: event, proxy: proxy)
            )
        }
        self.manager = manager

        // Manager must exist before applyEnvironment configures its hotkey bindings.
        applyEnvironment(to: handler)

        let request = handoffCoordinator.beginRequest(requesterPID: Int(getpid()))
        activeHandoffRequest = request
        let deadline = ProcessInfo.processInfo.systemUptime + Self.handoffTimeout
        handoffState = .waiting(request, deadline: deadline)
        continueHandoff(request: request, deadline: deadline)
    }

    private func continueHandoff(request: InputOwnershipHandoffRequest,
                                 deadline: TimeInterval) {
        guard case .waiting(let current, _) = handoffState, current == request else { return }
        let timedOut = ProcessInfo.processInfo.systemUptime >= deadline
        let decision = handoffCoordinator.claimDecision(for: request, timedOut: timedOut)
        switch decision {
        case .startAfterAcknowledgement:
            activeHandoffRequest = nil
            handoffState = .idle
            startArmedTap()
        case .startWithoutMain:
            handoffState = .idle
            startArmedTap()
        case .wait:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.handoffPollInterval) { [weak self] in
                self?.continueHandoff(request: request, deadline: deadline)
            }
        case .failSafe:
            _ = handoffCoordinator.cancelRequest(request)
            activeHandoffRequest = nil
            handoffState = .failed
            IMKitDebugger.shared.log(
                "Tap handoff timed out or was superseded; staying pass-through",
                category: "TAP"
            )
        }
    }

    private func startArmedTap() {
        guard activation.isActive, Self.hasEventPermission(), !isArmed,
              let handler, let manager else {
            cancelActiveHandoffRequest()
            return
        }

        // The matching handoff acknowledgement means XKey.app has already suspended
        // its sources and drained pending injection. If its registered PID was stale,
        // there is no main transformer to overlap.
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))

        do {
            try manager.start()
        } catch EventTapManager.EventTapError.alreadyRunning {
            manager.resume()
        } catch {
            IMKitDebugger.shared.log("Tap failed to start: \(error)", category: "TAP")
            cancelActiveHandoffRequest()
            SharedSettings.shared.disarmXKeyIMTap()
            return
        }

        isArmed = true
        channelDidChange = true

        // Drive the tap from the same event source XKey.app hosts (app-switch
        // handling, AX focus/title monitoring, mouse-click monitor, overlay
        // callback, Force Accessibility). Started only now that the tap itself
        // is confirmed armed, mirroring the old observeFrontmostApp() timing —
        // a failed manager.start() above returns before this point, so no AX
        // machinery ever runs while isArmed is false.
        // Always the active host here: this object only holds a TapEventSource while
        // its own tap is armed, and arm() is what claims ownership in the first place.
        let source = TapEventSource(handler: handler,
                                    isActiveHost: { true },
                                    secureInputMonitor: secureInputRuntime.monitor)
        // XKeyIM keeps its own log sink. Main-app window and toolbar callbacks stay nil;
        // shared app policy is wired below through onAppContext.
        source.onLogEvent = { message in
            IMKitDebugger.shared.log(message, category: "TAP")
        }
        source.onAppContext = { [weak self, weak handler] context in
            guard let self, let handler else { return }
            self.lastAppContext = context
            self.lastAppContextRefreshAt = ProcessInfo.processInfo.systemUptime
            self.applyAppPolicy(context, to: handler)
        }
        source.start()
        tapEventSource = source
        source.handleFocusCheck()

        // While the tap is armed it does all the typing, and XKeyIMController's
        // reloadSettings() only refreshes the marked-text path the tap bypasses. So
        // without this the armed session would keep the snapshot arm() read — old input
        // method, old macros, old excluded apps, old Window Title Rules switch — until
        // the user switched input source away and back.
        //
        // queue: .main is load-bearing twice over. It puts the rebuild on the same run
        // loop the tap callback runs on (EventTapManager adds its source to the main run
        // loop), so a keystroke can never observe a half-applied environment. And it
        // defers the block past this notification's synchronous observers, one of which
        // is SharedSettings invalidating the very cache loadPreferences() reads.
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .xkeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Ignore what this process posted itself. Four settings writes sit in this
            // target — the last of them latent — and skipping the reload loses nothing
            // for any of them:
            //   - armXKeyIMTap/disarmXKeyIMTap touch only the tap-ownership keys
            //     applyEnvironment never reads.
            //   - the menu's Vietnamese toggle pushes the new value straight into the
            //     handler through applyVietnameseEnabled.
            //   - AppBehaviorDetector.loadCustomRules() persists its sortIndex migration,
            //     but only after assigning the migrated rules in memory — and this
            //     observer reaches that call through applyEnvironment itself, so acting
            //     on the post would re-read what applyEnvironment had just written.
            //   - Smart Switch writes merge into the manager before notifying, so the
            //     process already sees its own newly persisted language.
            // So no self-posted change is ever missed here.
            // Distributed delivery is asynchronous, so arm()'s own armXKeyIMTap post can
            // land AFTER this observer is registered a few lines above, and without this
            // it buys a plist read, a JSON decode and a full runtime snapshot apply for nothing
            // on the path that arms the tap.
            guard (notification.object as? String) != Self.settingsProcessTag else { return }
            guard let self = self, self.isArmed, let handler = self.handler else { return }
            handler.engine.smartSwitchManager.loadFromPlist()
            self.applyEnvironment(to: handler)
            self.tapEventSource?.handleFocusCheck()
            self.updateSecureInputMonitoring()
            IMKitDebugger.shared.log("Settings changed — tap environment reloaded", category: "TAP")
        }

        IMKitDebugger.shared.log("Tap ARMED (pid \(getpid()))", category: "TAP")
    }

    private func applyAppPolicy(_ context: AppContext, to handler: KeyboardEventHandler) {
        handler.engine.smartSwitchManager.loadFromPlist()
        let preferences = SharedSettings.shared.loadPreferences()
        let runtimePreferences = RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
            windowTitleRulesEnabled: preferences.windowTitleRulesEnabled,
            remoteDesktopInjectMode: preferences.remoteDesktopInjectMode
        )
        let current = SharedSettings.shared.vietnameseEnabled
        let runtime = AppPolicyRuntime(
            smartSwitchStore: handler.engine.smartSwitchManager,
            windowTitleRules: { AppBehaviorDetector.shared.getCustomRules() }
        )
        let decision = runtime.evaluate(
            context: context,
            currentVietnameseEnabled: current,
            preferences: runtimePreferences
        )
        handler.applyAppPolicyDecision(decision, currentVietnameseEnabled: current)
        if case .restoreVietnamese(let enabled) = decision {
            SharedSettings.shared.vietnameseEnabled = enabled
        }
    }

    private func disarm() {
        cancelActiveHandoffRequest()
        handoffState = .idle
        guard isArmed else { return }
        manager?.suspend()
        handler?.releaseOwnership(afterPendingInjection: { [self] in
            isArmed = false
            SharedSettings.shared.disarmXKeyIMTap()
        })
        tapEventSource?.stop()
        tapEventSource = nil
        removeSettingsObserver()
        IMKitDebugger.shared.log("Tap DISARMED", category: "TAP")
    }

    private func removeSettingsObserver() {
        guard let observer = settingsObserver else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        settingsObserver = nil
    }

    private func cancelActiveHandoffRequest() {
        guard let request = activeHandoffRequest else { return }
        _ = handoffCoordinator.cancelRequest(request)
        activeHandoffRequest = nil
    }

    private func updateSecureInputMonitoring() {
        let shouldPoll = activation.isActive && SharedSettings.shared.vietnameseEnabled
        if shouldPoll && secureInputTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.secureInputRuntime.evaluatePhysicalInput()
            }
            timer.tolerance = 1
            secureInputTimer = timer
        } else if !shouldPoll {
            secureInputTimer?.invalidate()
            secureInputTimer = nil
        }
        secureInputRuntime.evaluatePhysicalInput()
    }

    /// Called from applicationWillTerminate: the flag must not outlive the process,
    /// or XKey.app would keep yielding to a tap that no longer exists. (The PID
    /// liveness check is the backstop for a hard crash.)
    func shutdown() {
        cancelActiveHandoffRequest()
        handoffState = .idle
        manager?.stop()
        let release = { [self] in
            isArmed = false
            SharedSettings.shared.disarmXKeyIMTap()
        }
        if let handler {
            handler.releaseOwnership(afterPendingInjection: release)
        } else {
            release()
        }
        tapEventSource?.stop()
        tapEventSource = nil
        removeSettingsObserver()
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        secureInputRuntime.monitor.invalidate()
    }
}
