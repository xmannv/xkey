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
    
    private var pinButton: NSButton?
    private var isAlwaysOnTop: Bool = true
    
    /// Callback when window is closed - used to nil out reference in AppDelegate
    var onWindowClosed: (() -> Void)?

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
        // Allow window to be released when closed to free memory
        window.isReleasedWhenClosed = true
        window.level = .floating
        window.center()

        self.init(window: window)
        
        // Set window delegate to handle close
        window.delegate = self

        // Create SwiftUI view with auto-save callback
        let settingsView = SettingsView(
            selectedSection: selectedSection,
            onSave: onSave,
            onClose: nil
        )

        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
        
        // Add pin button to title bar
        setupPinButton()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Clear content to release SwiftUI views immediately
        window?.contentViewController = nil
        
        // Notify delegate to nil out the reference
        onWindowClosed?()
    }
    
    // MARK: - Pin Button
    
    private func setupPinButton() {
        guard let window = window else { return }
        
        // Create pin button
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pin window")
        button.contentTintColor = .systemBlue
        button.target = self
        button.action = #selector(togglePin)
        button.toolTip = "Giữ cửa sổ luôn ở trên cùng"
        
        // Add to title bar
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.addSubview(button)
            
            // Position at top right
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor, constant: -8),
                button.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor)
            ])
        }
        
        self.pinButton = button
        updatePinButton(isAlwaysOnTop)
    }
    
    @objc private func togglePin() {
        isAlwaysOnTop.toggle()
        window?.level = isAlwaysOnTop ? .floating : .normal
        updatePinButton(isAlwaysOnTop)
    }
    
    private func updatePinButton(_ isPinned: Bool) {
        pinButton?.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin.slash",
            accessibilityDescription: isPinned ? "Bỏ ghim cửa sổ" : "Ghim cửa sổ"
        )
        pinButton?.contentTintColor = isPinned ? .systemBlue : .systemGray
    }
}

