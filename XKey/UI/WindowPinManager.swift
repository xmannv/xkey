//
//  WindowPinManager.swift
//  XKey
//
//  Shared pin button management for window controllers
//  Handles always-on-top toggle with pin/unpin button in title bar
//

import Cocoa

/// Manages pin (always-on-top) button for NSWindow title bars
/// Used by PreferencesWindowController, SettingsWindowController, and DebugWindowController
class WindowPinManager {
    
    private weak var window: NSWindow?
    private var pinButton: NSButton?
    private var isAlwaysOnTop: Bool
    
    /// Optional custom toggle handler. When set, togglePin delegates to this
    /// instead of directly setting window.level. The handler receives the NEW state.
    var onToggle: ((Bool) -> Void)?
    
    init(window: NSWindow, initiallyPinned: Bool = true) {
        self.window = window
        self.isAlwaysOnTop = initiallyPinned
    }
    
    /// Set up pin button in the window's title bar (trailing side)
    func setupPinButton() {
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
        
        // Add to title bar - position at top right
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.addSubview(button)
            
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
        
        if let onToggle = onToggle {
            // Delegate to custom handler (e.g. DebugWindowController syncs with ViewModel)
            onToggle(isAlwaysOnTop)
        } else {
            // Default behavior: directly set window level
            window?.level = isAlwaysOnTop ? .floating : .normal
        }
        
        updatePinButton(isAlwaysOnTop)
    }
    
    /// Update pin button appearance externally (e.g. when state changes from ViewModel)
    func updatePinButton(_ isPinned: Bool) {
        isAlwaysOnTop = isPinned
        pinButton?.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin.slash",
            accessibilityDescription: isPinned ? "Bỏ ghim cửa sổ" : "Ghim cửa sổ"
        )
        pinButton?.contentTintColor = isPinned ? .systemBlue : .systemGray
    }
    
    /// Handle window close - clear content to release SwiftUI views
    static func handleWindowClose(_ window: NSWindow?, onClosed: (() -> Void)?) {
        window?.contentViewController = nil
        onClosed?()
    }
}
