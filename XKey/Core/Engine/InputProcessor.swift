//
//  InputProcessor.swift
//  XKey
//
//  Processes keyboard input based on input method (Telex, VNI, etc.)
//

import Foundation

class InputProcessor {
    
    // MARK: - Properties
    
    private let inputMethod: InputMethod
    
    // MARK: - Initialization
    
    init(inputMethod: InputMethod) {
        self.inputMethod = inputMethod
    }
    
    // MARK: - Key Processing
    
    enum KeyAction {
        case appendVowel(VNVowel)
        case appendConsonant(VNConsonant)
        case addCircumflex
        case addBreve
        case addHorn
        case addTone(VNTone)
        case doubleLetter(Character)
        case normal(Character)
        case wordBreak
    }
    
    func processKey(_ character: Character, isUppercase: Bool) -> KeyAction {
        let lowerChar = character.lowercased().first ?? character
        
        switch inputMethod {
        case .telex:
            return processTelexKey(lowerChar, isUppercase: isUppercase)
        case .vni:
            return processVNIKey(lowerChar, isUppercase: isUppercase)
        case .simpleTelex1, .simpleTelex2:
            return processSimpleTelexKey(lowerChar, isUppercase: isUppercase)
        }
    }
    
    // MARK: - Telex Processing
    
    private func processTelexKey(_ char: Character, isUppercase: Bool) -> KeyAction {
        switch char {
        // Vowels - these can be double letters for transformations
        case "a": return .doubleLetter("a")  // aa -> â, aw -> ă
        case "e": return .doubleLetter("e")  // ee -> ê
        case "i": return .appendVowel(.i)
        case "o": return .doubleLetter("o")  // oo -> ô, ow -> ơ
        case "u": return .appendVowel(.u)    // uw -> ư
        case "y": return .appendVowel(.y)
            
        // Circumflex (^)
        case "^": return .addCircumflex
            
        // Breve (˘) - using 'w' after 'a'
        // Horn (+) - using 'w' after 'o' or 'u'
        case "w": return .addHorn // Will be context-dependent
            
        // Tones
        case "s": return .addTone(.acute)      // Sắc
        case "f": return .addTone(.grave)      // Huyền
        case "r": return .normal("r")          // Context-dependent: consonant 'r' or tone hỏi
        case "x": return .addTone(.tilde)      // Ngã
        case "j": return .addTone(.dotBelow)   // Nặng
            
        // Double letters for special consonants
        case "d": return .doubleLetter("d")    // dd -> đ
        case "z": return .normal("z")
            
        // Consonants
        case "b": return .appendConsonant(.b)
        case "c": return .appendConsonant(.c)
        case "g": return .appendConsonant(.g)
        case "h": return .appendConsonant(.h)
        case "k": return .appendConsonant(.k)
        case "l": return .appendConsonant(.l)
        case "m": return .appendConsonant(.m)
        case "n": return .appendConsonant(.n)
        case "p": return .appendConsonant(.p)
        case "q": return .appendConsonant(.q)
        case "t": return .appendConsonant(.t)
        case "v": return .appendConsonant(.v)
            
        // Word breaks
        case " ", ",", ".", "!", "?", ";", ":":
            return .wordBreak
            
        default:
            return .normal(char)
        }
    }
    
    // MARK: - VNI Processing
    
    private func processVNIKey(_ char: Character, isUppercase: Bool) -> KeyAction {
        switch char {
        // Vowels
        case "a": return .appendVowel(.a)
        case "e": return .appendVowel(.e)
        case "i": return .appendVowel(.i)
        case "o": return .appendVowel(.o)
        case "u": return .appendVowel(.u)
        case "y": return .appendVowel(.y)
            
        // Numbers for tones and transformations
        case "1": return .addTone(.acute)      // Sắc
        case "2": return .addTone(.grave)      // Huyền
        case "3": return .addTone(.hookAbove)  // Hỏi
        case "4": return .addTone(.tilde)      // Ngã
        case "5": return .addTone(.dotBelow)   // Nặng
        case "6": return .addCircumflex        // ^ (â, ê, ô)
        case "7": return .addBreve             // ˘ (ă)
        case "8": return .addHorn              // + (ơ, ư)
        case "9": return .appendConsonant(.dd) // đ
            
        // Consonants
        case "b": return .appendConsonant(.b)
        case "c": return .appendConsonant(.c)
        case "d": return .appendConsonant(.d)
        case "g": return .appendConsonant(.g)
        case "h": return .appendConsonant(.h)
        case "k": return .appendConsonant(.k)
        case "l": return .appendConsonant(.l)
        case "m": return .appendConsonant(.m)
        case "n": return .appendConsonant(.n)
        case "p": return .appendConsonant(.p)
        case "q": return .appendConsonant(.q)
        case "t": return .appendConsonant(.t)
        case "v": return .appendConsonant(.v)
            
        // Word breaks
        case " ", ",", ".", "!", "?", ";", ":":
            return .wordBreak
            
        default:
            return .normal(char)
        }
    }
    
    // MARK: - Simple Telex Processing
    
    private func processSimpleTelexKey(_ char: Character, isUppercase: Bool) -> KeyAction {
        // Simple Telex is similar to Telex but without some shortcuts
        return processTelexKey(char, isUppercase: isUppercase)
    }
    
    // MARK: - Helper Methods
    
    func isVowelKey(_ char: Character) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        return vowels.contains(char.lowercased().first ?? char)
    }
    
    func isConsonantKey(_ char: Character) -> Bool {
        let consonants: Set<Character> = [
            "b", "c", "d", "g", "h", "k", "l", "m",
            "n", "p", "q", "r", "s", "t", "v", "x", "z"
        ]
        return consonants.contains(char.lowercased().first ?? char)
    }
    
    func isToneKey(_ char: Character) -> Bool {
        switch inputMethod {
        case .telex, .simpleTelex1, .simpleTelex2:
            return ["s", "f", "r", "x", "j"].contains(char.lowercased().first ?? char)
        case .vni:
            return ["1", "2", "3", "4", "5"].contains(char)
        }
    }
    
    func isTransformKey(_ char: Character) -> Bool {
        switch inputMethod {
        case .telex, .simpleTelex1, .simpleTelex2:
            return char.lowercased().first == "w" || char == "^"
        case .vni:
            return ["6", "7", "8", "9"].contains(char)
        }
    }
    
    func isWordBreakKey(_ char: Character) -> Bool {
        let wordBreaks: Set<Character> = [
            " ", ",", ".", "!", "?", ";", ":",
            "\n", "\r", "\t"
        ]
        return wordBreaks.contains(char)
    }
}

// MARK: - Quick Telex Support

extension InputProcessor {
    
    /// Check if character sequence should be transformed (Quick Telex)
    /// cc -> ch, gg -> gi, kk -> kh, nn -> ng, qq -> qu, pp -> ph, tt -> th
    func shouldApplyQuickTelex(
        previousChar: Character?,
        currentChar: Character
    ) -> VNConsonant? {
        guard let prev = previousChar?.lowercased().first,
              let curr = currentChar.lowercased().first,
              prev == curr else {
            return nil
        }
        
        switch curr {
        case "c": return .ch
        case "g": return .gi
        case "k": return .kh
        case "n": return .ng
        case "q": return .qu
        case "p": return .ph
        case "t": return .th
        default: return nil
        }
    }
}

