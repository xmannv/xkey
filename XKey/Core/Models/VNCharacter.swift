//
//  VNCharacter.swift
//  XKey
//
//  Vietnamese character definitions and mappings
//

import Foundation

// MARK: - Vietnamese Tones

enum VNTone: Int, CaseIterable, Codable {
    case none = 0      // No tone
    case acute = 1     // Sắc (á)
    case grave = 2     // Huyền (à)
    case hookAbove = 3 // Hỏi (ả)
    case tilde = 4     // Ngã (ã)
    case dotBelow = 5  // Nặng (ạ)
    
    var displayName: String {
        switch self {
        case .none: return "Không dấu"
        case .acute: return "Sắc"
        case .grave: return "Huyền"
        case .hookAbove: return "Hỏi"
        case .tilde: return "Ngã"
        case .dotBelow: return "Nặng"
        }
    }
}

// MARK: - Vietnamese Vowels

enum VNVowel: String, CaseIterable {
    // Basic vowels
    case a, e, i, o, u, y
    
    // Vowels with circumflex (^)
    case aCircumflex = "â"
    case eCircumflex = "ê"
    case oCircumflex = "ô"
    
    // Vowels with breve (˘)
    case aBreve = "ă"
    
    // Vowels with horn (+)
    case oHorn = "ơ"
    case uHorn = "ư"
    
    var baseCharacter: Character {
        switch self {
        case .a, .aCircumflex, .aBreve: return "a"
        case .e, .eCircumflex: return "e"
        case .i: return "i"
        case .o, .oCircumflex, .oHorn: return "o"
        case .u, .uHorn: return "u"
        case .y: return "y"
        }
    }
    
    var hasCircumflex: Bool {
        switch self {
        case .aCircumflex, .eCircumflex, .oCircumflex: return true
        default: return false
        }
    }
    
    var hasBreve: Bool {
        self == .aBreve
    }
    
    var hasHorn: Bool {
        self == .oHorn || self == .uHorn
    }
}

// MARK: - Vietnamese Consonants

enum VNConsonant: String, CaseIterable {
    // Single consonants
    case b, c, d, g, h, k, l, m, n, p, q, r, s, t, v, x
    
    // Special consonant
    case dd = "đ"
    
    // Compound consonants
    case ch, gh, gi, kh, ng, ngh, nh, ph, qu, th, tr
    
    var isSingleConsonant: Bool {
        rawValue.count == 1
    }
    
    var isCompoundConsonant: Bool {
        rawValue.count > 1
    }
}

// MARK: - Vowel Sequences

enum VowelSequence: Equatable, Hashable {
    case single(VNVowel)
    case double(VNVowel, VNVowel)
    case triple(VNVowel, VNVowel, VNVowel)
    
    var vowels: [VNVowel] {
        switch self {
        case .single(let v): return [v]
        case .double(let v1, let v2): return [v1, v2]
        case .triple(let v1, let v2, let v3): return [v1, v2, v3]
        }
    }
    
    var length: Int {
        vowels.count
    }
    
    // Check if this is a valid Vietnamese vowel sequence
    var isValid: Bool {
        VowelSequenceValidator.isValid(self)
    }
}

// MARK: - Consonant Sequences

enum ConsonantSequence: Equatable {
    case single(VNConsonant)
    case compound(VNConsonant)
    
    var consonant: VNConsonant {
        switch self {
        case .single(let c), .compound(let c): return c
        }
    }
}

// MARK: - Vietnamese Character

struct VNCharacter: Equatable, Hashable {
    let vowel: VNVowel?
    let consonant: VNConsonant?
    let tone: VNTone
    let isUppercase: Bool
    let plainCharacter: Character?  // For pass-through characters
    
    init(vowel: VNVowel, tone: VNTone = .none, isUppercase: Bool = false) {
        self.vowel = vowel
        self.consonant = nil
        self.tone = tone
        self.isUppercase = isUppercase
        self.plainCharacter = nil
    }

    init(consonant: VNConsonant, isUppercase: Bool = false) {
        self.vowel = nil
        self.consonant = consonant
        self.tone = .none
        self.isUppercase = isUppercase
        self.plainCharacter = nil
    }

    // Initialize from plain character (for pass-through characters)
    init(character: Character) {
        self.vowel = nil
        self.consonant = nil
        self.tone = .none
        self.isUppercase = character.isUppercase
        self.plainCharacter = character
    }

    var isVowel: Bool {
        vowel != nil
    }
    
    var isConsonant: Bool {
        consonant != nil
    }
    
    // Get Unicode scalar value
    func unicode(codeTable: CodeTable) -> String {
        // Return plain character if set (for pass-through)
        if let plain = plainCharacter {
            return String(plain)
        }

        if let consonant = consonant {
            let base = consonant.rawValue
            if isUppercase {
                // Only capitalize the first character
                // Example: "tr" → "Tr", not "TR"
                return base.prefix(1).uppercased() + base.dropFirst()
            }
            return base
        }

        if let vowel = vowel {
            let result = VNCharacterMap.getUnicode(
                vowel: vowel,
                tone: tone,
                isUppercase: isUppercase,
                codeTable: codeTable
            )
            return result
        }

        return ""
    }
}

// MARK: - Code Tables

enum CodeTable: Int, CaseIterable, Codable {
    case unicode = 0
    case tcvn3 = 1
    case vniWindows = 2
    case unicodeCompound = 3
    case vietnameseLocaleCP1258 = 4
    
    var displayName: String {
        switch self {
        case .unicode: return "Unicode"
        case .tcvn3: return "TCVN3 (ABC)"
        case .vniWindows: return "VNI Windows"
        case .unicodeCompound: return "Unicode Compound"
        case .vietnameseLocaleCP1258: return "Vietnamese Locale CP1258"
        }
    }
    
    var requiresDoubleBackspace: Bool {
        self == .vniWindows || self == .unicodeCompound
    }
}

// MARK: - Input Methods

enum InputMethod: Int, CaseIterable, Codable {
    case telex = 0
    case vni = 1
    case simpleTelex1 = 2
    case simpleTelex2 = 3
    
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex1: return "Simple Telex 1"
        case .simpleTelex2: return "Simple Telex 2"
        }
    }
}

// MARK: - Key Codes

enum VNKeyCode: UInt16 {
    // Letters
    case a = 0x00, b = 0x0B, c = 0x08, d = 0x02, e = 0x0E
    case f = 0x03, g = 0x05, h = 0x04, i = 0x22, j = 0x26
    case k = 0x28, l = 0x25, m = 0x2E, n = 0x2D, o = 0x1F
    case p = 0x23, q = 0x0C, r = 0x0F, s = 0x01, t = 0x11
    case u = 0x20, v = 0x09, w = 0x0D, x = 0x07, y = 0x10
    case z = 0x06
    
    // Numbers
    case num0 = 0x1D, num1 = 0x12, num2 = 0x13, num3 = 0x14, num4 = 0x15
    case num5 = 0x17, num6 = 0x16, num7 = 0x1A, num8 = 0x1C, num9 = 0x19
    
    // Special keys
    case space = 0x31
    case delete = 0x33
    case enter = 0x24
    case escape = 0x35
    
    // Punctuation
    case minus = 0x1B
    case equals = 0x18
    case leftBracket = 0x21
    case rightBracket = 0x1E
    case backslash = 0x2A
    case semicolon = 0x29
    case quote = 0x27
    case comma = 0x2B
    case period = 0x2F
    case slash = 0x2C
    case grave = 0x32
}

