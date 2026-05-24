//
//  PreferencesViewModel.swift
//  XKey
//
//  ViewModel for Preferences
//

import SwiftUI
import Combine

import ServiceManagement

class PreferencesViewModel: ObservableObject {
    @Published var preferences: Preferences

    init() {
        self.preferences = SharedSettings.shared.loadPreferences()
        if let savedLang = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: savedLang) {
            self.preferences.appLanguage = lang
        }
    }

    func save() {
        // Save to SharedSettings (plist file)
        SharedSettings.shared.savePreferences(preferences)

        // Sync app language to standalone UserDefaults key (read at launch before Preferences loads)
        UserDefaults.standard.set(preferences.appLanguage.rawValue, forKey: "appLanguage")
        AppLanguage.applyLanguage()

        // Apply launch at login setting
        setLaunchAtLogin(preferences.startAtLogin)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Failed to set login item, ignore silently
            }
        } else {
            // Fallback for macOS 12.x
            // Note: SMLoginItemSetEnabled requires bundle identifier, not App Group ID
            SMLoginItemSetEnabled("com.codetay.XKey" as CFString, enabled)
        }
    }
}
