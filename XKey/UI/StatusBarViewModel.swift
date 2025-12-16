//
//  StatusBarViewModel.swift
//  XKey
//
//  ViewModel for Status Bar
//

import SwiftUI
import Combine

class StatusBarViewModel: ObservableObject {
    @Published var isVietnameseEnabled = true
    @Published var currentInputMethod: InputMethod = .telex
    @Published var currentCodeTable: CodeTable = .unicode
    @Published var hotkeyDisplay = "⌘⇧V"
    @Published var hotkeyKeyEquivalent: KeyEquivalent = "v"
    @Published var hotkeyModifiers: EventModifiers = [.command, .shift]
    
    private weak var keyboardHandler: KeyboardEventHandler?
    private weak var eventTapManager: EventTapManager?
    
    // Debug logging callback
    var debugLogCallback: ((String) -> Void)?
    
    var onOpenPreferences: (() -> Void)?
    var onOpenMacroManagement: (() -> Void)?
    var onOpenConvertTool: (() -> Void)?
    
    init(keyboardHandler: KeyboardEventHandler?, eventTapManager: EventTapManager?) {
        self.keyboardHandler = keyboardHandler
        self.eventTapManager = eventTapManager
        
        // Sync initial state with keyboard handler
        if let handler = keyboardHandler {
            handler.setVietnamese(isVietnameseEnabled)
        }
        
        // Load hotkey from preferences
        updateHotkeyDisplay()
    }
    
    private func log(_ message: String) {
        #if DEBUG
        debugLogCallback?(message)
        #endif
    }
    
    func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        keyboardHandler?.setVietnamese(isVietnameseEnabled)
        log("🔄 Vietnamese toggled: \(isVietnameseEnabled ? "ON" : "OFF")")
    }
    
    func selectInputMethod(_ method: InputMethod) {
        log("📋 selectInputMethod: BEFORE=\(currentInputMethod.displayName), setting to \(method.displayName)")
        
        currentInputMethod = method
        
        log("📋 selectInputMethod: AFTER=\(currentInputMethod.displayName)")
        
        if let handler = keyboardHandler {
            handler.inputMethod = method
            log("✅ Set handler.inputMethod to \(method.displayName)")
        } else {
            log("⚠️ keyboardHandler is nil!")
        }
        
        // Save to preferences
        var prefs = PreferencesManager.shared.loadPreferences()
        prefs.inputMethod = method
        PreferencesManager.shared.savePreferences(prefs)
        
        // Verify saved
        let savedPrefs = PreferencesManager.shared.loadPreferences()
        log("📋 Saved to prefs, verified: \(savedPrefs.inputMethod.displayName)")
    }
    
    func selectCodeTable(_ table: CodeTable) {
        log("📋 selectCodeTable: setting to \(table.displayName)")
        
        currentCodeTable = table
        keyboardHandler?.codeTable = table
        
        // Save to preferences
        var prefs = PreferencesManager.shared.loadPreferences()
        prefs.codeTable = table
        PreferencesManager.shared.savePreferences(prefs)
        
        log("✅ CodeTable set to \(table.displayName)")
    }
    
    func openPreferences() {
        onOpenPreferences?()
    }
    
    func openMacroManagement() {
        onOpenMacroManagement?()
    }
    
    func openConvertTool() {
        onOpenConvertTool?()
    }
    
    func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateHotkeyDisplay(_ hotkey: Hotkey? = nil) {
        let hotkeyToUse = hotkey ?? PreferencesManager.shared.loadPreferences().toggleHotkey
        
        // Update display string
        hotkeyDisplay = hotkeyToUse.displayString
        
        // Convert to SwiftUI KeyEquivalent and EventModifiers
        hotkeyKeyEquivalent = keyCodeToKeyEquivalent(hotkeyToUse.keyCode)
        hotkeyModifiers = modifierFlagsToEventModifiers(hotkeyToUse.modifiers)
    }
    
    private func keyCodeToKeyEquivalent(_ keyCode: UInt16) -> KeyEquivalent {
        let mapping: [UInt16: KeyEquivalent] = [
            0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
            0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
            0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
            0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
            0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
            0x06: "z",
            0x31: " "
        ]
        return mapping[keyCode] ?? "v"
    }
    
    private func modifierFlagsToEventModifiers(_ flags: ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
