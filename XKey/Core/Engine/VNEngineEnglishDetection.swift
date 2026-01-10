//
//  VNEngineEnglishDetection.swift
//  XKey
//
//  English word detection for spell checking optimization
//

import Foundation

// MARK: - Fast English Detection (for spell check optimization)

extension String {
    
    // ============================================
    // MARK: - Static Lookup Tables for Performance
    // ============================================
    
    /// Characters that NEVER start a Vietnamese word
    /// Vietnamese alphabet does not include: f, j, w, z
    /// Any word starting with these is 100% NOT Vietnamese
    private static let impossibleStartingChars: Set<Character> = ["f", "j", "w", "z"]
    
    // ============================================
    // MARK: - Valid Vietnamese Input Sequences (Telex & VNI)
    // ============================================
    // These patterns are VALID input sequences that produce Vietnamese characters
    // They should NOT be flagged as "impossible" patterns
    //
    // TELEX INPUT METHOD:
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ dd      │ đ       │ Valid at word start (đi, đến, đã)  │
    // │ aa      │ â       │ Vowel modifier (cân, tâm)          │
    // │ ee      │ ê       │ Vowel modifier (kê, đê)            │
    // │ oo      │ ô       │ Vowel modifier (cô, hô)            │
    // │ aw      │ ă       │ Vowel modifier (bắt, ăn)           │
    // │ ow      │ ơ       │ Vowel modifier (cơ, mơ)            │
    // │ uw      │ ư       │ Vowel modifier (cư, tư)            │
    // │ w       │ ư       │ Standalone ư                       │
    // │ [       │ ơ       │ Bracket for ơ                      │
    // │ ]       │ ư       │ Bracket for ư                      │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // VNI INPUT METHOD:
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ d9      │ đ       │ Valid at word start (đi, đến, đã)  │
    // │ a6      │ â       │ Vowel + 6 = circumflex (^)         │
    // │ e6      │ ê       │ Vowel + 6 = circumflex (^)         │
    // │ o6      │ ô       │ Vowel + 6 = circumflex (^)         │
    // │ a8      │ ă       │ Vowel + 8 = breve (˘)              │
    // │ o7      │ ơ       │ Vowel + 7 = horn (ơ, ư)            │
    // │ u7      │ ư       │ Vowel + 7 = horn (ơ, ư)            │
    // │ 1-5     │ tones   │ Tone marks after vowels            │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // QUICK TELEX (when vQuickTelex = 1):
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ cc      │ ch      │ Quick consonant (chào, chính)      │
    // │ gg      │ gi      │ Quick consonant (giá, giúp)        │
    // │ kk      │ kh      │ Quick consonant (không, khác)      │
    // │ nn      │ ng      │ Quick consonant (người, ngày)      │
    // │ qq      │ qu      │ Quick consonant (quá, quên)        │
    // │ pp      │ ph      │ Quick consonant (phải, phong)      │
    // │ tt      │ th      │ Quick consonant (thì, thế)         │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // IMPORTANT: "dd", "d9", and Quick Telex patterns are VALID starting sequences!
    // They should be EXCLUDED from impossible patterns.
    
    /// Valid 2-letter starting patterns for TELEX input method
    /// These produce valid Vietnamese characters and should NOT be blocked
    /// Includes: dd → đ, and Quick Telex patterns (cc, gg, kk, nn, qq, pp, tt)
    private static let validTelexStartingPatterns: Set<String> = [
        // Standard Telex
        "dd",  // dd → đ (đi, đến, đã, đây, đó, đang, được, đầu, đề)
        
        // Quick Telex (double consonants at word start)
        "cc",  // cc → ch (chào, chính, cho, chúng)
        "gg",  // gg → gi (giá, giúp, gì, giờ)
        "kk",  // kk → kh (không, khác, khi, khó)
        "nn",  // nn → ng (người, ngày, nghĩ, nghe)
        "qq",  // qq → qu (quá, quên, quốc, quen)
        "pp",  // pp → ph (phải, phong, phố, phim)
        "tt",  // tt → th (thì, thế, thành, theo)
    ]
    
    /// Valid 2-letter starting patterns for VNI input method
    /// These produce valid Vietnamese characters and should NOT be blocked
    private static let validVNIStartingPatterns: Set<String> = [
        "d9",  // d9 → đ (đi, đến, đã, đây, đó, đang, được, đầu, đề)
    ]
    
    /// Combined valid starting patterns for any input method
    /// Use this when input type is unknown or to be safe
    private static let allValidInputStartingPatterns: Set<String> = [
        // Telex patterns
        "dd",  // đ
        "cc",  // ch (Quick Telex)
        "gg",  // gi (Quick Telex)
        "kk",  // kh (Quick Telex)
        "nn",  // ng (Quick Telex)
        "qq",  // qu (Quick Telex)
        "pp",  // ph (Quick Telex)
        "tt",  // th (Quick Telex)
        // VNI patterns
        "d9",  // đ
    ]
    
    /// Set of 2-letter initial clusters that are IMPOSSIBLE in Vietnamese
    /// Vietnamese valid initials: b, c, ch, d, đ, g, gh, gi, h, k, kh, l, m, n,
    ///                           ng, ngh, nh, p, ph, qu, r, s, t, th, tr, v, x
    private static let impossible2LetterPrefixes: Set<String> = [
        // ========================================
        // L-clusters (consonant + L) - Vietnamese NEVER has these
        // NOTE: "yl" is EXCLUDED because 'y' is a vowel in Vietnamese
        // ========================================
        "bl", "cl", "dl", "fl", "gl", "hl", "jl", "kl", "ml", "nl",
        "pl", "rl", "sl", "tl", "vl", "wl", "xl", "zl",
        
        // ========================================
        // R-clusters (consonant + R) - Vietnamese only has "tr", exclude it
        // NOTE: "yr" is EXCLUDED because 'y' is a vowel in Vietnamese, not a consonant
        // ========================================
        "br", "cr", "dr", "fr", "gr", "hr", "jr", "kr", "lr", "mr", "nr",
        "pr", "rr", "sr", "vr", "wr", "xr", "zr",
        
        // ========================================
        // S-clusters - Vietnamese doesn't start with S + consonant
        // NOTE: "sy" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "sỹ")
        // ========================================
        "sb", "sc", "sd", "sf", "sg", "sh", "sj", "sk", "sl", "sm",
        "sn", "sp", "sq", "sr", "ss", "st", "sv", "sw", "sx", "sz",
        
        // ========================================
        // W-clusters - ALL w + letter (Vietnamese NEVER uses 'w')
        // ========================================
        "wa", "wb", "wc", "wd", "we", "wf", "wg", "wh", "wi", "wj",
        "wk", "wl", "wm", "wn", "wo", "wp", "wq", "wr", "ws", "wt",
        "wu", "wv", "ww", "wx", "wy", "wz",
        
        // ========================================
        // F-clusters - ALL f + letter (Vietnamese NEVER uses 'f')
        // ========================================
        "fa", "fb", "fc", "fd", "fe", "ff", "fg", "fh", "fi", "fj",
        "fk", "fl", "fm", "fn", "fo", "fp", "fq", "fr", "fs", "ft",
        "fu", "fv", "fw", "fx", "fy", "fz",
        
        // ========================================
        // J-clusters - ALL j + letter (Vietnamese NEVER uses 'j')
        // ========================================
        "ja", "jb", "jc", "jd", "je", "jf", "jg", "jh", "ji", "jj",
        "jk", "jl", "jm", "jn", "jo", "jp", "jq", "jr", "js", "jt",
        "ju", "jv", "jw", "jx", "jy", "jz",
        
        // ========================================
        // Z-clusters - ALL z + letter (Vietnamese NEVER uses 'z')
        // ========================================
        "za", "zb", "zc", "zd", "ze", "zf", "zg", "zh", "zi", "zj",
        "zk", "zl", "zm", "zn", "zo", "zp", "zq", "zr", "zs", "zt",
        "zu", "zv", "zw", "zx", "zy", "zz",
        
        // ========================================
        // Other consonant + W clusters (except valid qu)
        // ========================================
        "bw", "cw", "dw", "gw", "hw", "kw", "lw", "mw", "nw", "pw",
        "rw", "sw", "tw", "vw", "xw", "yw",
        
        // ========================================
        // Silent letter patterns and other impossible starts
        // ========================================
        "gn", "kn", "pn", "ps", "pt", "pf", "ks", "ts", "tz",
        
        // ========================================
        // Double consonants at start (Vietnamese never has)
        // EXCEPT: The following are EXCLUDED because they are valid Telex input:
        // - "dd" → đ (standard Telex)
        // - "cc" → ch, "gg" → gi, "kk" → kh, "nn" → ng, "pp" → ph, "tt" → th (Quick Telex)
        // - "qq" → qu (Quick Telex)
        // These are now in validTelexStartingPatterns and handled by isValidVietnameseInputSequence
        // ========================================
        "bb", "ff", "hh", "jj",
        "ll", "mm", "rr", "ss", "vv", "ww", "xx", "zz",
        
        // ========================================
        // Other invalid consonant combinations
        // ========================================
        // B + consonant (except bl, br which are above)
        // NOTE: "by" is EXCLUDED because 'y' is a vowel in Vietnamese
        "bc", "bd", "bf", "bg", "bh", "bj", "bk", "bm", "bn", "bp", "bq", "bs", "bt", "bv", "bx", "bz",
        // C + consonant (except ch, cl, cr - ch is valid Vietnamese, cl/cr are above)
        // NOTE: "cy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "cb", "cd", "cf", "cg", "cj", "ck", "cm", "cn", "cp", "cq", "cs", "ct", "cv", "cx", "cz",
        // D + consonant (except dr, dw which are above)
        // NOTE: "dy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "db", "dc", "df", "dg", "dh", "dj", "dk", "dm", "dn", "dp", "dq", "ds", "dt", "dv", "dx", "dz",
        // G + consonant (except gh, gi, gl, gr - gh/gi are valid Vietnamese, gl/gr are above)
        // NOTE: "gy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "gb", "gc", "gd", "gf", "gj", "gk", "gm", "gp", "gq", "gs", "gt", "gv", "gx", "gz",
        // H + consonant
        // NOTE: "hy" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "hỷ")
        "hb", "hc", "hd", "hf", "hg", "hj", "hk", "hl", "hm", "hn", "hp", "hq", "hr", "hs", "ht", "hv", "hx", "hz",
        // K + consonant (except kh - kh is valid Vietnamese)
        // NOTE: "ky" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "ký")
        "kb", "kc", "kd", "kf", "kg", "kj", "kk", "kl", "km", "kp", "kq", "ks", "kt", "kv", "kx", "kz",
        // L + consonant
        // NOTE: "ly" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "lý")
        "lb", "lc", "ld", "lf", "lg", "lh", "lj", "lk", "lm", "ln", "lp", "lq", "lr", "ls", "lt", "lv", "lx", "lz",
        // M + consonant
        // NOTE: "my" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "mỹ")
        "mb", "mc", "md", "mf", "mg", "mh", "mj", "mk", "ml", "mn", "mp", "mq", "mr", "ms", "mt", "mv", "mx", "mz",
        // N + consonant (except ng, nh - these are valid Vietnamese)
        // NOTE: "ny" is EXCLUDED because 'y' is a vowel in Vietnamese
        "nb", "nc", "nd", "nf", "nj", "nk", "nl", "nm", "np", "nq", "nr", "ns", "nt", "nv", "nx", "nz",
        // P + consonant (except ph, pl, pr - ph is valid Vietnamese, pl/pr are above)
        // NOTE: "py" is EXCLUDED because 'y' is a vowel in Vietnamese
        "pb", "pc", "pd", "pg", "pj", "pk", "pm", "pp", "pq", "pv", "px", "pz",
        // R + consonant
        // NOTE: "ry" is EXCLUDED because 'y' is a vowel in Vietnamese
        "rb", "rc", "rd", "rf", "rg", "rh", "rj", "rk", "rl", "rm", "rn", "rp", "rq", "rs", "rt", "rv", "rx", "rz",
        // T + consonant (except th, tr - these are valid Vietnamese)
        // NOTE: "ty" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "tỷ")
        "tb", "tc", "td", "tf", "tg", "tj", "tk", "tl", "tm", "tn", "tp", "tq", "ts", "tv", "tx", "tz",
        // V + consonant
        // NOTE: "vy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "vb", "vc", "vd", "vf", "vg", "vh", "vj", "vk", "vl", "vm", "vn", "vp", "vq", "vs", "vt", "vv", "vx", "vz",
        // X + consonant
        // NOTE: "xy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "xb", "xc", "xd", "xf", "xg", "xh", "xj", "xk", "xl", "xm", "xn", "xp", "xq", "xs", "xt", "xv", "xx", "xz",
    ]
    
    /// Set of 3-letter initial clusters that are IMPOSSIBLE in Vietnamese
    private static let impossible3LetterPrefixes: Set<String> = [
        // STR family
        "str", "spr", "spl", "scr", "shr", "squ", "stw", "swr",
        // SCH/SHR family
        "sch", "scl", "skr", "skw", "sph", "sth",
        // THR family
        "thr", "thw",
        // CHR/SHR family
        "chr", "shr", "phr",
        // Other 3-letter clusters
        "dge", "dgi", "kni", "pne", "psy", "gho", "ghu", "wri", "wro", "wra",
        "ght", "ghr", "ghl", "ghw",
        "ntr", "mpr", "xtr",
        // GR/GL/GW extended
        "gra", "gre", "gri", "gro", "gru", "gry",
        "gla", "gle", "gli", "glo", "glu", "gly",
        // BR/BL extended
        "bra", "bre", "bri", "bro", "bru", "bry",
        "bla", "ble", "bli", "blo", "blu", "bly",
        // DR extended
        "dra", "dre", "dri", "dro", "dru", "dry",
        // CR/CL extended
        "cra", "cre", "cri", "cro", "cru", "cry",
        "cla", "cle", "cli", "clo", "clu", "cly",
        // PR/PL extended
        "pra", "pre", "pri", "pro", "pru", "pry",
        "pla", "ple", "pli", "plo", "plu", "ply",
        // FR/FL extended
        "fra", "fre", "fri", "fro", "fru", "fry",
        "fla", "fle", "fli", "flo", "flu", "fly",
        // WR extended
        "wra", "wre", "wri", "wro", "wru",
    ]
    
    /// Set of 4-letter initial clusters that are IMPOSSIBLE in Vietnamese
    private static let impossible4LetterPrefixes: Set<String> = [
        // SCHR/SCHT/SCHW family (German loanwords)
        "schr", "schw", "schn", "schm", "schl",
        // STRI/STRA/STRO family
        "stra", "stre", "stri", "stro", "stru", "stry",
        // SPRI/SPRA family  
        "spra", "spre", "spri", "spro", "spru", "spry",
        // SCRA/SCRE/SCRI family
        "scra", "scre", "scri", "scro", "scru", "scry",
        // SPLA/SPLE family
        "spla", "sple", "spli", "splo", "splu",
        // SQUA/SQUE/SQUI family
        "squa", "sque", "squi", "squo",
        // THRO/THRA family
        "thra", "thre", "thri", "thro", "thru", "thry",
        // CHRO/CHRA family
        "chra", "chre", "chri", "chro", "chru",
        // PHRA/PHRE family
        "phra", "phre", "phri", "phro",
        // SHRA/SHRE family
        "shra", "shre", "shri", "shro", "shru",
        // Other
        "psyc", "pneu", "ghri",
    ]
    
    // ============================================
    // MARK: - Main Detection Properties
    // ============================================
    
    /// Ultra-fast detection: Does this word START with a pattern that is
    /// 100% IMPOSSIBLE in Vietnamese?
    /// 
    /// This is the most reliable rule because:
    /// 1. Vietnamese has a closed set of valid initial consonants/clusters
    /// 2. Uses Set lookup for O(1) performance
    /// 3. False positive rate is 0% (these patterns NEVER occur in Vietnamese)
    ///
    /// Valid Vietnamese initials: b, c, ch, d, đ, g, gh, gi, h, k, kh, l, m, n,
    ///                           ng, ngh, nh, p, ph, qu, r, s, t, th, tr, v, x
    ///
    /// - Parameter allowZFWJ: If true, allows words starting with z, f, w, j (for foreign words)
    /// Examples detected: "winner", "water", "food", "fast", "jazz", "zero",
    ///                    "street", "spring", "chrome", "psychology", "knight"
    func startsWithImpossibleVietnameseCluster(allowZFWJ: Bool = false) -> Bool {
        let word = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !word.isEmpty else { return false }
        
        // ============================================
        // RULE 0 (FASTEST): Check if word starts with letters that
        // NEVER exist in Vietnamese alphabet: f, j, w, z
        // ============================================
        // This catches: winner, water, food, fast, jazz, jungle, zero, zone, etc.
        // Vietnamese NEVER uses these letters at the start of words
        // This is the fastest check - O(1) Set lookup on a single character
        // EXCEPTION: If allowZFWJ is true, skip this check (for "Allow consonant Z, F, W, J" setting)
        if !allowZFWJ {
            if let firstChar = word.first, Self.impossibleStartingChars.contains(firstChar) {
                return true
            }
        }
        
        // For single character words, we've already checked impossible chars above
        guard word.count >= 2 else { return false }
        
        // Check 2-letter prefixes (most common case - check first for efficiency)
        let prefix2 = String(word.prefix(2))
        // When allowZFWJ is true, skip prefixes starting with z, f, w, j
        let skipPrefix = allowZFWJ && (prefix2.hasPrefix("z") || prefix2.hasPrefix("f") || 
                                        prefix2.hasPrefix("w") || prefix2.hasPrefix("j"))
        if !skipPrefix && Self.impossible2LetterPrefixes.contains(prefix2) {
            return true
        }
        
        // Check 3-letter prefixes
        if word.count >= 3 {
            let prefix3 = String(word.prefix(3))
            // When allowZFWJ is true, skip prefixes starting with z, f, w, j
            let skipPrefix3 = allowZFWJ && (prefix3.hasPrefix("z") || prefix3.hasPrefix("f") || 
                                            prefix3.hasPrefix("w") || prefix3.hasPrefix("j"))
            if !skipPrefix3 && Self.impossible3LetterPrefixes.contains(prefix3) {
                return true
            }
        }
        
        // Check 4-letter prefixes (most specific)
        if word.count >= 4 {
            let prefix4 = String(word.prefix(4))
            // When allowZFWJ is true, skip prefixes starting with z, f, w, j
            let skipPrefix4 = allowZFWJ && (prefix4.hasPrefix("z") || prefix4.hasPrefix("f") || 
                                            prefix4.hasPrefix("w") || prefix4.hasPrefix("j"))
            if !skipPrefix4 && Self.impossible4LetterPrefixes.contains(prefix4) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if this RAW INPUT string starts with a valid Vietnamese input sequence
    /// This is used to EXCLUDE valid typing patterns from being flagged as "impossible"
    ///
    /// For example:
    /// - "dd" in Telex → produces "đ" → should NOT be blocked
    /// - "d9" in VNI → produces "đ" → should NOT be blocked
    /// - "str" → NOT a valid sequence → should be blocked
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex, 3 = VIQR
    /// - Returns: true if starts with valid Vietnamese input sequence
    func isValidVietnameseInputSequence(inputType: Int = 0) -> Bool {
        let input = self.lowercased()
        
        guard input.count >= 2 else { return false }
        
        let prefix2 = String(input.prefix(2))
        
        switch inputType {
        case 0, 2, 3: // Telex, Simple Telex, VIQR
            return Self.validTelexStartingPatterns.contains(prefix2)
        case 1: // VNI
            return Self.validVNIStartingPatterns.contains(prefix2)
        default:
            // Unknown input type - check all patterns to be safe
            return Self.allValidInputStartingPatterns.contains(prefix2)
        }
    }
    
    /// Check if RAW INPUT starts with a pattern that is DEFINITELY NOT Vietnamese
    /// This considers valid input sequences like "dd" (Telex) or "d9" (VNI)
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex, 3 = VIQR
    /// - Parameter allowZFWJ: If true, allows words starting with z, f, w, j (for foreign words)
    /// - Returns: true if raw input starts with impossible pattern (excluding valid input sequences)
    func startsWithImpossiblePatternForRawInput(inputType: Int = 0, allowZFWJ: Bool = false) -> Bool {
        // First, check if this is a valid Vietnamese input sequence
        // If so, it's NOT impossible - return false early
        if isValidVietnameseInputSequence(inputType: inputType) {
            return false
        }
        
        // Otherwise, check against impossible patterns
        return startsWithImpossibleVietnameseCluster(allowZFWJ: allowZFWJ)
    }
    
    /// Check if RAW INPUT is definitely NOT Vietnamese based on START patterns only.
    /// 
    /// This is a conservative check that ONLY looks at the beginning of the word.
    /// Middle and end patterns are NOT checked here because:
    /// 1. Telex uses 'w' as a vowel modifier (ư, ơ, ă) which could create false clusters
    /// 2. Free Mark allows adding tone at the end of word
    /// 3. Complex patterns could interfere with valid Vietnamese input sequences
    ///
    /// Cases like "micros" (where middle/end patterns indicate English) are handled by:
    /// - Spell checking after word is complete
    /// - Instant restore feature (if enabled)
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex, 3 = VIQR
    /// - Parameter allowZFWJ: If true, allows words starting with z, f, w, j (for foreign words)
    /// - Returns: true if raw input STARTS with impossible Vietnamese pattern
    func isDefinitelyNotVietnameseForRawInput(inputType: Int = 0, allowZFWJ: Bool = false) -> Bool {
        // Simply delegate to the start pattern check
        // This already handles:
        // 1. Valid Vietnamese input sequences (dd, cc, gg, etc.)
        // 2. Impossible starting characters (f, j, w, z) - unless allowZFWJ is true
        // 3. Impossible 2/3/4-letter prefixes (str, bl, gr, etc.)
        return startsWithImpossiblePatternForRawInput(inputType: inputType, allowZFWJ: allowZFWJ)
    }
    
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
        // RULE 0: Check impossible Vietnamese prefixes (FASTEST)
        // ============================================
        // This uses Set lookup for O(1) performance
        if startsWithImpossibleVietnameseCluster() {
            return true
        }
        
        // ============================================
        // RULE 1: Contains f, j, z (NOT 'w' - it's used in Telex)
        // ============================================
        // Almost certainly not pure Vietnamese
        // NOTE: 'w' is EXCLUDED because in Telex, it's a vowel modifier (a+w=ă, o+w=ơ, u+w=ư)
        // Note: Some Vietnamese words use f, j, z with vAllowConsonantZFWJ,
        // but they're rare and mostly loan words
        if word.rangeOfCharacter(from: CharacterSet(charactersIn: "fjz")) != nil {
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
        // RULE 5: Additional English consonant clusters at START
        // ============================================
        // (Most are already covered by startsWithImpossibleVietnameseCluster)
        // This is kept for backwards compatibility and edge cases
        if word.count >= 3 {
            let englishInitialClusters = [
                // 3-letter clusters (check first)
                "str", "spr", "scr", "spl", "shr", "thr", "sch", "squ",
                // 4-letter clusters
                "schr", "schw", "stri", "spri", "squa",
                // L-clusters (Vietnamese doesn't have these)
                "bl", "cl", "fl", "gl", "pl", "sl",
                // R-clusters (Vietnamese only has "tr", exclude it)
                "br", "cr", "dr", "fr", "gr", "pr",
                // S-clusters
                "sc", "sk", "sm", "sn", "sp", "st", "sw", "sh",
                // W-clusters
                "wh", "wr",
                // Other clusters
                "dw", "tw", "gn", "kn", "pn", "ps",
                // CHR/PHR patterns
                "chr", "phr"
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
        // Vietnamese never has double consonants in FINAL output
        // BUT: In Telex input, these are VALID input sequences:
        // - dd → đ, cc → ch (Quick Telex), gg → gi, kk → kh, nn → ng, pp → ph, tt → th
        // So we exclude Telex patterns from this check
        if word.count >= 3 {
            let doubleConsonants = [
                // Only check non-Telex double consonants
                "bb", "ff", "hh", "jj",
                "ll", "mm", "rr", "ss", "vv", "zz"
                // EXCLUDED: "cc", "dd", "gg", "kk", "nn", "pp", "tt" - valid Telex input
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
        // NOTE: We're careful here because Telex mark keys (s/f/r/x/j) are at word end
        // These suffixes are checked on the FINAL output, not during typing
        if word.count >= 4 {
            let englishSuffixes = [
                // -tion, -sion (nation, vision)
                "tion", "sion",
                // -ing (running, playing) - but NOT "inh" sequence in VN
                "ing",
                // -ed past tense (walked, played)
                "ed",
                // EXCLUDED: "ly" - could conflict with Vietnamese "lý" input during Telex typing
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
        // NOTE: "oo" and "ee" are EXCLUDED because they are valid Telex input:
        // - aa → â, ee → ê, oo → ô (Telex vowel transformation)
        // - So "gooj" = "gộ", not English "oo"
        if word.count > 3 {
            let englishVowelCombos = [
                // Long vowel digraphs
                "ough", "eigh", "augh",
                // EXCLUDED: "oo", "ee" - valid Telex input (oo→ô, ee→ê)
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
        // RULE 1: Contains f, j, z (NOT 'w' - it's used in Telex)
        // ============================================
        // These characters don't exist in native Vietnamese words
        // NOTE: 'w' is EXCLUDED because in Telex, it's a vowel modifier:
        // - a+w = ă, o+w = ơ, u+w = ư
        // - So "bawf" = "bằ", not English
        // Check only in the START and MIDDLE (not the last character which could be mark key)
        let wordWithoutLast = word.count > 1 ? String(word.dropLast()) : word
        if wordWithoutLast.rangeOfCharacter(from: CharacterSet(charactersIn: "fjz")) != nil {
            return true
        }
        
        // ============================================
        // RULE 2: English consonant clusters at START
        // ============================================
        // Uses O(1) Set-based lookup for impossible Vietnamese prefixes
        if startsWithImpossibleVietnameseCluster() {
            return true
        }
        
        // Additional clusters check for edge cases
        if word.count >= 3 {
            let englishInitialClusters = [
                // 3-letter clusters (check first)
                "str", "spr", "scr", "spl", "shr", "thr", "sch", "squ",
                // L-clusters (Vietnamese doesn't have these)
                "bl", "cl", "fl", "gl", "pl", "sl",
                // R-clusters (Vietnamese only has "tr", exclude it)
                "br", "cr", "dr", "fr", "gr", "pr",
                // S-clusters
                "sc", "sk", "sm", "sn", "sp", "st", "sw", "sh",
                // W-clusters
                "wh", "wr",
                // Other clusters
                "dw", "tw", "gn", "kn", "pn", "ps",
                // CHR/PHR patterns
                "chr", "phr"
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
        // Vietnamese never has double consonants in FINAL output
        // BUT: In Telex input, these are VALID input sequences:
        // - dd → đ, cc → ch (Quick Telex), gg → gi, kk → kh, nn → ng, pp → ph, tt → th
        // So we exclude Telex patterns from this check
        if word.count >= 3 {
            let doubleConsonants = [
                // Only check non-Telex double consonants
                "bb", "ff", "hh", "jj",
                "ll", "mm", "rr", "ss", "vv", "zz"
                // EXCLUDED: "cc", "dd", "gg", "kk", "nn", "pp", "tt" - valid Telex input
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
