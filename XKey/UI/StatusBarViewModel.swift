//
//  StatusBarViewModel.swift
//  XKey
//
//  ViewModel for Status Bar
//

import SwiftUI
import Combine
import Cocoa

class StatusBarViewModel: ObservableObject {
    @Published var isVietnameseEnabled = true
    @Published var currentInputMethod: InputMethod = .telex
    @Published var currentCodeTable: CodeTable = .unicode
    @Published var hotkeyDisplay = "⌘⇧V"
    @Published var hotkeyKeyEquivalent: KeyEquivalent = "v"
    @Published var hotkeyModifiers: EventModifiers = [.command, .shift]
    @Published var debugModeEnabled = false
    
    private weak var keyboardHandler: KeyboardEventHandler?
    private weak var eventTapManager: EventTapManager?
    
    // Debug logging callback
    var debugLogCallback: ((String) -> Void)?
    
    var onOpenPreferences: (() -> Void)?
    var onOpenMacroManagement: (() -> Void)?
    var onOpenConvertTool: (() -> Void)?
    var onOpenDebugWindow: (() -> Void)?
    var onToggleDebugWindow: (() -> Void)?  // Toggle open/close debug window
    
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
        debugLogCallback?(message)
    }
    
    func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        keyboardHandler?.setVietnamese(isVietnameseEnabled)
        log("Vietnamese toggled: \(isVietnameseEnabled ? "ON" : "OFF")")
        
        // Play beep sound if enabled
        // Using AudioManager to handle wake-from-sleep audio routing issues
        let prefs = SharedSettings.shared.loadPreferences()
        if prefs.beepOnToggle {
            AudioManager.shared.playBeep()
        }
        
        // Save language for current app (Smart Switch)
        saveLanguageForCurrentApp()
    }
    
    /// Save current language for the active app (for Smart Switch feature)
    private func saveLanguageForCurrentApp() {
        guard let handler = keyboardHandler else { return }
        guard handler.smartSwitchEnabled else { return }

        // Check if overlay app detection is enabled
        let prefs = SharedSettings.shared.loadPreferences()
        if prefs.detectOverlayApps {
            // Check if an overlay app (Spotlight/Raycast/Alfred) is currently visible
            if OverlayAppDetector.shared.isOverlayAppVisible() {
                if let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() {
                    log("Smart Switch: Skipping save (overlay app '\(overlayName)' is active)")
                } else {
                    log("Smart Switch: Skipping save (overlay app detected)")
                }
                // Don't save language preference when overlay is active
                // This prevents overwriting the underlying app's language setting
                return
            }
        }

        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        let language = isVietnameseEnabled ? 1 : 0
        handler.engine.saveAppLanguage(bundleId: bundleId, language: language)
        log("📝 Smart Switch: Saved '\(bundleId)' → \(isVietnameseEnabled ? "Vietnamese" : "English")")
    }
    
    func selectInputMethod(_ method: InputMethod) {
        log("📋 selectInputMethod: BEFORE=\(currentInputMethod.displayName), setting to \(method.displayName)")
        
        currentInputMethod = method
        
        log("📋 selectInputMethod: AFTER=\(currentInputMethod.displayName)")
        
        if let handler = keyboardHandler {
            handler.inputMethod = method
            log("Set handler.inputMethod to \(method.displayName)")
        } else {
            log("keyboardHandler is nil!")
        }
        
        // Save to preferences
        var prefs = SharedSettings.shared.loadPreferences()
        prefs.inputMethod = method
        SharedSettings.shared.savePreferences(prefs)

        // Verify saved
        let savedPrefs = SharedSettings.shared.loadPreferences()
        log("📋 Saved to prefs, verified: \(savedPrefs.inputMethod.displayName)")
    }
    
    func selectCodeTable(_ table: CodeTable) {
        log("📋 selectCodeTable: setting to \(table.displayName)")
        
        currentCodeTable = table
        keyboardHandler?.codeTable = table
        
        // Save to preferences
        var prefs = SharedSettings.shared.loadPreferences()
        prefs.codeTable = table
        SharedSettings.shared.savePreferences(prefs)
        
        log("CodeTable set to \(table.displayName)")
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
    
    func openDebugWindow() {
        onOpenDebugWindow?()
    }
    
    func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateHotkeyDisplay(_ hotkey: Hotkey? = nil) {
        let hotkeyToUse = hotkey ?? SharedSettings.shared.loadPreferences().toggleHotkey
        
        // Update display string
        hotkeyDisplay = hotkeyToUse.displayString
        
        // For modifier-only hotkeys, don't set keyEquivalent (menu won't show shortcut)
        if hotkeyToUse.isModifierOnly {
            hotkeyKeyEquivalent = KeyEquivalent("\0")  // Null character - no key equivalent
        } else {
            hotkeyKeyEquivalent = keyCodeToKeyEquivalent(hotkeyToUse.keyCode)
        }
        hotkeyModifiers = modifierFlagsToEventModifiers(hotkeyToUse.modifiers)
    }
    
    private func keyCodeToKeyEquivalent(_ keyCode: UInt16) -> KeyEquivalent {
        // Use shared letter map, converting Character → KeyEquivalent
        if let letter = KeyCodeToCharacter.keyCodeToLetterMap[keyCode] {
            return KeyEquivalent(letter)
        }
        // Space key
        if keyCode == 0x31 { return " " }
        return "v"  // Default fallback
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
