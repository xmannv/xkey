//
//  IMKitHelper.swift
//  XKey
//
//  Helper utilities for IMKit integration
//

import Foundation
import AppKit
import Carbon

/// Helper class for managing XKeyIM Input Method
class IMKitHelper {
    
    // MARK: - Singleton
    
    static let shared = IMKitHelper()
    private init() {}
    
    // MARK: - Constants
    
    /// Bundle identifier for XKeyIM
    static let xkeyIMBundleId = "com.codetay.inputmethod.XKey"
    
    /// Installation path for Input Methods
    static let inputMethodsPath = "~/Library/Input Methods".expandingTildeInPath
    
    /// XKeyIM app name
    static let xkeyIMAppName = "XKeyIM.app"
    
    // MARK: - Installation Check
    
    /// Check if XKeyIM is installed
    static func isXKeyIMInstalled() -> Bool {
        let path = (inputMethodsPath as NSString).appendingPathComponent(xkeyIMAppName)
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// Check if XKeyIM is enabled in System Settings
    static func isXKeyIMEnabled() -> Bool {
        guard let inputSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as CFArray? else {
            return false
        }
        
        let count = CFArrayGetCount(inputSources)
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSources, i), to: TISInputSource.self)
            
            if let bundleIdPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
                let bundleId = Unmanaged<CFString>.fromOpaque(bundleIdPtr).takeUnretainedValue() as String
                if bundleId == xkeyIMBundleId {
                    if let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                        let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
                        return CFBooleanGetValue(enabled)
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Installation
    
    /// Kill running XKeyIM process
    private static func killXKeyIMProcess() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["XKeyIM"]
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Process might not be running, that's okay
        }
    }
    
    /// Install XKeyIM to ~/Library/Input Methods
    /// This also handles reinstallation by killing any running process first
    static func installXKeyIM() {
        // Kill running XKeyIM process first (safe even if not running)
        killXKeyIMProcess()
        
        // Wait for process to fully terminate
        Thread.sleep(forTimeInterval: 0.5)
        
        // Get XKeyIM from app bundle Resources
        guard let xkeyIMSource = Bundle.main.path(forResource: "XKeyIM", ofType: "app") else {
            showAlert(
                title: "Không tìm thấy XKeyIM",
                message: "XKeyIM.app không có trong bundle. Vui lòng tải phiên bản đầy đủ từ GitHub."
            )
            return
        }
        
        let destinationPath = (inputMethodsPath as NSString).appendingPathComponent(xkeyIMAppName)
        let fileManager = FileManager.default
        
        // First, try direct copy (works if not sandboxed or has permission)
        do {
            // Create Input Methods directory if needed
            if !fileManager.fileExists(atPath: inputMethodsPath) {
                try fileManager.createDirectory(
                    atPath: inputMethodsPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
            
            // Remove old version if exists
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            
            // Copy new version
            try fileManager.copyItem(atPath: xkeyIMSource, toPath: destinationPath)
            
            // Register the input source
            registerInputSource(at: destinationPath)
            
            showAlert(
                title: "Cài đặt thành công",
                message: "XKeyIM đã được cài đặt.\n\nVui lòng vào System Settings → Keyboard → Input Sources để bật XKey Vietnamese."
            )
            
            // Open Input Sources settings
            openInputSourcesSettings()
            
        } catch {
            // If direct copy fails, show XKeyIM in Finder for manual installation
            showManualInstallInstructions(xkeyIMSource: xkeyIMSource)
        }
    }
    
    /// Show manual installation instructions and reveal XKeyIM in Finder
    private static func showManualInstallInstructions(xkeyIMSource: String) {
        // Use a loop to keep dialog open until user clicks "Đóng"
        var shouldContinue = true
        
        while shouldContinue {
            let alert = NSAlert()
            alert.messageText = "Cài đặt thủ công XKeyIM"
            alert.informativeText = """
            Do giới hạn bảo mật, XKey không thể tự động cài đặt XKeyIM.
            
            Vui lòng làm theo các bước sau:
            1. Nhấn "Mở XKeyIM" để hiển thị XKeyIM.app
            2. Nhấn "Mở Input Methods" để mở thư mục đích
            3. Kéo thả XKeyIM.app vào thư mục Input Methods
            4. Nhấn "Mở Input Sources" để thêm XKey Vietnamese
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Mở XKeyIM")
            alert.addButton(withTitle: "Mở Input Methods")
            alert.addButton(withTitle: "Mở Input Sources")
            alert.addButton(withTitle: "Đóng")
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                // Reveal XKeyIM in Finder
                NSWorkspace.shared.selectFile(xkeyIMSource, inFileViewerRootedAtPath: "")
                
            case .alertSecondButtonReturn:
                // Open Input Methods folder (create if needed)
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: inputMethodsPath) {
                    try? fileManager.createDirectory(
                        atPath: inputMethodsPath,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }
                NSWorkspace.shared.open(URL(fileURLWithPath: inputMethodsPath))
                
            case .alertThirdButtonReturn:
                // Open System Settings > Keyboard > Input Sources
                openInputSourcesSettings()
                
            default:
                // "Đóng" button - exit the loop
                shouldContinue = false
            }
        }
    }
    
    /// Uninstall XKeyIM
    static func uninstallXKeyIM() {
        let path = (inputMethodsPath as NSString).appendingPathComponent(xkeyIMAppName)
        
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(atPath: path)
            
            showAlert(
                title: "Gỡ cài đặt thành công",
                message: "XKeyIM đã được gỡ bỏ."
            )
        } catch {
            showAlert(
                title: "Lỗi",
                message: "Không thể gỡ XKeyIM: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Input Source Registration
    
    /// Register input source with the system
    private static func registerInputSource(at path: String) {
        let url = URL(fileURLWithPath: path) as CFURL
        TISRegisterInputSource(url)
    }
    
    /// Enable XKeyIM input source
    static func enableXKeyIM() {
        guard let inputSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as CFArray? else {
            return
        }
        
        let count = CFArrayGetCount(inputSources)
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSources, i), to: TISInputSource.self)
            
            if let bundleIdPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
                let bundleId = Unmanaged<CFString>.fromOpaque(bundleIdPtr).takeUnretainedValue() as String
                if bundleId == xkeyIMBundleId {
                    TISEnableInputSource(source)
                    return
                }
            }
        }
    }
    
    /// Select XKeyIM as current input source
    static func selectXKeyIM() {
        guard let inputSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as CFArray? else {
            return
        }
        
        let count = CFArrayGetCount(inputSources)
        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(inputSources, i), to: TISInputSource.self)
            
            if let bundleIdPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID) {
                let bundleId = Unmanaged<CFString>.fromOpaque(bundleIdPtr).takeUnretainedValue() as String
                if bundleId == xkeyIMBundleId {
                    TISSelectInputSource(source)
                    return
                }
            }
        }
    }
    
    // MARK: - Open System Settings
    
    /// Open Keyboard Input Sources in System Settings
    static func openInputSourcesSettings() {
        if #available(macOS 13.0, *) {
            // macOS Ventura and later
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Older macOS
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - String Extension

extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}
