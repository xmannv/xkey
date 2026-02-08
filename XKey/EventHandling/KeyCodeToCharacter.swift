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
        // Without Shift
        let normalMap: [UInt16: Character] = [
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
        
        // With Shift
        let shiftMap: [UInt16: Character] = [
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
        
        if withShift {
            return shiftMap[keyCode]
        } else {
            return normalMap[keyCode]
        }
    }
    
    /// Shared QWERTY keyCode → lowercase letter mapping (26 keys)
    /// Used by MacroManager, StatusBarViewModel, and others
    static let keyCodeToLetterMap: [UInt16: Character] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
        0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
        0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
        0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
        0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
        0x06: "z"
    ]
    
    /// Get the lowercase QWERTY letter for a key code, or nil if not a letter
    static func qwertyLetter(keyCode: UInt16) -> Character? {
        return keyCodeToLetterMap[keyCode]
    }

    /// Convert a character to its QWERTY key code
    /// This is needed to support non-QWERTY keyboard layouts (QWERTZ, AZERTY, etc.)
    /// - Parameter character: The character to convert
    /// - Returns: The QWERTY key code for the character, or nil if not found
    static func keyCode(forCharacter character: Character) -> UInt16? {
        // Normalize to lowercase for lookup
        let lowerChar = character.lowercased().first ?? character

        // Reverse mapping: character → QWERTY keyCode
        let characterToKeyCode: [Character: UInt16] = [
            // Letters
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
            "z": 0x06,

            // Numbers
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
            "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,

            // Special characters (unshifted)
            "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E, ";": 0x29,
            "'": 0x27, "\\": 0x2A, ",": 0x2B, ".": 0x2F, "/": 0x2C,
            " ": 0x31, "`": 0x32,

            // Special characters (shifted - check these too)
            "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15, "%": 0x17,
            "^": 0x16, "&": 0x1A, "*": 0x1C, "(": 0x19, ")": 0x1D,
            "_": 0x1B, "+": 0x18, "{": 0x21, "}": 0x1E, ":": 0x29,
            "\"": 0x27, "|": 0x2A, "<": 0x2B, ">": 0x2F, "?": 0x2C,
            "~": 0x32
        ]

        return characterToKeyCode[lowerChar]
    }
}
