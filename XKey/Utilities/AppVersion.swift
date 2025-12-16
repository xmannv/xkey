//
//  AppVersion.swift
//  XKey
//
//  Utility to get app version from Info.plist
//

import Foundation

struct AppVersion {
    /// Get the app version from CFBundleShortVersionString in Info.plist
    static var current: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0" // Fallback
    }
    
    /// Get the build number from CFBundleVersion in Info.plist
    static var build: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "1" // Fallback
    }
    
    /// Get full version string (e.g., "1.0.0 (1)")
    static var fullVersion: String {
        return "\(current) (\(build))"
    }
}
