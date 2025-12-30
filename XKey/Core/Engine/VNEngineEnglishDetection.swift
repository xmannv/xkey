//
//  VNEngineEnglishDetection.swift
//  XKey
//
//  English word detection for spell checking optimization
//

import Foundation

// MARK: - Fast English Detection (for spell check optimization)

extension String {
    
    /// Ultra-fast English detection for real-time typing
    /// Returns true if word is DEFINITELY English (high confidence)
    /// Used to skip Vietnamese spell checking and processing
    var isDefinitelyEnglish: Bool {
        let word = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty or too short to determine
        if word.count < 2 {
            return false
        }
        
        // ============================================
        // RULE 1: Contains f, j, w, z
        // ============================================
        // Almost certainly not pure Vietnamese
        // Note: Some Vietnamese words use these with vAllowConsonantZFWJ,
        // but they're rare and mostly loan words
        if word.rangeOfCharacter(from: CharacterSet(charactersIn: "fjwz")) != nil {
            return true
        }
        
        // ============================================
        // RULE 2: Ends with 's' (English plural/verb)
        // ============================================
        // Vietnamese words never end with 's'
        if word.hasSuffix("s") && word.count > 2 {
            return true
        }
        
        // ============================================
        // RULE 3: Ends with invalid consonants
        // ============================================
        // Vietnamese only allows endings: c, ch, m, n, ng, nh, p, t
        // Invalid: b, d, g, k, l, r, v, x (f, z already caught in rule 1)
        if word.count >= 2 {
            if let last = word.last {
                // These consonants NEVER end Vietnamese words
                let invalidEndings = CharacterSet(charactersIn: "bdgklrvx")
                if String(last).rangeOfCharacter(from: invalidEndings) != nil {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 4: English consonant clusters at END
        // ============================================
        // Vietnamese never has these final clusters
        if word.count >= 3 {
            let englishFinalClusters = [
                // -Ck patterns
                "ck", "sk", "nk", "lk", "rk",
                // -Ct patterns (kept → -pt is English)
                "ct", "ft", "pt", "xt", "lt", "st",
                // -Cp patterns
                "lp", "mp", "sp",
                // -Cd patterns
                "nd", "ld", "rd",
                // Other clusters
                "nt", "lf", "lm", "lb", "rb", "rm"
            ]
            for cluster in englishFinalClusters {
                if word.hasSuffix(cluster) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 5: English consonant clusters at START
        // ============================================
        // These initial clusters don't exist in Vietnamese
        if word.count >= 3 {
            let englishInitialClusters = [
                // 3-letter clusters (check first)
                "str", "spr", "scr", "spl", "shr", "thr", "sch", "squ",
                // L-clusters (Vietnamese doesn't have these)
                "bl", "cl", "fl", "gl", "pl", "sl",
                // R-clusters (Vietnamese only has "tr", exclude it)
                "br", "cr", "dr", "fr", "gr", "pr",
                // S-clusters
                "sc", "sk", "sm", "sn", "sp", "st", "sw",
                // Other clusters
                "dw", "tw", "gn"
            ]
            for cluster in englishInitialClusters {
                if word.hasPrefix(cluster) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 6: Double consonants
        // ============================================
        // Vietnamese never has double consonants
        if word.count >= 3 {
            let doubleConsonants = [
                "bb", "cc", "dd", "ff", "gg", "hh", "jj", "kk",
                "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv", "zz"
            ]
            for dc in doubleConsonants {
                if word.contains(dc) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 7: English suffixes (derivational)
        // ============================================
        // Common English word endings not found in Vietnamese
        if word.count >= 4 {
            let englishSuffixes = [
                // -tion, -sion (nation, vision)
                "tion", "sion",
                // -ing (running, playing) - but NOT "inh" sequence in VN
                "ing",
                // -ed past tense (walked, played)
                "ed",
                // -ly adverbs (quickly, slowly)
                "ly",
                // -ness (happiness, sadness)
                "ness",
                // -ment (movement, government)
                "ment",
                // -able, -ible (readable, visible)
                "able", "ible",
                // -ful, -less (beautiful, careless)
                "ful", "less",
                // -ity (city, quality)
                "ity",
                // -ous (famous, nervous)
                "ous",
                // -ive (active, creative)
                "ive",
                // -er, -or comparison/agent (bigger, actor)
                // Note: Skip "er" as it might conflict; "or" is safe
                "or"
            ]
            for suffix in englishSuffixes {
                if word.hasSuffix(suffix) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 8: 3+ consecutive consonants
        // ============================================
        // Very rare in Vietnamese - exclude valid VN clusters first
        let wordForConsonantCheck = word
            .replacingOccurrences(of: "ngh", with: "_")  // ngh → single placeholder
            .replacingOccurrences(of: "ng", with: "_")   // ng → single placeholder
            .replacingOccurrences(of: "nh", with: "_")   // nh → single placeholder
            .replacingOccurrences(of: "ch", with: "_")   // ch → single placeholder
            .replacingOccurrences(of: "th", with: "_")   // th → single placeholder
            .replacingOccurrences(of: "kh", with: "_")   // kh → single placeholder
            .replacingOccurrences(of: "ph", with: "_")   // ph → single placeholder
            .replacingOccurrences(of: "tr", with: "_")   // tr → single placeholder
            .replacingOccurrences(of: "gi", with: "_")   // gi → single placeholder
            .replacingOccurrences(of: "qu", with: "_")   // qu → single placeholder
        
        if wordForConsonantCheck.range(of: "[bcdfghjklmnpqrstvwxyz]{3,}", 
                      options: .regularExpression) != nil {
            return true
        }
        
        // ============================================
        // RULE 9: Silent letter patterns
        // ============================================
        // Characteristic of English spelling
        let silentPatterns = ["^kn", "^wr", "^ps", "^pn", "mb$", "lm$", "gn$", "bt$"]
        for pattern in silentPatterns {
            if word.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        // ============================================
        // RULE 10: English vowel combinations
        // ============================================
        // Not found in Vietnamese orthography
        if word.count > 3 {
            let englishVowelCombos = [
                // Long vowel digraphs
                "ough", "eigh", "augh",
                // Double vowels (Vietnamese has different ones)
                "oo", "ee",
                // Specific English patterns
                "eau", "iew", "ow", "aw",
                // ie in specific positions (Vietnamese có "iê" nhưng khác)
                "ies"  // only plural form like "cookies"
            ]
            for combo in englishVowelCombos {
                if word.contains(combo) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 11: 'x' in the middle of word
        // ============================================
        // Vietnamese 'x' only appears at the start (xa, xanh, xin...)
        // English has 'x' in the middle (text, next, example)
        if word.count >= 3 {
            let middlePart = word.dropFirst().dropLast()
            if middlePart.contains("x") {
                return true
            }
        }
        
        // ============================================
        // RULE 12: 'q' not followed by 'u'
        // ============================================
        // Vietnamese always has "qu" (quả, quen, quý)
        // Some English words have standalone q (Iraq, qi)
        if let qIndex = word.firstIndex(of: "q") {
            let afterQ = word.index(after: qIndex)
            if afterQ >= word.endIndex || word[afterQ] != "u" {
                return true
            }
        }
        
        // ============================================
        // RULE 13: Consecutive vowels patterns
        // ============================================
        // Specific vowel sequences that don't exist in Vietnamese:
        // - "io": In English: -tion, action; VN doesn't have this
        // - "ae", "ea", "uo": Could be English-specific but many edge cases
        // For now, only flag "io" as it's highly distinctive and safe
        if word.count >= 3 {
            if word.contains("io") && !word.contains("iô") && !word.contains("iơ") {
                return true
            }
        }
        
        return false
    }
    
    /// English detection focusing ONLY on word START and MIDDLE patterns
    /// Does NOT check word endings (to avoid conflict with Telex mark keys s/f/r/x/j)
    /// Used for instant restore feature during typing
    var hasEnglishStartPattern: Bool {
        let word = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty or too short to determine
        if word.count < 2 {
            return false
        }
        
        // ============================================
        // RULE 1: Contains f, j, w, z
        // ============================================
        // These characters don't exist in native Vietnamese words
        // Check only in the START and MIDDLE (not the last character which could be mark key)
        let wordWithoutLast = word.count > 1 ? String(word.dropLast()) : word
        if wordWithoutLast.rangeOfCharacter(from: CharacterSet(charactersIn: "fjwz")) != nil {
            return true
        }
        
        // ============================================
        // RULE 2: English consonant clusters at START
        // ============================================
        // These initial clusters don't exist in Vietnamese
        if word.count >= 3 {
            let englishInitialClusters = [
                // 3-letter clusters (check first)
                "str", "spr", "scr", "spl", "shr", "thr", "sch", "squ",
                // L-clusters (Vietnamese doesn't have these)
                "bl", "cl", "fl", "gl", "pl", "sl",
                // R-clusters (Vietnamese only has "tr", exclude it)
                "br", "cr", "dr", "fr", "gr", "pr",
                // S-clusters
                "sc", "sk", "sm", "sn", "sp", "st", "sw",
                // Other clusters
                "dw", "tw", "gn"
            ]
            for cluster in englishInitialClusters {
                if word.hasPrefix(cluster) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 3: Double consonants in the word
        // ============================================
        // Vietnamese never has double consonants
        if word.count >= 3 {
            let doubleConsonants = [
                "bb", "cc", "dd", "ff", "gg", "hh", "jj", "kk",
                "ll", "mm", "nn", "pp", "rr", "ss", "tt", "vv", "zz"
            ]
            for dc in doubleConsonants {
                if word.contains(dc) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 4: 3+ consecutive consonants 
        // ============================================
        // Very rare in Vietnamese - exclude valid VN clusters first
        let wordForCheck = word
            .replacingOccurrences(of: "ngh", with: "_")
            .replacingOccurrences(of: "ng", with: "_")
            .replacingOccurrences(of: "nh", with: "_")
            .replacingOccurrences(of: "ch", with: "_")
            .replacingOccurrences(of: "th", with: "_")
            .replacingOccurrences(of: "kh", with: "_")
            .replacingOccurrences(of: "ph", with: "_")
            .replacingOccurrences(of: "tr", with: "_")
            .replacingOccurrences(of: "gi", with: "_")
            .replacingOccurrences(of: "qu", with: "_")
        
        if wordForCheck.range(of: "[bcdfghjklmnpqrstvwxyz]{3,}", 
                      options: .regularExpression) != nil {
            return true
        }
        
        // ============================================
        // RULE 5: Silent letter patterns at START
        // ============================================
        // Characteristic of English spelling (only check start patterns)
        let silentStartPatterns = ["^kn", "^wr", "^ps", "^pn"]
        for pattern in silentStartPatterns {
            if word.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        // ============================================
        // RULE 6: English vowel combinations (middle of word)
        // ============================================
        // These don't exist in Vietnamese orthography
        // NOTE: "oo" and "ee" are EXCLUDED because they conflict with Telex:
        // - In Telex, e+e = ê (so "tiees" = "tiế", not English "ee")
        // - In Telex, o+o can be part of Vietnamese typing
        if word.count > 3 {
            let englishVowelCombos = [
                // Long vowel digraphs (distinctive and safe)
                "ough", "eigh", "augh",
                // Specific English patterns
                "eau", "iew"
            ]
            for combo in englishVowelCombos {
                if word.contains(combo) {
                    return true
                }
            }
        }
        
        // ============================================
        // RULE 7: 'x' in the middle of word
        // ============================================
        // Vietnamese 'x' only appears at the start (xa, xanh, xin...)
        // English has 'x' in the middle (text, next, example)
        if word.count >= 3 {
            // Check middle part (excluding first and last character)
            let middlePart = word.dropFirst().dropLast()
            if middlePart.contains("x") {
                return true
            }
        }
        
        // ============================================
        // RULE 8: 'q' not followed by 'u'
        // ============================================
        // Vietnamese always has "qu" (quả, quen, quý)
        if let qIndex = word.firstIndex(of: "q") {
            let afterQ = word.index(after: qIndex)
            if afterQ >= word.endIndex || word[afterQ] != "u" {
                return true
            }
        }
        
        return false
    }
}

// MARK: - VNEngine Helper Extensions

extension VNEngine {
    
    /// Get current typing word as a String for analysis
    /// Converts internal buffer to readable text
    func getCurrentWordString() -> String {
        guard index > 0 else { return "" }
        
        var result = ""
        for i in 0..<Int(index) {
            let keyCode = UInt16(typingWord[i] & VNEngine.CHAR_MASK)
            
            // Convert keyCode to character
            if let char = keyCodeToCharacter(keyCode) {
                result.append(char)
            }
        }
        
        return result
    }
    
    /// Get raw input keys as a String (original ASCII without Vietnamese transforms)
    func getRawInputString() -> String {
        guard stateIndex > 0 else { return "" }
        
        var result = ""
        for i in 0..<Int(stateIndex) {
            let keyCode = UInt16(keyStates[i] & VNEngine.CHAR_MASK)
            
            // Convert keyCode to character
            if let char = keyCodeToCharacter(keyCode) {
                result.append(char)
            }
        }
        
        return result
    }
    
    /// Convert keyCode to character for string building
    private func keyCodeToCharacter(_ keyCode: UInt16) -> Character? {
        // Map common key codes to characters
        let mapping: [UInt16: Character] = [
            0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
            0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
            0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
            0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
            0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
            0x06: "z"
        ]
        return mapping[keyCode]
    }
    
    /// Check if current buffer is definitely English
    /// Used as early exit optimization in spell checking
    func isCurrentWordDefinitelyEnglish() -> Bool {
        // Only check if we have enough characters to make a determination
        guard index >= 3 else { return false }
        
        let word = getCurrentWordString()
        return word.isDefinitelyEnglish
    }
}
