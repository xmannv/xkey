//
//  OverlayAppDetector.swift
//  XKey
//
//  Detects overlay apps (Spotlight, Raycast, Alfred) that don't trigger
//  standard workspace notifications and appear over the current app.
//
//  This helps Smart Switch avoid overwriting the underlying app's language
//  preference when user toggles language while an overlay is active.
//
//  Detection method:
//  - AX Attributes: Check focused element's Title/Subrole/Identifier/Placeholder
//    This is the most accurate method as it only detects when the overlay is focused
//

import Cocoa
import ApplicationServices
import ObjectiveC

/// Detects overlay/panel apps that appear over the current application
class OverlayAppDetector {

    // MARK: - Singleton

    static let shared = OverlayAppDetector()

    // MARK: - State Tracking

    /// Callback when overlay visibility changes
    /// Parameters: (isVisible: Bool, overlayName: String?) - overlayName is provided on close for Smart Switch
    var onOverlayVisibilityChanged: ((Bool, String?) -> Void)?

    /// Called on the main thread every time a probe is armed, so the host can run the
    /// probe's AX read somewhere other than the thread that armed it.
    ///
    /// Wired the same way `onOverlayVisibilityChanged` is — TapEventSource.start() sets
    /// it, stop() clears it — because this class owns no queue of its own and must not
    /// grow one: the serial queue, the generation counter and the coalescer all live in
    /// TapEventSource.
    ///
    /// Left nil, nothing breaks and nothing is silently wrong: an armed probe is then
    /// resolved by whichever AX pass runs next (app switch, focus change, title change,
    /// mouse click all take a token through beginProbe), exactly as it was before this
    /// callback existed. What is lost is the one case with no such pass — an overlay
    /// opened by a keyboard shortcut, where nothing else is happening — which is the
    /// case this exists for.
    var onProbeArmed: (() -> Void)?

    /// Called on the main thread when the 0.5s monitor below needs one overlay read taken
    /// somewhere other than the thread it fires on, with the completion that hands the
    /// result back — on the main thread, where every write this class makes belongs.
    ///
    /// Wired like `onProbeArmed`, for the same reason: the queue lives in TapEventSource
    /// and this class must not grow one. The read is `readOverlayNameViaAX()`, which is
    /// the half of the probe split that touches no state.
    ///
    /// Left nil the monitor reads on the thread the timer fires on, exactly as it did
    /// before this existed. That is the fallback for a detector with no host running
    /// (before start(), after stop()), not a mode: on the host's run loop it is up to five
    /// blocking AX round-trips every 0.5s on the thread the CGEventTap callback also runs
    /// on, while the user is typing into the launcher.
    ///
    /// Deliberately not gated on tap ownership, unlike the passes in TapEventSource: the
    /// only answer a skipped read could report is "nothing found", which is a dismissal.
    var onOverlayReadNeeded: ((@escaping (String?) -> Void) -> Void)?

    /// Previous overlay visibility state (for change detection)
    private var wasOverlayVisible = false

    /// Timer for monitoring overlay state changes
    private var monitorTimer: Timer?
    
    /// Last detected overlay app name (for logging)
    private var lastDetectedOverlay: String?
    
    /// Cached overlay state (updated by probe and timer)
    private var cachedOverlayVisible = false
    private var cachedOverlayName: String?

    /// True while the monitor's read is outstanding. Main thread only.
    ///
    /// The timer keeps firing every 0.5s, and one read against a degraded AX server takes
    /// longer than that, so without this the timer would stack reads onto the shared queue.
    private var dismissCheckInFlight = false

    /// Bumped every time a probe turns the cache positive. Main thread only.
    ///
    /// The monitor's read captures it and drops its own nil if it changed while the read
    /// was in flight: a find that landed after the read started is newer than the read, and
    /// dismissing on it would run the whole "overlay closed" sequence with the overlay
    /// still open. Same hazard `PendingProbe.cachedVisibleAtBegin` covers on the probe
    /// path, which cannot cover this one — the cache is already positive when the monitor
    /// takes its read, so there is no change of cached visibility to notice.
    private var overlayFindGeneration: UInt64 = 0
    
    // MARK: - Event-Driven Probe State
    
    /// Whether an AX probe is needed on next isOverlayAppVisible() call
    /// Armed by external signals (modifier keys, Esc, mouse clicks)
    private var probeNeeded = false
    
    /// Deadline after which the probe auto-disarms (safety net)
    private var probeDeadline: CFAbsoluteTime = 0
    
    /// A probe that `beginProbe()` decided needs an AX read, carried to `finishProbe`.
    /// Holds the two things the read cannot re-derive afterwards: whether the probe had
    /// already outlived its window when the decision was taken, which is what makes the
    /// read a find-only last chance that must never dismiss, and the cached visibility
    /// the decision was taken against, which is what tells `finishProbe` whether a nil
    /// read still describes the state it was asked about.
    struct PendingProbe {
        let expired: Bool

        /// `cachedOverlayVisible` as it was when `beginProbe()` ran.
        ///
        /// Always equal to the current value on the unsplit path — `isOverlayAppVisible()`
        /// runs all three halves in one main-thread turn. It differs only when the read
        /// happened on another thread (`TapEventSource.runAXPass`) and someone found an
        /// overlay while it was in flight.
        let cachedVisibleAtBegin: Bool
    }

    /// Window during which an armed probe runs a full AX check on every
    /// consumer call (and may dismiss on a nil read). Past the deadline the
    /// probe degrades to a single find-only last-chance check, then disarms —
    /// it does NOT silently disarm, or an overlay opened right before a pause
    /// would stay undetected (see isOverlayAppVisible).
    ///
    /// That last-chance check is no longer a keystroke's: nothing on the keystroke path
    /// probes any more, so whoever answers `onProbeArmed` spends it, and this window is
    /// only as good as what that host does when the check comes back empty. A launcher
    /// that takes longer than this to appear is not covered by the window at all —
    /// TapEventSource's chase re-arms once for exactly that case.
    private static let probeTimeout: CFAbsoluteTime = 0.8

    private init() {
        // Start monitoring overlay state changes
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }
    
    // MARK: - AX Attribute Patterns for Detection
    
    /// Patterns to match in AX Title attribute
    private static let axTitlePatterns: [String] = [
        "Alfred Search Field",      // Alfred
    ]
    
    /// Patterns to match in AX Subrole attribute
    private static let axSubrolePatterns: [String] = [
        "raycast_searchField",      // Raycast
    ]
    
    /// Patterns to match in AX Placeholder attribute
    private static let axPlaceholderPatterns: [String] = [
        "Spotlight Search",         // Spotlight
    ]
    
    // MARK: - Overlay Name to Bundle ID Mapping

    /// Map overlay app name to bundle ID (single source of truth)
    static func bundleId(forOverlayName name: String) -> String? {
        switch name {
        case "Spotlight": return "com.apple.Spotlight"
        case "Raycast": return "com.raycast.macos"
        case "Alfred": return "com.runningwithcrayons.Alfred"
        default: return nil
        }
    }

    // MARK: - Probe Arming (called from EventTapManager / AppDelegate)

    /// Arm a probe immediately.
    /// Use for OPEN signals: modifier keys, Cmd+keyDown — overlay may appear
    /// before the next keyDown arrives.
    func armProbe() {
        probeNeeded = true
        probeDeadline = CFAbsoluteTimeGetCurrent() + Self.probeTimeout
        onProbeArmed?()
    }

    /// Arm a probe with a short delay for CLOSE signals (Esc, Return).
    /// CGEventTap intercepts the key BEFORE the target app processes it,
    /// so an immediate probe would still see the overlay as focused.
    /// The 50ms delay lets the overlay process the key and close first.
    func armProbeDeferred() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.armProbe()
        }
    }

    /// Whether a probe is still waiting for an AX read to resolve it.
    ///
    /// True from `armProbe()` until something spends the probe: a find, a dismissal, or
    /// `beginProbe()` expiring it past `probeTimeout`. The off-thread reader retries while
    /// this is true, because an overlay that has not appeared yet leaves the probe armed
    /// (see finishProbe's "cache=false + AX nil" branch).
    var isProbeArmed: Bool {
        return probeNeeded
    }

    // MARK: - Primary Detection Method

    /// Check if any overlay app is currently active
    /// Uses event-driven probing for both zero detection gap AND O(1) steady-state:
    /// - No probe → return cached value immediately (O(1))
    /// - Probe armed → do fresh AX check, update cache both directions
    ///
    /// Probes are armed by external signals (modifier keys, Esc, mouse clicks)
    /// that indicate overlay state MAY have just changed.
    ///
    /// Split into three parts — beginProbe / readOverlayNameViaAX / finishProbe — so a
    /// caller that must not block can run the AX read on another thread. This function
    /// is the unsplit form and behaves exactly as it always did.
    func isOverlayAppVisible() -> Bool {
        guard let probe = beginProbe() else { return cachedOverlayVisible }
        return finishProbe(probe, overlayName: readOverlayNameViaAX())
    }

    /// The main-thread half of a probe that runs BEFORE the AX read: decides whether a
    /// read is needed at all, and expires an overdue probe.
    ///
    /// Returns nil when no AX read should happen — the cached state is the answer.
    /// Otherwise returns a token the caller must hand back to `finishProbe` together
    /// with what the read found.
    ///
    /// Mutates probe state (the expiry disarm), so it stays on the main thread with
    /// every other consumer of that state.
    func beginProbe() -> PendingProbe? {
        guard probeNeeded else { return nil }

        let expired = CFAbsoluteTimeGetCurrent() > probeDeadline
        if expired {
            // Probe outlived its window — disarm, then run ONE last-chance
            // find-only check. Covers "Cmd+Space → pause > timeout →
            // first keystroke": without it the overlay stays undetected
            // (stuck on the previous injection method) until the next arm
            // signal.
            probeNeeded = false
            // Skip the AX query when the cache is already positive: the
            // expired path never dismisses (see finishProbe), so the query could
            // not change any state — it would be pure keystroke latency.
            if cachedOverlayVisible { return nil }
        }
        return PendingProbe(expired: expired, cachedVisibleAtBegin: cachedOverlayVisible)
    }

    /// The AX read half of a probe. Reads attributes and nothing else: no cache, no
    /// probe state, no callback — which is what makes it safe to call from any thread.
    func readOverlayNameViaAX() -> String? {
        return detectOverlayViaAXAttributes()
    }

    /// The main-thread half of a probe that runs AFTER the AX read: applies the result
    /// to the cache, disarms, and fires `onOverlayVisibilityChanged` on a transition.
    ///
    /// Every state write and every callback of the probe lives here, so the read that
    /// precedes it is free to have happened on another thread.
    /// - Parameters:
    ///   - probe: the token `beginProbe()` returned
    ///   - overlayName: what `readOverlayNameViaAX()` found, or nil
    /// - Returns: whether an overlay is visible after applying the result
    @discardableResult
    func finishProbe(_ probe: PendingProbe, overlayName: String?) -> Bool {
        if let overlayName = overlayName {
            return handleOverlayFound(overlayName, finalCheck: probe.expired)
        }
        if probe.expired {
            // Nil read at expiry: keep cached state untouched. Dismissal of
            // a visible overlay is the monitor timer's job (0.5s poll) —
            // acting on a stale-probe nil could false-dismiss on a transient
            // AX failure. (The fresh path below MAY dismiss: it runs right
            // after an explicit close signal — Esc/Return/click — where a
            // nil read is expected and meaningful.)
            return cachedOverlayVisible
        }
        // Probe armed and fresh — nil read may mean a real dismissal
        if cachedOverlayVisible {
            // …unless the cache turned positive while this read was in flight. That can
            // only happen when the read ran off the main thread (TapEventSource.runAXPass,
            // ~200ms while the target app's AX server is degraded): the overlay appeared
            // after the read started, another consumer's probe found it, and this nil is
            // simply older than that find. Dismissing on it would run the whole "overlay
            // closed" sequence with the overlay still open — save/restore language, the
            // mid-sentence reset, and injection dropping off .axDirect — and nothing
            // would heal it: checkOverlayStateChange() returns immediately once
            // wasOverlayVisible is false, and probes are armed only by modifier keys, Esc
            // and mouse-up, never by ordinary typing, so a user still typing in the
            // overlay never re-arms one.
            guard probe.cachedVisibleAtBegin else { return true }

            // Was visible, now gone — clear cache, disarm
            // Fixes stale-positive: no more waiting for timer poll
            let closingOverlayName = cachedOverlayName  // Capture before clearing
            cachedOverlayVisible = false
            cachedOverlayName = nil
            lastDetectedOverlay = nil
            probeNeeded = false
            logDebug("Overlay dismissed (probe)")

            if wasOverlayVisible {
                wasOverlayVisible = false
                onOverlayVisibilityChanged?(false, closingOverlayName)
            }
            return false
        }
        // cache=false + AX nil → overlay hasn't appeared yet
        // Keep probe armed — it might appear on next keyDown
        return false
    }

    /// Handle a positive overlay detection from a probe: update cache, disarm, notify.
    private func handleOverlayFound(_ overlayName: String, finalCheck: Bool) -> Bool {
        lastDetectedOverlay = overlayName
        cachedOverlayVisible = true
        cachedOverlayName = overlayName
        probeNeeded = false
        overlayFindGeneration &+= 1
        logDebug("found (probe\(finalCheck ? ", final check" : "")): '\(overlayName)'")

        if !wasOverlayVisible {
            wasOverlayVisible = true
            onOverlayVisibilityChanged?(true, overlayName)
        }
        return true
    }
    
    /// Get the name of the currently visible overlay app, if any
    /// Probe-aware: triggers AX check when probe is armed, ensuring
    /// consumers that only read overlay name still detect new overlays.
    /// When no probe is pending, returns cached value (O(0)).
    func getVisibleOverlayAppName() -> String? {
        if probeNeeded {
            // Delegate to probe-aware check to update cache
            _ = isOverlayAppVisible()
        }
        return cachedOverlayName
    }

    /// The cached overlay name with no probe of any kind — never an AX call.
    /// For callers that have already run the probe's three halves themselves and only
    /// want the name the last one settled on.
    var lastKnownOverlayName: String? {
        return cachedOverlayName
    }

    /// The cached overlay visibility with no probe of any kind — never an AX call.
    ///
    /// This is what the CGEventTap callback reads (KeyboardEventHandler.isCurrentAppExcluded):
    /// `isOverlayAppVisible()` would run the probe's AX read on the tap thread, which is
    /// the stall this split exists to remove. Kept fresh by whoever answers `onProbeArmed`.
    var lastKnownOverlayVisible: Bool {
        return cachedOverlayVisible
    }

    // MARK: - AX Attribute Detection

    /// Detect overlay app by checking focused element's AX attributes
    /// - Returns: Name of detected overlay app, or nil if not found
    private func detectOverlayViaAXAttributes() -> String? {
        guard let axElement = AXHelper.getFocusedElement() else {
            return nil
        }

        // Check AX Title
        if let title = AXHelper.getString(axElement, attribute: kAXTitleAttribute) {
            for pattern in Self.axTitlePatterns {
                if title.contains(pattern) {
                    return "Alfred"  // Alfred Search Field
                }
            }
        }

        // Check AX Subrole
        if let subrole = AXHelper.getString(axElement, attribute: kAXSubroleAttribute) {
            for pattern in Self.axSubrolePatterns {
                if subrole.contains(pattern) {
                    return "Raycast"  // raycast_searchField
                }
            }
        }

        // Check AX Identifier for Spotlight (most reliable - persists even when user types)
        if let identifier = AXHelper.getString(axElement, attribute: kAXIdentifierAttribute) {
            if identifier == "SpotlightSearchField" {
                return "Spotlight"
            }
        }
        
        // Check AX Placeholder (fallback for Spotlight - only visible when input is empty)
        if let placeholder = AXHelper.getString(axElement, attribute: kAXPlaceholderValueAttribute) {
            for pattern in Self.axPlaceholderPatterns {
                if placeholder.contains(pattern) {
                    return "Spotlight"  // Spotlight Search
                }
            }
        }

        return nil
    }



    // MARK: - Logging

    /// Log debug message
    private func logDebug(_ message: String) {
        DebugLogger.shared.info(message, source: "OverlayDetector")
    }

    // MARK: - Monitoring

    /// Start monitoring overlay state changes
    private func startMonitoring() {
        // Check every 0.5 seconds for overlay state changes
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkOverlayStateChange()
        }
    }

    /// Stop monitoring overlay state changes
    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Check if overlay state has changed and notify callback
    /// OPTIMIZED: Only performs AX polling when overlay was previously visible
    /// (need to detect dismissal). When steady-state (no overlay), this is O(0) — no AX calls.
    /// Overlay appearance is detected by event-driven probes (armProbe/armProbeDeferred),
    /// so the timer only needs to catch dismiss events not covered by Esc/Return/click.
    ///
    /// The read goes through `onOverlayReadNeeded` when a host has wired one: the timer
    /// fires on the run loop the CGEventTap callback runs on, and `guard wasOverlayVisible`
    /// only keeps it free at steady state — while a launcher IS open it is up to five
    /// blocking AX round-trips every 0.5s, during the moments the user is typing into that
    /// launcher.
    private func checkOverlayStateChange() {
        // OPTIMIZATION: Skip AX polling entirely when no overlay is visible
        // Overlay appearance is handled by event-driven probes (armProbe/armProbeDeferred)
        // Timer only needs to detect dismissal of currently-visible overlays
        guard wasOverlayVisible else {
            return
        }

        guard let readOffThread = onOverlayReadNeeded else {
            applyDismissCheck(overlayName: detectOverlayViaAXAttributes(),
                              findGenerationAtRead: overlayFindGeneration)
            return
        }

        guard !dismissCheckInFlight else { return }
        dismissCheckInFlight = true
        let findGenerationAtRead = overlayFindGeneration
        readOffThread { [weak self] overlayName in
            guard let self = self else { return }
            self.dismissCheckInFlight = false
            self.applyDismissCheck(overlayName: overlayName,
                                   findGenerationAtRead: findGenerationAtRead)
        }
    }

    /// Apply what the monitor's read found. Main thread, on both sides of the split.
    private func applyDismissCheck(overlayName: String?, findGenerationAtRead: UInt64) {
        // The state this read was taken against may be gone: a probe can dismiss the
        // overlay, or find a different one, while the read is in flight.
        guard wasOverlayVisible else { return }
        if overlayName == nil && findGenerationAtRead != overlayFindGeneration { return }

        let isCurrentlyVisible = overlayName != nil
        lastDetectedOverlay = overlayName

        // Capture overlay name before clearing cache (for Smart Switch save on close)
        let closingOverlayName = cachedOverlayName

        // Update cached state for hot path consumers (O(1) reads)
        cachedOverlayVisible = isCurrentlyVisible
        cachedOverlayName = overlayName

        // Detect state change (overlay dismissed)
        if !isCurrentlyVisible {
            logDebug("Overlay dismissed")
            wasOverlayVisible = false

            // Notify callback
            onOverlayVisibilityChanged?(false, closingOverlayName)
        }
    }

    // MARK: - Notes on Permissions

    // ℹ️ Screen Recording permission is NOT required for this feature!
    //
    // AX Attributes Detection:
    // - Uses Accessibility API to read focused element attributes
    // - Requires Accessibility permission (which XKey already needs)
    // - Only detects overlay when it's actually focused (not when process is running in background)
}
