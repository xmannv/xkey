//
//  Preferences.swift
//  XKey
//
//  User preferences and settings
//

import Foundation
import Cocoa

struct Preferences: Codable {
    // Hotkey settings
    var toggleHotkey: Hotkey = Hotkey(keyCode: 9, modifiers: [.command, .shift]) // Default: Cmd+Shift+V
    
    // Input settings
    var inputMethod: InputMethod = .telex
    var codeTable: CodeTable = .unicode
    var modernStyle: Bool = true
    var spellCheckEnabled: Bool = false
    var fixAutocomplete: Bool = true
    
    // Advanced features
    var quickTelexEnabled: Bool = true           // cc→ch, gg→gi, etc.
    var quickStartConsonantEnabled: Bool = false // f→ph, j→gi, w→qu
    var quickEndConsonantEnabled: Bool = false   // g→ng, h→nh, k→ch
    var upperCaseFirstChar: Bool = false         // Auto capitalize first letter
    var restoreIfWrongSpelling: Bool = true      // Restore if wrong spelling
    var allowConsonantZFWJ: Bool = false         // Allow Z, F, W, J consonants
    var freeMarkEnabled: Bool = false            // Free mark placement (đặt dấu tự do)
    var tempOffSpellingEnabled: Bool = false     // Temp off spelling with Ctrl key
    var tempOffEngineEnabled: Bool = false       // Temp off engine with Option key
    
    // Macro settings
    var macroEnabled: Bool = false               // Enable text shortcuts
    var macroInEnglishMode: Bool = false         // Use macro in English mode
    var autoCapsMacro: Bool = false              // Auto capitalize macro output
    
    // Smart switch settings
    var smartSwitchEnabled: Bool = false         // Remember language per app
    
    // Debug settings
    var debugModeEnabled: Bool = false           // Show debug window (even in production)
    
    // UI settings
    var showStatusBarIcon: Bool = true
    var startAtLogin: Bool = false
}

struct Hotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: ModifierFlags
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        // Convert keyCode to character
        if let char = keyCodeToCharacter(keyCode) {
            parts.append(char.uppercased())
        } else {
            parts.append("?")
        }
        
        return parts.joined()
    }
    
    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let mapping: [UInt16: String] = [
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
            0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
            0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O",
            0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
            0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y",
            0x06: "Z",
            0x31: "Space", 0x24: "Return", 0x35: "Esc"
        ]
        return mapping[keyCode]
    }
}

struct ModifierFlags: OptionSet, Codable {
    let rawValue: UInt
    
    static let control = ModifierFlags(rawValue: 1 << 0)
    static let option = ModifierFlags(rawValue: 1 << 1)
    static let shift = ModifierFlags(rawValue: 1 << 2)
    static let command = ModifierFlags(rawValue: 1 << 3)
    
    init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    init(from eventFlags: NSEvent.ModifierFlags) {
        var flags: ModifierFlags = []
        if eventFlags.contains(.control) { flags.insert(.control) }
        if eventFlags.contains(.option) { flags.insert(.option) }
        if eventFlags.contains(.shift) { flags.insert(.shift) }
        if eventFlags.contains(.command) { flags.insert(.command) }
        self = flags
    }
}
