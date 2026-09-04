import Foundation
import AppKit

/// Process-wide memo of NSSpellChecker verdicts.
/// Each cache miss costs a synchronous XPC round-trip to the AppleSpell
/// service (~0.1-1ms, 10-200ms under memory pressure), and the engine asks
/// about the same strings constantly: every intermediate state of a word
/// being typed ("ngh", "nghi", ...) that is not in the hunspell dictionary
/// falls through to this check on every keystroke.
/// Verdicts are stable for the app's lifetime: the app never calls
/// learnWord/unlearnWord, and tier-1 (user dictionary) and tier-2 (hunspell)
/// checks run BEFORE this fallback, so their changes never need to
/// invalidate this cache. System-wide dictionary edits made in another app
/// are picked up on next launch — acceptable for a spell-check hint.
private enum NLSpellVerdictCache {
    private static let maxEntries = 2048
    private static var verdicts: [String: Bool] = [:]
    private static let lock = NSLock()

    static func verdict(for word: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return verdicts[word]
    }

    static func store(_ verdict: Bool, for word: String) {
        lock.lock()
        defer { lock.unlock() }
        if verdicts.count >= maxEntries {
            // Simple full reset — refills within seconds of typing and avoids
            // LRU bookkeeping on the hot path
            verdicts.removeAll(keepingCapacity: true)
        }
        verdicts[word] = verdict
    }
}

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

    func isDefaultDStrokeAbbreviation(_ word: String) -> Bool {
        let characters = Array(word)
        guard characters.count >= 2, characters.contains("Đ") else {
            return false
        }

        return characters.allSatisfy { $0.isLetter && String($0) == String($0).uppercased() }
    }

    private func isUppercaseVietnameseMarkedAbbreviation(_ word: String) -> Bool {
        let characters = Array(word)
        guard characters.count >= 2,
              characters.allSatisfy({ $0.isLetter && String($0) == String($0).uppercased() }),
              let first = characters.first else {
            return false
        }

        return isVietnameseMarkedLetter(first)
    }

    private func isVietnameseMarkedLetter(_ character: Character) -> Bool {
        let text = String(character)
        if text == "Đ" || text == "đ" {
            return true
        }

        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        return text.lowercased() != folded.lowercased()
    }

    /// Validate if a given word string is a valid Vietnamese word
    /// This is used for checking words from Accessibility API
    func checkWordSpelling(word: String) -> Bool {
        guard vCheckSpelling == 1 else {
            logCallback?("📖 checkWordSpelling: DISABLED (spellCheckEnabled=false)")
            return true // Spell checking disabled
        }

        guard !word.isEmpty else {
            logCallback?("📖 checkWordSpelling: SKIPPED (empty word)")
            return true // Empty word is considered valid
        }

        // When custom consonants are enabled, words containing those consonants
        // should be considered valid without dictionary check
        if !vCustomConsonants.isEmpty {
            let lowercaseWord = word.lowercased()
            let customChars = customConsonantChars

            if let firstChar = lowercaseWord.first, customChars.contains(firstChar) {
                logCallback?("📖 checkWordSpelling: SKIPPED (customConsonant, starts with '\(firstChar)')")
                return true
            }

            for consonant in customChars {
                if lowercaseWord.contains(consonant) {
                    logCallback?("📖 checkWordSpelling: SKIPPED (customConsonant, contains '\(consonant)')")
                    return true
                }
            }
        }

        // All-caps abbreviations containing Đ at any position (ĐN, HĐ, PGĐ, HĐQT, ĐHQG)
        // are valid short forms even though they are not dictionary words. Vietnamese-first:
        // typing HĐ/GĐ is far more common than raw English caps like HDD, and the raw
        // form is still reachable with an extra D (HDDD → HDD).
        if isDefaultDStrokeAbbreviation(word) {
            logCallback?("📖 checkWordSpelling: SKIPPED (uppercase d-stroke abbreviation), word='\(word)'")
            return true
        }

        // Optional broader rule: all-caps abbreviations that start with a Vietnamese
        // marked letter (ÂT, ÔM, ỨH, ...) can also skip restore, but default is OFF
        // to avoid broad false negatives in spell checking.
        if vSkipRestoreForUppercaseVietnameseAbbreviations == 1,
           isUppercaseVietnameseMarkedAbbreviation(word) {
            logCallback?("📖 checkWordSpelling: SKIPPED (uppercase Vietnamese abbreviation), word='\(word)'")
            return true
        }

        if let spellCheckVerdictOverride {
            return spellCheckVerdictOverride(word)
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
    /// This serves as a fallback when word is not found in the custom dictionary.
    /// Results are memoized (NLSpellVerdictCache) — the XPC round-trip to
    /// AppleSpell is the single most expensive step on the spell-check path.
    private func isValidWordUsingNaturalLanguage(_ word: String) -> Bool {
        if let cached = NLSpellVerdictCache.verdict(for: word) {
            return cached
        }

        // Use NLSpellChecker to check spelling
        let checker = NSSpellChecker.shared

        // Check spelling for Vietnamese language
        let range = checker.checkSpelling(of: word, startingAt: 0, language: "vi", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

        // If range.location == NSNotFound, the word is correctly spelled
        let isCorrect = range.location == NSNotFound

        NLSpellVerdictCache.store(isCorrect, for: word)
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
