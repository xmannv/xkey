import Foundation

/// Extension for VNEngine to support spell checking
extension VNEngine {

    /// Validate if the current word buffer is a valid Vietnamese word
    func isCurrentWordValid() -> Bool {
        guard SharedSettings.shared.spellCheckEnabled else {
            logCallback?("📖 Dictionary check: DISABLED (spellCheckEnabled=false)")
            return true // Spell checking disabled
        }

        let currentWord = self.getCurrentWord()
        guard !currentWord.isEmpty else {
            logCallback?("📖 Dictionary check: SKIPPED (empty word)")
            return true // Empty word is considered valid
        }

        // When vAllowConsonantZFWJ is enabled, words containing Z, F, W, J consonants
        // should be considered valid without dictionary check
        // This allows foreign-influenced Vietnamese words like "zị", "wốn", etc.
        if vAllowConsonantZFWJ == 1 {
            let lowercaseWord = currentWord.lowercased()
            let specialConsonants: [Character] = ["z", "f", "w", "j"]
            
            // Check if word starts with or contains these consonants
            if let firstChar = lowercaseWord.first, specialConsonants.contains(firstChar) {
                logCallback?("📖 Dictionary check: SKIPPED (vAllowConsonantZFWJ=1, starts with '\(firstChar)')")
                return true
            }
            
            // Also check if word contains these consonants anywhere (for compound words)
            for consonant in specialConsonants {
                if lowercaseWord.contains(consonant) {
                    logCallback?("📖 Dictionary check: SKIPPED (vAllowConsonantZFWJ=1, contains '\(consonant)')")
                    return true
                }
            }
        }
        
        // First, check user dictionary (custom words defined by user)
        if SharedSettings.shared.isWordInUserDictionary(currentWord) {
            logCallback?("📖 Dictionary check: FOUND in User Dictionary, word='\(currentWord)'")
            return true // Word is in user dictionary, considered valid
        }

        // Check against hunspell dictionary
        let style: VNDictionaryManager.DictionaryStyle = SharedSettings.shared.modernStyle ? .dauMoi : .dauCu
        let styleName = style == .dauCu ? "Dấu cũ" : "Dấu mới"
        
        let isDictionaryLoaded = VNDictionaryManager.shared.isDictionaryLoaded(style: style)
        if !isDictionaryLoaded {
            logCallback?("📖 Dictionary check: NOT LOADED (style=\(styleName))")
            return true // Dictionary not loaded, assume valid
        }
        
        let isValid = VNDictionaryManager.shared.isValidWord(currentWord, style: style)
        logCallback?("📖 Dictionary check: word='\(currentWord)', style=\(styleName), valid=\(isValid)")
        
        return isValid
    }

    /// Get spell check suggestion status for the word
    func getSpellCheckStatus() -> SpellCheckStatus {
        guard SharedSettings.shared.spellCheckEnabled else {
            return .disabled
        }

        let style: VNDictionaryManager.DictionaryStyle = SharedSettings.shared.modernStyle ? .dauMoi : .dauCu
        guard VNDictionaryManager.shared.isDictionaryLoaded(style: style) else {
            return .dictionaryNotLoaded
        }

        let currentWord = self.getCurrentWord()
        guard !currentWord.isEmpty else {
            return .valid
        }

        if isCurrentWordValid() {
            return .valid
        } else {
            return .invalid(word: currentWord)
        }
    }

    /// Find similar words for spell correction suggestions
    func getSuggestions(for word: String, maxSuggestions: Int = 5) -> [String] {
        guard SharedSettings.shared.spellCheckEnabled,
              VNDictionaryManager.shared.isDictionaryLoaded() else {
            return []
        }

        // For now, return empty array
        // TODO: Implement edit distance based suggestions
        return []
    }
}

// MARK: - Supporting Types

enum SpellCheckStatus: Equatable {
    case disabled
    case dictionaryNotLoaded
    case valid
    case invalid(word: String)

    var isValid: Bool {
        switch self {
        case .valid, .disabled, .dictionaryNotLoaded:
            return true
        case .invalid:
            return false
        }
    }

    var needsDownload: Bool {
        if case .dictionaryNotLoaded = self {
            return true
        }
        return false
    }
}
