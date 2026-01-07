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
//  Detection methods (in priority order):
//  1. AX Attributes: Check focused element's Title/Subrole/Placeholder
//  2. Window Owner Name: Fallback to CGWindowList check
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

    private init() {
        // Start monitoring overlay state changes
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Known Overlay Apps (Window Owner Names)

    /// List of known overlay apps that should be detected via window owner name
    private static let overlayAppOwnerNames: Set<String> = [
        "Spotlight",      // macOS Spotlight search (Cmd+Space)
        "Raycast",        // Raycast launcher
        "Alfred",         // Alfred launcher
        // Note: Add more overlay apps here if needed
    ]
    
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

    // MARK: - Primary Detection Method (Combined)

    /// Check if any overlay app is currently active
    /// Uses AX attributes first (more accurate), then falls back to window owner name
    /// - Returns: True if an overlay app is detected
    func isOverlayAppVisible() -> Bool {
        // Priority 1: Check AX attributes of focused element (most accurate)
        if let overlayName = detectOverlayViaAXAttributes() {
            logDebug("Overlay detected via AX: '\(overlayName)'")
            lastDetectedOverlay = overlayName
            return true
        }
        
        // Priority 2: Fallback to window owner name check
        if let overlayName = detectOverlayViaWindowOwner() {
            logDebug("Overlay detected via Window: '\(overlayName)'")
            lastDetectedOverlay = overlayName
            return true
        }
        
        lastDetectedOverlay = nil
        return false
    }
    
    /// Get the name of the currently visible overlay app, if any
    /// - Returns: Name of the overlay app, or nil if none visible
    func getVisibleOverlayAppName() -> String? {
        // Check via AX first
        if let name = detectOverlayViaAXAttributes() {
            return name
        }
        
        // Fallback to window owner
        return detectOverlayViaWindowOwner()
    }

    // MARK: - AX Attribute Detection (Priority 1)

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

        // Priority 0: Skip overlay detection if focused element belongs to a browser
        // This prevents false positives when browser is focused but Spotlight window is visible in background
        if let bundleId = getAppBundleIdFromElement(axElement),
           AppBehaviorDetector.browserApps.contains(bundleId) {
            // No logging here - this is called frequently by monitor timer
            return nil
        }

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

        // Check AX Placeholder
        if let placeholder = getAXStringAttribute(axElement, attribute: kAXPlaceholderValueAttribute) {
            for pattern in Self.axPlaceholderPatterns {
                if placeholder.contains(pattern) {
                    return "Spotlight"  // Spotlight Search
                }
            }
        }

        // Check AX Description (for Terminal panels in VSCode, Cursor, etc.)
        // Terminal panels have descriptions like "Terminal 1", "Terminal 2", etc.
        if let description = getAXStringAttribute(axElement, attribute: kAXDescriptionAttribute) {
            if description.hasPrefix("Terminal") {
                return "Terminal"  // Terminal in editors like VSCode, Cursor
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

    /// Helper to get bundle ID of the app that owns an AX element
    private func getAppBundleIdFromElement(_ element: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Window Owner Detection (Priority 2 - Fallback)

    /// Detect overlay app by checking window owner names
    /// - Returns: Name of detected overlay app, or nil if not found
    private func detectOverlayViaWindowOwner() -> String? {
        // Don't detect overlay via window owner if focused element belongs to a browser
        // This prevents false positives when browser is focused but Spotlight window
        // is visible in background (e.g., user clicked Chrome address bar while XKey Debug Window is floating)
        // Note: We check focused element's app, not frontmost app, because XKey's floating window
        // can be frontmost while user is actually typing in Chrome
        if let focusedAppBundleId = getFocusedElementAppBundleId(),
           AppBehaviorDetector.browserApps.contains(focusedAppBundleId) {
            // No logging here - this is called frequently by monitor timer
            return nil
        }

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               Self.overlayAppOwnerNames.contains(owner) {
                // Verify it's a visible window (has non-zero bounds)
                if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                   let width = bounds["Width"],
                   let height = bounds["Height"],
                   width > 0 && height > 0 {
                    return owner
                }
            }
        }

        return nil
    }

    /// Get bundle ID of the app that owns the currently focused element
    /// This is more accurate than frontmostApplication when floating windows are involved
    private func getFocusedElementAppBundleId() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement
        var pid: pid_t = 0

        guard AXUIElementGetPid(axElement, &pid) == .success else {
            return nil
        }

        // Get bundle ID from PID
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.bundleIdentifier
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
    private func checkOverlayStateChange() {
        let isCurrentlyVisible = isOverlayVisibleQuiet()

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
        // Priority 1: AX Attributes
        if let overlayName = detectOverlayViaAXAttributes() {
            lastDetectedOverlay = overlayName
            return true
        }
        
        // Priority 2: Window Owner
        if let overlayName = detectOverlayViaWindowOwner() {
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
    //
    // Window Owner Detection:
    // - We only read kCGWindowOwnerName (application name like "Spotlight", "Raycast")
    // - Available WITHOUT Screen Recording permission on all macOS versions
    //
    // Screen Recording permission is only needed for:
    // - kCGWindowName (window title)
    // - kCGWindowSharingState
    //
    // References:
    // - https://developer.apple.com/forums/thread/126860
    // - https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/
}
