//
//  VNEngineSmartSwitch.swift
//  XKey
//
//  Smart Switch integration for VNEngine
//  Ported from OpenKey SmartSwitchKey.cpp
//

import Foundation
import Cocoa

extension VNEngine {
    
    // MARK: - Smart Switch Manager
    
    /// Shared smart switch manager instance
    private static var _smartSwitchManager: SmartSwitchManager?
    
    var smartSwitchManager: SmartSwitchManager {
        if VNEngine._smartSwitchManager == nil {
            VNEngine._smartSwitchManager = SmartSwitchManager()
            // Load saved data
            let path = smartSwitchDataPath
            _ = VNEngine._smartSwitchManager?.loadFromFile(path: path)
        }
        return VNEngine._smartSwitchManager!
    }
    
    /// Set shared smart switch manager (for integration with KeyboardEventHandler)
    static func setSharedSmartSwitchManager(_ manager: SmartSwitchManager) {
        _smartSwitchManager = manager
    }
    
    /// Path to smart switch data file
    private var smartSwitchDataPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let xkeyDir = appSupport.appendingPathComponent("XKey")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: xkeyDir, withIntermediateDirectories: true)
        
        return xkeyDir.appendingPathComponent("smart_switch.json").path
    }
    
    // MARK: - Smart Switch Processing
    
    /// Handle app switch - get/set language for the new app
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the new active app
    ///   - currentLanguage: Current language setting (0: English, 1: Vietnamese)
    /// - Returns: Language to use for this app, or -1 if no change needed
    func handleAppSwitch(bundleId: String, currentLanguage: Int) -> Int {
        guard vUseSmartSwitchKey == 1 else { return -1 }
        
        let savedLanguage = smartSwitchManager.getAppLanguage(bundleId: bundleId, currentLanguage: currentLanguage)
        
        if savedLanguage >= 0 && savedLanguage != currentLanguage {
            logCallback?("Smart Switch: App '\(bundleId)' → Language \(savedLanguage == 1 ? "Vietnamese" : "English")")
            return savedLanguage
        }
        
        return -1
    }
    
    /// Save current language for the active app
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the active app
    ///   - language: Language to save (0: English, 1: Vietnamese)
    func saveAppLanguage(bundleId: String, language: Int) {
        guard vUseSmartSwitchKey == 1 else { return }
        
        smartSwitchManager.setAppLanguage(bundleId: bundleId, language: language)
        
        // Save to file
        _ = smartSwitchManager.saveToFile(path: smartSwitchDataPath)
        
        logCallback?("Smart Switch: Saved '\(bundleId)' → Language \(language == 1 ? "Vietnamese" : "English")")
    }
    
    /// Get current active app bundle ID
    static func getCurrentAppBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

// MARK: - Smart Switch Result

extension VNEngine {
    
    /// Result of smart switch check
    struct SmartSwitchResult {
        let shouldSwitch: Bool
        let newLanguage: Int  // 0: English, 1: Vietnamese
        let bundleId: String
    }
    
    /// Check if should switch language for current app
    func checkSmartSwitch() -> SmartSwitchResult {
        guard vUseSmartSwitchKey == 1 else {
            return SmartSwitchResult(shouldSwitch: false, newLanguage: vLanguage, bundleId: "")
        }
        
        guard let bundleId = VNEngine.getCurrentAppBundleId() else {
            return SmartSwitchResult(shouldSwitch: false, newLanguage: vLanguage, bundleId: "")
        }
        
        let newLanguage = handleAppSwitch(bundleId: bundleId, currentLanguage: vLanguage)
        
        if newLanguage >= 0 {
            return SmartSwitchResult(shouldSwitch: true, newLanguage: newLanguage, bundleId: bundleId)
        }
        
        return SmartSwitchResult(shouldSwitch: false, newLanguage: vLanguage, bundleId: bundleId)
    }
}
