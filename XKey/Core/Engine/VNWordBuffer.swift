//
//  VNWordBuffer.swift
//  XKey
//
//  Manages the current word being typed and its state
//

import Foundation

class VNWordBuffer {
    
    // MARK: - Word State
    
    struct WordState {
        var consonant1: ConsonantSequence?
        var vowelSequence: [VNVowel] = []
        var consonant2: ConsonantSequence?
        var tone: VNTone = .none
        var tonePosition: Int = 0

        var isEmpty: Bool {
            consonant1 == nil && vowelSequence.isEmpty && consonant2 == nil
        }

        var hasVowels: Bool {
            !vowelSequence.isEmpty
        }

        var hasEndingConsonant: Bool {
            consonant2 != nil
        }

        var debugDescription: String {
            var parts: [String] = []
            if let c1 = consonant1 {
                parts.append("C1:\(c1.consonant.rawValue)")
            }
            if !vowelSequence.isEmpty {
                let vowels = vowelSequence.map { String(describing: $0) }.joined(separator: ",")
                parts.append("V:[\(vowels)]")
            }
            if let c2 = consonant2 {
                parts.append("C2:\(c2.consonant.rawValue)")
            }
            if tone != .none {
                parts.append("T:\(tone)")
            }
            return parts.isEmpty ? "empty" : parts.joined(separator: " ")
        }
    }
    
    // MARK: - Properties

    private(set) var state = WordState()
    private(set) var keyStrokes: [KeyStroke] = []
    private(set) var characters: [VNCharacter] = []

    // Track the start index of current word in keystroke buffer
    // This is used to calculate backspace count for free marking
    private(set) var wordStartIndex: Int = 0

    private let maxBufferSize = 40
    
    var logCallback: ((String) -> Void)?
    
    // MARK: - Key Stroke Tracking

    struct KeyStroke {
        let keyCode: UInt16
        let character: Character
        let isUppercase: Bool
        let timestamp: Date
        var isPassThrough: Bool = false  // Mark if this keystroke was pass-through (not consumed)
    }
    
    // MARK: - Public Methods
    
    func append(keyCode: UInt16, character: Character, isUppercase: Bool, isPassThrough: Bool = false) {
        let keyStroke = KeyStroke(
            keyCode: keyCode,
            character: character,
            isUppercase: isUppercase,
            timestamp: Date(),
            isPassThrough: isPassThrough
        )
        keyStrokes.append(keyStroke)

        // Prevent buffer overflow
        if keyStrokes.count > maxBufferSize {
            removeOldest()
        }
    }
    
    func clear() {
        state = WordState()
        keyStrokes.removeAll()
        characters.removeAll()
        wordStartIndex = 0
    }

    func restore(keyStrokes: [KeyStroke], state: WordState) {
        self.keyStrokes = keyStrokes
        self.state = state
        self.wordStartIndex = 0
        
        // Note: We trust the saved state because it was validated when saved.
        // If we rebuild here, we might lose important state information like tone position.
        // The state should already be correct from when it was saved.
    }

    /// Rebuild word state from current keystrokes without processing input
    /// This is similar to OpenKey's checkSpelling() - it analyzes the keystroke buffer
    /// and rebuilds the word state (consonants, vowels, tone) from scratch
    func rebuildStateFromKeyStrokes(inputProcessor: InputProcessor, logCallback: ((String) -> Void)? = nil) {
        logCallback?("    → rebuildStateFromKeyStrokes: \(keyStrokes.count) keystrokes, wordStartIndex=\(wordStartIndex)")

        // Clear current state
        state = WordState()

        // Process each keystroke to rebuild state
        for (index, keystroke) in keyStrokes.enumerated() {
            let action = inputProcessor.processKey(keystroke.character, isUppercase: keystroke.isUppercase)
            logCallback?("      [\(index)]: '\(keystroke.character)' → \(action)")

            // Apply action to state using existing methods
            switch action {
            case .appendConsonant(let consonant):
                // Check consonant2 first (if we have C1 + V + C2, new consonant might form compound with C2)
                if let existingConsonant = state.consonant2?.consonant, !state.vowelSequence.isEmpty {
                    // Try to form compound ending consonant (e.g., n + g → ng)
                    if let compoundConsonant = tryFormCompoundConsonant(existingConsonant, consonant) {
                        setConsonant2(.compound(compoundConsonant))
                        logCallback?("        → Formed compound ending consonant '\(compoundConsonant.rawValue)'")
                    } else {
                        // Cannot form compound ending consonant - this is a new word
                        // Mark this and all remaining keystrokes as pass-through
                        logCallback?("        → Cannot form compound ending consonant, marking remaining keystrokes as pass-through")
                        for i in index..<keyStrokes.count {
                            keyStrokes[i].isPassThrough = true
                        }
                        break
                    }
                } else if let existingConsonant = state.consonant1?.consonant, state.vowelSequence.isEmpty {
                    // Try to form compound consonant (e.g., n + h → nh)
                    if let compoundConsonant = tryFormCompoundConsonant(existingConsonant, consonant) {
                        setConsonant1(.compound(compoundConsonant))
                        logCallback?("        → Formed compound consonant '\(compoundConsonant.rawValue)'")
                    } else {
                        // Cannot form compound - this is a new word
                        // Mark this and all remaining keystrokes as pass-through
                        logCallback?("        → Cannot form compound, marking remaining keystrokes as pass-through")
                        for i in index..<keyStrokes.count {
                            keyStrokes[i].isPassThrough = true
                        }
                        break
                    }
                } else if let consonant1 = state.consonant1?.consonant, !state.vowelSequence.isEmpty, state.consonant2 == nil {
                    // Check if this is a double letter with consonant1 (e.g., d + u + d → đu)
                    if consonant1 == consonant && consonant == .d {
                        // Transform consonant1 to đ
                        setConsonant1(.single(.dd))
                        logCallback?("        → Double letter 'd' + 'd' → 'đ' (after vowels)")
                    } else {
                        // Not a double letter - set as ending consonant
                        let sequence: ConsonantSequence = consonant.isCompoundConsonant ? .compound(consonant) : .single(consonant)
                        setConsonant2(sequence)
                    }
                } else {
                    // No existing consonant to combine with
                    let sequence: ConsonantSequence = consonant.isCompoundConsonant ? .compound(consonant) : .single(consonant)
                    if state.consonant1 == nil {
                        setConsonant1(sequence)
                    } else if state.consonant2 == nil {
                        setConsonant2(sequence)
                    }
                }
            case .appendVowel(let vowel):
                addVowel(vowel)
            case .doubleLetter(let char):
                // Handle double letter - need to determine if it's vowel or consonant
                // IMPORTANT: Check if this is a double letter transformation (e.g., dd → đ)
                if let consonant = VNConsonant(rawValue: String(char)) {
                    // Check if previous keystroke is the same consonant
                    if index > 0 {
                        let prevKeystroke = keyStrokes[index - 1]
                        let prevAction = inputProcessor.processKey(prevKeystroke.character, isUppercase: prevKeystroke.isUppercase)
                        
                        // Check if previous keystroke is the same character
                        let isPrevSameChar: Bool
                        switch prevAction {
                        case .doubleLetter(let prevChar):
                            isPrevSameChar = prevChar == char
                        case .appendConsonant(let prevConsonant):
                            isPrevSameChar = prevConsonant.rawValue == String(char)
                        default:
                            isPrevSameChar = false
                        }
                        
                        // If previous is same consonant and we have no vowels yet, this is dd → đ
                        if isPrevSameChar && state.vowelSequence.isEmpty && char == "d" {
                            // Transform consonant1 to đ
                            setConsonant1(.single(.dd))
                            logCallback?("        → Double letter 'dd' → 'đ'")
                            break
                        }
                    }
                    
                    // Not a double letter transformation, process as normal consonant
                    let sequence: ConsonantSequence = consonant.isCompoundConsonant ? .compound(consonant) : .single(consonant)
                    if state.consonant1 == nil {
                        setConsonant1(sequence)
                    } else if state.consonant2 == nil {
                        setConsonant2(sequence)
                    }
                } else if let vowel = VNVowel(rawValue: String(char)) {
                    // Check if previous keystroke is the same vowel for double vowel transformation
                    if index > 0 {
                        let prevKeystroke = keyStrokes[index - 1]
                        let prevAction = inputProcessor.processKey(prevKeystroke.character, isUppercase: prevKeystroke.isUppercase)
                        
                        // Check if previous keystroke is the same vowel
                        let isPrevSameVowel: Bool
                        switch prevAction {
                        case .doubleLetter(let prevChar):
                            isPrevSameVowel = prevChar == char
                        case .appendVowel(let prevVowel):
                            isPrevSameVowel = prevVowel.rawValue == String(char)
                        default:
                            isPrevSameVowel = false
                        }
                        
                        // If previous is same vowel, check if this is marking or FREE UNDO
                        if isPrevSameVowel {
                            // Check if we already have 2+ base vowels in state
                            // If yes, don't transform (this is FREE UNDO result)
                            let baseVowelCount = state.vowelSequence.filter { $0 == vowel }.count
                            if baseVowelCount >= 2 {
                                // Already have 2+ base vowels, don't transform
                                logCallback?("        → Already have \(baseVowelCount) base vowels, not transforming")
                                addVowel(vowel)
                            } else {
                                // Check if next keystroke is also the same vowel (FREE UNDO pattern: o-o-o)
                                let isNextSameVowel: Bool
                                if index + 1 < keyStrokes.count {
                                    let nextKeystroke = keyStrokes[index + 1]
                                    let nextAction = inputProcessor.processKey(nextKeystroke.character, isUppercase: nextKeystroke.isUppercase)
                                    switch nextAction {
                                    case .doubleLetter(let nextChar):
                                        isNextSameVowel = nextChar == char
                                    case .appendVowel(let nextVowel):
                                        isNextSameVowel = nextVowel.rawValue == String(char)
                                    default:
                                        isNextSameVowel = false
                                    }
                                } else {
                                    isNextSameVowel = false
                                }
                                
                                if isNextSameVowel {
                                    // This is FREE UNDO pattern (o-o-o → goo)
                                    // Just add the vowel normally, don't transform
                                    logCallback?("        → FREE UNDO pattern detected, adding vowel normally")
                                    addVowel(vowel)
                                } else {
                                    // This is marking (o-o → gô)
                                    // Remove last vowel and add marked vowel
                                    if !state.vowelSequence.isEmpty {
                                        state.vowelSequence.removeLast()
                                    }
                                    
                                    // Add marked vowel based on char
                                    switch char {
                                    case "a":
                                        addVowel(.aCircumflex)
                                        logCallback?("        → Double vowel 'aa' → 'â'")
                                    case "e":
                                        addVowel(.eCircumflex)
                                        logCallback?("        → Double vowel 'ee' → 'ê'")
                                    case "o":
                                        addVowel(.oCircumflex)
                                        logCallback?("        → Double vowel 'oo' → 'ô'")
                                    default:
                                        addVowel(vowel)
                                    }
                                }
                            }
                            break
                        }
                    }
                    
                    // Not a double vowel transformation, add vowel normally
                    addVowel(vowel)
                }
            case .addHorn:
                // Add horn - check for "uo" pattern first (u + o → ư + ơ)
                if state.vowelSequence.count >= 2 {
                    // Check for "uo" or "ưo" pattern at any position
                    var foundPattern = false
                    for i in 0..<(state.vowelSequence.count - 1) {
                        if (state.vowelSequence[i] == .u && state.vowelSequence[i+1] == .o) ||
                           (state.vowelSequence[i] == .uHorn && state.vowelSequence[i+1] == .o) {
                            // Transform both to ư and ơ
                            state.vowelSequence[i] = .uHorn
                            state.vowelSequence[i+1] = .oHorn
                            logCallback?("        → Added horn: uo → ươ")
                            foundPattern = true
                            break
                        }
                    }
                    
                    if !foundPattern {
                        // No "uo" pattern, add horn to last vowel
                        let lastIndex = state.vowelSequence.count - 1
                        let lastVowel = state.vowelSequence[lastIndex]
                        
                        switch lastVowel {
                        case .u:
                            state.vowelSequence[lastIndex] = .uHorn
                            logCallback?("        → Added horn: u → ư")
                        case .o:
                            state.vowelSequence[lastIndex] = .oHorn
                            logCallback?("        → Added horn: o → ơ")
                        default:
                            break
                        }
                    }
                } else if !state.vowelSequence.isEmpty {
                    // Single vowel, add horn to it
                    let lastIndex = state.vowelSequence.count - 1
                    let lastVowel = state.vowelSequence[lastIndex]
                    
                    switch lastVowel {
                    case .u:
                        state.vowelSequence[lastIndex] = .uHorn
                        logCallback?("        → Added horn: u → ư")
                    case .o:
                        state.vowelSequence[lastIndex] = .oHorn
                        logCallback?("        → Added horn: o → ơ")
                    default:
                        break
                    }
                }
            case .addCircumflex:
                // Add circumflex to last vowel (a → â, e → ê, o → ô)
                if !state.vowelSequence.isEmpty {
                    let lastIndex = state.vowelSequence.count - 1
                    let lastVowel = state.vowelSequence[lastIndex]
                    
                    switch lastVowel {
                    case .a:
                        state.vowelSequence[lastIndex] = .aCircumflex
                        logCallback?("        → Added circumflex: a → â")
                    case .e:
                        state.vowelSequence[lastIndex] = .eCircumflex
                        logCallback?("        → Added circumflex: e → ê")
                    case .o:
                        state.vowelSequence[lastIndex] = .oCircumflex
                        logCallback?("        → Added circumflex: o → ô")
                    default:
                        break
                    }
                }
            case .addBreve:
                // Add breve to last vowel (a → ă)
                if !state.vowelSequence.isEmpty {
                    let lastIndex = state.vowelSequence.count - 1
                    let lastVowel = state.vowelSequence[lastIndex]
                    
                    if lastVowel == .a {
                        state.vowelSequence[lastIndex] = .aBreve
                        logCallback?("        → Added breve: a → ă")
                    }
                }
            case .addTone(let tone):
                // Auto-correct [ư, o] → [ư, ơ] before adding tone (like in processTone)
                if state.vowelSequence.count == 2 &&
                   state.vowelSequence[0] == .uHorn &&
                   state.vowelSequence[1] == .o {
                    state.vowelSequence[1] = .oHorn
                    logCallback?("        → Auto-correcting [ư, o] → [ư, ơ]")
                }
                
                // Find the position to add tone (usually on the main vowel)
                if !state.vowelSequence.isEmpty {
                    let position = VowelSequenceValidator.calculateTonePosition(
                        vowels: state.vowelSequence,
                        hasEndingConsonant: state.hasEndingConsonant,
                        modernStyle: true,
                        firstConsonant: state.consonant1?.consonant,
                        hasPassThroughAfterVowels: false
                    )
                    setTone(tone, at: position)
                }
            case .normal(let char):
                // Special handling for 'r' in Telex - it can be tone hỏi when after vowels
                if char == "r" && state.hasVowels {
                    // 'r' after vowels -> tone hỏi
                    if !state.vowelSequence.isEmpty {
                        let position = VowelSequenceValidator.calculateTonePosition(
                            vowels: state.vowelSequence,
                            hasEndingConsonant: state.hasEndingConsonant,
                            modernStyle: true,
                            firstConsonant: state.consonant1?.consonant,
                            hasPassThroughAfterVowels: false
                        )
                        setTone(.hookAbove, at: position)
                    }
                } else if let consonant = VNConsonant(rawValue: String(char)) {
                    // Normal consonant
                    let sequence: ConsonantSequence = consonant.isCompoundConsonant ? .compound(consonant) : .single(consonant)
                    if state.consonant1 == nil {
                        setConsonant1(sequence)
                    } else if state.consonant2 == nil {
                        setConsonant2(sequence)
                    }
                }
            default:
                break
            }
        }
    }

    func markWordStart() {
        wordStartIndex = keyStrokes.count
    }

    func setWordStartIndex(_ index: Int) {
        wordStartIndex = index
    }

    func getBackspaceCountFromWordStart() -> Int {
        // Calculate backspace count from word start to current position
        // This includes all keystrokes (consumed and pass-through)
        guard !keyStrokes.isEmpty && wordStartIndex < keyStrokes.count else {
            return 0
        }
        return keyStrokes.count - wordStartIndex
    }

    func getPassThroughCharactersFromWordStart(excludingLast: Bool = false) -> [Character] {
        // Get all pass-through characters from word start to current position
        guard !keyStrokes.isEmpty && wordStartIndex < keyStrokes.count else {
            return []
        }

        var passThrough: [Character] = []
        let endIndex = excludingLast ? keyStrokes.count - 1 : keyStrokes.count
        for i in wordStartIndex..<endIndex {
            if keyStrokes[i].isPassThrough {
                passThrough.append(keyStrokes[i].character)
            }
        }
        return passThrough
    }

    func hasPassThroughAfterVowels() -> Bool {
        // Check if there are any pass-through characters in the keystroke buffer
        // This is used to determine "terminated" status for tone position calculation
        //
        // In free marking mode, when we have:
        // - Word state: vowels = [y, e]
        // - Keystroke buffer: ["y", "e", "u" (pass-through)]
        // The vowel sequence is NOT terminated because there's a pass-through character after it
        guard !keyStrokes.isEmpty && wordStartIndex < keyStrokes.count else {
            return false
        }

        // Simply check if there are ANY pass-through characters from word start
        // If there are, it means the vowel sequence is not at the end of the word
        for i in wordStartIndex..<keyStrokes.count {
            if keyStrokes[i].isPassThrough {
                return true
            }
        }

        return false
    }
    
    func removeLastKeyStroke() {
        guard !keyStrokes.isEmpty else { return }
        keyStrokes.removeLast()
    }

    func removeKeyStroke(at index: Int) {
        guard index >= 0 && index < keyStrokes.count else { return }
        keyStrokes.remove(at: index)
    }

    func markLastKeystrokeAsPassThrough() {
        guard !keyStrokes.isEmpty else { return }
        let lastIndex = keyStrokes.count - 1
        var lastKeystroke = keyStrokes[lastIndex]
        lastKeystroke.isPassThrough = true
        keyStrokes[lastIndex] = lastKeystroke
    }
    
    // MARK: - State Management
    
    func setConsonant1(_ consonant: ConsonantSequence) {
        state.consonant1 = consonant
    }
    
    func addVowel(_ vowel: VNVowel) {
        state.vowelSequence.append(vowel)
    }
    
    func setVowelSequence(_ vowels: [VNVowel]) {
        state.vowelSequence = vowels
    }
    
    func setConsonant2(_ consonant: ConsonantSequence) {
        state.consonant2 = consonant
    }

    func clearConsonant2() {
        state.consonant2 = nil
    }
    
    func setTone(_ tone: VNTone, at position: Int) {
        state.tone = tone
        state.tonePosition = position
    }
    
    func removeTone() {
        state.tone = .none
        state.tonePosition = 0
    }

    func removeEndingConsonant() {
        state.consonant2 = nil
    }

    func updateState(_ newState: WordState) {
        state = newState
    }

    // MARK: - Vowel Transformation
    
    func transformVowel(at index: Int, to newVowel: VNVowel) -> Bool {
        guard index >= 0 && index < state.vowelSequence.count else {
            return false
        }
        
        var newSequence = state.vowelSequence
        newSequence[index] = newVowel
        
        // Validate new sequence
        if VowelSequenceValidator.isValid(newSequence) {
            state.vowelSequence = newSequence
            return true
        }
        
        return false
    }
    
    func replaceVowelSequence(_ newSequence: [VNVowel]) -> Bool {
        if VowelSequenceValidator.isValid(newSequence) {
            state.vowelSequence = newSequence
            return true
        }
        return false
    }
    
    // MARK: - Tone Management
    
    func canPlaceTone(_ tone: VNTone, modernStyle: Bool) -> Bool {
        guard state.hasVowels else { return false }

        // Calculate where tone should go
        let position = VowelSequenceValidator.calculateTonePosition(
            vowels: state.vowelSequence,
            hasEndingConsonant: state.hasEndingConsonant,
            modernStyle: modernStyle,
            firstConsonant: state.consonant1?.consonant,
            hasPassThroughAfterVowels: hasPassThroughAfterVowels()
        )

        return position >= 0 && position < state.vowelSequence.count
    }

    func updateTonePosition(modernStyle: Bool) {
        guard state.hasVowels else { return }

        let newPosition = VowelSequenceValidator.calculateTonePosition(
            vowels: state.vowelSequence,
            hasEndingConsonant: state.hasEndingConsonant,
            modernStyle: modernStyle,
            firstConsonant: state.consonant1?.consonant,
            hasPassThroughAfterVowels: hasPassThroughAfterVowels()
        )

        state.tonePosition = newPosition
    }
    
    // MARK: - Word Validation
    
    func isValidVietnameseWord() -> Bool {
        // Empty word is valid
        if state.isEmpty {
            return true
        }
        
        // Single consonant without vowel is valid (e.g., "đ" from "dd" before typing vowel)
        // This allows typing "đang" as "dd" + "a" + "ng"
        if !state.hasVowels && state.consonant1 != nil && state.consonant2 == nil {
            return true
        }
        
        // Must have at least one vowel
        guard state.hasVowels else {
            return false
        }
        

        
        // Validate vowel sequence
        if !VowelSequenceValidator.isValid(state.vowelSequence) {
            return false
        }
        
        // Validate consonant combinations
        if let c1 = state.consonant1, let c2 = state.consonant2 {
            return isValidConsonantCombination(c1, c2)
        }
        
        return true
    }
    
    private func isValidConsonantCombination(
        _ c1: ConsonantSequence,
        _ c2: ConsonantSequence
    ) -> Bool {
        // Vietnamese phonetic rules for consonant combinations
        // This is a simplified version - full implementation would include all rules
        
        let validEndingConsonants: Set<VNConsonant> = [
            .c, .ch, .m, .n, .ng, .nh, .p, .t
        ]
        
        return validEndingConsonants.contains(c2.consonant)
    }
    
    // MARK: - Character Generation
    
    func generateCharacters(codeTable: CodeTable) -> [VNCharacter] {
        var result: [VNCharacter] = []
        
        // Add first consonant
        if let c1 = state.consonant1 {
            let char = VNCharacter(
                consonant: c1.consonant,
                isUppercase: shouldCapitalizeConsonant1()
            )
            result.append(char)
        }
        
        // Add vowels with tone
        for (index, vowel) in state.vowelSequence.enumerated() {
            let tone = (index == state.tonePosition) ? state.tone : .none
            logCallback?("    generateCharacters: vowel[\(index)]=\(vowel), tone=\(tone), tonePos=\(state.tonePosition)")
            let char = VNCharacter(
                vowel: vowel,
                tone: tone,
                isUppercase: shouldCapitalizeVowel(at: index)
            )
            logCallback?("    → VNCharacter created: vowel=\(char.vowel?.rawValue ?? "nil"), tone=\(char.tone)")
            result.append(char)
        }
        
        // Add second consonant
        if let c2 = state.consonant2 {
            let char = VNCharacter(
                consonant: c2.consonant,
                isUppercase: false
            )
            result.append(char)
        }
        
        return result
    }
    
    private func shouldCapitalizeConsonant1() -> Bool {
        // Find the first keystroke that corresponds to consonant1
        // This should be the first non-pass-through keystroke from wordStartIndex
        guard !keyStrokes.isEmpty && wordStartIndex < keyStrokes.count else { 
            return keyStrokes.first?.isUppercase ?? false 
        }
        
        for i in wordStartIndex..<keyStrokes.count {
            if !keyStrokes[i].isPassThrough {
                return keyStrokes[i].isUppercase
            }
        }
        
        return keyStrokes.first?.isUppercase ?? false
    }
    
    private func shouldCapitalizeVowel(at index: Int) -> Bool {
        // Only capitalize the first character of the word
        // If we have consonant1, vowels should NOT be capitalized
        // If we don't have consonant1, only the first vowel (index 0) should be capitalized
        
        guard !keyStrokes.isEmpty && wordStartIndex < keyStrokes.count else { 
            return false 
        }
        
        // If we have consonant1, vowels should never be capitalized
        // because consonant1 is already the first character
        if state.consonant1 != nil {
            return false
        }
        
        // If no consonant1, only the first vowel (index 0) should be capitalized
        if index == 0 {
            for i in wordStartIndex..<keyStrokes.count {
                if !keyStrokes[i].isPassThrough {
                    return keyStrokes[i].isUppercase
                }
            }
            return false
        }
        
        // All other vowels should be lowercase
        return false
    }
    
    // MARK: - Helper Methods
    
    private func removeOldest() {
        // Keep only recent keystrokes
        let keepCount = maxBufferSize / 2
        keyStrokes = Array(keyStrokes.suffix(keepCount))
    }
    
    // MARK: - Debug
    
    var debugDescription: String {
        var parts: [String] = []
        
        if let c1 = state.consonant1 {
            parts.append("C1: \(c1.consonant.rawValue)")
        }
        
        if !state.vowelSequence.isEmpty {
            let vowelStr = state.vowelSequence.map { $0.rawValue }.joined()
            parts.append("V: \(vowelStr)")
        }
        
        if state.tone != .none {
            parts.append("Tone: \(state.tone.displayName) at \(state.tonePosition)")
        }
        
        if let c2 = state.consonant2 {
            parts.append("C2: \(c2.consonant.rawValue)")
        }
        
        return parts.joined(separator: ", ")
    }
    
    // MARK: - Helper Methods for Rebuild
    
    /// Try to form a compound consonant from two single consonants
    /// Returns the compound consonant if valid, nil otherwise
    private func tryFormCompoundConsonant(_ first: VNConsonant, _ second: VNConsonant) -> VNConsonant? {
        // Valid Vietnamese compound consonants:
        // ch, gh, gi, kh, ng, ngh, nh, ph, qu, th, tr
        
        let combined = first.rawValue + second.rawValue
        
        switch combined {
        case "ch": return .ch
        case "gh": return .gh
        case "gi": return .gi
        case "kh": return .kh
        case "ng": return .ng
        case "nh": return .nh
        case "ph": return .ph
        case "qu": return .qu
        case "th": return .th
        case "tr": return .tr
        default: return nil
        }
    }
}

