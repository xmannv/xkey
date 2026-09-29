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

    /// Persist one entry by merging against the latest shared map, then adopt that
    /// merged map locally so subsequent reads see writes from the other process.
    func setAndSaveAppLanguage(bundleId: String, language: Int) {
        guard let data = SharedSettings.shared.updateSmartSwitchLanguage(
            bundleIdentifier: bundleId,
            language: language
        ), let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            setAppLanguage(bundleId: bundleId, language: language)
            return
        }
        appLanguageMap = map
    }
    
    // MARK: - Persistence

    /// Load from plist via SharedSettings
    func loadFromPlist() {
        guard let data = SharedSettings.shared.getSmartSwitchData(),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return
        }
        appLanguageMap = map
    }
}
