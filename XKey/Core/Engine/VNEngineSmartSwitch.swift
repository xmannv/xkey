//
//  VNEngineSmartSwitch.swift
//  XKey
//
//  Smart Switch integration for VNEngine
//  Ported from OpenKey SmartSwitchKey.cpp
//

import Foundation

extension VNEngine {

    // MARK: - Smart Switch Manager

    /// Shared smart switch manager instance
    private static var _smartSwitchManager: SmartSwitchManager?

    var smartSwitchManager: SmartSwitchManager {
        if VNEngine._smartSwitchManager == nil {
            VNEngine._smartSwitchManager = SmartSwitchManager()
            VNEngine._smartSwitchManager?.loadFromPlist()
        }
        return VNEngine._smartSwitchManager!
    }

    /// Set shared smart switch manager (for integration with KeyboardEventHandler)
    static func setSharedSmartSwitchManager(_ manager: SmartSwitchManager) {
        _smartSwitchManager = manager
    }

    // MARK: - Smart Switch Processing
    //
    // Restoring an app's language is decided by AppPolicyRuntime, which both hosts share.

    /// Save current language for the active app
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the active app
    ///   - language: Language to save (0: English, 1: Vietnamese)
    func saveAppLanguage(bundleId: String, language: Int) {
        guard vUseSmartSwitchKey == 1 else { return }

        smartSwitchManager.setAndSaveAppLanguage(bundleId: bundleId, language: language)

        logCallback?("Smart Switch: Saved '\(bundleId)' → Language \(language == 1 ? "Vietnamese" : "English")")
    }
}
