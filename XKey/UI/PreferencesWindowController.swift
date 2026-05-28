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

    /// Drives the active section; shared with PreferencesView so it can be switched live
    private let navigator = PreferencesNavigator()

    convenience init(selectedTab: Int = 0, onSave: @escaping (Preferences) -> Void) {
        // Create window first
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Cài đặt XKey")
        window.titlebarAppearsTransparent = false
        // Allow window to be released when closed to free memory
        window.isReleasedWhenClosed = true
        window.level = .floating
        window.center()

        self.init(window: window)

        navigator.selectedSection = PreferencesSection.from(tabIndex: selectedTab)

        // Set window delegate to handle close
        window.delegate = self

        // Create SwiftUI view with auto-save callback
        let preferencesView = PreferencesView(
            navigator: navigator,
            onSave: onSave
        )

        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: preferencesView)
        window.contentViewController = hostingController
        
        // Add pin button to title bar
        pinManager = WindowPinManager(window: window)
        pinManager?.setupPinButton()
    }

    /// Switch to a tab live and bring the window forward (restoring it from the Dock if minimized).
    func reveal(tabIndex: Int) {
        navigator.selectedSection = PreferencesSection.from(tabIndex: tabIndex)
        if let window = window, window.isMiniaturized {
            window.deminiaturize(nil)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        WindowPinManager.handleWindowClose(window, onClosed: onWindowClosed)
    }
}
