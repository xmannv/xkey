//
//  InputSourceSwitcher.swift
//  XKey
//
//  Utility to switch between input sources programmatically
//

import Carbon
import Cocoa

class InputSourceSwitcher {
    
    static let shared = InputSourceSwitcher()
    
    /// XKeyIM bundle identifier
    static let xkeyIMBundleId = "com.codetay.inputmethod.XKey"
    
    // MARK: - Switch Input Source
    
    /// Switch to XKeyIM input method
    /// - Returns: true if successfully switched, false otherwise
    @discardableResult
    func switchToXKey() -> Bool {
        return selectInputSource(bundleId: Self.xkeyIMBundleId)
    }
    
    /// Switch to a specific input source by bundle identifier
    /// - Parameter bundleId: The bundle identifier of the input source
    /// - Returns: true if successfully switched, false otherwise
    func selectInputSource(bundleId: String) -> Bool {
        // Create filter for the specific bundle ID
        let filter: [String: Any] = [
            kTISPropertyBundleID as String: bundleId
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            NSLog("InputSourceSwitcher: Input source '\(bundleId)' not found")
            return false
        }
        
        let result = TISSelectInputSource(source)
        if result == noErr {
            NSLog("InputSourceSwitcher: Switched to '\(bundleId)'")
            return true
        } else {
            NSLog("InputSourceSwitcher: Failed to switch to '\(bundleId)', error: \(result)")
            return false
        }
    }
    
    /// Get currently selected input source bundle ID
    func getCurrentInputSourceId() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        if let bundleId = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
            return Unmanaged<CFString>.fromOpaque(bundleId).takeUnretainedValue() as String
        }
        
        return nil
    }
    
    /// Check if XKeyIM is currently active
    var isXKeyActive: Bool {
        return getCurrentInputSourceId() == Self.xkeyIMBundleId
    }
    
    /// Check if XKeyIM is installed (available in input sources list)
    var isXKeyInstalled: Bool {
        let filter: [String: Any] = [
            kTISPropertyBundleID as String: Self.xkeyIMBundleId
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        
        return !sourceList.isEmpty
    }
    
    /// Get list of all enabled keyboard input sources
    func getEnabledInputSources() -> [(bundleId: String, name: String)] {
        var result: [(bundleId: String, name: String)] = []
        
        // Get all enabled input sources
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return result
        }
        
        for source in sourceList {
            var bundleId = ""
            var name = ""
            
            if let bundleIdRef = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
                bundleId = Unmanaged<CFString>.fromOpaque(bundleIdRef).takeUnretainedValue() as String
            }
            
            if let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                name = Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String
            }
            
            if !bundleId.isEmpty {
                result.append((bundleId: bundleId, name: name))
            }
        }
        
        return result
    }
}
