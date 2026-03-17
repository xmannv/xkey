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
    /// - Returns: Name of the overlay app, or nil if none visible
    func getVisibleOverlayAppName() -> String? {
        return cachedOverlayName
    }

    // MARK: - AX Attribute Detection

    /// Detect overlay app by checking focused element's AX attributes
    /// - Returns: Name of detected overlay app, or nil if not found
    private func detectOverlayViaAXAttributes() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement

        // Check AX Title
        if let title = getAXStringAttribute(axElement, attribute: kAXTitleAttribute) {
            for pattern in Self.axTitlePatterns {
                if title.contains(pattern) {
                    return "Alfred"  // Alfred Search Field
                }
            }
        }

        // Check AX Subrole
        if let subrole = getAXStringAttribute(axElement, attribute: kAXSubroleAttribute) {
            for pattern in Self.axSubrolePatterns {
                if subrole.contains(pattern) {
                    return "Raycast"  // raycast_searchField
                }
            }
        }

        // Check AX Identifier for Spotlight (most reliable - persists even when user types)
        if let identifier = getAXStringAttribute(axElement, attribute: kAXIdentifierAttribute) {
            if identifier == "SpotlightSearchField" {
                return "Spotlight"
            }
        }
        
        // Check AX Placeholder (fallback for Spotlight - only visible when input is empty)
        if let placeholder = getAXStringAttribute(axElement, attribute: kAXPlaceholderValueAttribute) {
            for pattern in Self.axPlaceholderPatterns {
                if placeholder.contains(pattern) {
                    return "Spotlight"  // Spotlight Search
                }
            }
        }

        return nil
    }
    
    /// Helper to get string attribute from AX element
    private func getAXStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else {
            return nil
        }
        return value
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
    private func checkOverlayStateChange() {
        let isCurrentlyVisible = isOverlayVisibleQuiet()
        
        // Update cached state for hot path consumers (O(1) reads)
        cachedOverlayVisible = isCurrentlyVisible
        cachedOverlayName = isCurrentlyVisible ? lastDetectedOverlay : nil

        // Detect state change
        if isCurrentlyVisible != wasOverlayVisible {
            let overlayName = lastDetectedOverlay ?? "unknown"
            if isCurrentlyVisible {
                logDebug("found: '\(overlayName)'")
            } else {
                logDebug("Overlay dismissed")
            }
            wasOverlayVisible = isCurrentlyVisible

            // Notify callback
            onOverlayVisibilityChanged?(isCurrentlyVisible)
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
