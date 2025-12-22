//
//  MacroManager.swift
//  XKey
//
//  Macro management - Ported from OpenKey Macro.cpp
//

import Foundation

/// Manages text expansion macros (e.g., "btw" → "by the way")
class MacroManager {
    
    // MARK: - Types
    
    struct MacroData {
        let macroText: String        // e.g., "btw"
        let macroContent: String     // e.g., "by the way"
        var macroContentCode: [UInt32]  // Converted codes
    }
    
    // MARK: - Properties
    
    private var macroMap: [[UInt32]: MacroData] = [:]
    private var vCodeTable: Int = 0
    private var vAutoCapsMacro: Bool = false
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Configuration
    
    func setCodeTable(_ codeTable: Int) {
        self.vCodeTable = codeTable
        // Reload all macro content codes when code table changes
        onTableCodeChange()
    }
    
    func setAutoCapsMacro(_ enabled: Bool) {
        self.vAutoCapsMacro = enabled
    }
    
    // MARK: - Macro Management
    
    /// Add or update a macro
    func addMacro(text: String, content: String) -> Bool {
        let key = convertStringToKey(text)
        let contentCode = convertStringToCode(content)
        
        macroMap[key] = MacroData(
            macroText: text,
            macroContent: content,
            macroContentCode: contentCode
        )
        
        return true
    }
    
    /// Delete a macro
    func deleteMacro(text: String) -> Bool {
        let key = convertStringToKey(text)
        if macroMap[key] != nil {
            macroMap.removeValue(forKey: key)
            return true
        }
        return false
    }
    
    /// Check if macro exists
    func hasMacro(text: String) -> Bool {
        let key = convertStringToKey(text)
        return macroMap[key] != nil
    }
    
    /// Logging callback for debug
    var logCallback: ((String) -> Void)?
    
    /// Find macro by key and return content
    func findMacro(key: [UInt32]) -> [UInt32]? {
        // Convert key to character codes
        let searchKey = key.map { getCharacterCode($0) }

        // Debug logging - detailed information about key comparison
        let keyStr = key.map { String(format: "0x%X", $0) }.joined(separator: ", ")
        let searchKeyStr = searchKey.map { String(format: "0x%X ('%@')", $0, String(UnicodeScalar($0) ?? UnicodeScalar(0))) }.joined(separator: ", ")
        logCallback?("🔍 MacroManager.findMacro:")
        logCallback?("🔍   input key (raw): [\(keyStr)]")
        logCallback?("🔍   searchKey (converted): [\(searchKeyStr)]")
        logCallback?("🔍   macroMap has \(macroMap.count) macros")

        // Debug: show all stored macros with their keys
        for (storedKey, macro) in macroMap {
            let storedKeyStr = storedKey.map { String(format: "0x%X ('%@')", $0, String(UnicodeScalar($0) ?? UnicodeScalar(0))) }.joined(separator: ", ")
            logCallback?("🔍   - Stored: key=[\(storedKeyStr)] text='\(macro.macroText)'")
            
            // Compare keys element by element
            if storedKey.count == searchKey.count {
                var matches = true
                for i in 0..<storedKey.count {
                    if storedKey[i] != searchKey[i] {
                        matches = false
                        logCallback?("🔍     ↳ Mismatch at index \(i): stored=0x\(String(format: "%X", storedKey[i])) vs search=0x\(String(format: "%X", searchKey[i]))")
                        break
                    }
                }
                if matches {
                    logCallback?("🔍     ↳ ALL ELEMENTS MATCH!")
                }
            } else {
                logCallback?("🔍     ↳ Length mismatch: stored=\(storedKey.count) vs search=\(searchKey.count)")
            }
        }

        // Try exact match first
        if let macro = macroMap[searchKey] {
            logCallback?("🔍 MacroManager.findMacro: FOUND exact match! text='\(macro.macroText)', content='\(macro.macroContent)'")
            return macro.macroContentCode
        }
        
        // Try with auto caps if enabled
        if vAutoCapsMacro && !searchKey.isEmpty {
            // Check if first character is uppercase
            let firstCharWasUppercase = isUppercaseChar(searchKey[0])
            
            // Check if ALL characters are uppercase (for ALL CAPS case like "BTW")
            var allCapsFlag = true
            for i in 0..<searchKey.count {
                if !isUppercaseChar(searchKey[i]) {
                    allCapsFlag = false
                    break
                }
            }
            
            // Convert all characters to lowercase for search
            var lowercaseKey = searchKey
            for i in 0..<lowercaseKey.count {
                _ = modifyCaseUnicode(&lowercaseKey[i], isUpperCase: false)
            }
            
            // Try to find macro with lowercase key
            if let macro = macroMap[lowercaseKey] {
                var result = macro.macroContentCode
                
                // Apply caps to result based on input case
                if allCapsFlag {
                    // ALL CAPS input -> ALL CAPS output
                    for i in 0..<result.count {
                        _ = modifyCaseUnicode(&result[i], isUpperCase: true)
                    }
                } else if firstCharWasUppercase {
                    // First char uppercase -> capitalize first char of result
                    if !result.isEmpty {
                        _ = modifyCaseUnicode(&result[0], isUpperCase: true)
                    }
                }
                
                return result
            }
        }
        
        return nil
    }
    
    /// Check if a character code represents an uppercase letter
    private func isUppercaseChar(_ code: UInt32) -> Bool {
        let charValue = code & 0xFFFF
        if let scalar = UnicodeScalar(charValue) {
            let char = Character(scalar)
            return char.isUppercase
        }
        return false
    }
    
    /// Get all macros
    func getAllMacros() -> [(key: [UInt32], text: String, content: String)] {
        return macroMap.map { (key: $0.key, text: $0.value.macroText, content: $0.value.macroContent) }
    }
    
    /// Clear all macros
    func clearAll() {
        macroMap.removeAll()
    }
    
    // MARK: - File I/O
    
    /// Save macros to file
    func saveToFile(path: String) -> Bool {
        var content = ";Compatible OpenKey Macro Data file for UniKey*** version=1 ***\n"
        
        for (_, macro) in macroMap {
            content += "\(macro.macroText):\(macro.macroContent)\n"
        }
        
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            logCallback?("Error saving macros: \(error)")
            return false
        }
    }
    
    /// Load macros from file
    func loadFromFile(path: String, append: Bool = true) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        
        if !append {
            macroMap.removeAll()
        }
        
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            // Skip first line (header)
            if index == 0 { continue }
            
            // Skip empty lines
            if line.isEmpty { continue }
            
            // Parse line: "text:content"
            if let colonIndex = line.firstIndex(of: ":") {
                var text = String(line[..<colonIndex])
                var content = String(line[line.index(after: colonIndex)...])
                
                // Handle multiple colons in content
                while text.isEmpty && !content.isEmpty {
                    if let nextColon = content.firstIndex(of: ":") {
                        text += ":" + String(content[..<nextColon])
                        content = String(content[content.index(after: nextColon)...])
                    } else {
                        break
                    }
                }
                
                if !text.isEmpty && !hasMacro(text: text) {
                    _ = addMacro(text: text, content: content)
                }
            }
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    private func convertStringToKey(_ str: String) -> [UInt32] {
        var result: [UInt32] = []
        
        for char in str {
            let scalar = char.unicodeScalars.first!.value
            // Simple conversion - can be enhanced
            result.append(UInt32(scalar))
        }
        
        return result
    }
    
    private func convertStringToCode(_ str: String) -> [UInt32] {
        var result: [UInt32] = []
        
        for char in str {
            let scalar = char.unicodeScalars.first!.value
            result.append(UInt32(scalar) | 0x2000000) // Mark as character code
        }
        
        return result
    }
    
    private func getCharacterCode(_ data: UInt32) -> UInt32 {
        // Check if it's already a character code (has 0x2000000 flag)
        if (data & 0x2000000) != 0 {
            return data & 0xFFFF
        }
        
        // It's a keyCode - convert to character
        // Note: data may contain VNEngine masks (TONE_MASK, MARK_MASK, etc.)
        // We only care about the lower 16 bits for keyCode
        let keyCode = UInt16(data & 0xFFFF)
        let isCaps = (data & 0x10000) != 0  // CAPS_MASK
        
        // KeyCode to character mapping (macOS virtual key codes)
        let keyCodeToChar: [UInt16: Character] = [
            0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
            0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
            0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
            0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
            0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
            0x06: "z",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
            0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
            // Special characters
            0x32: "`",  // KEY_BACKQUOTE (tilde ~ with Shift)
            0x1B: "-",  // KEY_MINUS
            0x18: "=",  // KEY_EQUALS
            0x21: "[",  // KEY_LEFT_BRACKET
            0x1E: "]",  // KEY_RIGHT_BRACKET
            0x2A: "\\", // KEY_BACK_SLASH
            0x29: ";",  // KEY_SEMICOLON
            0x27: "'",  // KEY_QUOTE
            0x2B: ",",  // KEY_COMMA
            0x2F: ".",  // KEY_DOT
            0x2C: "/"   // KEY_SLASH
        ]
        
        if let char = keyCodeToChar[keyCode] {
            // Handle special characters with Shift modifier
            let charStr: String
            if isCaps {
                // Map shifted special characters
                switch keyCode {
                case 0x32: charStr = "~"  // Shift + ` → ~
                case 0x12: charStr = "!"  // Shift + 1 → !
                case 0x13: charStr = "@"  // Shift + 2 → @
                case 0x14: charStr = "#"  // Shift + 3 → #
                case 0x15: charStr = "$"  // Shift + 4 → $
                case 0x17: charStr = "%"  // Shift + 5 → %
                case 0x16: charStr = "^"  // Shift + 6 → ^
                case 0x1A: charStr = "&"  // Shift + 7 → &
                case 0x1C: charStr = "*"  // Shift + 8 → *
                case 0x19: charStr = "("  // Shift + 9 → (
                case 0x1D: charStr = ")"  // Shift + 0 → )
                case 0x1B: charStr = "_"  // Shift + - → _
                case 0x18: charStr = "+"  // Shift + = → +
                case 0x21: charStr = "{"  // Shift + [ → {
                case 0x1E: charStr = "}"  // Shift + ] → }
                case 0x2A: charStr = "|"  // Shift + \ → |
                case 0x29: charStr = ":"  // Shift + ; → :
                case 0x27: charStr = "\"" // Shift + ' → "
                case 0x2B: charStr = "<"  // Shift + , → <
                case 0x2F: charStr = ">"  // Shift + . → >
                case 0x2C: charStr = "?"  // Shift + / → ?
                default:
                    charStr = String(char).uppercased()
                }
            } else {
                charStr = String(char)
            }

            if let scalar = charStr.unicodeScalars.first {
                return UInt32(scalar.value)
            }
        }
        
        logCallback?("⚠️ getCharacterCode: Unknown keyCode=0x\(String(format: "%X", keyCode)) from data=0x\(String(format: "%X", data))")
        
        // Fallback - return as is
        return data & 0xFFFF
    }
    
    private func modifyCaseUnicode(_ code: inout UInt32, isUpperCase: Bool) -> Bool {
        let charBuff = code
        
        // Get the actual character value (remove any flags)
        let charValue = code & 0xFFFF
        
        // Convert to character and change case
        if let scalar = UnicodeScalar(charValue) {
            let char = Character(scalar)
            let converted = isUpperCase ? char.uppercased() : char.lowercased()
            if let newScalar = converted.unicodeScalars.first {
                // Preserve the 0x2000000 flag if it was set
                let flags = code & 0xFFFF0000
                code = UInt32(newScalar.value) | flags
                return code != charBuff
            }
        }
        
        return false
    }
    
    private func onTableCodeChange() {
        // Reload all macro content codes
        for (key, var macro) in macroMap {
            macro.macroContentCode = convertStringToCode(macro.macroContent)
            macroMap[key] = macro
        }
    }
}
