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
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cài đặt XKey"
        window.titlebarAppearsTransparent = false
        // Allow window to be released when closed to free memory
        window.isReleasedWhenClosed = true
        window.level = .floating
        window.center()

        self.init(window: window)
        
        // Set window delegate to handle close
        window.delegate = self

        // Create SwiftUI view with auto-save callback
        let preferencesView = PreferencesView(
            selectedTab: selectedTab,
            onSave: onSave
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
