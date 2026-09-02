//
//  TapController.swift
//  XKeyIM
//
//  Owns XKeyIM's CGEventTap. When armed, the tap does all the typing (exactly the
//  path XKey.app uses) and XKeyIMController becomes a pass-through pipe. Without
//  Accessibility permission the tap never arms and XKeyIM falls back to marked text.
//

import Cocoa
import ApplicationServices

final class TapController {

    static let shared = TapController()

    private var manager: EventTapManager?
    private var handler: KeyboardEventHandler?
    private var activation = IMEActivation()

    /// App-switch handling, AX focus/title monitoring, the mouse-click monitor,
    /// and the overlay callback — the same machinery XKey.app hosts via
    /// AppDelegate. Constructed fresh on every arm() and released in disarm()/
    /// shutdown() rather than cached like `manager`/`handler`: it is cheap to
    /// rebuild and this keeps its AXObserver/NSWorkspace registrations scoped
    /// exactly to "tap is armed", with no separate suspend state to track.
    private var tapEventSource: TapEventSource?

    /// Observes settings changes for as long as the tap is armed. Registered in arm()
    /// and removed in disarm()/shutdown(), symmetrically with tapEventSource.
    private var settingsObserver: NSObjectProtocol?

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

    private init() {}

    // MARK: - Permission

    /// Ground truth for "may I post and listen to events?". `AXIsProcessTrusted()`
    /// answers a broader question; these two are the specific permissions a tap
    /// needs, and they are what CGEventTapCreate is actually gated on.
    static func hasEventPermission() -> Bool {
        CGPreflightListenEventAccess() && CGPreflightPostEventAccess()
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
    }

    func imeDidDeactivate(stillSelected: Bool) {
        activation.deactivate(stillSelected: stillSelected)
        reconcile()
    }

    func inputSourceChanged(isXKeyIM: Bool) {
        activation.selectionChanged(isXKeyIM: isXKeyIM)
        reconcile()
    }

    /// Keeps KeyboardEventHandler's frontmost-app cache fresh. Without this its
    /// exclusion check falls back to a live NSWorkspace query on every keystroke.
    func noteFrontmostApp(bundleId: String?) {
        handler?.noteFrontmostApp(bundleId: bundleId)
    }

    /// Push the shared on/off state into the tap's handler, which caches it.
    func applyVietnameseEnabled(_ enabled: Bool) {
        handler?.setVietnamese(enabled)
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
    }

    private func arm() {
        guard !isArmed else { return }

        let handler = self.handler ?? KeyboardEventHandler()
        self.handler = handler
        handler.noteFrontmostApp(bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        applyEnvironment(to: handler)

        let manager = self.manager ?? EventTapManager()
        manager.delegate = handler
        self.manager = manager

        // Claim ownership BEFORE the tap goes live, the mirror of disarm()'s order.
        // Starting the tap first leaves a window where it is already processing while
        // XKey.app still believes it owns the keyboard, and both transform the same
        // keystroke. Claiming first yields a harmless "nobody transforms" gap instead,
        // and the failure path below hands ownership straight back.
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))

        do {
            try manager.start()
        } catch EventTapManager.EventTapError.alreadyRunning {
            manager.resume()
        } catch {
            IMKitDebugger.shared.log("Tap failed to start: \(error)", category: "TAP")
            SharedSettings.shared.disarmXKeyIMTap()
            return
        }

        isArmed = true

        // Drive the tap from the same event source XKey.app hosts (app-switch
        // handling, AX focus/title monitoring, mouse-click monitor, overlay
        // callback, Force Accessibility). Started only now that the tap itself
        // is confirmed armed, mirroring the old observeFrontmostApp() timing —
        // a failed manager.start() above returns before this point, so no AX
        // machinery ever runs while isArmed is false.
        // Always the active host here: this object only holds a TapEventSource while
        // its own tap is armed, and arm() is what claims ownership in the first place.
        let source = TapEventSource(handler: handler, isActiveHost: { true })
        // Of TapEventSource's host callbacks, only onLogEvent applies here: it is
        // plain event logging, not gated on any UI XKeyIM lacks, and XKeyIM
        // already has a log sink. The rest are debug-window, temp-off/
        // translation-toolbar, or Smart Switch hooks — XKey.app-only UI/state
        // that XKeyIM has no equivalent for — and are intentionally left nil.
        source.onLogEvent = { message in
            IMKitDebugger.shared.log(message, category: "TAP")
        }
        source.start()
        tapEventSource = source

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
            //   - SmartSwitchManager.saveToPlist() likewise persists a language already
            //     applied in memory. Its only caller, VNEngine.saveAppLanguage, is not
            //     compiled into this target, so it cannot fire here today; wiring Smart
            //     Switch into XKeyIM would not change the reasoning.
            // So no self-posted change is ever missed here.
            // Distributed delivery is asynchronous, so arm()'s own armXKeyIMTap post can
            // land AFTER this observer is registered a few lines above, and without this
            // it buys a plist read, a JSON decode and a full applyAllSettings for nothing
            // on the path that arms the tap.
            guard (notification.object as? String) != Self.settingsProcessTag else { return }
            guard let self = self, self.isArmed, let handler = self.handler else { return }
            self.applyEnvironment(to: handler)
            IMKitDebugger.shared.log("Settings changed — tap environment reloaded", category: "TAP")
        }

        IMKitDebugger.shared.log("Tap ARMED (pid \(getpid()))", category: "TAP")
    }

    private func disarm() {
        guard isArmed else { return }
        manager?.suspend()
        isArmed = false
        SharedSettings.shared.disarmXKeyIMTap()
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

    /// Called from applicationWillTerminate: the flag must not outlive the process,
    /// or XKey.app would keep yielding to a tap that no longer exists. (The PID
    /// liveness check is the backstop for a hard crash.)
    func shutdown() {
        manager?.stop()
        isArmed = false
        SharedSettings.shared.disarmXKeyIMTap()
        tapEventSource?.stop()
        tapEventSource = nil
        removeSettingsObserver()
    }
}
