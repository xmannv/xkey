//
//  XKeyIMUpdateManager.swift
//  XKey
//
//  Manages automatic updates for XKeyIM (Input Method Extension)
//  Updates XKeyIM by installing the bundled version from XKey.app/Contents/Resources/
//

import Foundation
import AppKit
import UserNotifications

/// Manager for XKeyIM auto-update functionality
class XKeyIMUpdateManager {
    
    // MARK: - Singleton
    
    static let shared = XKeyIMUpdateManager()
    
    // MARK: - Properties
    
    /// Callback for logging debug messages
    var debugLogCallback: ((String) -> Void)?
    
    /// Path to installed XKeyIM
    private let installedXKeyIMPath = NSHomeDirectory() + "/Library/Input Methods/XKeyIM.app"
    
    /// Path to bundled XKeyIM in XKey.app
    private var bundledXKeyIMPath: String? {
        return Bundle.main.resourcePath.map { $0 + "/XKeyIM.app" }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Version Checking
    
    /// Check if XKeyIM needs update
    /// - Returns: True if bundled version is newer than installed version
    func needsUpdate() -> Bool {
        guard let bundledPath = bundledXKeyIMPath,
              FileManager.default.fileExists(atPath: bundledPath) else {
            logDebug("XKeyIM: No bundled version found in XKey.app/Contents/Resources/")
            return false
        }
        
        // Check if XKeyIM is installed
        guard FileManager.default.fileExists(atPath: installedXKeyIMPath) else {
            logDebug("XKeyIM: Not installed yet, will install bundled version")
            return true
        }
        
        // Compare versions
        let installedVersion = getVersion(at: installedXKeyIMPath)
        let bundledVersion = getVersion(at: bundledPath)
        
        logDebug("XKeyIM Version Check:")
        logDebug("   Installed: \(installedVersion ?? "unknown")")
        logDebug("   Bundled:   \(bundledVersion ?? "unknown")")
        
        guard let installed = installedVersion,
              let bundled = bundledVersion else {
            logDebug("XKeyIM: Could not determine versions")
            return false
        }
        
        // Compare version strings
        let needsUpdate = compareVersions(bundled, installed) == .orderedDescending
        
        if needsUpdate {
            logDebug("XKeyIM: Update available (\(installed) → \(bundled))")
        } else {
            logDebug("XKeyIM: Up to date (\(installed))")
        }
        
        return needsUpdate
    }
    
    /// Get version from XKeyIM.app bundle
    private func getVersion(at path: String) -> String? {
        let infoPlistPath = path + "/Contents/Info.plist"
        
        guard let plistData = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }
        
        // Get version and build number
        let version = plist["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = plist["CFBundleVersion"] as? String ?? "0"
        
        return "\(version).\(build)"
    }
    
    /// Compare two version strings (e.g., "1.2.17.20251229")
    /// - Returns: ComparisonResult (.orderedAscending, .orderedSame, .orderedDescending)
    private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1 = i < v1Components.count ? v1Components[i] : 0
            let v2 = i < v2Components.count ? v2Components[i] : 0
            
            if v1 < v2 {
                return .orderedAscending
            } else if v1 > v2 {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    // MARK: - Installation
    
    /// Install bundled XKeyIM to ~/Library/Input Methods/
    /// - Parameter showNotification: Whether to show user notification after installation
    /// - Returns: True if installation succeeded
    @discardableResult
    func installBundledXKeyIM(showNotification: Bool = true) -> Bool {
        guard let bundledPath = bundledXKeyIMPath,
              FileManager.default.fileExists(atPath: bundledPath) else {
            logDebug("XKeyIM: Cannot install - bundled version not found")
            return false
        }
        
        // Log version info if available
        let bundledVersion = getVersion(at: bundledPath)
        let installedVersion = FileManager.default.fileExists(atPath: installedXKeyIMPath) 
            ? getVersion(at: installedXKeyIMPath) 
            : nil
        
        if let installed = installedVersion, let bundled = bundledVersion {
            logDebug("XKeyIM: Installing bundled version (\(installed) → \(bundled))...")
        } else {
            logDebug("XKeyIM: Installing bundled version...")
        }
        
        // Kill running XKeyIM process if exists
        killXKeyIMProcess()
        
        // Wait a bit for process to fully terminate
        Thread.sleep(forTimeInterval: 0.5)
        
        // Create Input Methods directory if needed
        let inputMethodsDir = NSHomeDirectory() + "/Library/Input Methods"
        do {
            try FileManager.default.createDirectory(atPath: inputMethodsDir, withIntermediateDirectories: true)
        } catch {
            logDebug("XKeyIM: Failed to create Input Methods directory: \(error)")
            return false
        }
        
        // Remove old version
        if FileManager.default.fileExists(atPath: installedXKeyIMPath) {
            do {
                try FileManager.default.removeItem(atPath: installedXKeyIMPath)
                logDebug("Removed old version")
            } catch {
                logDebug("XKeyIM: Failed to remove old version: \(error)")
                // Continue anyway, copyItem might overwrite
            }
        }
        
        // Copy new version
        do {
            try FileManager.default.copyItem(atPath: bundledPath, toPath: installedXKeyIMPath)
            logDebug("Copied new version")
        } catch {
            logDebug("XKeyIM: Failed to copy new version: \(error)")
            return false
        }
        
        // Verify installation
        guard FileManager.default.fileExists(atPath: installedXKeyIMPath) else {
            logDebug("XKeyIM: Installation verification failed")
            return false
        }
        
        let finalVersion = getVersion(at: installedXKeyIMPath)
        logDebug("XKeyIM: Installed successfully (v\(finalVersion ?? "unknown"))")
        
        // Show notification to user
        if showNotification {
            showUpdateNotification(version: finalVersion ?? "unknown")
        }
        
        return true
    }
    
    /// Kill running XKeyIM process
    private func killXKeyIMProcess() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["XKeyIM"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logDebug("Killed running XKeyIM process")
            }
        } catch {
            // Process might not be running, that's okay
            logDebug("No running XKeyIM process found")
        }
    }
    
    /// Show notification to user about XKeyIM update
    private func showUpdateNotification(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "XKeyIM đã được cập nhật"
            content.body = "Phiên bản \(version) đã được cài đặt.\n\nVui lòng chuyển sang input method khác rồi quay lại XKey để áp dụng."
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: "xkeyim-update-\(version)", content: content, trigger: nil)
            center.add(request)
        }
        
        logDebug("XKeyIM: Update notification sent to user")
    }
    
    // MARK: - Auto-Update Check
    
    /// Check and install XKeyIM update if available
    /// Called automatically when XKey app updates
    func checkAndInstallUpdate() {
        logDebug("XKeyIM: Checking for updates...")
        
        if needsUpdate() {
            installBundledXKeyIM(showNotification: true)
        } else {
            logDebug("XKeyIM: Already up to date")
        }
    }
    
    // MARK: - Debug Logging
    
    private func logDebug(_ message: String) {
        // Only use DebugLogger (which writes to file), debugWindowController will read from file
        sharedLogInfo(message)
    }
}
