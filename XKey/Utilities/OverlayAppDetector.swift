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

    // MARK: - Primary Detection Method

    /// Check if any overlay app is currently active
    /// Uses AX attributes of focused element (most accurate - only detects when overlay is focused)
    /// - Returns: True if an overlay app is detected
    func isOverlayAppVisible() -> Bool {
        if let overlayName = detectOverlayViaAXAttributes() {
            logDebug("Overlay detected via AX: '\(overlayName)'")
            lastDetectedOverlay = overlayName
            return true
        }
        
        lastDetectedOverlay = nil
        return false
    }
    
    /// Get the name of the currently visible overlay app, if any
    /// - Returns: Name of the overlay app, or nil if none visible
    func getVisibleOverlayAppName() -> String? {
        return detectOverlayViaAXAttributes()
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

    /// Helper to get bundle ID of the app that owns an AX element
    private func getAppBundleIdFromElement(_ element: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
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
