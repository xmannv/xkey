import Foundation
import AppKit

/// Extension for VNEngine to support spell checking
extension VNEngine {

    /// Validate if the current word buffer is a valid Vietnamese word
    /// Delegates to checkWordSpelling(word:) with the current buffer word
    func isCurrentWordValid() -> Bool {
        let currentWord = self.getCurrentWord()
        return checkWordSpelling(word: currentWord)
    }

    /// Check if the current word buffer contains Vietnamese-specific characters
    func hasVietnameseProcessing() -> Bool {
        guard !buffer.isEmpty else { return false }

        for i in 0..<buffer.count {
            let entry = buffer[i]
            if entry.hasTone || entry.hasToneW || entry.hasMark || entry.isStandalone {
                return true
            }
        }
        return false
    }

    /// Validate if a given word string is a valid Vietnamese word
    /// This is used for checking words from Accessibility API
    func checkWordSpelling(word: String) -> Bool {
        guard SharedSettings.shared.spellCheckEnabled else {
            logCallback?("📖 checkWordSpelling: DISABLED (spellCheckEnabled=false)")
            return true // Spell checking disabled
        }

        guard !word.isEmpty else {
            logCallback?("📖 checkWordSpelling: SKIPPED (empty word)")
            return true // Empty word is considered valid
        }

        // When vAllowConsonantZFWJ is enabled, words containing Z, F, W, J consonants
        // should be considered valid without dictionary check
        if vAllowConsonantZFWJ == 1 {
            let lowercaseWord = word.lowercased()
            let specialConsonants: [Character] = ["z", "f", "w", "j"]

            if let firstChar = lowercaseWord.first, specialConsonants.contains(firstChar) {
                logCallback?("📖 checkWordSpelling: SKIPPED (vAllowConsonantZFWJ=1, starts with '\(firstChar)')")
                return true
            }

            for consonant in specialConsonants {
                if lowercaseWord.contains(consonant) {
                    logCallback?("📖 checkWordSpelling: SKIPPED (vAllowConsonantZFWJ=1, contains '\(consonant)')")
                    return true
                }
            }
        }

        // Check user dictionary
        if SharedSettings.shared.isWordInUserDictionary(word) {
            logCallback?("📖 checkWordSpelling: FOUND in User Dictionary, word='\(word)'")
            return true
        }

        // Check against hunspell dictionary
        let style: VNDictionaryManager.DictionaryStyle = SharedSettings.shared.modernStyle ? .dauMoi : .dauCu
        let styleName = style == .dauCu ? "Dấu cũ" : "Dấu mới"

        let isDictionaryLoaded = VNDictionaryManager.shared.isDictionaryLoaded(style: style)
        if !isDictionaryLoaded {
            logCallback?("📖 checkWordSpelling: NOT LOADED (style=\(styleName))")
            return true
        }

        let isValid = VNDictionaryManager.shared.isValidWord(word, style: style)
        logCallback?("📖 checkWordSpelling: word='\(word)', style=\(styleName), valid=\(isValid)")

        if isValid {
            return true
        }

        // Fallback to Natural Language framework
        let nlValid = isValidWordUsingNaturalLanguage(word)
        logCallback?("📖 checkWordSpelling NL: word='\(word)', valid=\(nlValid)")

        return nlValid
    }

    /// Check if word is valid using macOS Natural Language framework
    /// This serves as a fallback when word is not found in the custom dictionary
    private func isValidWordUsingNaturalLanguage(_ word: String) -> Bool {
        // Use NLSpellChecker to check spelling
        let checker = NSSpellChecker.shared

        // Check spelling for Vietnamese language
        let range = checker.checkSpelling(of: word, startingAt: 0, language: "vi", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

        // If range.location == NSNotFound, the word is correctly spelled
        let isCorrect = range.location == NSNotFound

        return isCorrect
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
