//
//  KeyCodeToCharacter.swift
//  XKey
//
//  Converts macOS physical key codes to QWERTY character layout
//  This is needed to support non-QWERTY keyboards (QWERTZ, AZERTY, etc.)
//

import Foundation

/// Maps physical macOS key codes to their QWERTY character equivalents
/// This ensures Vietnamese typing works correctly regardless of keyboard layout
class KeyCodeToCharacter {
    
    /// Convert a physical key code to its QWERTY character
    /// Returns the character that would be typed on a US QWERTY keyboard
    /// - Parameters:
    ///   - keyCode: The physical key code from CGEvent
    ///   - withShift: Whether Shift/Caps Lock is applied
    /// - Returns: The character on a QWERTY layout, or nil if not a printable key
    static func qwertyCharacter(keyCode: UInt16, withShift: Bool = false) -> Character? {
        return withShift ? shiftMap[keyCode] : normalMap[keyCode]
    }
    
    // MARK: - QWERTY Layout Maps (includes non-printable keys for display)
    
    /// Unshifted QWERTY layout: keyCode → character
    private static let normalMap: [UInt16: Character] = [
        // Row 1 (numbers)
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
        
        // Row 1 special chars (top row)
        0x1B: "-",  // Minus
        0x18: "=",  // Equals
        
        // Row 2 (QWERTY)
        0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x11: "t",
        0x10: "y", 0x20: "u", 0x22: "i", 0x1F: "o", 0x23: "p",
        0x21: "[",  // Left bracket
        0x1E: "]",  // Right bracket
        
        // Row 3 (ASDF)
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x05: "g",
        0x04: "h", 0x26: "j", 0x28: "k", 0x25: "l",
        0x29: ";",  // Semicolon
        0x27: "'",  // Quote
        0x2A: "\\", // Backslash
        
        // Row 4 (ZXCV)
        0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b",
        0x2D: "n", 0x2E: "m",
        0x2B: ",",  // Comma
        0x2F: ".",  // Period
        0x2C: "/",  // Slash
        
        // Special keys
        0x31: " ",     // Space
        0x32: "`",     // Backtick/Grave
        0x24: "\r",    // Return/Enter
        0x33: "\u{08}", // Backspace/Delete
        0x30: "\t",    // Tab
        0x35: "\u{1B}", // Escape
        0x75: "\u{7F}", // Forward Delete (Fn+Delete)

        // Arrow keys
        0x7B: "\u{2190}", // Left Arrow ←
        0x7C: "\u{2192}", // Right Arrow →
        0x7D: "\u{2193}", // Down Arrow ↓
        0x7E: "\u{2191}", // Up Arrow ↑

        // Navigation keys
        0x73: "\u{2196}", // Home ↖
        0x77: "\u{2198}", // End ↘
        0x74: "\u{21DE}", // Page Up ⇞
        0x79: "\u{21DF}"  // Page Down ⇟
    ]
    
    /// Shifted QWERTY layout: keyCode → character (with Shift/Caps)
    private static let shiftMap: [UInt16: Character] = [
        // Row 1 (shifted numbers → special chars)
        0x12: "!", 0x13: "@", 0x14: "#", 0x15: "$", 0x17: "%",
        0x16: "^", 0x1A: "&", 0x1C: "*", 0x19: "(", 0x1D: ")",
        
        // Row 1 special chars (shifted)
        0x1B: "_",  // Minus → Underscore
        0x18: "+",  // Equals → Plus
        
        // Row 2 (QWERTY - uppercase)
        0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x11: "T",
        0x10: "Y", 0x20: "U", 0x22: "I", 0x1F: "O", 0x23: "P",
        0x21: "{",  // [ → {
        0x1E: "}",  // ] → }
        
        // Row 3 (ASDF - uppercase)
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x05: "G",
        0x04: "H", 0x26: "J", 0x28: "K", 0x25: "L",
        0x29: ":",  // Semicolon → :
        0x27: "\"", // Quote → "
        0x2A: "|",  // \ → |
        
        // Row 4 (ZXCV - uppercase)
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B",
        0x2D: "N", 0x2E: "M",
        0x2B: "<",  // Comma → <
        0x2F: ">",  // Period → >
        0x2C: "?",  // Slash → ?
        
        // Special keys (shifted)
        0x31: " ",     // Space (unchanged)
        0x32: "~",     // ` → ~
        0x24: "\r",    // Return/Enter (unchanged)
        0x33: "\u{08}", // Backspace/Delete (unchanged)
        0x30: "\t",    // Tab (unchanged)
        0x35: "\u{1B}", // Escape (unchanged)
        0x75: "\u{7F}", // Forward Delete (unchanged)

        // Arrow keys (unchanged)
        0x7B: "\u{2190}", // Left Arrow ←
        0x7C: "\u{2192}", // Right Arrow →
        0x7D: "\u{2193}", // Down Arrow ↓
        0x7E: "\u{2191}", // Up Arrow ↑

        // Navigation keys (unchanged)
        0x73: "\u{2196}", // Home ↖
        0x77: "\u{2198}", // End ↘
        0x74: "\u{21DE}", // Page Up ⇞
        0x79: "\u{21DF}"  // Page Down ⇟
    ]
    
    /// Shared QWERTY keyCode → lowercase letter mapping (26 keys)
    /// Delegates to VietnameseData's single source of truth.
    static let keyCodeToLetterMap: [UInt16: Character] = VietnameseData.keyCodeToLetterMap
    
    /// Get the lowercase QWERTY letter for a key code, or nil if not a letter
    static func qwertyLetter(keyCode: UInt16) -> Character? {
        return VietnameseData.keyCodeToLetterMap[keyCode]
    }

    /// Convert a character to its QWERTY key code
    /// This is needed to support non-QWERTY keyboard layouts (QWERTZ, AZERTY, etc.)
    /// Delegates to VietnameseData for base mapping, adds shifted character support.
    /// - Parameter character: The character to convert
    /// - Returns: The QWERTY key code for the character, or nil if not found
    static func keyCode(forCharacter character: Character) -> UInt16? {
        // Try the canonical mapping first (covers letters, numbers, unshifted special chars)
        if let code = VietnameseData.keyCode(for: character) {
            return code
        }
        
        // Shifted characters map to the same physical key as their unshifted counterpart
        return shiftedCharacterToKeyCode[character]
    }
    
    /// Mapping for shifted characters that aren't in the base characterToKeyCodeMap.
    /// These characters share the same physical key as their unshifted counterpart.
    private static let shiftedCharacterToKeyCode: [Character: UInt16] = [
        "!": VietnameseData.KEY_1, "@": VietnameseData.KEY_2,
        "#": VietnameseData.KEY_3, "$": VietnameseData.KEY_4,
        "%": VietnameseData.KEY_5, "^": VietnameseData.KEY_6,
        "&": VietnameseData.KEY_7, "*": VietnameseData.KEY_8,
        "(": VietnameseData.KEY_9, ")": VietnameseData.KEY_0,
        "_": VietnameseData.KEY_MINUS, "+": VietnameseData.KEY_EQUALS,
        "{": VietnameseData.KEY_LEFT_BRACKET, "}": VietnameseData.KEY_RIGHT_BRACKET,
        ":": VietnameseData.KEY_SEMICOLON, "\"": VietnameseData.KEY_QUOTE,
        "|": VietnameseData.KEY_BACK_SLASH, "<": VietnameseData.KEY_COMMA,
        ">": VietnameseData.KEY_DOT, "?": VietnameseData.KEY_SLASH,
        "~": VietnameseData.KEY_BACKQUOTE
    ]
}
