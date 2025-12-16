//
//  PreferencesManager.swift
//  XKey
//
//  Manages user preferences persistence
//

import Foundation

class PreferencesManager {
    static let shared = PreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "XKeyPreferences"
    
    private init() {}
    
    // MARK: - Load/Save
    
    func loadPreferences() -> Preferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences() // Return default preferences
        }
        return preferences
    }
    
    func savePreferences(_ preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            userDefaults.set(data, forKey: preferencesKey)
        }
    }
}
