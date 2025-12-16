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
        var contentCode = convertStringToCode(content)
        
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
    
    /// Find macro by key and return content
    func findMacro(key: [UInt32]) -> [UInt32]? {
        // Convert key to character codes
        var searchKey = key.map { getCharacterCode($0) }
        
        // Debug: print search key as string
        let searchStr = searchKey.compactMap { UnicodeScalar($0) }.map { String(Character($0)) }.joined()
        print("MacroManager.findMacro: searching for '\(searchStr)' (codes: \(searchKey))")
        print("MacroManager: available macros: \(macroMap.keys.map { $0.compactMap { UnicodeScalar($0) }.map { String(Character($0)) }.joined() })")
        
        // Try exact match first
        if let macro = macroMap[searchKey] {
            print("MacroManager: FOUND macro!")
            return macro.macroContentCode
        }
        
        // Try with auto caps if enabled
        if vAutoCapsMacro {
            var allCapsFlag = false
            
            // Check if second character onwards are uppercase
            if searchKey.count > 1 {
                allCapsFlag = modifyCaseUnicode(&searchKey[1], isUpperCase: false)
                for i in 2..<searchKey.count {
                    _ = modifyCaseUnicode(&searchKey[i], isUpperCase: false)
                }
            }
            
            // Convert first character to lowercase
            if searchKey.count > 0 {
                if modifyCaseUnicode(&searchKey[0], isUpperCase: false) {
                    // Found macro with lowercase
                    if let macro = macroMap[searchKey] {
                        var result = macro.macroContentCode
                        
                        // Apply caps to result
                        for i in 0..<result.count {
                            if i == 0 || allCapsFlag {
                                _ = modifyCaseUnicode(&result[i], isUpperCase: true)
                            }
                        }
                        
                        return result
                    }
                }
            }
        }
        
        return nil
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
            print("Error saving macros: \(error)")
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
            0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0"
        ]
        
        if let char = keyCodeToChar[keyCode] {
            let charStr = isCaps ? String(char).uppercased() : String(char)
            if let scalar = charStr.unicodeScalars.first {
                return UInt32(scalar.value)
            }
        }
        
        // Fallback - return as is
        return data & 0xFFFF
    }
    
    private func modifyCaseUnicode(_ code: inout UInt32, isUpperCase: Bool) -> Bool {
        let charBuff = code
        
        if (code & 0x2000000) == 0 {
            // Normal char
            if isUpperCase {
                code |= 0x10000  // CAPS_MASK
            } else {
                code &= ~0x10000
            }
            return code != charBuff
        }
        
        // Unicode character - simple case conversion
        let charValue = code & 0xFFFF
        if let scalar = UnicodeScalar(charValue) {
            let char = Character(scalar)
            let converted = isUpperCase ? char.uppercased() : char.lowercased()
            if let newScalar = converted.unicodeScalars.first {
                code = UInt32(newScalar.value) | 0x2000000
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
