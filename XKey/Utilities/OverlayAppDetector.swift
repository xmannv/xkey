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
    var onOverlayVisibilityChanged: ((Bool) -> Void)?

    /// Previous overlay visibility state (for change detection)
    private var wasOverlayVisible = false

    /// Timer for monitoring overlay state changes
    private var monitorTimer: Timer?
    
    /// Last detected overlay app name (for logging)
    private var lastDetectedOverlay: String?
    
    /// Cached overlay state (updated by probe and timer)
    private var cachedOverlayVisible = false
    private var cachedOverlayName: String?
    
    // MARK: - Event-Driven Probe State
    
    /// Whether an AX probe is needed on next isOverlayAppVisible() call
    /// Armed by external signals (modifier keys, Esc, mouse clicks)
    private var probeNeeded = false
    
    /// Deadline after which the probe auto-disarms (safety net)
    private var probeDeadline: CFAbsoluteTime = 0
    
    /// Duration to keep a probe armed before auto-disarming (seconds)
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
    
    // MARK: - Probe Arming (called from EventTapManager / AppDelegate)
    
    /// Arm a probe immediately for the next isOverlayAppVisible() call.
    /// Use for OPEN signals: modifier keys, Cmd+keyDown — overlay may appear
    /// before the next keyDown arrives.
    func armProbe() {
        probeNeeded = true
        probeDeadline = CFAbsoluteTimeGetCurrent() + Self.probeTimeout
    }
    
    /// Arm a probe with a short delay for CLOSE signals (Esc, Return).
    /// CGEventTap intercepts the key BEFORE the target app processes it,
    /// so an immediate probe would still see the overlay as focused.
    /// The 50ms delay lets the overlay process the key and close first.
    func armProbeDeferred() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.probeNeeded = true
            self.probeDeadline = CFAbsoluteTimeGetCurrent() + Self.probeTimeout
        }
    }

    // MARK: - Primary Detection Method

    /// Check if any overlay app is currently active
    /// Uses event-driven probing for both zero detection gap AND O(1) steady-state:
    /// - No probe → return cached value immediately (O(1))
    /// - Probe armed → do fresh AX check, update cache both directions
    ///
    /// Probes are armed by external signals (modifier keys, Esc, mouse clicks)
    /// that indicate overlay state MAY have just changed.
    func isOverlayAppVisible() -> Bool {
        if probeNeeded {
            let now = CFAbsoluteTimeGetCurrent()
            if now > probeDeadline {
                // Probe expired — safety net, disarm
                probeNeeded = false
            } else {
                // Execute AX probe
                if let overlayName = detectOverlayViaAXAttributes() {
                    // Overlay found — update cache, disarm
                    lastDetectedOverlay = overlayName
                    cachedOverlayVisible = true
                    cachedOverlayName = overlayName
                    probeNeeded = false
                    logDebug("found (probe): '\(overlayName)'")
                    
                    if !wasOverlayVisible {
                        wasOverlayVisible = true
                        onOverlayVisibilityChanged?(true)
                    }
                    return true
                } else if cachedOverlayVisible {
                    // Was visible, now gone — clear cache, disarm
                    // Fixes stale-positive: no more waiting for timer poll
                    cachedOverlayVisible = false
                    cachedOverlayName = nil
                    lastDetectedOverlay = nil
                    probeNeeded = false
                    logDebug("Overlay dismissed (probe)")
                    
                    if wasOverlayVisible {
                        wasOverlayVisible = false
                        onOverlayVisibilityChanged?(false)
                    }
                    return false
                }
                // cache=false + AX nil → overlay hasn't appeared yet
                // Keep probe armed — it might appear on next keyDown
                return false
            }
        }
        return cachedOverlayVisible
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
    private func checkOverlayStateChange() {
        // OPTIMIZATION: Skip AX polling entirely when no overlay is visible
        // Overlay appearance is handled by event-driven probes (armProbe/armProbeDeferred)
        // Timer only needs to detect dismissal of currently-visible overlays
        guard wasOverlayVisible else {
            return
        }
        
        let isCurrentlyVisible = isOverlayVisibleQuiet()
        
        // Update cached state for hot path consumers (O(1) reads)
        cachedOverlayVisible = isCurrentlyVisible
        cachedOverlayName = isCurrentlyVisible ? lastDetectedOverlay : nil

        // Detect state change (overlay dismissed)
        if !isCurrentlyVisible {
            logDebug("Overlay dismissed")
            wasOverlayVisible = false

            // Notify callback
            onOverlayVisibilityChanged?(false)
        }
    }

    /// Check overlay visibility without verbose logging (for polling)
    private func isOverlayVisibleQuiet() -> Bool {
        if let overlayName = detectOverlayViaAXAttributes() {
            lastDetectedOverlay = overlayName
            return true
        }
        
        lastDetectedOverlay = nil
        return false
    }

    // MARK: - Notes on Permissions

    // ℹ️ Screen Recording permission is NOT required for this feature!
    //
    // AX Attributes Detection:
    // - Uses Accessibility API to read focused element attributes
    // - Requires Accessibility permission (which XKey already needs)
    // - Only detects overlay when it's actually focused (not when process is running in background)
}
