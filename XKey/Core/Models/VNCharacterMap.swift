//
//  VNCharacterMap.swift
//  XKey
//
//  Vietnamese character Unicode mappings
//

import Foundation

struct VNCharacterMap {
    
    // MARK: - Unicode Mappings
    
    // Unicode values for Vietnamese characters
    // Format: [vowel][tone] = Unicode scalar
    private static let unicodeMap: [VNVowel: [VNTone: (lowercase: UInt32, uppercase: UInt32)]] = [
        // A
        .a: [
            .none: (0x0061, 0x0041),        // a, A
            .acute: (0x00E1, 0x00C1),       // á, Á
            .grave: (0x00E0, 0x00C0),       // à, À
            .hookAbove: (0x1EA3, 0x1EA2),   // ả, Ả
            .tilde: (0x00E3, 0x00C3),       // ã, Ã
            .dotBelow: (0x1EA1, 0x1EA0)     // ạ, Ạ
        ],
        
        // Â
        .aCircumflex: [
            .none: (0x00E2, 0x00C2),        // â, Â
            .acute: (0x1EA5, 0x1EA4),       // ấ, Ấ
            .grave: (0x1EA7, 0x1EA6),       // ầ, Ầ
            .hookAbove: (0x1EA9, 0x1EA8),   // ẩ, Ẩ
            .tilde: (0x1EAB, 0x1EAA),       // ẫ, Ẫ
            .dotBelow: (0x1EAD, 0x1EAC)     // ậ, Ậ
        ],
        
        // Ă
        .aBreve: [
            .none: (0x0103, 0x0102),        // ă, Ă
            .acute: (0x1EAF, 0x1EAE),       // ắ, Ắ
            .grave: (0x1EB1, 0x1EB0),       // ằ, Ằ
            .hookAbove: (0x1EB3, 0x1EB2),   // ẳ, Ẳ
            .tilde: (0x1EB5, 0x1EB4),       // ẵ, Ẵ
            .dotBelow: (0x1EB7, 0x1EB6)     // ặ, Ặ
        ],
        
        // E
        .e: [
            .none: (0x0065, 0x0045),        // e, E
            .acute: (0x00E9, 0x00C9),       // é, É
            .grave: (0x00E8, 0x00C8),       // è, È
            .hookAbove: (0x1EBB, 0x1EBA),   // ẻ, Ẻ
            .tilde: (0x1EBD, 0x1EBC),       // ẽ, Ẽ
            .dotBelow: (0x1EB9, 0x1EB8)     // ẹ, Ẹ
        ],
        
        // Ê
        .eCircumflex: [
            .none: (0x00EA, 0x00CA),        // ê, Ê
            .acute: (0x1EBF, 0x1EBE),       // ế, Ế
            .grave: (0x1EC1, 0x1EC0),       // ề, Ề
            .hookAbove: (0x1EC3, 0x1EC2),   // ể, Ể
            .tilde: (0x1EC5, 0x1EC4),       // ễ, Ễ
            .dotBelow: (0x1EC7, 0x1EC6)     // ệ, Ệ
        ],
        
        // I
        .i: [
            .none: (0x0069, 0x0049),        // i, I
            .acute: (0x00ED, 0x00CD),       // í, Í
            .grave: (0x00EC, 0x00CC),       // ì, Ì
            .hookAbove: (0x1EC9, 0x1EC8),   // ỉ, Ỉ
            .tilde: (0x0129, 0x0128),       // ĩ, Ĩ
            .dotBelow: (0x1ECB, 0x1ECA)     // ị, Ị
        ],
        
        // O
        .o: [
            .none: (0x006F, 0x004F),        // o, O
            .acute: (0x00F3, 0x00D3),       // ó, Ó
            .grave: (0x00F2, 0x00D2),       // ò, Ò
            .hookAbove: (0x1ECF, 0x1ECE),   // ỏ, Ỏ
            .tilde: (0x00F5, 0x00D5),       // õ, Õ
            .dotBelow: (0x1ECD, 0x1ECC)     // ọ, Ọ
        ],
        
        // Ô
        .oCircumflex: [
            .none: (0x00F4, 0x00D4),        // ô, Ô
            .acute: (0x1ED1, 0x1ED0),       // ố, Ố
            .grave: (0x1ED3, 0x1ED2),       // ồ, Ồ
            .hookAbove: (0x1ED5, 0x1ED4),   // ổ, Ổ
            .tilde: (0x1ED7, 0x1ED6),       // ỗ, Ỗ
            .dotBelow: (0x1ED9, 0x1ED8)     // ộ, Ộ
        ],
        
        // Ơ
        .oHorn: [
            .none: (0x01A1, 0x01A0),        // ơ, Ơ
            .acute: (0x1EDB, 0x1EDA),       // ớ, Ớ
            .grave: (0x1EDD, 0x1EDC),       // ờ, Ờ
            .hookAbove: (0x1EDF, 0x1EDE),   // ở, Ở
            .tilde: (0x1EE1, 0x1EE0),       // ỡ, Ỡ
            .dotBelow: (0x1EE3, 0x1EE2)     // ợ, Ợ
        ],
        
        // U
        .u: [
            .none: (0x0075, 0x0055),        // u, U
            .acute: (0x00FA, 0x00DA),       // ú, Ú
            .grave: (0x00F9, 0x00D9),       // ù, Ù
            .hookAbove: (0x1EE7, 0x1EE6),   // ủ, Ủ
            .tilde: (0x0169, 0x0168),       // ũ, Ũ
            .dotBelow: (0x1EE5, 0x1EE4)     // ụ, Ụ
        ],
        
        // Ư
        .uHorn: [
            .none: (0x01B0, 0x01AF),        // ư, Ư
            .acute: (0x1EE9, 0x1EE8),       // ứ, Ứ
            .grave: (0x1EEB, 0x1EEA),       // ừ, Ừ
            .hookAbove: (0x1EED, 0x1EEC),   // ử, Ử
            .tilde: (0x1EEF, 0x1EEE),       // ữ, Ữ
            .dotBelow: (0x1EF1, 0x1EF0)     // ự, Ự
        ],
        
        // Y
        .y: [
            .none: (0x0079, 0x0059),        // y, Y
            .acute: (0x00FD, 0x00DD),       // ý, Ý
            .grave: (0x1EF3, 0x1EF2),       // ỳ, Ỳ
            .hookAbove: (0x1EF7, 0x1EF6),   // ỷ, Ỷ
            .tilde: (0x1EF9, 0x1EF8),       // ỹ, Ỹ
            .dotBelow: (0x1EF5, 0x1EF4)     // ỵ, Ỵ
        ]
    ]
    
    // MARK: - Public Methods
    
    static func getUnicode(
        vowel: VNVowel,
        tone: VNTone,
        isUppercase: Bool,
        codeTable: CodeTable
    ) -> String {
        switch codeTable {
        case .unicode, .unicodeCompound:
            return getUnicodeCharacter(vowel: vowel, tone: tone, isUppercase: isUppercase)
        case .tcvn3:
            return getTCVN3Character(vowel: vowel, tone: tone, isUppercase: isUppercase)
        case .vniWindows:
            return getVNICharacter(vowel: vowel, tone: tone, isUppercase: isUppercase)
        case .vietnameseLocaleCP1258:
            return getCP1258Character(vowel: vowel, tone: tone, isUppercase: isUppercase)
        }
    }
    
    private static func getUnicodeCharacter(
        vowel: VNVowel,
        tone: VNTone,
        isUppercase: Bool
    ) -> String {
        guard let toneMap = unicodeMap[vowel],
              let unicodeValue = toneMap[tone] else {
            return ""
        }
        
        let scalar = isUppercase ? unicodeValue.uppercase : unicodeValue.lowercase
        guard let unicodeScalar = UnicodeScalar(scalar) else {
            return ""
        }
        
        return String(unicodeScalar)
    }
    
    private static func getTCVN3Character(
        vowel: VNVowel,
        tone: VNTone,
        isUppercase: Bool
    ) -> String {
        // TCVN3 mapping implementation
        // This is a simplified version - full implementation would include complete TCVN3 table
        return getUnicodeCharacter(vowel: vowel, tone: tone, isUppercase: isUppercase)
    }
    
    private static func getVNICharacter(
        vowel: VNVowel,
        tone: VNTone,
        isUppercase: Bool
    ) -> String {
        // VNI Windows mapping implementation
        // This is a simplified version - full implementation would include complete VNI table
        return getUnicodeCharacter(vowel: vowel, tone: tone, isUppercase: isUppercase)
    }
    
    private static func getCP1258Character(
        vowel: VNVowel,
        tone: VNTone,
        isUppercase: Bool
    ) -> String {
        // CP1258 mapping implementation
        return getUnicodeCharacter(vowel: vowel, tone: tone, isUppercase: isUppercase)
    }
}

