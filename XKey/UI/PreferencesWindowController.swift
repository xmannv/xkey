//
//  PreferencesWindowController.swift
//  XKey
//
//  Window controller for SwiftUI Preferences
//

import Cocoa
import SwiftUI

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    
    private var pinManager: WindowPinManager?
    
    /// Callback when window is closed - used to nil out reference in AppDelegate
    var onWindowClosed: (() -> Void)?

    convenience init(selectedTab: Int = 0, onSave: @escaping (Preferences) -> Void) {
        // Create window first
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Bảng điều khiển XKey"
        // Allow window to be released when closed to free memory
        window.isReleasedWhenClosed = true
        window.level = .floating  // Always on top
        window.center()

        // Hide traffic light buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.init(window: window)
        
        // Set window delegate to handle close
        window.delegate = self

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
        
        // Add pin button to title bar
        pinManager = WindowPinManager(window: window)
        pinManager?.setupPinButton()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        WindowPinManager.handleWindowClose(window, onClosed: onWindowClosed)
    }
}
