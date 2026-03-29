//
//  SmartSwitchManager.swift
//  XKey
//
//  Smart switch key - Remember language per app
//  Ported from OpenKey SmartSwitchKey.cpp
//

import Foundation

/// Manages per-app language settings
class SmartSwitchManager {
    
    // MARK: - Properties
    
    private var appLanguageMap: [String: Int] = [:]  // bundleId -> language (0: English, 1: Vietnamese)
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - App Language Management
    
    /// Get language for app
    /// - Parameters:
    ///   - bundleId: App bundle identifier
    ///   - currentLanguage: Current language (used for reference, not auto-saved)
    /// - Returns: Language for this app (-1 if not found, 0: English, 1: Vietnamese)
    func getAppLanguage(bundleId: String, currentLanguage: Int) -> Int {
        if let language = appLanguageMap[bundleId] {
            return language
        }
        
        // Not found - return -1 to indicate app is new
        // The caller should decide whether to save the current language
        return -1
    }
    
    /// Set language for app
    func setAppLanguage(bundleId: String, language: Int) {
        appLanguageMap[bundleId] = language
    }
    
    /// Remove app from map
    func removeApp(bundleId: String) {
        appLanguageMap.removeValue(forKey: bundleId)
    }
    
    /// Clear all app settings
    func clearAll() {
        appLanguageMap.removeAll()
    }
    
    /// Get all app settings
    func getAllApps() -> [(bundleId: String, language: Int)] {
        return appLanguageMap.map { (bundleId: $0.key, language: $0.value) }
    }
    
    // MARK: - Persistence
    
    /// Save to plist via SharedSettings
    func saveToPlist() {
        guard let data = try? JSONEncoder().encode(appLanguageMap) else { return }
        SharedSettings.shared.setSmartSwitchData(data)
    }
    
    /// Load from plist via SharedSettings
    func loadFromPlist() {
        guard let data = SharedSettings.shared.getSmartSwitchData(),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        appLanguageMap = map
    }
}
