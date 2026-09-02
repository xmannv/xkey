//
//  TapEventSource.swift
//
//  Machinery that feeds the shared event-tap layer, relocated out of
//  XKey.app's AppDelegate so XKeyIM can host the same behaviour. Each
//  relocation task is a mechanical move — XKey.app's users must not be able
//  to tell it happened.
//
//  App-switch handling (Task 6), AXObserver focus/title monitoring (Task 7),
//  and the mouse-click monitor + overlay callback (this file, Task 8) have
//  moved. TapController (Task 9) constructs this class.
//
//  Some calls the moved code makes reach into state that still lives on the
//  host (AppDelegate) — Smart Switch, the debug window, the temp-off/
//  translation toolbars, Secure Input. Those are routed through the callback
//  properties below instead of being dragged along. Force Accessibility used
//  to be one of them (Task 8) until ForceAccessibilityManager joined the
//  XKeyIM target and the call became direct. Each remaining callback's doc
//  comment says whether it stays on the host forever, or is temporary until
//  a later task inlines it.
//

import Cocoa

// MARK: - AXObserver Callback (C function)

/// C callback for AXObserver notifications (focus change + title change)
/// Must be outside class since AXObserver requires a C function pointer
/// Dispatches to appropriate handler based on notification type
private func axNotificationCallback(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    // Get TapEventSource instance from refcon
    guard let refcon = refcon else { return }
    let tapEventSource = Unmanaged<TapEventSource>.fromOpaque(refcon).takeUnretainedValue()
    let name = notificationName as String

    // Handle on main thread — dispatch to appropriate handler
    DispatchQueue.main.async {
        if name == kAXFocusedUIElementChangedNotification as String {
            tapEventSource.handleAXFocusChanged(element)
        } else if name == kAXTitleChangedNotification as String {
            tapEventSource.handleAXTitleChanged()
        }
    }
}

// MARK: - Focused Element Info (typealias to AppBehaviorDetector)

/// Use the unified FocusedElementInfo struct from AppBehaviorDetector
/// to avoid redundant struct definitions and AX queries
private typealias FocusedElementInfo = AppBehaviorDetector.FocusedElementInfo

/// Owns the shared event-tap machinery. Both XKey.app (CGEvent mode) and
/// XKeyIM host this so the two processes can never drift apart.
final class TapEventSource {

    // MARK: - Host callbacks

    /// Smart Switch: auto-switches input language per app / window-title rule.
    /// Stays on the host forever — Smart Switch is app/status-bar behaviour.
    var onSmartSwitch: ((Notification) -> Void)?

    /// Debug window event log.
    /// Stays on the host forever — the debug window is XKey.app UI.
    var onLogEvent: ((String) -> Void)?

    /// Re-evaluates Secure Input state (overlay warning + status bar) after
    /// an app switch.
    /// Stays on the host forever — the Secure Input overlay/status bar are
    /// XKey.app UI.
    var onEvaluateSecureInput: (() -> Void)?

    /// Hides the temp-off toolbar when there is no AX-focused element at all.
    /// Stays on the host forever — the temp-off toolbar is XKey.app UI.
    var onNoFocusedElement: (() -> Void)?

    /// Shows/updates/hides the temp-off and translation toolbars for the
    /// given focused element.
    /// Stays on the host forever — those toolbars are XKey.app UI.
    /// Typed with the full name (not the private `FocusedElementInfo` alias
    /// below) because this property's access level crosses the file boundary.
    var onCheckToolbarForFocusedElement: ((AppBehaviorDetector.FocusedElementInfo) -> Void)?

    /// Clears the host's cached last-focused element so the toolbar
    /// re-evaluates on the next check.
    /// Stays on the host forever — toolbar tracking is XKey.app UI.
    var onResetLastFocusedElement: (() -> Void)?

    /// Records the host's last-focused element for toolbar tracking, without
    /// forcing a toolbar re-evaluation.
    /// Stays on the host forever — toolbar tracking is XKey.app UI.
    var onUpdateLastFocusedElement: ((AXUIElement) -> Void)?

    /// Restores the overlay app's (Spotlight/Raycast/Alfred) saved Smart Switch
    /// language when the overlay opens.
    /// Stays on the host forever — Smart Switch/per-app language is XKey.app behaviour.
    var onEnableVietnameseForOverlay: (() -> Void)?

    /// Saves the current language for the given overlay app name (for Smart Switch).
    /// Stays on the host forever — Smart Switch/per-app language is XKey.app behaviour.
    var onSaveLanguageForOverlay: ((String?) -> Void)?

    /// Restores the current frontmost app's Smart Switch language.
    /// Stays on the host forever — Smart Switch/per-app language is XKey.app behaviour.
    var onRestoreLanguageForCurrentApp: (() -> Void)?

    /// Whether the debug window is currently open. Gates the extra AX
    /// retry-detection queries after a mouse click (perf: avoids the extra
    /// work during normal use, see setupMouseClickMonitor).
    /// Stays on the host forever — the debug window is XKey.app UI.
    var isDebugWindowVisible: (() -> Bool)?

    /// Detailed mouse-click debug log (app info, AX role, injection method,
    /// behavior, matched rule).
    /// Stays on the host forever — the debug window is XKey.app UI.
    var onLogMouseClickDetection: ((Int, Bool, InjectionMethodInfo, AppBehaviorDetector.FocusedElementInfo) -> Void)?

    // MARK: - State

    private let handler: KeyboardEventHandler

    /// True when THIS process owns the keystroke path and its tap-feeding AX work is worth doing.
    /// Required, not optional: a host that forgets it would silently duplicate every AX query in
    /// this file against the target app. See Task 9b.
    private let isActiveHost: () -> Bool

    /// Guards start()/stop() so a host that arms and disarms repeatedly (XKeyIM,
    /// once per IME activation) never double-registers the observers below.
    private var isRunning = false

    private var appSwitchObserver: NSObjectProtocol?
    private var appDeactivateObserver: NSObjectProtocol?

    /// The NSWorkspace.didActivateApplicationNotification observer registered by
    /// setupFocusChangeMonitoring(). Kept distinct from appSwitchObserver (same
    /// notification name, different observer/purpose) so stop() can remove both.
    private var focusCheckObserver: NSObjectProtocol?

    /// Global monitor for mouse-up events, used to detect focus changes from clicks.
    private var mouseClickMonitor: Any?

    /// AXObserver watching focus/title changes in the currently-tracked app.
    private var focusObserver: AXObserver?
    private var focusObserverPID: pid_t = 0

    /// PID whose last AXObserver install failed, so handleFocusCheck's re-arm does not
    /// retry it on every mouse-up. Set on exactly the two failure returns in
    /// setupAXObserverForApp — both of which leave `focusObserver` nil — and cleared on
    /// the success assignment right below them, so `focusObserverFailedPID != 0` always
    /// implies `focusObserver == nil`.
    /// Deliberately NOT cleared in removeAXObserver() alongside focusObserver and
    /// focusObserverPID: that function early-returns on `guard let observer =
    /// focusObserver`, so a reset sitting with the rest of the clearing would be dead
    /// exactly when it would matter, and one placed above that guard would drop the
    /// suppression on every teardown — stop(), setupAXObserverForApp's own, the
    /// ownership self-heal in handleAXFocusChanged/handleAXTitleChanged — handing the
    /// app that just refused another install attempt, and its AX messaging timeout, on
    /// the next mouse-up each time.
    /// What clears it instead is the next install that succeeds, so the two install
    /// paths that reach a refused app must stay unconditional for that to happen:
    /// setupFocusChangeMonitoring() (via start()) and the app-switch block. Moving this
    /// guard into setupAXObserverForApp — the intuitive place — would gate both of them
    /// too, leaving nothing to clear the field: one refused install would lock that app
    /// out permanently, across app switches AND across stop()/start().
    /// Not private: TapEventSourceObserverSelfHealTests clears it to prove the re-arm
    /// still fires once the suppression is lifted — the only assertion on that block that
    /// holds on a host without Accessibility permission, where every install is refused.
    var focusObserverFailedPID: pid_t = 0

    /// Track the last focused element's signature for injection detection
    /// Used to detect when user switches from web content to address bar, etc.
    /// Signature includes role, subrole, and description/identifier
    /// Not private: checkAndShowToolbarForFocusedElement (host, AppDelegate) still
    /// compares against it — see Task 7 report.
    private(set) var lastFocusedElementSignature: String = ""

    /// Throttle AXObserver focus change callbacks to prevent rapid-fire AX queries
    /// When apps have animations or autocomplete, AXObserver can fire many times per second
    private var lastAXFocusChangeTime: CFAbsoluteTime = 0
    private let axFocusChangeThrottleInterval: CFAbsoluteTime = 0.1 // 100ms

    /// Delayed title verification after AXObserver focus change (Layer 2)
    /// Catches stale window titles when apps update title AFTER focus change notification
    private var titleVerificationWorkItem: DispatchWorkItem?

    /// Window title used in last detection — for comparing in delayed verification
    private var lastDetectedTitle: String?

    /// Debounce for kAXTitleChangedNotification (Layer 1)
    /// Apps may fire multiple title changes during a single navigation (e.g., "Loading..." → final title)
    private var titleChangeDebounceWorkItem: DispatchWorkItem?

    /// True while an overlay chase chain is alive — from its first read until the step
    /// that stops it. Main thread only.
    ///
    /// What keeps the chain single: a chain only starts while this is false, and only a
    /// chain clears it. Arming signals arrive in bursts — Cmd down and the chord itself
    /// are two arms for one Cmd+Space, the Cmd-up flagsChanged carrying no modifier and so
    /// missing EventTapManager's guard — and one chain per burst is the point.
    private var overlayChaseActive = false

    /// Index into `overlayChaseDelays` for the live chain's next gap, restarted by every
    /// arming signal. Main thread only.
    ///
    /// Counting the chain's reads instead would anchor the backoff to the burst's FIRST
    /// arm, and the arm that matters is the last one: Cmd goes down, and the chord that
    /// actually opens the launcher follows tens or hundreds of milliseconds later.
    /// Anchored to the first arm and with Cmd held 100ms, the reads land at chord−100,
    /// −50 and +50, then not again until +250 — after a first character at ~chord+200ms,
    /// which then goes out on the underlying app's injection method and is scrambled by
    /// the launcher's inline autocomplete.
    ///
    /// Internal rather than private only so a test can assert that restart; nothing
    /// outside this type writes it.
    private(set) var overlayChaseBackoff = 0

    /// The live chain's next read while it is sleeping out its gap, held as a cancellable
    /// unit so an arming signal can drop that sleep and take the read now. Main thread only.
    ///
    /// nil whenever a read is in flight rather than sleeping: the step clears this before
    /// it runs, and the next one is not stored until that read's completion schedules it.
    ///
    /// Restarting `overlayChaseBackoff` is only half of aiming the chase at the chord,
    /// because a restart does not move a sleep that is already scheduled. Reads land at
    /// 0, 50, 150, 350, 750ms from the chain's start, so a chord arriving just after one
    /// of them waits out the whole gap that was already running — up to
    /// `overlayChaseDelays.last`, 400ms, against a first character at roughly
    /// chord+200ms. Taking that sleeping read now is what closes it.
    ///
    /// Deliberately NOT cancelled by `stop()` — see stop(), where `overlayChaseActive` is
    /// left set for the matching reason.
    ///
    /// Internal rather than private only so a test can assert that an arming signal leaves
    /// no read sleeping; nothing outside this type writes it.
    private(set) var overlayChaseStepWorkItem: DispatchWorkItem?

    /// How long a chase waits before its next overlay read, indexed by
    /// `overlayChaseBackoff`. The last entry repeats for every read after that.
    ///
    /// Progressive, not the flat 50ms this started as, because most chases find nothing
    /// and every read is up to five blocking AX round-trips into the app the user is
    /// typing in, on the queue the focus/title/app-switch passes share. armProbe() fires
    /// on every modifier press and every Cmd keyDown, so a Cmd+C arms two probes and a
    /// flat interval spent the whole window reading for an overlay that was never opening.
    ///
    /// The two short gaps up front are what keeps the find fast on a healthy machine, and
    /// what aims them at the chord rather than at the modifier press that preceded it is
    /// the pair an arming signal applies together: `overlayChaseBackoff` back to 0, and
    /// the step sleeping out the previous gap taken now rather than waited out. The table
    /// is therefore walked from the start from a read at the chord itself — chord+0, +50
    /// and +150, against a first character at roughly chord+200ms. Not a guarantee that a
    /// launcher is seen before that character: the read is queued behind whatever else is
    /// on axPassQueue, and a launcher slower than ~150ms is first seen by the +350 read.
    /// The long gaps are for the case that only costs: nothing appeared and nothing will.
    /// Deliberately not armProbeDeferred's 50ms and not for its reason: that is a FIRST
    /// delay, sized so the tap does not read before the app has processed the key, while
    /// these are the gaps BETWEEN reads and are sized against what each read costs.
    private static let overlayChaseDelays: [TimeInterval] = [0.05, 0.1, 0.2, 0.4]

    // MARK: - Off-main AX passes

    /// The queue this source's off-main AX reads run on: every snapshot `scheduleAXPass`
    /// takes, plus the two overlay reads that go straight to it without one — the chase's,
    /// and the one OverlayAppDetector's 0.5s dismissal poll asks for through
    /// `onOverlayReadNeeded`.
    ///
    /// Not every blocking AX read in this file. Two sets stay on main by choice:
    /// `setupAXObserverForApp` makes its AXObserverCreate and its two
    /// AXObserverAddNotification round-trips there, and the debug-gated
    /// `detectBehaviorWithRetry` takes a whole snapshot there (getFocusedElementInfo,
    /// then detectInjectionMethod, then isOverlayAppVisible, up to three times). Neither
    /// is per-notification: the first runs once per app switch and per re-arm, the second
    /// only while the debug window is open. The per-notification reads are what stalled
    /// the tap, and those are the ones this queue takes.
    ///
    /// Serial, not concurrent, and not `DispatchQueue.global()`: two snapshots racing
    /// into the same app's AX server gain nothing and multiply the load on the server
    /// that is the reason this work left the main thread in the first place.
    /// Created here so it lives exactly as long as the source does.
    private let axPassQueue = DispatchQueue(label: "com.xkey.TapEventSource.axPass",
                                            qos: .userInitiated)

    /// Generation of the newest AX pass scheduled. Main thread only.
    ///
    /// Passes can overlap and finish out of order; applying an older one would confirm
    /// an injection method for a context the user has already left, which is the class
    /// of bug this file spent seven rounds removing. So each pass captures this on
    /// schedule and the main-thread stage drops its result unless the value still
    /// matches. Not a timestamp: a timestamp cannot prove which snapshot is newer when
    /// the passes overlap.
    private var axPassGeneration: UInt64 = 0

    /// True from the moment a pass is handed to the queue until its main-thread stage
    /// begins. Main thread only.
    private var axPassInFlight = false

    /// The one pass that arrived while another was in flight. Main thread only.
    ///
    /// A later arrival replaces this rather than joining a queue: the generation check
    /// would drop every older result anyway, so only the newest is worth taking. Without
    /// it, notification bursts (Chrome fires ~7 AX notifications a second while the user
    /// interacts) would hand the AX server new multi-round-trip snapshots faster than it
    /// answers them, and the injection method applied would fall further behind with
    /// every one.
    private var pendingAXPass: PendingAXPass?

    /// A scheduled AX pass: the generation it must still match to be applied, the
    /// element to snapshot (nil = whatever is focused when it runs), and what to do with
    /// the result on the main thread.
    private struct PendingAXPass {
        let generation: UInt64
        let element: AXUIElement?
        /// Takes the source rather than capturing it, so a queued pass never keeps a
        /// released source alive past its deinit.
        let apply: (TapEventSource, AXSnapshot) -> Void
    }

    /// What one AX pass materialised off the main thread, so the stage that applies it
    /// makes no AX call of its own.
    struct AXSnapshot {
        /// The focused element's attributes, with every field a detection pass can read
        /// already resolved — see FocusedElementInfo.materialise(bundleId:includingCaret:).
        let focusedInfo: AppBehaviorDetector.FocusedElementInfo

        /// False when AX reported no focused element at all. `focusedInfo` is still
        /// usable in that case: it carries no element attributes but resolves the window
        /// title, which is all the title-only detectors need.
        let hasFocusedElement: Bool

        /// The overlay launcher's name, or nil when none is visible. Resolved through
        /// OverlayAppDetector's split probe: the AX read on the pass's queue, the cache
        /// write and the visibility callback on main.
        let overlayName: String?
    }

    init(handler: KeyboardEventHandler, isActiveHost: @escaping () -> Bool) {
        self.handler = handler
        self.isActiveHost = isActiveHost
    }

    deinit {
        // A host that constructs and releases a TapEventSource per arm/disarm
        // cycle (XKeyIM) must not be able to deallocate one that is still
        // running: the AXObserver callback resolves this instance with
        // Unmanaged.takeUnretainedValue(), which would read freed memory the
        // next time AX fires if the observer's run-loop source were still
        // installed. stop() is idempotent (guarded by isRunning), so this is a
        // no-op for the common case where the host already called stop().
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Listen for app activation changes to reset engine buffer
        // This prevents buffer from previous app affecting typing in new app
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Record the new frontmost app for per-keystroke exclusion checks.
            // The bundle ID comes straight from the notification's userInfo — no
            // extra IPC. nil falls back to a live NSWorkspace query per keystroke.
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.handler.noteFrontmostApp(bundleId: activatedApp?.bundleIdentifier)

            // Reset keyboard handler engine when switching apps
            // Use resetForAppSwitch() which assumes typing mid-sentence to prevent
            // Forward Delete from deleting text on the right of cursor
            self.handler.resetForAppSwitch()

            AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
            // The tap thread answers a cleared cache from the last confirmed values. This
            // is the one transition after which those describe the wrong app, so they go
            // too — the pass scheduled below refills them.
            AppBehaviorDetector.shared.clearInjectionMethodFallback()

            // Cancel pending title verifications from previous app
            self.titleVerificationWorkItem?.cancel()
            self.titleChangeDebounceWorkItem?.cancel()
            self.lastDetectedTitle = nil

            // Apply Force Accessibility (AXManualAccessibility) FIRST if matching rule exists
            // This MUST happen BEFORE detectInjectionMethod() because:
            // 1. Force AX enables enhanced accessibility for Electron/Chromium apps
            // 2. detectInjectionMethod() may need to read AX values
            // 3. AX values won't be available without Force AX enabled first
            //
            // Gated on ownership (Task 9b): while another process owns the keystroke
            // path, this app-switch pass would only duplicate that process's AX
            // round-trips into the app the user just switched to.
            if self.isActiveHost() {
                ForceAccessibilityManager.shared.applyForCurrentApp()
            }

            // Small delay to allow AX tree to update after setting AXManualAccessibility
            // Electron/Chromium apps need a moment to refresh their accessibility tree
            // NOTE: handleSmartSwitch is also inside this delay because it evaluates window
            // title rules via getTargetInputSourceOverride() → getMergedRuleResult().
            // Without the delay, window title may not be available yet (AX timing issue).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }

                // Handle Smart Switch - auto switch language per app
                // Moved INSIDE delay to ensure window title is available for rule-based
                // input source switching (targetInputSourceId in rules)
                self.onSmartSwitch?(notification)

                // Everything below is AX work that only feeds THIS process's tap, so it
                // is gated on ownership (Task 9b). Smart Switch above stays ungated
                // deliberately, and it is NOT free: handleSmartSwitch →
                // getTargetInputSourceOverride → getMergedRuleResult →
                // findAllMatchingRules → getCurrentWindowTitle costs roughly one
                // window-title AX query per app switch, plus one focused-element
                // snapshot as soon as a rule carrying AX patterns is EVALUATED —
                // matchRules loads it before it knows whether that rule matches. The
                // whole residual is zero while Window Title Rules is off:
                // findAllMatchingRules returns on that master switch before it asks for
                // the window title. That residual cost is accepted because gating it
                // would silence per-app language switching entirely — XKeyIM has no
                // Smart Switch of its own — and because it writes the shared language
                // state the owning process reads back. It can only be removed once
                // XKeyIM owns Smart Switch itself.
                guard self.isActiveHost() else { return }

                // Setup AXObserver for the new app to monitor focus changes (CMD+T, etc.)
                //
                // Runs here, not inside the pass below, because the pass may never run:
                // scheduleAXPass bumps the generation even when the pass only lands in the
                // pending slot, and the coalescer evicts whatever is in that slot as soon
                // as a newer pass arrives — the old app's AXObserver firing once during the
                // in-flight window is enough. That loss does not heal. This is the only
                // place the observer moves to the new app: handleFocusCheck re-arms only
                // while focusObserver is nil and it is not — it still points at the old
                // PID — and setupAXObserverForApp itself returns early unless the PID
                // differs. The process would then see no focus or title notification at
                // all for as long as the user stayed in the new app.
                //
                // Safe ahead of the detection below: neither call reads the snapshot or
                // anything the detection writes — setupAXObserverForApp takes the app out
                // of the notification and only installs callbacks, and onEvaluateSecureInput
                // reads IsSecureEventInputEnabled, not AppBehaviorDetector. The one thing
                // the earlier install changes is that the observer's first notification can
                // now supersede the pass below, and that direction is harmless: a
                // focus-change pass re-detects and re-confirms the injection method itself
                // (applyAXFocusChange), which is exactly what the superseded pass was for.
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.setupAXObserverForApp(app)
                }

                // Check Secure Input on app switch — password managers often enable it when focused
                self.onEvaluateSecureInput?()

                // Detect and set confirmed injection method for the new app
                // This ensures keystrokes use correct method immediately after app switch.
                // Only the detection result lives in the pass: everything a dropped pass
                // must not take with it is above.
                self.scheduleAXPass(element: nil) { source, snapshot in
                    let injectionInfo = source.confirmInjectionMethod(from: snapshot)

                    // DEBUG: Log window title available at app switch time
                    let switchWindowTitle = snapshot.focusedInfo.windowTitle ?? "(nil)"
                    source.onLogEvent?("App switched - engine reset, mid-sentence mode")
                    source.onLogEvent?("   Window: \(switchWindowTitle)")
                    let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                    source.onLogEvent?("   Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
                }
            }

            // Reset intra-app focus tracking (new app = new baseline)
            self.lastFocusedElementSignature = ""
        }

        // Safety net for the frontmost-app cache: if an app deactivates without a
        // matching didActivate (rare edge cases), clear the cache so exclusion
        // checks fall back to a live NSWorkspace query until the next activation.
        appDeactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler.noteFrontmostApp(bundleId: nil)
        }

        // AXObserver focus/title monitoring, relocated from AppDelegate (Task 7).
        setupFocusChangeMonitoring()

        // Mouse click monitor + overlay visibility callback, relocated from
        // AppDelegate (Task 8).
        setupMouseClickMonitor()
        setupOverlayDetectorCallback()

        // The tap thread's way of asking for an AX snapshot it must not take itself.
        AppBehaviorDetector.shared.scheduleInjectionMethodDetection = { [weak self] delay in
            self?.scheduleInjectionMethodDetection(after: delay)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        // Drop every AX pass this source has in flight, and the one waiting behind it.
        // Bumping the generation is what the main-thread stage checks, so an in-flight
        // pass still returns to main but applies nothing — it must not confirm an
        // injection method for a host that has already yielded, and deinit's stop() must
        // leave nothing that can reach this instance afterwards. Clearing the pending
        // slot stops the drain at the end of that stage from starting a fresh one.
        axPassGeneration &+= 1
        pendingAXPass = nil

        // Remove app switch observer
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }

        // Remove the deactivate-observer safety net registered in start().
        if let observer = appDeactivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appDeactivateObserver = nil
        }

        // Remove the focus-check observer registered by setupFocusChangeMonitoring().
        if let observer = focusCheckObserver {
            NotificationCenter.default.removeObserver(observer)
            focusCheckObserver = nil
        }

        removeAXObserver()

        // Remove mouse click monitor
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
        }

        OverlayAppDetector.shared.onOverlayVisibilityChanged = nil
        OverlayAppDetector.shared.onProbeArmed = nil
        OverlayAppDetector.shared.onOverlayReadNeeded = nil
        AppBehaviorDetector.shared.scheduleInjectionMethodDetection = nil

        // `overlayChaseActive` is deliberately NOT cleared here. A chase step already
        // sleeping ends itself on the isRunning guard when it wakes; clearing the flag now
        // would let a start() + arm inside that sleep begin a second chain alongside the
        // one still sleeping, and both would then read AX in lockstep. Left set, the
        // sleeping step either ends the chain (still stopped) or simply carries on as the
        // one live chain (restarted), and an arm inside that sleep does not wait it out —
        // startOverlayChase() fires the sleeping step there and then.
        //
        // `overlayChaseStepWorkItem` is left alone here for the matching reason: cancelling
        // it would leave nothing scheduled while `overlayChaseActive` is still set, and a
        // later arm, finding a chain it believes alive and no step to fire, would start
        // nothing at all.
    }

    // MARK: - AX Pass Scheduling

    /// Take one AX snapshot off the main thread, then apply it on main.
    ///
    /// Every detection driven by a notification, an app switch or a click goes through
    /// here. It is not the file's only AX-reading detection: `detectBehaviorWithRetry`
    /// still detects on the main thread — getFocusedElementInfo, detectInjectionMethod,
    /// setConfirmedInjectionMethod, isOverlayAppVisible — but only while the debug window
    /// is open, which is the gate it was given for the same cost reason.
    ///
    /// Everything that mutates AppBehaviorDetector or TapEventSource state, and every
    /// host callback, runs in `apply` — on the main thread, where the tap callback also
    /// runs, so none of that state ever becomes concurrent.
    /// - Parameters:
    ///   - element: the element to snapshot, or nil to snapshot whatever is focused when
    ///     the pass runs
    ///   - apply: the main-thread stage
    private func scheduleAXPass(element: AXUIElement?,
                                apply: @escaping (TapEventSource, AXSnapshot) -> Void) {
        // Ownership is checked here and again after the hop: a pass costs AX round-trips
        // into the target app, and while another process owns the keystroke path it
        // would only duplicate that process's (Task 9b).
        guard isActiveHost() else { return }

        axPassGeneration &+= 1
        let pass = PendingAXPass(generation: axPassGeneration, element: element, apply: apply)

        guard !axPassInFlight else {
            pendingAXPass = pass
            return
        }
        runAXPass(pass)
    }

    private func runAXPass(_ pass: PendingAXPass) {
        axPassInFlight = true

        // Read on the main thread and carried in, so the queue never touches NSWorkspace:
        // the frontmost app is AppKit state. Pinning it here also ties the window title
        // and the DOM-attribute gate to the app that was frontmost when the pass started.
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appElement = frontApp.map { AXUIElementCreateApplication($0.processIdentifier) }
        let bundleId = frontApp?.bundleIdentifier

        // Only the overlay probe's AX read moves; its decision half and its apply half
        // stay on this thread, on either side of the hop. nil means no read is needed —
        // the cached overlay state is already the answer.
        let probe = OverlayAppDetector.shared.beginProbe()

        // hasCaret is one AX round-trip that only the host's toolbar reads. XKeyIM wires
        // no toolbar callback, so it does not pay for it.
        let needsCaret = onCheckToolbarForFocusedElement != nil

        axPassQueue.async { [weak self] in
            let focusedInfo: AppBehaviorDetector.FocusedElementInfo
            let hasFocusedElement: Bool
            if let element = pass.element ?? AXHelper.getFocusedElement() {
                focusedInfo = .from(element, appElement: appElement)
                hasFocusedElement = true
            } else {
                focusedInfo = .withoutFocusedElement(appElement: appElement)
                hasFocusedElement = false
            }
            focusedInfo.materialise(bundleId: bundleId, includingCaret: needsCaret)
            let probedOverlayName = probe == nil ? nil : OverlayAppDetector.shared.readOverlayNameViaAX()

            DispatchQueue.main.async {
                // Ahead of every guard below, `guard let self` included, because
                // beginProbe() has already spent state this read cannot be separated
                // from: an expired probe was disarmed there and this token IS the one
                // find-only last-chance check that replaces it. Dropping the finish would
                // throw the read away with the probe left disarmed, and "Cmd+Space →
                // pause > timeout → first keystroke" would stop detecting the overlay
                // until the next arming signal — which ordinary typing never produces.
                // Safe out here: finishProbe is main-thread bookkeeping on a singleton,
                // it reads nothing on this source and nothing in it depends on the pass
                // generation. Applying it while ownership has flipped is the same call
                // setupOverlayDetectorCallback already documents as deliberately ungated,
                // and the only AX work it can start goes back through scheduleAXPass,
                // which is gated. After stop() it can reach no host callback at all —
                // stop() clears onOverlayVisibilityChanged.
                // Read freshness BEFORE finishProbe. finishProbe can fire
                // onOverlayVisibilityChanged, which reaches refreshInjectionMethodForOverlay
                // and schedules a new pass, bumping the generation — so checking after it
                // would make an overlay transition drop this pass's own apply, losing the
                // focus-change bookkeeping (signature, notifyFocusChanged, title
                // verification, toolbar) and onEvaluateSecureInput. The replacement pass
                // only redoes the injection-method detection, not the rest.
                let isCurrent = self?.axPassGeneration == pass.generation

                if let probe = probe {
                    OverlayAppDetector.shared.finishProbe(probe, overlayName: probedOverlayName)
                }

                guard let self = self else { return }
                self.axPassInFlight = false
                defer { self.runPendingAXPass() }

                // Dropped rather than applied once a newer pass has been scheduled —
                // including by stop(), which bumps the generation for exactly this
                // reason, so nothing in flight can land on a source that has been torn
                // down or on a host that has already yielded.
                guard isCurrent else { return }

                // Ownership can flip while a pass is in flight.
                guard self.isActiveHost() else { return }

                pass.apply(self, AXSnapshot(focusedInfo: focusedInfo,
                                            hasFocusedElement: hasFocusedElement,
                                            overlayName: OverlayAppDetector.shared.lastKnownOverlayName))
            }
        }
    }

    /// Run the pass that was coalesced while another was in flight, if any.
    /// Main thread only. A pass applied from `apply` may itself schedule one, so this
    /// must not start a second pass while that one is running.
    private func runPendingAXPass() {
        guard !axPassInFlight, let pass = pendingAXPass else { return }
        pendingAXPass = nil
        // Re-checked for the same reason scheduleAXPass checks it: this pass was
        // scheduled a whole AX round-trip ago, and its reads are worth nothing if
        // another process has taken the keystroke path since.
        guard isActiveHost() else { return }
        runAXPass(pass)
    }

    // MARK: - Focus Change Monitoring

    /// Setup monitoring for focus changes to auto-show toolbar when focusing text fields
    private func setupFocusChangeMonitoring() {
        // Use NSWorkspace notification to detect app activation
        // Then check if focused element is a text field
        focusCheckObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFocusCheck()
        }

        // Mouse clicks are already handled by mouseClickMonitor
        // Focus changes within apps are handled by AXObserver (event-driven, no polling)

        // Setup AXObserver for the current frontmost app on launch
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            setupAXObserverForApp(frontApp)
        }

        onLogEvent?("Focus change monitoring enabled (AXObserver + NSWorkspace notifications)")
    }

    /// Main focus check handler - schedules one AX pass and lets applyFocusCheck feed
    /// both processors from it, so the focused element and its attributes are read once,
    /// off the main thread.
    func handleFocusCheck() {
        // Skip the whole AX pass while another process owns the keystroke path
        // (Task 9b). Gating the function covers all of its callers — the NSWorkspace
        // observer, the mouse-click monitor, and AppDelegate's forwarder.
        guard isActiveHost() else { return }

        // Ownership can come back WITHOUT an app switch — the user selects a different
        // input source while staying in the same window. The self-healing teardown in
        // handleAXFocusChanged/handleAXTitleChanged has already removed the observer by
        // then, and the only two places that install one are the app-switch block and
        // start(), so nothing would re-arm it: this process would miss every intra-app
        // focus change (Cmd+T, Tab between fields) and keep injecting with the method
        // confirmed for the previous field until the next app switch or mouse click.
        // setupAXObserverForApp is already a no-op when an observer for that PID is
        // installed, and it never calls back into this function.
        // Skipped for an app whose install already failed: this path runs on every
        // mouse-up and every activation, and re-attempting against an AX server that is
        // slow or refusing costs up to the AX messaging timeout every time. The
        // app-switch block still retries that app — the cadence a failed install had
        // before this re-arm existed.
        if focusObserver == nil, let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier != focusObserverFailedPID {
            setupAXObserverForApp(frontApp)
        }

        // The focused element and its attributes are read on axPassQueue; applyFocusCheck
        // takes it from there.
        scheduleAXPass(element: nil) { source, snapshot in
            source.applyFocusCheck(snapshot)
        }
    }

    /// Main-thread stage of the focus check.
    private func applyFocusCheck(_ snapshot: AXSnapshot) {
        guard snapshot.hasFocusedElement else {
            // No focused element - hide toolbar if visible
            onNoFocusedElement?()
            return
        }

        let elementInfo = snapshot.focusedInfo

        // 1. ALWAYS check for injection method changes (CMD+T, Tab, etc.)
        checkIntraAppFocusChange(with: elementInfo, overlayName: snapshot.overlayName)

        // 2. Check toolbar display (only if enabled)
        if SharedSettings.shared.tempOffToolbarEnabled {
            onCheckToolbarForFocusedElement?(elementInfo)
        }
    }

    // MARK: - Intra-App Focus Monitoring

    /// Check if focused element has changed within the same app (e.g., CMD+T in browser)
    /// If so, re-detect injection method (but DO NOT reset engine - that's handled by user actions)
    /// Also re-primes cache when confirmedInjectionMethod was cleared (e.g., after mouse click)
    /// - Parameters:
    ///   - elementInfo: Cached AX element info (passed from handleFocusCheck)
    ///   - overlayName: overlay launcher name the same pass resolved, so re-detection
    ///     does not run the overlay probe again on this thread
    private func checkIntraAppFocusChange(with elementInfo: FocusedElementInfo, overlayName: String?) {
        // OPTIMIZED: Use pre-computed signature from FocusedElementInfo
        let currentSignature = elementInfo.signature
        let detector = AppBehaviorDetector.shared

        // Check if signature changed (different element type)
        if currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty {

            // Re-detect injection method (needed for address bar, terminal, etc.)
            let previousMethod = detector.confirmedInjectionMethod
            let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo,
                                                              resolvedOverlayName: .some(overlayName))

            // Log focus change
            onLogEvent?("Focus changed (keyboard): \(lastFocusedElementSignature) → \(currentSignature)")

            // ALWAYS set confirmed method to ensure cache is populated
            detector.setConfirmedInjectionMethod(injectionInfo)

            // Log injection method change
            if let prev = previousMethod, (prev.method != injectionInfo.method || prev.description != injectionInfo.description) {
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                let emptyCharStr = injectionInfo.needsEmptyCharPrefix ? ", emptyCharPrefix=true" : ""
                onLogEvent?("   Injection: \(prev.description) → \(injectionInfo.description) [\(textMethodName)\(emptyCharStr)]")
            }

            // NOTE: Engine reset is NOT done here!
            // Engine reset is handled by explicit user actions:
            // - Mouse click (setupMouseClickMonitor)
            // - Tab key (KeyboardEventHandler.processKeyEvent)
            // - Arrow keys / Home / End / PageUp / PageDown (KeyboardEventHandler.processKeyEvent)
            // - App switch (handleAppSwitch)
            //
            // Focus change detection is ONLY for re-detecting injection method.
            // This avoids issues where apps "refine" focus after user starts typing
            // (e.g., VSCode: AXWindow → AXTextArea, Facebook: dropdown menus).

            // NEW: Notify engine about focus change during typing
            // This is important for suggestion popup scenarios where keystrokes may go to popup
            // causing buffer desync. Engine will use AX verify at next word break.
            handler.engine.notifyFocusChanged()
        } else if detector.confirmedInjectionMethod == nil {
            // Cache was cleared (e.g., by mouse click resetWithCursorMoved)
            // but signature is unchanged (same field).
            // Re-prime cache to avoid live AX detection on every keystroke.
            let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo,
                                                              resolvedOverlayName: .some(overlayName))
            detector.setConfirmedInjectionMethod(injectionInfo)
        }

        // Update last signature
        lastFocusedElementSignature = currentSignature
    }

    // MARK: - AXObserver for Focus Changes

    /// Setup AXObserver for the given app to receive focus change notifications
    /// This is called when app switches to monitor focus changes within that app (e.g., Cmd+T in browser)
    private func setupAXObserverForApp(_ app: NSRunningApplication) {
        // Focus/title notifications only feed THIS process's tap, so install nothing
        // while another process owns the keystroke path (Task 9b).
        guard isActiveHost() else { return }

        // Skip if it's XKey itself
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let pid = app.processIdentifier

        // Skip if already observing this app
        guard pid != focusObserverPID else { return }

        // Remove existing observer if any
        removeAXObserver()

        // Create new observer for this app
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axNotificationCallback, &observer)

        guard result == .success, let newObserver = observer else {
            focusObserverFailedPID = pid
            onLogEvent?("AXObserver: Failed to create for PID \(pid) (error: \(result.rawValue))")
            return
        }

        // Get the app's AXUIElement
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Register for focused UI element changed notification
        let addResult = AXObserverAddNotification(
            newObserver,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )

        guard addResult == .success else {
            focusObserverFailedPID = pid
            onLogEvent?("AXObserver: Failed to add focus notification for PID \(pid) (error: \(addResult.rawValue))")
            return
        }

        // Register for window title changed notification (Layer 1)
        // Catches apps that update window title AFTER focus change (e.g., Slack channel switch)
        let titleResult = AXObserverAddNotification(
            newObserver,
            appElement,
            kAXTitleChangedNotification as CFString,
            refcon
        )

        if titleResult != .success {
            // Non-fatal: some apps may not support this notification
            // Layer 2 (delayed verification) will handle those cases
            onLogEvent?("AXObserver: Title notification not supported for PID \(pid)")
        }

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )

        // Save observer and PID
        focusObserver = newObserver
        focusObserverPID = pid
        focusObserverFailedPID = 0

        onLogEvent?("AXObserver: Monitoring '\(app.localizedName ?? "Unknown")' (PID: \(pid))")
    }

    /// Remove current AXObserver
    private func removeAXObserver() {
        // Cancel pending title verifications
        titleVerificationWorkItem?.cancel()
        titleVerificationWorkItem = nil
        titleChangeDebounceWorkItem?.cancel()
        titleChangeDebounceWorkItem = nil
        lastDetectedTitle = nil

        guard let observer = focusObserver else { return }

        // Remove from run loop
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        focusObserver = nil
        focusObserverPID = 0
    }

    /// Handle focus changed notification from AXObserver
    /// This is called by the C callback function
    /// Schedules the AX snapshot on axPassQueue and returns; applyAXFocusChange does the
    /// rest on the main thread. This is the stack the freeze was profiled in: the
    /// snapshot's AX round-trips used to run here, on the thread the CGEventTap callback
    /// also runs on, so every keystroke queued behind them.
    /// ALWAYS re-detects injection method (event-driven path, already throttled)
    /// to catch same-app context switches (tab/window) where signature stays the same
    /// but window title rules and injection method may change.
    func handleAXFocusChanged(_ element: AXUIElement) {
        guard isActiveHost() else {
            // Ownership flipped while this observer was live. Tear it down here rather
            // than waiting for an app switch that may never come — otherwise every focus
            // and title change keeps running a full AX pass from a process whose tap is
            // already yielding. See Task 9b fix round 1.
            removeAXObserver()
            return
        }

        // Throttle: skip if called less than 100ms after the last focus-change pass was
        // APPLIED. AXObserver can fire many times per second during autocomplete,
        // animations or rapid UI updates. lastAXFocusChangeTime is written in
        // applyAXFocusChange and nowhere else, so a pass that was superseded, or dropped
        // by stop() or by an ownership flip, never moves it: the window is measured from
        // the last re-detection that actually landed, not from the last read that ran.
        // Bursts arriving while a pass is in flight are coalesced by scheduleAXPass
        // instead.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAXFocusChangeTime > axFocusChangeThrottleInterval else {
            return
        }

        scheduleAXPass(element: element) { source, snapshot in
            source.applyAXFocusChange(element: element, snapshot: snapshot)
        }
    }

    /// Main-thread stage of the focus-change pass: everything handleAXFocusChanged used
    /// to do after its AX snapshot, with the snapshot handed in already materialised.
    private func applyAXFocusChange(element: AXUIElement, snapshot: AXSnapshot) {
        // Assigned here rather than at schedule time, so the field says what it means:
        // when the last focus-change re-detection was applied. This is the only
        // assignment, so a pass that never reaches this line leaves the throttle window
        // open — see handleAXFocusChanged.
        lastAXFocusChangeTime = CFAbsoluteTimeGetCurrent()

        let elementInfo = snapshot.focusedInfo
        let currentSignature = elementInfo.signature
        let signatureChanged = currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty

        // ALWAYS re-detect injection method in event-driven path.
        // AXObserver fires indicate genuine focus changes (throttle handles spam).
        // This ensures same-app tab/window switches re-evaluate window title rules
        // even when AX role/subrole/description are identical.
        // Both AX inputs are pre-resolved — the snapshot's fields by the pass that
        // materialised them, the overlay name by that pass's probe — so re-detection is
        // pure logic here, with the one residual named in
        // FocusedElementInfo.materialise: a custom rule carrying AX patterns can still
        // resolve a DOM attribute during matching.
        let detector = AppBehaviorDetector.shared
        // Read cache BEFORE re-detection to compare correctly
        let previousMethod = detector.confirmedInjectionMethod
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo,
                                                          resolvedOverlayName: .some(snapshot.overlayName))

        // Log focus change (only when signature actually changed)
        if signatureChanged {
            onLogEvent?("Focus changed (AXObserver): \(lastFocusedElementSignature) → \(currentSignature)")
        }

        // ALWAYS set confirmed method to ensure cache is populated
        // (after mouse click clears cache, this re-populates it)
        detector.setConfirmedInjectionMethod(injectionInfo)

        // Log injection method change
        if let prev = previousMethod, (prev.method != injectionInfo.method || prev.description != injectionInfo.description) {
            let axWindowTitle = elementInfo.windowTitle ?? "(nil)"
            let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
            let emptyCharStr = injectionInfo.needsEmptyCharPrefix ? ", emptyCharPrefix=true" : ""
            onLogEvent?("   Injection: \(prev.description) → \(injectionInfo.description) [\(textMethodName)\(emptyCharStr)]")
            onLogEvent?("   Window: \(axWindowTitle)")
        }

        // Layer 2: Schedule delayed title verification
        // Apps like Slack update window title 200-500ms AFTER focus change notification.
        // The detection above may have used a STALE title → wrong rule applied.
        // This re-checks the title after a delay and re-detects if it changed.
        // Note: windowTitle was resolved by the AX pass that produced this snapshot, so
        // reading it here costs nothing — it is not another cascade on this thread.
        lastDetectedTitle = elementInfo.windowTitle
        titleVerificationWorkItem?.cancel()
        let verifyWork = DispatchWorkItem { [weak self] in
            self?.performTitleChangeRedetection()
        }
        titleVerificationWorkItem = verifyWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: verifyWork)

        // NOTE: Engine reset is NOT done here!
        // See checkIntraAppFocusChange for explanation.

        // NEW: Notify engine about focus change during typing
        if signatureChanged {
            handler.engine.notifyFocusChanged()
        }

        // Update last signature (for timer-based checkIntraAppFocusChange)
        lastFocusedElementSignature = currentSignature

        // Focusing a password field enables Secure Input with no app switch — WebKit does
        // this in Safari and Chrome. This is the only trigger that catches it promptly.
        onEvaluateSecureInput?()

        // Check toolbar display (only if enabled)
        // This ensures toolbar shows/hides when focus changes via keyboard (CMD+T, Tab, etc.)
        let preferences = SharedSettings.shared.loadPreferences()
        let shouldShowTempOffToolbar = preferences.tempOffToolbarEnabled
        let shouldShowTranslationToolbar = preferences.translationEnabled && preferences.translationToolbarEnabled

        if shouldShowTempOffToolbar || shouldShowTranslationToolbar {
            // Reset lastFocusedElement to force toolbar re-evaluation
            onResetLastFocusedElement?()
            onCheckToolbarForFocusedElement?(elementInfo)
        } else {
            // Just update for tracking
            onUpdateLastFocusedElement?(element)
        }
    }

    // MARK: - Window Title Change Re-detection

    /// Handle window title changed notification from AXObserver (Layer 1)
    /// Apps like Slack fire this when switching channels/conversations
    /// Uses debounce to coalesce rapid-fire title updates
    func handleAXTitleChanged() {
        guard isActiveHost() else {
            // Same self-healing teardown as handleAXFocusChanged: whichever of the two
            // fires first after ownership moves away removes the observer, and
            // removeAXObserver() is idempotent so the other one is a no-op.
            removeAXObserver()
            return
        }

        // Guard: Only re-detect if we have a confirmed method (active context)
        guard AppBehaviorDetector.shared.confirmedInjectionMethod != nil else { return }

        // Debounce: Coalesce rapid title changes (e.g., "Loading..." → "vn-abc - Slack")
        // We want the FINAL title, not intermediate states
        titleChangeDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performTitleChangeRedetection()
        }
        titleChangeDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Re-detect injection method after window title changed
    /// Called by both Layer 1 (kAXTitleChangedNotification) and Layer 2 (delayed verification)
    /// Uses lastDetectedTitle guard to avoid duplicate work when both layers trigger
    private func performTitleChangeRedetection() {
        // Both the title query and the snapshot the re-detection needs run on
        // axPassQueue. Before, this took the title cascade AND — because it passed no
        // focusedInfo — a full fresh snapshot inside detectInjectionMethod, all on the
        // main thread.
        scheduleAXPass(element: nil) { source, snapshot in
            source.applyTitleChangeRedetection(snapshot)
        }
    }

    /// Main-thread stage of the title-change re-detection.
    private func applyTitleChangeRedetection(_ snapshot: AXSnapshot) {
        let detector = AppBehaviorDetector.shared

        // The title the pass resolved — the same cascade getCurrentWindowTitle() ran
        // here before, already paid for off this thread.
        let freshTitle = snapshot.focusedInfo.windowTitle ?? ""

        // Skip if title hasn't actually changed from last detection
        guard freshTitle != (lastDetectedTitle ?? "") else { return }

        // Title DID change — re-detect with fresh state
        lastDetectedTitle = freshTitle

        let previousMethod = detector.confirmedInjectionMethod
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: snapshot.focusedInfo,
                                                          resolvedOverlayName: .some(snapshot.overlayName))

        // Only update and log if detection result actually changed
        if previousMethod == nil ||
           injectionInfo.method != previousMethod!.method ||
           injectionInfo.description != previousMethod!.description {
            detector.setConfirmedInjectionMethod(injectionInfo)
            onLogEvent?("[TitleVerify] \"\(freshTitle.prefix(60))\"")
            onLogEvent?("   Injection: \(previousMethod?.description ?? "nil") → \(injectionInfo.description)")
        }
    }

    // MARK: - Mouse Click Monitoring

    private func setupMouseClickMonitor() {
        // Monitor mouse up events to detect focus changes
        // Using mouseUp instead of mouseDown to avoid triggering during drag operations
        // When user releases mouse, they have completed a click or drag selection

        // Global monitor - catches clicks in OTHER apps
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            // Gate the handler body, not the registration above: start()/stop() stay
            // symmetric, and ownership is re-read on every click (Task 9b).
            guard self?.isActiveHost() == true else { return }

            // Arm overlay probe — mouse clicks can dismiss overlays (Spotlight, Raycast, Alfred)
            OverlayAppDetector.shared.armProbe()

            // Reset engine when mouse is released (click completed or drag finished)
            // Mark as cursor moved to disable autocomplete fix (avoid deleting text on right)
            self?.handler.resetWithCursorMoved()

            // Log detailed input detection info (ONLY when debug window is visible)
            // This avoids expensive AX calls during normal usage
            // PERF: Skip when debug window is hidden to fix spring-loaded tools lag
            // Note: Overlay mid-sentence reset is handled by OverlayAppDetector's timer callback
            if self?.isDebugWindowVisible?() == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.logMouseClickInputDetection()
                }
            }

            // Reset lastFocusedElement to allow toolbar to re-show after auto-hide
            // When user clicks, they might be moving cursor within same field
            self?.onResetLastFocusedElement?()

            // Trigger toolbar check with slight delay to allow focus to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.handleFocusCheck()
            }
        }
    }

    /// Log detailed information about the input type when mouse is clicked
    /// Uses 3x retry detection with 0.15s interval to handle AX API timing issues
    /// This fixes false positive overlay detection when clicking another app while Spotlight is visible
    private func logMouseClickInputDetection() {
        // Start 3x retry detection to handle AX API timing issues
        // When user clicks, focused element may still report Spotlight (stale data)
        // After 300ms (0.15s x 2), AX API should have updated to the new focused element
        detectBehaviorWithRetry(attempt: 1, maxAttempts: 3, interval: 0.15)
    }

    /// Perform behavior detection with retry to handle AX API timing issues
    /// - Parameters:
    ///   - attempt: Current attempt number (1-based)
    ///   - maxAttempts: Maximum number of attempts
    ///   - interval: Time interval between attempts in seconds
    private func detectBehaviorWithRetry(attempt: Int, maxAttempts: Int, interval: TimeInterval) {
        let detector = AppBehaviorDetector.shared

        // OPTIMIZED: Query focusedInfo ONCE, pass to detectInjectionMethod
        let focusedInfo = detector.getFocusedElementInfo()

        // Detect injection method from current snapshot
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: focusedInfo)

        // IMMEDIATELY set confirmed injection method so keystrokes use this method
        // This applies the best available method at each retry attempt
        detector.setConfirmedInjectionMethod(injectionInfo)

        // Check if an overlay app is still visible (may be stale AX data after click)
        // Uses OverlayAppDetector which queries actual AX state, not bundle-cached detect()
        let isOverlayVisible = OverlayAppDetector.shared.isOverlayAppVisible()

        if attempt < maxAttempts && isOverlayVisible {
            // Overlay still visible - might be AX timing issue, retry after interval
            let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() ?? "overlay"
            if attempt == 1 {
                onLogEvent?("Mouse click detected (checking for AX timing...)")
            }
            onLogEvent?("   Attempt \(attempt): \(overlayName) → \(injectionInfo.method) (applying...)")

            // Schedule next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.detectBehaviorWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts, interval: interval)
            }
            return
        }

        // Final attempt OR no overlay - log the result
        // OPTIMIZED: Pass pre-queried data to avoid redundant AX queries in logging
        onLogMouseClickDetection?(attempt, attempt > 1, injectionInfo, focusedInfo)
    }

    // MARK: - Overlay Visibility

    /// Re-detect and confirm the injection method for an overlay open/close transition.
    ///
    /// Gated on ownership (Task 9b): this is a full AX snapshot, and while another
    /// process owns the keystroke path it only duplicates that process's round-trips —
    /// into the overlay (Spotlight/Raycast/Alfred), which is the exact path whose AX
    /// pressure this project already had to fix a freeze in once. scheduleAXPass applies
    /// that gate, on both sides of the hop, and `completion` simply never runs when it
    /// closes — so the caller skips the injection logging, exactly as it did when this
    /// returned nil, while still doing the non-AX work it owes.
    ///
    /// The snapshot itself is asynchronous now, which also settles the one-level
    /// re-entrancy this path had: the overlay visibility callback fires from
    /// OverlayAppDetector's probe on the main thread, and what it reaches here no longer
    /// takes a nested AX snapshot on that thread.
    private func refreshInjectionMethodForOverlay(completion: @escaping (InjectionMethodInfo) -> Void) {
        scheduleAXPass(element: nil) { source, snapshot in
            completion(source.confirmInjectionMethod(from: snapshot))
        }
    }

    /// Detect the injection method from a snapshot an AX pass already took, and confirm it.
    ///
    /// Main-thread stage of every pass that exists to answer "what method now?" — the app
    /// switch, the overlay transition, and the tap thread's own request below. The snapshot
    /// carries the focused element's attributes and the overlay name pre-resolved, so
    /// detectInjectionMethod makes no AX call of its own here.
    @discardableResult
    private func confirmInjectionMethod(from snapshot: AXSnapshot) -> InjectionMethodInfo {
        let detector = AppBehaviorDetector.shared
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: snapshot.focusedInfo,
                                                          resolvedOverlayName: .some(snapshot.overlayName))
        detector.setConfirmedInjectionMethod(injectionInfo)
        return injectionInfo
    }

    /// Run one injection-method detection off the tap thread, on the tap thread's request.
    ///
    /// AppBehaviorDetector answers the CGEventTap callback from its caches and cannot refill
    /// them itself; this is the refill. Two callers, both in AppBehaviorDetector:
    /// `requestInjectionMethodDetection()` when a cleared cache has left the tap on its
    /// fallbacks, and `armMethodReprobe()` after a focus-moving browser chord, which passes
    /// a delay so the snapshot is taken once the browser has moved focus.
    ///
    /// Always deferred, including at delay 0. `requestInjectionMethodDetection()` calls in
    /// from inside the CGEventTap callback, and running the pass inline there would put
    /// scheduleAXPass's prologue — NSWorkspace.shared.frontmostApplication,
    /// AXUIElementCreateApplication, OverlayAppDetector.beginProbe() — back on the
    /// keystroke, which is the whole point of the request being a request.
    private func scheduleInjectionMethodDetection(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runInjectionMethodDetection()
        }
    }

    private func runInjectionMethodDetection() {
        scheduleAXPass(element: nil) { source, snapshot in
            source.confirmInjectionMethod(from: snapshot)
        }
    }

    /// Resolve an armed overlay probe off the tap thread, and keep resolving it until the
    /// probe is spent.
    ///
    /// KeyboardEventHandler.isCurrentAppExcluded() reads OverlayAppDetector's cache and
    /// never probes, so nothing on the keystroke path runs the probe's AX read any more.
    /// This runs it instead, during the gap between the arming signal (Cmd+Space, Esc, a
    /// click) and the first character — typically 200ms or more.
    ///
    /// One read is not enough. The arming signal reaches the tap BEFORE the app that owns
    /// the overlay has processed the key, and an overlay takes 50-150ms to appear, so a
    /// single read fired at arm time can see nothing. That answer is not cached as a
    /// negative: a nil read against an empty cache leaves the probe armed (finishProbe's
    /// last branch), which is exactly the condition this chain retries on. It stops when
    /// beginProbe() hands out no token — an overlay was found, or one was dismissed — or
    /// when the probe has outlived its window twice: beginProbe expires it at 0.8s and
    /// hands out the find-only last-chance read the tap thread used to make when a probe
    /// expired under a keystroke, and the step below re-arms once on that read coming back
    /// empty, so a launcher still has a second window to appear in.
    ///
    /// Chained from the previous read's completion rather than fired on a timer, so a
    /// chase never has more than one read queued: axPassQueue is serial and shared with
    /// the full focus/title/app-switch passes, and a backlog of chase reads would delay
    /// those. Not a bound on the overlay reads in that queue overall — the detector's 0.5s
    /// dismissal poll is a second producer on it and goes nowhere near this chain, so one
    /// read of each kind can be waiting and a detection pass can sit behind two overlay
    /// reads rather than one.
    private func startOverlayChase() {
        // Every arming signal restarts the backoff, whether or not a chain is already
        // alive — see overlayChaseBackoff. The gaps are measured from the moment an
        // overlay may be opening, and inside one burst that moment is the last arm, the
        // chord, not the Cmd press that started the chain.
        overlayChaseBackoff = 0
        guard !overlayChaseActive else {
            // The live chain's next read may be sleeping out a gap the PREVIOUS arm sized,
            // and the restart above does not move that sleep. Take the read now instead.
            //
            // perform() runs the step on this thread, and the step clears
            // overlayChaseStepWorkItem before running, so the chain is neither doubled nor
            // left dead. cancel() comes after, and only so the asyncAfter delivery at the
            // original deadline finds a cancelled item and does not run the step a second
            // time. Nothing re-enters here in between: runOverlayChaseStep() only enqueues
            // its read, and everything that can re-arm a probe runs in that read's
            // completion.
            if let sleepingStep = overlayChaseStepWorkItem {
                sleepingStep.perform()
                sleepingStep.cancel()
            }
            return
        }
        runOverlayChaseStep(rearmed: false)
    }

    private func runOverlayChaseStep(rearmed: Bool) {
        // isRunning, not a cancelled work item, is what ends a chain across stop(): a step
        // that wakes after stop() ends the chain, and one that wakes after a stop()/start()
        // pair simply carries on as the single live chain.
        guard isRunning, isActiveHost(),
              let probe = OverlayAppDetector.shared.beginProbe() else {
            overlayChaseActive = false
            return
        }
        overlayChaseActive = true

        axPassQueue.async { [weak self] in
            let overlayName = OverlayAppDetector.shared.readOverlayNameViaAX()

            DispatchQueue.main.async {
                // Ahead of `guard let self`, for the reason runAXPass spells out: beginProbe()
                // already spent probe state this read cannot be separated from.
                OverlayAppDetector.shared.finishProbe(probe, overlayName: overlayName)

                guard let self = self else { return }

                // Taken before the re-arm below, which re-enters startOverlayChase() and
                // restarts the backoff there. That restart is for a NEW arming signal, and
                // the chain re-arming its own probe is not one: restarting on it would
                // spend the second window's budget on a burst of reads at that window's
                // start, where a launcher still cold-starting is no likelier to be found
                // than anywhere else in it.
                let backoff = self.overlayChaseBackoff

                // The read that beginProbe() marked `expired` is the probe's find-only
                // last chance, and it has just come back empty against an empty cache: the
                // launcher the arming signal was about did not appear inside the window.
                // Re-arm once and keep chasing, because nothing else would ever look
                // again — the keystroke path reads the cache and never probes, ordinary
                // characters arm nothing, and the 0.5s monitor returns on
                // `guard wasOverlayVisible`. A launcher that cold-starts past 0.8s
                // (Raycast or Alfred on first launch, Spotlight on a loaded machine) would
                // otherwise take the user's first character on the underlying app's
                // injection method and scramble it against inline autocomplete.
                //
                // Once, not until it finds something: two windows are ~1.6s, which covers
                // a cold start, and a chase that keeps re-arming would never end — every
                // Cmd+C would leave one reading AX forever.
                var rearmed = rearmed
                if self.isRunning, !rearmed, probe.expired, overlayName == nil,
                   !OverlayAppDetector.shared.lastKnownOverlayVisible {
                    // Re-entrant into startOverlayChase through onProbeArmed:
                    // overlayChaseActive is this chain's and still set, so no second chain
                    // starts, and the backoff restart it makes there is undone by the
                    // write below, which carries `backoff` forward. Nor is there a
                    // sleeping step for it to take early — this chain's next one is not
                    // scheduled until the end of this completion.
                    OverlayAppDetector.shared.armProbe()
                    rearmed = true
                }

                guard OverlayAppDetector.shared.isProbeArmed else {
                    self.overlayChaseActive = false
                    return
                }
                let delay = Self.overlayChaseDelays[backoff]
                self.overlayChaseBackoff = min(backoff + 1, Self.overlayChaseDelays.count - 1)
                let step = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    // Cleared before the step runs, not after: from here on the read is in
                    // flight, and an arming signal that arrives during it has nothing to
                    // take early — the sleep it would have shortened does not exist yet.
                    self.overlayChaseStepWorkItem = nil
                    self.runOverlayChaseStep(rearmed: rearmed)
                }
                self.overlayChaseStepWorkItem = step
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
            }
        }
    }

    /// Setup callback for overlay visibility changes
    private func setupOverlayDetectorCallback() {
        OverlayAppDetector.shared.onProbeArmed = { [weak self] in
            self?.startOverlayChase()
        }

        // The detector's 0.5s dismissal poll, moved off this run loop. Captures the queue
        // rather than the source: the completion is what clears the detector's in-flight
        // flag, so a released source must not be able to swallow it and leave the poll
        // permanently blocked. stop() clears the callback, which is what ends this.
        let axPassQueue = self.axPassQueue
        OverlayAppDetector.shared.onOverlayReadNeeded = { completion in
            axPassQueue.async {
                let overlayName = OverlayAppDetector.shared.readOverlayNameViaAX()
                DispatchQueue.main.async { completion(overlayName) }
            }
        }

        OverlayAppDetector.shared.onOverlayVisibilityChanged = { [weak self] isVisible, overlayName in
            guard let self = self else { return }

            // Only the AX snapshot is gated. Everything below stays ungated for the same
            // reason onSmartSwitch does in the app-switch block: the overlay Smart Switch
            // callbacks write the shared language state the owning process reads back,
            // and the engine bookkeeping is this process's own state, not an AX query.
            // The snapshot now completes after them rather than before, so its injection
            // line lands after the transition's other log lines instead of between them.
            let transition = isVisible ? "opened" : "closed"
            self.refreshInjectionMethodForOverlay { [weak self] injectionInfo in
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                self?.onLogEvent?("Overlay \(transition) — Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
            }

            if isVisible {
                // When overlay opens (hidden → visible):
                // 1. Detect and set injection method for overlay (Spotlight/Raycast/Alfred)
                // 2. Apply Smart Switch for overlay (restore saved language)
                // 3. Reset mid-sentence flag (overlay apps start with empty/fresh input)
                self.onLogEvent?("Overlay opened - checking overlay rules")
                self.onEnableVietnameseForOverlay?()

                // CRITICAL FIX: When overlay opens (e.g., CMD+Space for Spotlight),
                // reset mid-sentence flag. The resetForAppSwitch() called earlier sets isTypingMidSentence=true
                // to protect text in normal apps, but overlay apps always start fresh.
                // If user clicks into existing text, mouse click handler will set mid-sentence appropriately.
                self.handler.resetMidSentenceFlag()
                let name = overlayName ?? "Overlay"
                self.onLogEvent?("'\(name)' opened → reset mid-sentence flag")
            } else {
                // When overlay closes (visible → hidden):
                // 1. Detect and set injection method for the underlying app
                // 2. Save overlay's language (using overlayName from callback, cache is already cleared)
                // 3. Restore language for current app
                // 4. Set mid-sentence flag (protect text in underlying app)
                self.onLogEvent?("Overlay closed - saving overlay state, restoring underlying app language")
                // Save overlay's language BEFORE restoring underlying app
                // Use overlayName from callback parameter (cache is already cleared at this point)
                self.onSaveLanguageForOverlay?(overlayName)
                self.onRestoreLanguageForCurrentApp?()

                // When overlay closes, user returns to previous app where cursor position is unknown.
                // Set mid-sentence flag to protect text on the right of cursor.
                // Note: Overlay close doesn't trigger didActivateApplicationNotification since
                // frontmost app is still the original app (Spotlight runs as overlay, not frontmost).
                self.handler.resetWithCursorMoved()
                self.onLogEvent?("Overlay closed → set mid-sentence flag (protect underlying app)")
            }
        }
    }
}
