//
//  SettingsWindowController.swift
//  XKey
//
//  Window controller for unified Settings with Apple-style design
//

import Cocoa
import SwiftUI

@available(macOS 13.0, *)
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    
    private var pinManager: WindowPinManager?

    /// Callback when window is closed - used to nil out reference in AppDelegate
    var onWindowClosed: (() -> Void)?

    /// Drives the active section; shared with SettingsView so it can be switched live
    private let navigator = SettingsNavigator()

    convenience init(selectedSection: SettingsSection = .general, onSave: @escaping (Preferences) -> Void) {
        // Create window with modern style
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

        navigator.selectedSection = selectedSection

        // Set window delegate to handle close
        window.delegate = self

        // Create SwiftUI view with auto-save callback
        let settingsView = SettingsView(
            navigator: navigator,
            onSave: onSave
        )

        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
        
        // Add pin button to title bar
        pinManager = WindowPinManager(window: window)
        pinManager?.setupPinButton()
    }

    /// Switch to a section live and bring the window forward (restoring it from the Dock if minimized).
    func reveal(section: SettingsSection) {
        navigator.selectedSection = section
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
