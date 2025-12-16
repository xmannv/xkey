//
//  SettingsWindowController.swift
//  XKey
//
//  Window controller for unified Settings with Apple-style design
//

import Cocoa
import SwiftUI

@available(macOS 13.0, *)
class SettingsWindowController: NSWindowController {
    
    convenience init(selectedSection: SettingsSection = .general, onSave: @escaping (Preferences) -> Void) {
        // Create window with modern style
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Cài đặt XKey"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        
        self.init(window: window)
        
        // Create SwiftUI view with auto-save callback
        let settingsView = SettingsView(
            selectedSection: selectedSection,
            onSave: onSave,
            onClose: nil
        )
        
        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
    }
}
