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
        self.preferences = PreferencesManager.shared.loadPreferences()
    }
    
    func save() {
        // Save preferences
        PreferencesManager.shared.savePreferences(preferences)
        
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
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            SMLoginItemSetEnabled("com.codetay.XKey.debug" as CFString, enabled)
        }
    }
}
