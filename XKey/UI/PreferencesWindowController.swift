//
//  PreferencesWindowController.swift
//  XKey
//
//  Window controller for SwiftUI Preferences
//

import Cocoa
import SwiftUI

class PreferencesWindowController: NSWindowController {
    
    convenience init(selectedTab: Int = 0, onSave: @escaping (Preferences) -> Void) {
        // Create window first
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Bảng điều khiển XKey"
        window.isReleasedWhenClosed = false
        window.level = .floating  // Always on top
        window.center()
        
        // Hide traffic light buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.init(window: window)
        
        // Create SwiftUI view with close callback
        let preferencesView = PreferencesView(
            selectedTab: selectedTab,
            onSave: onSave,
            onClose: { [weak self] in
                self?.close()
            }
        )
        
        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: preferencesView)
        window.contentViewController = hostingController
    }
}
