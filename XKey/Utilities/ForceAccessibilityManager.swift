//
//  ForceAccessibilityManager.swift
//  XKey
//
//  Manages Force Accessibility (AXManualAccessibility) for Electron/Chromium apps
//  This helps retrieve more detailed text info from web-based apps like VS Code, Slack, Discord
//

import Cocoa

/// Manages Force Accessibility (AXManualAccessibility) for apps
/// This enables enhanced accessibility for Electron/Chromium apps based on Window Title Rules
class ForceAccessibilityManager {
    
    // MARK: - Singleton
    
    static let shared = ForceAccessibilityManager()
    
    // MARK: - State
    
    /// Currently enabled app's PID (0 = no app enabled)
    private var enabledPid: pid_t = 0
    
    /// Currently enabled app's bundle ID
    private var enabledBundleId: String = ""
    
    /// Log callback for debug logging
    var logCallback: ((String) -> Void)?
    
    // MARK: - Public Methods
    
    /// Apply Force Accessibility based on current app and matching rule
    /// Call this on app switch to enable/disable AXManualAccessibility as needed
    func applyForCurrentApp() {
        let detector = AppBehaviorDetector.shared
        let override = detector.getForceAccessibilityOverride()
        
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            // No frontmost app - disable if we had one enabled
            if enabledPid != 0 {
                disableForceAccessibility()
            }
            return
        }
        
        // If current app matches a rule with Force Accessibility enabled
        if override.shouldEnable {
            // Check if we need to switch apps
            if bundleId != enabledBundleId {
                // Disable for previous app (if any)
                if enabledPid != 0 {
                    disableForceAccessibility()
                }
                // Enable for new app
                enableForceAccessibility(bundleId: bundleId, ruleName: override.ruleName ?? "Unknown")
            }
            // Already enabled for this app - do nothing
        } else {
            // No rule match - disable if we had Force Accessibility enabled
            if enabledPid != 0 {
                disableForceAccessibility()
            }
        }
    }
    
    /// Enable AXManualAccessibility for an app by bundle ID
    /// - Parameters:
    ///   - bundleId: Bundle ID of the app to enable Force Accessibility for
    ///   - ruleName: Name of the rule that triggered this (for logging)
    private func enableForceAccessibility(bundleId: String, ruleName: String) {
        // Find the app's PID
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            logCallback?("[FORCE-AX] App not found: \(bundleId)")
            return
        }
        
        let pid = app.processIdentifier
        let appName = app.localizedName ?? bundleId
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try to set AXManualAccessibility = true
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        
        if result == .success {
            enabledPid = pid
            enabledBundleId = bundleId
            logCallback?("[FORCE-AX] ✅ Enabled for '\(appName)' (rule: \(ruleName))")
        } else {
            let errorDesc = result.humanReadableDescription
            logCallback?("[FORCE-AX] ❌ Failed for '\(appName)': \(errorDesc)")
            
            // If attribute unsupported, this app doesn't support AXManualAccessibility
            // This is expected for native macOS apps
            if result == .attributeUnsupported {
                logCallback?("[FORCE-AX] ℹ️ '\(appName)' doesn't support AXManualAccessibility (native app?)")
            }
        }
    }
    
    /// Disable AXManualAccessibility for the previously enabled app
    private func disableForceAccessibility() {
        guard enabledPid != 0 else { return }
        
        let appElement = AXUIElementCreateApplication(enabledPid)
        
        // Set AXManualAccessibility = false
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanFalse
        )
        
        if result == .success {
            logCallback?("[FORCE-AX] Disabled for previous app (PID=\(enabledPid))")
        } else {
            // App may have closed - that's fine
            logCallback?("[FORCE-AX] Previous app (PID=\(enabledPid)) may have closed")
        }
        
        enabledPid = 0
        enabledBundleId = ""
    }
}
