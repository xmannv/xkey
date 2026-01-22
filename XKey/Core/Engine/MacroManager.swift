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
    
    // MARK: - Vietnamese Mask Constants (matching VNEngine)
    
    private static let CAPS_MASK: UInt32      = 0x10000
    private static let TONE_MASK: UInt32      = 0x20000     // Circumflex (â, ê, ô)
    private static let TONEW_MASK: UInt32     = 0x40000     // Breve/Horn (ă, ơ, ư)
    private static let MARK1_MASK: UInt32     = 0x80000     // Sắc
    private static let MARK2_MASK: UInt32     = 0x100000    // Huyền
    private static let MARK3_MASK: UInt32     = 0x200000    // Hỏi
    private static let MARK4_MASK: UInt32     = 0x400000    // Ngã
    private static let MARK5_MASK: UInt32     = 0x800000    // Nặng
    private static let MARK_MASK: UInt32      = 0xF80000
    private static let CHAR_CODE_MASK: UInt32 = 0x2000000   // Already Unicode character
    
    // Vietnamese vowel key codes (macOS virtual key codes)
    private static let KEY_A: UInt16 = 0x00
    private static let KEY_E: UInt16 = 0x0E
    private static let KEY_I: UInt16 = 0x22
    private static let KEY_O: UInt16 = 0x1F
    private static let KEY_U: UInt16 = 0x20
    private static let KEY_Y: UInt16 = 0x10
    private static let KEY_D: UInt16 = 0x02
    
    /// Vietnamese vowel Unicode mapping: vowelKey -> [hasTone][hasToneW][markIndex] -> (lowercase, uppercase)
    /// This allows converting internal Vietnamese data to proper Unicode characters
    private static let vietnameseUnicodeMap: [UInt16: [[[UInt32]]]] = {
        // Mark index: 0=none, 1=sắc, 2=huyền, 3=hỏi, 4=ngã, 5=nặng
        // Format: [hasTone=false][hasToneW=false/true][markIndex] or [hasTone=true][hasToneW=false][markIndex]
        
        // Helper to create tone array: [none, sắc, huyền, hỏi, ngã, nặng] x [lowercase, uppercase]
        func toneArray(_ chars: [(UInt32, UInt32)]) -> [UInt32] {
            // Return lowercase values only, uppercase will be calculated by shifting
            return chars.map { $0.0 }
        }
        
        return [
            // A: base, â (tone), ă (toneW)
            KEY_A: [
                // hasTone = false
                [
                    // hasToneW = false: plain A
                    [0x0061, 0x00E1, 0x00E0, 0x1EA3, 0x00E3, 0x1EA1],  // a, á, à, ả, ã, ạ
                    // hasToneW = true: Ă
                    [0x0103, 0x1EAF, 0x1EB1, 0x1EB3, 0x1EB5, 0x1EB7]   // ă, ắ, ằ, ẳ, ẵ, ặ
                ],
                // hasTone = true
                [
                    // hasToneW = false: Â
                    [0x00E2, 0x1EA5, 0x1EA7, 0x1EA9, 0x1EAB, 0x1EAD],  // â, ấ, ầ, ẩ, ẫ, ậ
                    // hasToneW = true: (not used, same as ă)
                    [0x0103, 0x1EAF, 0x1EB1, 0x1EB3, 0x1EB5, 0x1EB7]
                ]
            ],
            // E: base, ê (tone)
            KEY_E: [
                // hasTone = false
                [
                    // hasToneW = false: plain E
                    [0x0065, 0x00E9, 0x00E8, 0x1EBB, 0x1EBD, 0x1EB9],  // e, é, è, ẻ, ẽ, ẹ
                    // hasToneW = true: (not applicable for E)
                    [0x0065, 0x00E9, 0x00E8, 0x1EBB, 0x1EBD, 0x1EB9]
                ],
                // hasTone = true
                [
                    // hasToneW = false: Ê
                    [0x00EA, 0x1EBF, 0x1EC1, 0x1EC3, 0x1EC5, 0x1EC7],  // ê, ế, ề, ể, ễ, ệ
                    // hasToneW = true: (not applicable)
                    [0x00EA, 0x1EBF, 0x1EC1, 0x1EC3, 0x1EC5, 0x1EC7]
                ]
            ],
            // I: base only
            KEY_I: [
                [
                    [0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB],  // i, í, ì, ỉ, ĩ, ị
                    [0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB]
                ],
                [
                    [0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB],
                    [0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB]
                ]
            ],
            // O: base, ô (tone), ơ (toneW)
            KEY_O: [
                // hasTone = false
                [
                    // hasToneW = false: plain O
                    [0x006F, 0x00F3, 0x00F2, 0x1ECF, 0x00F5, 0x1ECD],  // o, ó, ò, ỏ, õ, ọ
                    // hasToneW = true: Ơ
                    [0x01A1, 0x1EDB, 0x1EDD, 0x1EDF, 0x1EE1, 0x1EE3]   // ơ, ớ, ờ, ở, ỡ, ợ
                ],
                // hasTone = true
                [
                    // hasToneW = false: Ô
                    [0x00F4, 0x1ED1, 0x1ED3, 0x1ED5, 0x1ED7, 0x1ED9],  // ô, ố, ồ, ổ, ỗ, ộ
                    // hasToneW = true: (Ơ takes precedence)
                    [0x01A1, 0x1EDB, 0x1EDD, 0x1EDF, 0x1EE1, 0x1EE3]
                ]
            ],
            // U: base, ư (toneW)
            KEY_U: [
                // hasTone = false
                [
                    // hasToneW = false: plain U
                    [0x0075, 0x00FA, 0x00F9, 0x1EE7, 0x0169, 0x1EE5],  // u, ú, ù, ủ, ũ, ụ
                    // hasToneW = true: Ư
                    [0x01B0, 0x1EE9, 0x1EEB, 0x1EED, 0x1EEF, 0x1EF1]   // ư, ứ, ừ, ử, ữ, ự
                ],
                // hasTone = true
                [
                    // hasToneW = false: plain U (no circumflex U in Vietnamese)
                    [0x0075, 0x00FA, 0x00F9, 0x1EE7, 0x0169, 0x1EE5],
                    // hasToneW = true: Ư
                    [0x01B0, 0x1EE9, 0x1EEB, 0x1EED, 0x1EEF, 0x1EF1]
                ]
            ],
            // Y: base only
            KEY_Y: [
                [
                    [0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5],  // y, ý, ỳ, ỷ, ỹ, ỵ
                    [0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5]
                ],
                [
                    [0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5],
                    [0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5]
                ]
            ]
        ]
    }()
    
    /// Uppercase offset map for Vietnamese characters
    /// Maps lowercase Unicode to uppercase Unicode
    private static let uppercaseMap: [UInt32: UInt32] = {
        var map: [UInt32: UInt32] = [:]
        
        // A variants
        map[0x0061] = 0x0041  // a → A
        map[0x00E1] = 0x00C1  // á → Á
        map[0x00E0] = 0x00C0  // à → À
        map[0x1EA3] = 0x1EA2  // ả → Ả
        map[0x00E3] = 0x00C3  // ã → Ã
        map[0x1EA1] = 0x1EA0  // ạ → Ạ
        map[0x00E2] = 0x00C2  // â → Â
        map[0x1EA5] = 0x1EA4  // ấ → Ấ
        map[0x1EA7] = 0x1EA6  // ầ → Ầ
        map[0x1EA9] = 0x1EA8  // ẩ → Ẩ
        map[0x1EAB] = 0x1EAA  // ẫ → Ẫ
        map[0x1EAD] = 0x1EAC  // ậ → Ậ
        map[0x0103] = 0x0102  // ă → Ă
        map[0x1EAF] = 0x1EAE  // ắ → Ắ
        map[0x1EB1] = 0x1EB0  // ằ → Ằ
        map[0x1EB3] = 0x1EB2  // ẳ → Ẳ
        map[0x1EB5] = 0x1EB4  // ẵ → Ẵ
        map[0x1EB7] = 0x1EB6  // ặ → Ặ
        
        // E variants
        map[0x0065] = 0x0045  // e → E
        map[0x00E9] = 0x00C9  // é → É
        map[0x00E8] = 0x00C8  // è → È
        map[0x1EBB] = 0x1EBA  // ẻ → Ẻ
        map[0x1EBD] = 0x1EBC  // ẽ → Ẽ
        map[0x1EB9] = 0x1EB8  // ẹ → Ẹ
        map[0x00EA] = 0x00CA  // ê → Ê
        map[0x1EBF] = 0x1EBE  // ế → Ế
        map[0x1EC1] = 0x1EC0  // ề → Ề
        map[0x1EC3] = 0x1EC2  // ể → Ể
        map[0x1EC5] = 0x1EC4  // ễ → Ễ
        map[0x1EC7] = 0x1EC6  // ệ → Ệ
        
        // I variants
        map[0x0069] = 0x0049  // i → I
        map[0x00ED] = 0x00CD  // í → Í
        map[0x00EC] = 0x00CC  // ì → Ì
        map[0x1EC9] = 0x1EC8  // ỉ → Ỉ
        map[0x0129] = 0x0128  // ĩ → Ĩ
        map[0x1ECB] = 0x1ECA  // ị → Ị
        
        // O variants
        map[0x006F] = 0x004F  // o → O
        map[0x00F3] = 0x00D3  // ó → Ó
        map[0x00F2] = 0x00D2  // ò → Ò
        map[0x1ECF] = 0x1ECE  // ỏ → Ỏ
        map[0x00F5] = 0x00D5  // õ → Õ
        map[0x1ECD] = 0x1ECC  // ọ → Ọ
        map[0x00F4] = 0x00D4  // ô → Ô
        map[0x1ED1] = 0x1ED0  // ố → Ố
        map[0x1ED3] = 0x1ED2  // ồ → Ồ
        map[0x1ED5] = 0x1ED4  // ổ → Ổ
        map[0x1ED7] = 0x1ED6  // ỗ → Ỗ
        map[0x1ED9] = 0x1ED8  // ộ → Ộ
        map[0x01A1] = 0x01A0  // ơ → Ơ
        map[0x1EDB] = 0x1EDA  // ớ → Ớ
        map[0x1EDD] = 0x1EDC  // ờ → Ờ
        map[0x1EDF] = 0x1EDE  // ở → Ở
        map[0x1EE1] = 0x1EE0  // ỡ → Ỡ
        map[0x1EE3] = 0x1EE2  // ợ → Ợ
        
        // U variants
        map[0x0075] = 0x0055  // u → U
        map[0x00FA] = 0x00DA  // ú → Ú
        map[0x00F9] = 0x00D9  // ù → Ù
        map[0x1EE7] = 0x1EE6  // ủ → Ủ
        map[0x0169] = 0x0168  // ũ → Ũ
        map[0x1EE5] = 0x1EE4  // ụ → Ụ
        map[0x01B0] = 0x01AF  // ư → Ư
        map[0x1EE9] = 0x1EE8  // ứ → Ứ
        map[0x1EEB] = 0x1EEA  // ừ → Ừ
        map[0x1EED] = 0x1EEC  // ử → Ử
        map[0x1EEF] = 0x1EEE  // ữ → Ữ
        map[0x1EF1] = 0x1EF0  // ự → Ự
        
        // Y variants
        map[0x0079] = 0x0059  // y → Y
        map[0x00FD] = 0x00DD  // ý → Ý
        map[0x1EF3] = 0x1EF2  // ỳ → Ỳ
        map[0x1EF7] = 0x1EF6  // ỷ → Ỷ
        map[0x1EF9] = 0x1EF8  // ỹ → Ỹ
        map[0x1EF5] = 0x1EF4  // ỵ → Ỵ
        
        // Đ
        map[0x0111] = 0x0110  // đ → Đ
        
        return map
    }()
    
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
    
    /// Public wrapper for getCharacterCode - converts internal data to Unicode character code
    /// Used by VNEngine.getMacroKeyAsString() for context-aware macro checking
    func getCharacterCodeForDisplay(_ data: UInt32) -> UInt32 {
        return getCharacterCode(data)
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

        // Try exact match first
        if let macro = macroMap[searchKey] {
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
        // Check if it's already a character code (has CHAR_CODE_MASK flag)
        if (data & MacroManager.CHAR_CODE_MASK) != 0 {
            return data & 0xFFFF
        }
        
        // Extract Vietnamese-related masks
        let keyCode = UInt16(data & 0xFFFF)
        let isCaps = (data & MacroManager.CAPS_MASK) != 0
        let hasTone = (data & MacroManager.TONE_MASK) != 0
        let hasToneW = (data & MacroManager.TONEW_MASK) != 0
        let markMask = data & MacroManager.MARK_MASK
        
        // Check for Đ/đ first (D with TONE_MASK)
        if keyCode == MacroManager.KEY_D && hasTone {
            let unicodeValue: UInt32 = isCaps ? 0x0110 : 0x0111  // Đ or đ
            return unicodeValue
        }
        
        // Check if this is a Vietnamese vowel with diacritics
        if let vowelMap = MacroManager.vietnameseUnicodeMap[keyCode] {
            // Determine mark index: 0=none, 1=sắc, 2=huyền, 3=hỏi, 4=ngã, 5=nặng
            let markIndex: Int
            switch markMask {
            case MacroManager.MARK1_MASK: markIndex = 1  // Sắc
            case MacroManager.MARK2_MASK: markIndex = 2  // Huyền
            case MacroManager.MARK3_MASK: markIndex = 3  // Hỏi
            case MacroManager.MARK4_MASK: markIndex = 4  // Ngã
            case MacroManager.MARK5_MASK: markIndex = 5  // Nặng
            default: markIndex = 0  // No mark
            }
            
            // Get Unicode value from map: [hasTone][hasToneW][markIndex]
            let toneIndex = hasTone ? 1 : 0
            let toneWIndex = hasToneW ? 1 : 0
            
            if toneIndex < vowelMap.count,
               toneWIndex < vowelMap[toneIndex].count,
               markIndex < vowelMap[toneIndex][toneWIndex].count {
                var unicodeValue = vowelMap[toneIndex][toneWIndex][markIndex]
                
                // Convert to uppercase if needed
                if isCaps, let uppercaseValue = MacroManager.uppercaseMap[unicodeValue] {
                    unicodeValue = uppercaseValue
                }
                
                return unicodeValue
            }
        }
        
        // Fallback: Basic keyCode to character mapping for consonants and special chars
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
        
        logCallback?("getCharacterCode: Unknown keyCode=0x\(String(format: "%X", keyCode)) from data=0x\(String(format: "%X", data))")
        
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
