//
//  LaunchAtLogin.swift
//  XKey
//
//  Utility for managing launch at login
//

import Foundation
import ServiceManagement

class LaunchAtLogin {
    
    /// Enable or disable launch at login
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Modern API for macOS 13+
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            // Legacy API for macOS 12 and below
            SMLoginItemSetEnabled("com.codetay.XKey" as CFString, enabled)
        }
    }
    
    /// Check if launch at login is currently enabled
    static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For legacy API, we can't reliably check status
            // Return false as default
            return false
        }
    }
}
