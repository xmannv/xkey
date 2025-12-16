//
//  VowelSequenceValidator.swift
//  XKey
//
//  Validates Vietnamese vowel sequences based on phonetic rules
//

import Foundation

struct VowelSequenceValidator {

    // MARK: - Vowel Sequence Properties

    /// Vowel sequences that are "complete" (can accept tone without ending consonant)
    /// Based on Unikey's VSeqList[].complete flag
    ///
    /// Complete sequences (complete = 1):
    /// - ai, ao, au, ay (diphthongs ending in i/o/u/y)
    /// - eu, eo
    /// - ia, ie, iu
    /// - ua, ue, ui, uu, uy
    /// - ya, ye, yu
    /// - All sequences with circumflex or horn
    ///
    /// Incomplete sequences (complete = 0):
    /// - oa, oe, uo, ie, ue, ye, ưo (need ending consonant or are exceptions in modern style)
    private static let completeSequences: Set<[VNVowel]> = [
        // Complete double vowels (complete = 1, conSuffix = 0)
        [.a, .i], [.a, .o], [.a, .u], [.a, .y],  // ai, ao, au, ay - ukengine.cpp line 90-93
        [.e, .o],                                 // eo - ukengine.cpp line 96
        [.i, .a], [.i, .u],                      // ia, iu - ukengine.cpp line 99, 102
        [.o, .i],                                 // oi - ukengine.cpp line 106
        [.u, .a], [.u, .i],                      // ua, ui - ukengine.cpp line 109, 113
        [.y, .a], [.y, .u],                      // ya, yu - ukengine.cpp line (uh sequences)

        // Complete double vowels with breve (complete = 1, conSuffix = 1)
        [.o, .aBreve],  // oă (hoặc, loại) - ukengine.cpp line 104

        // Complete double vowels with circumflex (complete = 1, conSuffix = 1)
        [.aCircumflex, .u], [.aCircumflex, .y],  // âu, ây - ukengine.cpp line 94-95
        [.eCircumflex, .u],                       // êu - ukengine.cpp line 98
        [.i, .eCircumflex],  // iê (việt, tiên) - ukengine.cpp line 101
        [.oCircumflex, .i],  // ôi - ukengine.cpp line 107
        [.u, .aCircumflex],  // uâ (xuân, tuần) - ukengine.cpp line 110
        [.u, .eCircumflex],  // uê (thuê, xuê) - ukengine.cpp line 112
        [.u, .oCircumflex],  // uô (muốn, thuốc) - ukengine.cpp line 115
        [.y, .eCircumflex],  // yê (yêu, yếu) - ukengine.cpp line 125

        // Complete double vowels with horn (complete = 1, conSuffix = 1)
        [.oHorn, .i],  // ơi - ukengine.cpp line 108
        [.u, .oHorn],  // uơ (lươn) - ukengine.cpp line 116
        [.u, .y],  // uy (uy, huy) - ukengine.cpp line 118
        [.uHorn, .a], [.uHorn, .i], [.uHorn, .u],  // ưa, ưi, ưu - ukengine.cpp line 119, 120, 123
        [.uHorn, .oHorn],  // ươ (trường, lường) - ukengine.cpp line 122

        // Complete triple vowels (complete = 1)
        [.i, .eCircumflex, .u],  // iêu (tiêu, điều) - ukengine.cpp line 127
        [.o, .a, .i],  // oai (loai, hoài) - ukengine.cpp line 128
        [.o, .a, .y],  // oay (hoay) - ukengine.cpp line 129
        [.o, .e, .o],  // oeo (kẹo, khéo) - ukengine.cpp line 130
        [.u, .aCircumflex, .y],  // uây (thuây) - ukengine.cpp line 132
        [.u, .oCircumflex, .i],  // uôi (tuổi, chuối) - ukengine.cpp line 135
        [.u, .y, .a],  // uya (khuyá) - ukengine.cpp line 138
        [.u, .y, .eCircumflex],  // uyê (quyền, tuyên) - ukengine.cpp line 140
        [.u, .y, .u],  // uyu (khuyủ) - ukengine.cpp line 141
        [.uHorn, .oHorn, .i],  // ươi (người, tươi) - ukengine.cpp line 144
        [.uHorn, .oHorn, .u],  // ươu (hương, thương) - ukengine.cpp line 145
    ]

    /// Vowel sequences that can have ending consonant (conSuffix = 1)
    /// Based on Unikey's VSeqList[].conSuffix flag
    /// These sequences have different tone position rules:
    /// - When no ending consonant: tone on LAST vowel (position = len-1)
    /// - When has ending consonant: tone on LAST vowel (position = len-1)
    ///
    /// Examples:
    /// - [u, a]: "quar" → "quả" (tone on 'a'), "quan" → "quán" (tone on 'a')
    private static let sequencesWithConsonantSuffix: Set<[VNVowel]> = [
        // Double vowels with conSuffix = 1
        [.o, .a], [.o, .aBreve], [.o, .e],  // oa, oă, oe - ukengine.cpp line 103-105
        [.u, .a], [.u, .aCircumflex],  // ua, uâ - ukengine.cpp line 109-110
        [.u, .e], [.u, .eCircumflex],  // ue, uê - ukengine.cpp line 111-112
        [.u, .o], [.u, .oCircumflex], [.u, .oHorn],  // uo, uô, uơ - ukengine.cpp line 114-116
        [.u, .y],  // uy - ukengine.cpp line 118
        [.i, .e], [.i, .eCircumflex],  // ie, iê - ukengine.cpp line 100-101
        [.y, .e], [.y, .eCircumflex],  // ye, yê - ukengine.cpp line 124-125
        [.uHorn, .o], [.uHorn, .oHorn],  // ưo, ươ - ukengine.cpp line 121-122

        // Triple vowels with conSuffix = 1
        [.u, .y, .e], [.u, .y, .eCircumflex],  // uye, uyê - ukengine.cpp line 139-140
    ]

    /// Vowel sequences that are "incomplete" (need ending consonant to be valid)
    /// Based on Unikey's VSeqList[].complete = 0
    private static let incompleteSequences: Set<[VNVowel]> = [
        // Double vowels with complete = 0
        [.e, .u],  // eu (complete = 0, conSuffix = 0) - ukengine.cpp line 97
        [.i, .e],  // ie (complete = 0, conSuffix = 1) - ukengine.cpp line 100
        [.u, .e],  // ue (complete = 0, conSuffix = 1) - ukengine.cpp line 111
        [.u, .o],  // uo (complete = 0, conSuffix = 1) - ukengine.cpp line 114
        [.u, .u],  // uu (complete = 0, conSuffix = 0) - ukengine.cpp line 117
        [.y, .e],  // ye (complete = 0, conSuffix = 1) - ukengine.cpp line 124
        [.uHorn, .o],  // ưo (complete = 0, conSuffix = 1) - ukengine.cpp line 121

        // Triple vowels with complete = 0
        [.i, .e, .u],  // ieu (complete = 0, conSuffix = 0) - ukengine.cpp line 126
        [.u, .a, .y],  // uay (complete = 0, conSuffix = 0) - ukengine.cpp line 131
        [.u, .o, .i],  // uoi (complete = 0, conSuffix = 0) - ukengine.cpp line 133
        [.u, .o, .u],  // uou (complete = 0, conSuffix = 0) - ukengine.cpp line 134
        [.u, .oHorn, .i],  // uơi (complete = 0, conSuffix = 0) - ukengine.cpp line 136
        [.u, .oHorn, .u],  // uơu (complete = 0, conSuffix = 0) - ukengine.cpp line 137
        [.u, .y, .e],  // uye (complete = 0, conSuffix = 1) - ukengine.cpp line 139
        [.uHorn, .o, .i],  // ưoi (complete = 0, conSuffix = 0) - ukengine.cpp line 142
        [.uHorn, .o, .u],  // ưou (complete = 0, conSuffix = 0) - ukengine.cpp line 143
    ]

    // MARK: - Valid Vowel Sequences

    // All valid Vietnamese vowel sequences
    private static let validSequences: Set<[VNVowel]> = [
        // Single vowels
        [.a], [.e], [.i], [.o], [.u], [.y],
        [.aCircumflex], [.aBreve], [.eCircumflex],
        [.oCircumflex], [.oHorn], [.uHorn],

        // Double vowels
        [.a, .i], [.a, .o], [.a, .u], [.a, .y],
        [.e, .o], [.e, .u],
        [.i, .a], [.i, .e], [.i, .u],
        [.o, .a], [.o, .e], [.o, .i],
        [.u, .a], [.u, .e], [.u, .i], [.u, .o], [.u, .u], [.u, .y],
        [.y, .a], [.y, .e], [.y, .u],

        // Double vowels with breve
        [.o, .aBreve],  // oă (hoặc, loại, toàn) - ukengine.cpp line 104

        // Double vowels with circumflex
        [.aCircumflex, .u], [.aCircumflex, .y],
        [.eCircumflex, .u],
        [.i, .eCircumflex],  // iê (việt, tiên, miền, điểm) - ukengine.cpp line 101
        [.oCircumflex, .i],
        [.u, .aCircumflex],  // uâ (xuân, tuần, luận) - ukengine.cpp line 110
        [.u, .eCircumflex],  // uê (thuê, xuê, huê) - ukengine.cpp line 112
        [.u, .oCircumflex],  // uô (muốn, thuốc, cuốn) - ukengine.cpp line 115
        [.y, .eCircumflex],  // yê (yêu, yếu, yên) - ukengine.cpp line 125

        // Double vowels with horn
        [.oHorn, .i],
        [.u, .oHorn],  // uơ (lươn, tươm) - ukengine.cpp line 116
        [.uHorn, .a], [.uHorn, .i], [.uHorn, .o], [.uHorn, .u],
        [.uHorn, .oHorn],  // ươ (trường, lường, cường) - ukengine.cpp line 122
        
        // Triple vowels
        [.i, .e, .u],  // ieu (tiếu, điếu) - ukengine.cpp line 126
        [.i, .eCircumflex, .u],  // iêu (tiêu, điều, siêu) - ukengine.cpp line 127
        [.i, .a, .u],  // iau (yêu, giàu) - ukengine.cpp line 126 (same as ieu)
        [.o, .a, .i],  // oai (loai, hoài) - ukengine.cpp line 128
        [.o, .a, .y],  // oay (hoay) - ukengine.cpp line 129
        [.o, .e, .o],  // oeo (kẹo, khéo) - ukengine.cpp line 130
        [.u, .a, .i],  // uai (quai, khuây) - ukengine.cpp line 131 (same as uay)
        [.u, .a, .y],  // uay (quay, khuây) - ukengine.cpp line 131
        [.u, .aCircumflex, .y],  // uây (thuây) - ukengine.cpp line 132
        [.u, .e, .i],  // uei (tuếch) - existing
        [.u, .o, .i],  // uoi (chuối, tuổi) - ukengine.cpp line 133
        [.u, .o, .u],  // uou (rượu) - ukengine.cpp line 134
        [.u, .oCircumflex, .i],  // uôi (tuổi, chuối, nguội) - ukengine.cpp line 135
        [.u, .oHorn, .i],  // uơi (tươi) - ukengine.cpp line 136
        [.u, .oHorn, .u],  // uơu (hương) - ukengine.cpp line 137
        [.u, .y, .a],  // uya (khuyá) - ukengine.cpp line 138
        [.u, .y, .e],  // uye (quyết, tuyệt) - ukengine.cpp line 139
        [.u, .y, .eCircumflex],  // uyê (quyền, tuyên) - ukengine.cpp line 140
        [.u, .y, .u],  // uyu (khuyủ) - ukengine.cpp line 141
        [.uHorn, .o, .i],  // ưoi (ướt, mười) - ukengine.cpp line 142
        [.uHorn, .o, .u],  // ưou (ương) - ukengine.cpp line 143
        [.uHorn, .oHorn, .i],  // ươi (người, tươi, cười) - ukengine.cpp line 144
        [.uHorn, .oHorn, .u]  // ươu (hương, thương) - ukengine.cpp line 145
    ]
    
    // MARK: - Validation
    
    static func isValid(_ sequence: VowelSequence) -> Bool {
        return validSequences.contains(sequence.vowels)
    }
    
    static func isValid(_ vowels: [VNVowel]) -> Bool {
        return validSequences.contains(vowels)
    }
    
    // MARK: - Tone Position Calculation
    
    /// Calculate the position where tone should be placed in a vowel sequence
    /// Based on Unikey's algorithm (ukengine.cpp:929-951)
    ///
    /// Unikey logic:
    /// - Single vowel: position 0
    /// - Triple vowels: position 1 (middle)
    /// - Double vowels with roof/hook: position depends on vowel type
    /// - Double vowels: terminated ? 0 : 1
    ///   WHERE terminated = (vowel sequence is complete AND at end of word)
    ///
    ///   Complete sequences (ai, ao, au, ay, etc.):
    ///     - At end of word (no ending consonant) → position 0 (first vowel)
    ///     - Has ending consonant → position 1 (second vowel)
    ///
    ///   Incomplete sequences (oa, oe):
    ///     - Always position 1 (second vowel)
    ///     - Exception: modern style oa, oe, uy → always position 1
    static func calculateTonePosition(
        vowels: [VNVowel],
        hasEndingConsonant: Bool,
        modernStyle: Bool,
        firstConsonant: VNConsonant? = nil,
        hasPassThroughAfterVowels: Bool = false
    ) -> Int {
        let count = vowels.count

        // Single vowel: tone goes on that vowel
        if count == 1 {
            return 0
        }

        // Check if vowel has roof (circumflex)
        // If roof exists, tone goes on the vowel with roof
        for (index, vowel) in vowels.enumerated() {
            if vowel.hasCircumflex {
                return index
            }
        }

        // Check if vowel has hook (horn)
        // Special cases for horn vowels
        for (index, vowel) in vowels.enumerated() {
            if vowel.hasHorn {
                // Special case: ươ sequences (u+o+, u+o+i, u+o+u)
                if count >= 2 && index == 0 && vowel == .uHorn {
                    if count == 2 && vowels[1] == .oHorn {
                        return 1  // ươ → tone on ơ
                    }
                    if count == 3 && vowels[1] == .oHorn {
                        return 1  // ươi, ươu → tone on ơ (middle)
                    }
                }
                return index
            }
        }

        // Triple vowels: tone on middle vowel
        if count == 3 {
            return 1
        }

        // Double vowels: apply Unikey's rule
        if count == 2 {
            // Special case for oi, ai, ui (Engine.cpp line 641-646)
            // These sequences always have tone on FIRST vowel
            if (vowels[0] == .o && vowels[1] == .i) ||
               (vowels[0] == .a && vowels[1] == .i) ||
               (vowels[0] == .u && vowels[1] == .i) {
                return 0
            }

            // Special case for ay without ending consonant (Engine.cpp line 647-649)
            if vowels[0] == .a && vowels[1] == .y {
                if !hasEndingConsonant {
                    return 0
                }
                // With ending consonant, fall through to normal logic
            }

            // Special case for oo (Engine.cpp line 720-723)
            // Example: "thoong" → "thoóng"
            if vowels[0] == .o && vowels[1] == .o {
                return 1
            }

            // Special case for ưu (uHorn + u) (Engine.cpp line 688-695)
            if vowels[0] == .uHorn && vowels[1] == .u {
                return 0
            }
            // Special case for "ua" sequence
            // Rule from OpenKey Engine.cpp line 710-719:
            // - "qu" + "a" → vowel sequence is [.a] (single vowel), tone on 'a' ✓
            // - "c" + "ua" without ending consonant → tone on 'u' (position 0): của, mua
            // - "c" + "ua" with ending consonant → fall through to normal logic
            if vowels[0] == .u && vowels[1] == .a {
                if !hasEndingConsonant {
                    // No ending consonant → tone on 'u' (position 0)
                    return 0
                }
                // Has ending consonant → fall through to normal logic
            }

            // Special case for "ia", "iu", "io", "ya" sequences
            // Rule from OpenKey Engine.cpp line 699-709 and 688-695:
            // - If preceded by "gi" → tone on second vowel (position 1)
            // - Otherwise → tone on first vowel (position 0)
            if (vowels[0] == .i || vowels[0] == .y) &&
               (vowels[1] == .a || vowels[1] == .u || vowels[1] == .o) {
                if firstConsonant == .gi {
                    return 1
                } else {
                    return 0
                }
            }

            // Check if sequence can have ending consonant (conSuffix = 1)
            let hasConsonantSuffix = sequencesWithConsonantSuffix.contains(vowels)

            if hasConsonantSuffix {
                // Special case: Modern Style for oa, oe, uy (Specification Rule 2)
                // Modern Style ONLY applies when there IS an ending consonant
                // Examples: 
                //   "hoan" → "hoán" (has ending consonant 'n' → tone on 'a')
                //   "hoa" → "hóa" (no ending consonant → tone on 'o')
                if modernStyle && hasEndingConsonant && (vowels == [.o, .a] || vowels == [.o, .e] || vowels == [.u, .y]) {
                    return 1
                }
                
                // Old Style logic (default):
                // Sequences with conSuffix=1: tone position depends on "terminated"
                // Following Unikey's rule: terminated ? 0 : 1
                // WHERE terminated = (vowel sequence is at end of word)
                //
                // A vowel sequence is NOT terminated if:
                // 1. Has ending consonant (e.g., "hoan" → vowels not at end)
                // 2. Has pass-through characters after vowels (e.g., "yeus" → "ye" + "u" pass-through)
                //
                // Examples:
                //   hoaf → hóa (no ending consonant, no pass-through → terminated → tone on 'o', position 0)
                //   hoan → hoán (has ending consonant → not terminated → tone on 'a', position 1)
                //   yeus → yếu (no ending consonant, but has pass-through 'u' → not terminated → tone on 'e', position 1)
                let terminated = !hasEndingConsonant && !hasPassThroughAfterVowels
                let pos = terminated ? 0 : 1
                return pos
            }

            // Check if sequence is "complete" (can accept tone without ending consonant)
            let isComplete = completeSequences.contains(vowels)
            let isIncomplete = incompleteSequences.contains(vowels)

            // Unikey's core rule: terminated ? 0 : 1
            // WHERE terminated = (sequence is complete AND at end of word)
            //
            // Complete sequences (ai, ao, au, ay, etc.) with conSuffix=0:
            //   - At end of word (no ending consonant) → terminated = true → position 0
            //   - Has ending consonant → terminated = false → position 1
            //
            // Incomplete sequences (oa, oe):
            //   - Always terminated = false → position 1

            if isComplete {
                // Complete sequence: tone position depends on ending consonant
                // No ending consonant → at end of word → terminated = true → position 0
                // Has ending consonant → not at end → terminated = false → position 1
                let pos = hasEndingConsonant ? 1 : 0
                return pos
            } else if isIncomplete {
                // Incomplete sequence: tone position ALSO depends on ending consonant
                // Even though sequence is "incomplete", tone placement follows same rule:
                // No ending consonant → position 0 (first vowel)
                // Has ending consonant → position 1 (second vowel)
                // Examples:
                //   hoa + tone → hóa (no ending consonant → tone on 'o')
                //   hoan + tone → hoán (has ending consonant 'n' → tone on 'a')
                let pos = hasEndingConsonant ? 1 : 0
                return pos
            } else {
                // Unknown sequence: default to position 0
                return 0
            }
        }

        return 0
    }
    
    // MARK: - Sequence Transformation
    
    /// Check if adding circumflex to a vowel creates valid sequence
    static func canAddCircumflex(to vowel: VNVowel, in sequence: [VNVowel]) -> Bool {
        let transformed = transformWithCircumflex(vowel)
        guard let newVowel = transformed else { return false }
        
        var newSequence = sequence
        if let index = sequence.firstIndex(of: vowel) {
            newSequence[index] = newVowel
        }
        
        return isValid(newSequence)
    }
    
    /// Check if adding breve to a vowel creates valid sequence
    static func canAddBreve(to vowel: VNVowel, in sequence: [VNVowel]) -> Bool {
        guard vowel == .a else { return false }
        
        var newSequence = sequence
        if let index = sequence.firstIndex(of: .a) {
            newSequence[index] = .aBreve
        }
        
        return isValid(newSequence)
    }
    
    /// Check if adding horn to a vowel creates valid sequence
    static func canAddHorn(to vowel: VNVowel, in sequence: [VNVowel]) -> Bool {
        let transformed = transformWithHorn(vowel)
        guard let newVowel = transformed else { return false }
        
        var newSequence = sequence
        if let index = sequence.firstIndex(of: vowel) {
            newSequence[index] = newVowel
        }
        
        return isValid(newSequence)
    }
    
    // MARK: - Helper Methods
    
    private static func isSequence(_ vowels: [VNVowel], _ expected: [VNVowel]) -> Bool {
        return vowels == expected
    }
    
    private static func transformWithCircumflex(_ vowel: VNVowel) -> VNVowel? {
        switch vowel {
        case .a: return .aCircumflex
        case .e: return .eCircumflex
        case .o: return .oCircumflex
        default: return nil
        }
    }
    
    private static func transformWithHorn(_ vowel: VNVowel) -> VNVowel? {
        switch vowel {
        case .o: return .oHorn
        case .u: return .uHorn
        default: return nil
        }
    }
    
    // MARK: - Vowel Sequence Analysis
    
    /// Find the rightmost vowel in a sequence that can accept a tone
    static func findToneableVowelPosition(in vowels: [VNVowel]) -> Int? {
        // In Vietnamese, typically the main vowel (which can have tone) is:
        // - The only vowel in single vowel sequences
        // - Determined by specific rules in multi-vowel sequences
        
        if vowels.isEmpty {
            return nil
        }
        
        if vowels.count == 1 {
            return 0
        }
        
        // For multi-vowel sequences, use the tone position calculation
        return calculateTonePosition(vowels: vowels, hasEndingConsonant: false, modernStyle: true)
    }
    
    /// Check if a vowel sequence is complete (no more vowels can be added)
    static func isComplete(_ vowels: [VNVowel]) -> Bool {
        // A sequence is complete if adding any vowel would make it invalid
        for vowel in VNVowel.allCases {
            var testSequence = vowels
            testSequence.append(vowel)
            if isValid(testSequence) {
                return false
            }
        }
        return true
    }
}

