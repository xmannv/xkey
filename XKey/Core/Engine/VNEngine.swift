//
//  VNEngine.swift
//  XKey
//
//  Vietnamese Input Engine - Complete rewrite based on OpenKey Engine
//  Ported from OpenKey C++ engine to Swift with full feature parity
//

import Foundation
import Cocoa

/// Main Vietnamese typing engine - Direct port from OpenKey
class VNEngine {
    
    // MARK: - Constants (from DataType.h)
    // Note: Using internal access for extension support
    
    static let MAX_BUFF = 32
    
    // Masks for internal data structure
    static let CAPS_MASK: UInt32           = 0x10000
    static let TONE_MASK: UInt32           = 0x20000
    static let TONEW_MASK: UInt32          = 0x40000
    static let MARK1_MASK: UInt32          = 0x80000    // Sắc
    static let MARK2_MASK: UInt32          = 0x100000   // Huyền
    static let MARK3_MASK: UInt32          = 0x200000   // Hỏi
    static let MARK4_MASK: UInt32          = 0x400000   // Ngã
    static let MARK5_MASK: UInt32          = 0x800000   // Nặng
    static let MARK_MASK: UInt32           = 0xF80000
    static let CHAR_MASK: UInt32           = 0xFFFF
    static let STANDALONE_MASK: UInt32     = 0x1000000
    static let CHAR_CODE_MASK: UInt32      = 0x2000000
    static let PURE_CHARACTER_MASK: UInt32 = 0x80000000
    static let END_CONSONANT_MASK: UInt32  = 0x4000
    static let CONSONANT_ALLOW_MASK: UInt32 = 0x8000
    
    // MARK: - Settings (from Engine.h)
    
    var vLanguage = 1              // 0: English, 1: Vietnamese
    var vInputType = 0             // 0: Telex, 1: VNI
    var vFreeMark = 0              // 0: No, 1: Yes
    var vCodeTable = 0             // 0: Unicode, 1: TCVN3, 2: VNI-Windows
    var vCheckSpelling = 1         // 0: No, 1: Yes
    var vUseModernOrthography = 1  // 0: òa/úy, 1: oà/uý
    var vQuickTelex = 1            // 0: No, 1: Yes (cc=ch, gg=gi, etc.)
    var vRestoreIfWrongSpelling = 1 // 0: No, 1: Yes
    var vFixRecommendBrowser = 1   // 0: No, 1: Yes
    var vUseMacro = 0              // 0: No, 1: Yes
    var vUseMacroInEnglishMode = 0 // 0: No, 1: Yes
    var vAutoCapsMacro = 0         // 0: No, 1: Yes
    var vUseSmartSwitchKey = 0     // 0: No, 1: Yes
    var vUpperCaseFirstChar = 0    // 0: No, 1: Yes
    var vTempOffSpelling = 0       // 0: No, 1: Yes
    var vAllowConsonantZFWJ = 0    // 0: No, 1: Yes
    var vQuickStartConsonant = 0   // 0: No, 1: Yes (f->ph, j->gi, w->qu)
    var vQuickEndConsonant = 0     // 0: No, 1: Yes (g->ng, h->nh, k->ch)
    var vTempOffOpenKey = 0        // 0: No, 1: Yes (temp off engine with Option key)
    
    // MARK: - Internal State (from Engine.cpp)
    // Note: Using internal access for extension support
    
    var typingWord = [UInt32](repeating: 0, count: MAX_BUFF)
    var index: UInt8 = 0
    var longWordHelper = [UInt32]()
    var typingStates = [[UInt32]]()
    
    var keyStates = [UInt32](repeating: 0, count: MAX_BUFF)
    var stateIndex: UInt8 = 0
    
    var tempDisableKey = false
    var spaceCount = 0
    var hasHandledMacro = false
    var upperCaseStatus: UInt8 = 0
    var specialChar = [UInt32]()
    var useSpellCheckingBefore = false
    var hasHandleQuickConsonant = false
    var willTempOffEngine = false
    
    // MARK: - Logging
    
    /// Logging callback
    var logCallback: ((String) -> Void)?
    
    // MARK: - Hook State (result to send back)
    
    struct HookState {
        var code: UInt8 = 0           // 0: DoNothing, 1: Process, 2: WordBreak, 3: Restore, 4: ReplaceMacro
        var backspaceCount: UInt8 = 0
        var newCharCount: UInt8 = 0
        var extCode: UInt8 = 0        // 1: WordBreak, 2: Delete, 3: Normal, 4: ShouldNotSendEmpty
        var charData = [UInt32](repeating: 0, count: MAX_BUFF)
        var macroKey = [UInt32]()
        var macroData = [UInt32]()
    }
    
    var hookState = HookState()
    
    // Hook codes - internal for extension access
    let vDoNothing = 0
    let vWillProcess = 1
    let vBreakWord = 2
    let vRestore = 3
    let vReplaceMacro = 4
    let vRestoreAndStartNewSession = 5
    
    // MARK: - Vietnamese Data Tables
    
    var vietnameseData: VietnameseData!
    
    // MARK: - Initialization
    
    init() {
        vietnameseData = VietnameseData()
        useSpellCheckingBefore = (vCheckSpelling == 1)
    }
    
    // MARK: - Main Entry Point
    
    /// Main entry point for processing key events
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - character: The character
    ///   - isUppercase: Whether Shift or CapsLock is active
    ///   - hasOtherModifier: Whether Ctrl/Cmd/Option is pressed
    /// - Returns: HookState with processing result
    func handleKeyEvent(keyCode: UInt16, character: Character, isUppercase: Bool, hasOtherModifier: Bool) -> HookState {
        // Save macroKey before reset (it accumulates across key events)
        let savedMacroKey = hookState.macroKey
        
        // Reset hook state
        hookState = HookState()
        
        // Restore macroKey
        hookState.macroKey = savedMacroKey
        
        let isCaps = isUppercase
        
        // Check if number key with shift or has other modifier
        if (vietnameseData.isNumberKey(keyCode) && isUppercase) || hasOtherModifier || isWordBreak(keyCode: keyCode) {
            handleWordBreak(keyCode: keyCode, character: character, isCaps: isCaps)
            return hookState
        }
        
        // Handle space
        if keyCode == VietnameseData.KEY_SPACE {
            handleSpace()
            return hookState
        }
        
        // Handle delete/backspace
        if keyCode == VietnameseData.KEY_DELETE {
            handleDelete()
            return hookState
        }
        
        // Handle normal key
        handleNormalKey(keyCode: keyCode, character: character, isCaps: isCaps)
        
        return hookState
    }
    
    // MARK: - Word Break Handling
    
    private func isWordBreak(keyCode: UInt16) -> Bool {
        return vietnameseData.breakCode.contains(keyCode)
    }
    
    private func isMacroBreakCode(keyCode: UInt16) -> Bool {
        return vietnameseData.macroBreakCode.contains(keyCode)
    }
    
    private func handleWordBreak(keyCode: UInt16, character: Character, isCaps: Bool) {
        hookState.code = UInt8(vDoNothing)
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.extCode = 1 // word break
        
        // Check macro
        if vUseMacro == 1 && isMacroBreakCode(keyCode: keyCode) && !hasHandledMacro {
            _ = findAndReplaceMacro()
        }
        
        // Check quick consonant
        if (vQuickStartConsonant == 1 || vQuickEndConsonant == 1) && !tempDisableKey && isMacroBreakCode(keyCode: keyCode) {
            checkQuickConsonant()
        }
        
        // Check restore if wrong spelling
        if vRestoreIfWrongSpelling == 1 && isWordBreak(keyCode: keyCode) {
            if !tempDisableKey && vCheckSpelling == 1 {
                checkSpelling(forceCheckVowel: true)
            }
            if tempDisableKey {
                checkRestoreIfWrongSpelling(handleCode: vRestoreAndStartNewSession)
            }
        }
        
        // Check if char key code
        let isCharKeyCode = vietnameseData.charKeyCode.contains(keyCode)
        if !isCharKeyCode {
            specialChar.removeAll()
            typingStates.removeAll()
        } else {
            if spaceCount > 0 {
                saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
                spaceCount = 0
            } else {
                saveWord()
            }
            specialChar.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            hookState.extCode = 3 // normal word
        }
        
        if hookState.code == UInt8(vDoNothing) {
            startNewSession()
            vCheckSpelling = useSpellCheckingBefore ? 1 : 0
            willTempOffEngine = false
        } else if hookState.code == UInt8(vReplaceMacro) || hasHandleQuickConsonant {
            index = 0
        }
        
        // Insert key for macro
        if vUseMacro == 1 {
            if isCharKeyCode {
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            } else {
                hookState.macroKey.removeAll()
            }
        }
        
        // Upper case first char
        if vUpperCaseFirstChar == 1 {
            if keyCode == VietnameseData.KEY_DOT {
                upperCaseStatus = 1
            } else if keyCode == VietnameseData.KEY_ENTER || keyCode == VietnameseData.KEY_RETURN {
                upperCaseStatus = 2
            } else {
                upperCaseStatus = 0
            }
        }
    }
    
    // MARK: - Space Handling
    
    private func handleSpace() {
        if !tempDisableKey && vCheckSpelling == 1 {
            checkSpelling(forceCheckVowel: true)
        }
        
        // Check macro first - if found, return early
        if vUseMacro == 1 && !hasHandledMacro {
            if findAndReplaceMacro() {
                // Macro found and replaced - clear macro key and return
                hookState.macroKey.removeAll()
                spaceCount += 1
                return
            }
        }
        
        if (vQuickStartConsonant == 1 || vQuickEndConsonant == 1) && !tempDisableKey {
            checkQuickConsonant()
            spaceCount += 1
        } else if vRestoreIfWrongSpelling == 1 && tempDisableKey && !hasHandledMacro {
            if !checkRestoreIfWrongSpelling(handleCode: vRestore) {
                hookState.code = UInt8(vDoNothing)
            }
            spaceCount += 1
        } else {
            hookState.code = UInt8(vDoNothing)
            spaceCount += 1
        }
        
        if vUseMacro == 1 {
            hookState.macroKey.removeAll()
        }
        
        if vUpperCaseFirstChar == 1 && upperCaseStatus == 1 {
            upperCaseStatus = 2
        }
        
        // Save word
        if spaceCount == 1 {
            if !specialChar.isEmpty {
                saveSpecialChar()
            } else {
                saveWord()
            }
        }
        
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false
    }
    
    // MARK: - Delete Handling
    
    private func handleDelete() {
        logCallback?("handleDelete: index=\(index), spaceCount=\(spaceCount), specialChar.count=\(specialChar.count)")
        
        hookState.code = UInt8(vDoNothing)
        hookState.extCode = 2 // delete
        
        if !specialChar.isEmpty {
            specialChar.removeLast()
            logCallback?("  → Removed special char, remaining=\(specialChar.count)")
            if specialChar.isEmpty {
                logCallback?("  → specialChar empty, restoring...")
                restoreLastTypingState()
            }
        } else if spaceCount > 0 {
            spaceCount -= 1
            logCallback?("  → Removed space, remaining spaceCount=\(spaceCount)")
            if spaceCount == 0 {
                logCallback?("  → spaceCount=0, restoring...")
                restoreLastTypingState()
            }
        } else {
            if stateIndex > 0 {
                stateIndex -= 1
            }
            if index > 0 {
                index -= 1
                logCallback?("  → Removed char, new index=\(index)")
                if !longWordHelper.isEmpty {
                    // Right shift
                    for i in stride(from: VNEngine.MAX_BUFF - 1, through: 1, by: -1) {
                        typingWord[i] = typingWord[i - 1]
                    }
                    typingWord[0] = longWordHelper.removeLast()
                    index += 1
                }
                if vCheckSpelling == 1 {
                    checkSpelling()
                }
            }
            
            if vUseMacro == 1 && !hookState.macroKey.isEmpty {
                hookState.macroKey.removeLast()
            }
            
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 2
            
            if index == 0 {
                logCallback?("  → index=0, starting new session and restoring...")
                startNewSession()
                specialChar.removeAll()
                restoreLastTypingState()
            } else {
                checkGrammar(deltaBackSpace: 1)
            }
        }
    }
    
    // MARK: - Normal Key Handling
    
    private func handleNormalKey(keyCode: UInt16, character: Character, isCaps: Bool) {
        if willTempOffEngine {
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            return
        }
        
        if spaceCount > 0 {
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 0
            startNewSession()
            saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
            spaceCount = 0
        } else if !specialChar.isEmpty {
            saveSpecialChar()
        }
        
        insertState(keyCode: keyCode, isCaps: isCaps)
        
        let isSpecial = isSpecialKey(keyCode: keyCode)
        logCallback?("handleNormalKey: keyCode=\(keyCode), isSpecial=\(isSpecial), tempDisableKey=\(tempDisableKey)")
        
        if !isSpecial || tempDisableKey {
            if vQuickTelex == 1 && isQuickTelexKey(keyCode: keyCode) {
                handleQuickTelex(keyCode: keyCode, isCaps: isCaps)
                return
            } else {
                hookState.code = UInt8(vDoNothing)
                hookState.backspaceCount = 0
                hookState.newCharCount = 0
                hookState.extCode = 3
                insertKey(keyCode: keyCode, isCaps: isCaps)
                logCallback?("Normal key inserted: keyCode=\(keyCode), index=\(index), buffer=\(getCurrentWord())")
            }
        } else {
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            handleMainKey(keyCode: keyCode, isCaps: isCaps)
            logCallback?("Special key handled: keyCode=\(keyCode), index=\(index), buffer=\(getCurrentWord())")
        }
        
        // Always check for vowel auto-fix (ưo → ươ) regardless of vFreeMark
        // This is important for correct Vietnamese typing
        if !isKeyD(keyCode: keyCode, inputType: vInputType) {
            let deltaBS = hookState.code == UInt8(vDoNothing) ? -1 : 0
            checkVowelAutoFix(deltaBackSpace: deltaBS)
        }
        
        // Check mark position - ALWAYS check when typing end consonant
        // Vietnamese spelling rule: with end consonant, tone must be on the vowel closest to it
        // Example: "hoạt" - tone on 'a', not 'o'; "hiện" - tone on 'ê', not 'i'
        // This rule applies regardless of vFreeMark setting
        logCallback?("checkMarkPosition check: vFreeMark=\(vFreeMark), isKeyD=\(isKeyD(keyCode: keyCode, inputType: vInputType))")
        if !isKeyD(keyCode: keyCode, inputType: vInputType) {
            // Check if this key is an end consonant
            let isEndConsonant = vietnameseData.isConsonant(keyCode) && index > 1
            
            // Always check mark position if:
            // 1. vFreeMark is disabled, OR
            // 2. This is an end consonant (Vietnamese spelling rule)
            if vFreeMark == 0 || isEndConsonant {
                if hookState.code == UInt8(vDoNothing) {
                    checkMarkPosition(deltaBackSpace: -1)
                } else {
                    checkMarkPosition(deltaBackSpace: 0)
                }
            } else {
                logCallback?("  → Skipping checkMarkPosition (vFreeMark=1, not end consonant)")
            }
        }
        
        if hookState.code == UInt8(vRestore) {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            stateIndex -= 1
        }
        
        // Insert or replace key for macro
        if vUseMacro == 1 {
            if hookState.code == UInt8(vDoNothing) {
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            } else if hookState.code == UInt8(vWillProcess) || hookState.code == UInt8(vRestore) {
                for _ in 0..<hookState.backspaceCount {
                    if !hookState.macroKey.isEmpty {
                        hookState.macroKey.removeLast()
                    }
                }
                let startIdx = Int(index) - Int(hookState.backspaceCount)
                for i in startIdx..<(Int(hookState.newCharCount) + startIdx) {
                    if i >= 0 && i < typingWord.count {
                        hookState.macroKey.append(typingWord[i])
                    }
                }
            }
        }
        
        // Upper case first char
        if vUpperCaseFirstChar == 1 {
            if index == 1 && upperCaseStatus == 2 {
                upperCaseFirstCharacter()
            }
            upperCaseStatus = 0
        }
        
        // Handle bracket keys
        if isBracketKey(keyCode: keyCode) && (isBracketKey(hookState.charData[0]) || vInputType == 2 || vInputType == 3) {
            if Int(index) - (hookState.code == UInt8(vWillProcess) ? Int(hookState.backspaceCount) : 0) > 0 {
                index -= 1
                saveWord()
            }
            index = 0
            tempDisableKey = false
            stateIndex = 0
            hookState.extCode = 3
            specialChar.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
        }
    }
    
    // MARK: - Main Key Processing
    
    private func handleMainKey(keyCode: UInt16, isCaps: Bool) {
        // Handle Z key - remove mark
        if isKeyZ(keyCode: keyCode, inputType: vInputType) {
            removeMark()
            if !isChanged {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        // Handle [ key - standalone ơ
        if keyCode == VietnameseData.KEY_LEFT_BRACKET {
            checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_O)
            return
        }
        
        // Handle ] key - standalone ư
        if keyCode == VietnameseData.KEY_RIGHT_BRACKET {
            checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            return
        }
        
        // Handle D key
        if isKeyD(keyCode: keyCode, inputType: vInputType) {
            var isCorrect = false
            var isChanged = false
            var k = Int(index)
            
            for i in 0..<vietnameseData.consonantDTable.count {
                if Int(index) < vietnameseData.consonantDTable[i].count {
                    continue
                }
                isCorrect = true
                k = Int(index)
                
                // Check if matches consonant D pattern
                for j in stride(from: vietnameseData.consonantDTable[i].count - 1, through: 0, by: -1) {
                    let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                    if (vietnameseData.consonantDTable[i][j] & ~endMask) != chr(k - 1) {
                        isCorrect = false
                        break
                    }
                    k -= 1
                    if k < 0 {
                        break
                    }
                }
                
                // Allow d after consonant
                if !isCorrect && Int(index) >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_D &&
                   vietnameseData.isConsonant(chr(Int(index) - 2)) {
                    isCorrect = true
                }
                
                if isCorrect {
                    isChanged = true
                    insertD(keyCode: keyCode, isCaps: isCaps)
                    break
                }
            }
            
            if !isChanged {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        // Handle mark keys (S, F, R, X, J or 1-5 for VNI)
        if isMarkKey(keyCode: keyCode, inputType: vInputType) {
            handleMarkKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // Handle vowel keys
        handleVowelKey(keyCode: keyCode, isCaps: isCaps)
    }
    
    private func handleMarkKey(keyCode: UInt16, isCaps: Bool) {
        var isCorrect = false
        var isChanged = false
        
        logCallback?("handleMarkKey: keyCode=\(keyCode), index=\(index), buffer=\(getCurrentWord())")
        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q {
            logCallback?("  → Skipping: qu case")
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        for (vowelKey, charsets) in vietnameseData.vowelForMarkTable {
            for charset in charsets {
                if Int(index) < charset.count {
                    continue
                }
                isCorrect = true
                var k = Int(index)
                
                // Check if matches vowel pattern
                for j in stride(from: charset.count - 1, through: 0, by: -1) {
                    let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                    let charsetChar = charset[j] & ~endMask
                    let bufferChar = chr(k - 1)
                    if charsetChar != bufferChar {
                        isCorrect = false
                        break
                    }
                    k -= 1
                    if k < 0 {
                        break
                    }
                }
                
                // Limit mark for end consonant: "C", "T" - OpenKey: checkCorrectVowel
                // Cannot use huyền (F), hỏi (R), ngã (X) with end consonant C or T
                if isCorrect && charset.count > 1 {
                    let isMarkFRX = (vInputType != 1) ? 
                        (keyCode == VietnameseData.KEY_F || keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_X) :
                        (keyCode == VietnameseData.KEY_2 || keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4)
                    
                    if isMarkFRX {
                        if charset[1] == VietnameseData.KEY_C || charset[1] == VietnameseData.KEY_T {
                            logCallback?("  → Rejected: mark FRX with end consonant C/T")
                            isCorrect = false
                        } else if charset.count > 2 && charset[2] == VietnameseData.KEY_T {
                            logCallback?("  → Rejected: mark FRX with end consonant T")
                            isCorrect = false
                        }
                    }
                }
                
                // Check duplicate consonant - OpenKey: checkCorrectVowel
                // IMPORTANT: Only check if k+1 is within current buffer (k+1 < index)
                // This fixes a bug where stale data in typingWord could cause false positives
                if isCorrect && k >= 0 && k + 1 < Int(index) {
                    if chr(k) == chr(k + 1) {
                        logCallback?("  → Rejected: duplicate consonant at k=\(k)")
                        isCorrect = false
                    }
                }
                
                if isCorrect {
                    logCallback?("  → Pattern matched! vowelKey=\(vowelKey), charset=\(charset)")
                    isChanged = true
                    
                    // Determine which mark to insert based on key
                    var markMask: UInt32 = 0
                    if vInputType != 1 { // Not VNI
                        if keyCode == VietnameseData.KEY_S {
                            markMask = VNEngine.MARK1_MASK
                        } else if keyCode == VietnameseData.KEY_F {
                            markMask = VNEngine.MARK2_MASK
                        } else if keyCode == VietnameseData.KEY_R {
                            markMask = VNEngine.MARK3_MASK
                        } else if keyCode == VietnameseData.KEY_X {
                            markMask = VNEngine.MARK4_MASK
                        } else if keyCode == VietnameseData.KEY_J {
                            markMask = VNEngine.MARK5_MASK
                        }
                    } else { // VNI
                        if keyCode == VietnameseData.KEY_1 {
                            markMask = VNEngine.MARK1_MASK
                        } else if keyCode == VietnameseData.KEY_2 {
                            markMask = VNEngine.MARK2_MASK
                        } else if keyCode == VietnameseData.KEY_3 {
                            markMask = VNEngine.MARK3_MASK
                        } else if keyCode == VietnameseData.KEY_4 {
                            markMask = VNEngine.MARK4_MASK
                        } else if keyCode == VietnameseData.KEY_5 {
                            markMask = VNEngine.MARK5_MASK
                        }
                    }
                    
                    insertMarkInternal(markMask: markMask, canModifyFlag: true)
                    break
                }
            }
            
            if isCorrect {
                break
            }
        }
        
        if !isChanged {
            logCallback?("  → No pattern matched, inserting key as-is")
            insertKey(keyCode: keyCode, isCaps: isCaps)
        }
    }
    
    private func handleVowelKey(keyCode: UInt16, isCaps: Bool) {
        logCallback?("handleVowelKey: keyCode=\(keyCode), index=\(index), tempDisableKey=\(tempDisableKey), buffer=\(getCurrentWord())")
        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // Check VNI special case - find the vowel to apply circumflex/horn
        // VEI = -1 means no valid vowel (a, e, o) was found
        var VEI = -1
        if vInputType == 1 { // VNI
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let key = chr(i)
                if key == VietnameseData.KEY_O || key == VietnameseData.KEY_A || key == VietnameseData.KEY_E {
                    VEI = i
                    break
                }
            }
        }

        let keyForAEO: UInt16
        if vInputType != 1 {
            keyForAEO = keyCode
        } else {
            if keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8 {
                keyForAEO = VietnameseData.KEY_W
            } else if keyCode == VietnameseData.KEY_6 {
                // For VNI key 6: apply circumflex to found vowel (a->â, e->ê, o->ô)
                // If no vowel found (VEI == -1), keyForAEO will be 0 and won't match any pattern
                keyForAEO = VEI >= 0 ? chr(VEI) : 0
            } else {
                keyForAEO = keyCode
            }
        }
        
        guard let charsets = vietnameseData.vowelTable[keyForAEO] else {
            if keyCode == VietnameseData.KEY_W && vInputType != 2 {
                checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            } else {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        var isCorrect = false
        var isChanged = false
        
        for charset in charsets {
            if Int(index) < charset.count {
                continue
            }
            isCorrect = true
            var k = Int(index)
            
            // Check if matches vowel pattern
            for j in stride(from: charset.count - 1, through: 0, by: -1) {
                let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                if (charset[j] & ~endMask) != chr(k - 1) {
                    isCorrect = false
                    break
                }
                k -= 1
                if k < 0 {
                    break
                }
            }
            
            // NOTE: Duplicate consonant check is NOT applied for vowel keys (A, O, E, W)
            // It's only for mark keys (S, F, R, X, J) - see handleMarkKey
            
            if isCorrect {
                isChanged = true
                
                // Check if it's double letter (A, O, E) or W
                // For VNI: key 6 adds circumflex (^) to a, e, o -> â, ê, ô
                // We check keyCode (original key pressed) for VNI, not keyForAEO (which is already converted to vowel)
                let isKeyDouble = (vInputType != 1 && (keyForAEO == VietnameseData.KEY_A ||
                                                       keyForAEO == VietnameseData.KEY_O ||
                                                       keyForAEO == VietnameseData.KEY_E)) ||
                                 (vInputType == 1 && keyCode == VietnameseData.KEY_6)
                
                let isKeyW = isKeyW(keyCode: keyCode, inputType: vInputType)
                
                if isKeyDouble {
                    insertAOE(keyCode: keyForAEO, isCaps: isCaps)
                } else if isKeyW {
                    // VNI special validation for key 7 and key 8:
                    // Key 7: horn (móc) for 'o' → 'ơ' and 'u' → 'ư'
                    // Key 8: breve (trăng) only for 'a' → 'ă'
                    var shouldProcess = true
                    if vInputType == 1 {
                        // Re-search for vowels including U for horn (key 7)
                        VEI = -1
                        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                            let key = chr(i)
                            if key == VietnameseData.KEY_O || key == VietnameseData.KEY_U ||
                               key == VietnameseData.KEY_A || key == VietnameseData.KEY_E {
                                VEI = i
                                break
                            }
                        }

                        if VEI < 0 {
                            // No vowel found - don't process, insert key as-is
                            shouldProcess = false
                        } else {
                            let vowelKey = chr(VEI)
                            if keyCode == VietnameseData.KEY_7 {
                                // Key 7: horn (móc) for 'o' → 'ơ' and 'u' → 'ư'
                                // Only valid if previous vowel is 'o' or 'u'
                                shouldProcess = (vowelKey == VietnameseData.KEY_O || vowelKey == VietnameseData.KEY_U)
                            } else if keyCode == VietnameseData.KEY_8 {
                                // Key 8: breve (trăng) only for 'a' → 'ă'
                                // Only valid if previous vowel is 'a'
                                shouldProcess = (vowelKey == VietnameseData.KEY_A)
                            }
                        }
                    }
                    if shouldProcess {
                        insertW(keyCode: keyForAEO, isCaps: isCaps)
                    } else {
                        // Not a valid VNI combination - will be handled in the outer "if !isChanged" block
                        isChanged = false
                    }
                }
                break
            }
        }
        
        if !isChanged {
            logCallback?("handleVowelKey: no pattern matched, inserting key")
            if keyCode == VietnameseData.KEY_W && vInputType != 2 {
                checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            } else {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
        } else {
            logCallback?("handleVowelKey: pattern matched, isChanged=\(isChanged)")
        }
    }
    
    // MARK: - Key Checking Functions
    
    private func isSpecialKey(keyCode: UInt16) -> Bool {
        if vInputType == 0 { // Telex
            return keyCode == VietnameseData.KEY_W || keyCode == VietnameseData.KEY_E ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_O ||
                   keyCode == VietnameseData.KEY_LEFT_BRACKET || keyCode == VietnameseData.KEY_RIGHT_BRACKET ||
                   keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_S ||
                   keyCode == VietnameseData.KEY_D || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_J || keyCode == VietnameseData.KEY_Z ||
                   keyCode == VietnameseData.KEY_X
        } else if vInputType == 1 { // VNI
            return keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4 ||
                   keyCode == VietnameseData.KEY_5 || keyCode == VietnameseData.KEY_6 ||
                   keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8 ||
                   keyCode == VietnameseData.KEY_9 || keyCode == VietnameseData.KEY_0
        } else if vInputType == 2 || vInputType == 3 { // Simple Telex 1 & 2
            // Same as Telex but WITHOUT bracket keys [ and ]
            return keyCode == VietnameseData.KEY_W || keyCode == VietnameseData.KEY_E ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_O ||
                   keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_S ||
                   keyCode == VietnameseData.KEY_D || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_J || keyCode == VietnameseData.KEY_Z ||
                   keyCode == VietnameseData.KEY_X
        }
        return false
    }
    
    private func isQuickTelexKey(keyCode: UInt16) -> Bool {
        if index <= 0 {
            return false
        }
        let prevKey = UInt16(typingWord[Int(index) - 1] & VNEngine.CHAR_MASK)
        
        // Quick Telex only applies when:
        // 1. Current key is one of C, G, K, N, Q, P, T
        // 2. Previous key is the same (double letter)
        // 3. The double letter is at the beginning of the word (index == 1)
        //    This prevents "app" from becoming "aph"
        //    Quick Telex is meant for quickly typing consonant clusters at word start:
        //    pp → ph, cc → ch, gg → gi, nn → ng, kk → kh, qq → qu, tt → th
        let isQuickTelexChar = (keyCode == VietnameseData.KEY_C || keyCode == VietnameseData.KEY_G ||
                                keyCode == VietnameseData.KEY_K || keyCode == VietnameseData.KEY_N ||
                                keyCode == VietnameseData.KEY_Q || keyCode == VietnameseData.KEY_P ||
                                keyCode == VietnameseData.KEY_T)
        
        // Only apply at word start to avoid bugs like "app" → "aph"
        return isQuickTelexChar && prevKey == keyCode && index == 1
    }
    
    private func isKeyZ(keyCode: UInt16, inputType: Int) -> Bool {
        return vietnameseData.processingChar[inputType][10] == keyCode
    }
    
    private func isKeyD(keyCode: UInt16, inputType: Int) -> Bool {
        return vietnameseData.processingChar[inputType][9] == keyCode
    }
    
    private func isKeyW(keyCode: UInt16, inputType: Int) -> Bool {
        if inputType != 1 {
            return vietnameseData.processingChar[inputType][8] == keyCode
        } else {
            return vietnameseData.processingChar[inputType][8] == keyCode ||
                   vietnameseData.processingChar[inputType][7] == keyCode
        }
    }
    
    private func isMarkKey(keyCode: UInt16, inputType: Int) -> Bool {
        if inputType != 1 { // Not VNI
            return keyCode == VietnameseData.KEY_S || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_J ||
                   keyCode == VietnameseData.KEY_X
        } else { // VNI
            return keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_5 ||
                   keyCode == VietnameseData.KEY_4
        }
    }
    
    private func isBracketKey(keyCode: UInt16) -> Bool {
        return keyCode == VietnameseData.KEY_LEFT_BRACKET || keyCode == VietnameseData.KEY_RIGHT_BRACKET
    }
    
    private func isBracketKey(_ data: UInt32) -> Bool {
        let keyCode = UInt16(data & VNEngine.CHAR_MASK)
        return isBracketKey(keyCode: keyCode)
    }
    
    // MARK: - Insert Functions
    
    func insertKey(keyCode: UInt16, isCaps: Bool, isCheckSpelling: Bool = true) {
        logCallback?("insertKey: keyCode=\(keyCode), isCaps=\(isCaps), currentIndex=\(index)")
        if index >= VNEngine.MAX_BUFF {
            longWordHelper.append(typingWord[0])
            // Left shift
            for i in 0..<(VNEngine.MAX_BUFF - 1) {
                typingWord[i] = typingWord[i + 1]
            }
            setKeyData(index: UInt8(VNEngine.MAX_BUFF - 1), keyCode: keyCode, isCaps: isCaps)
        } else {
            setKeyData(index: index, keyCode: keyCode, isCaps: isCaps)
            index += 1
            logCallback?("  → After insert: index=\(index), typingWord[\(index-1)]=\(typingWord[Int(index)-1])")
        }
        
        if vCheckSpelling == 1 && isCheckSpelling {
            checkSpelling()
        }
        
        // Allow d after consonant
        if keyCode == VietnameseData.KEY_D && index >= 2 {
            let prevKey = UInt16(typingWord[Int(index) - 2] & VNEngine.CHAR_MASK)
            if vietnameseData.isConsonant(prevKey) {
                tempDisableKey = false
            }
        }
    }
    
    func setKeyData(index: UInt8, keyCode: UInt16, isCaps: Bool) {
        if index < 0 || index >= VNEngine.MAX_BUFF {
            return
        }
        typingWord[Int(index)] = UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0)
    }
    
    func insertState(keyCode: UInt16, isCaps: Bool) {
        if stateIndex >= VNEngine.MAX_BUFF {
            // Left shift
            for i in 0..<(VNEngine.MAX_BUFF - 1) {
                keyStates[i] = keyStates[i + 1]
            }
            keyStates[VNEngine.MAX_BUFF - 1] = UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0)
        } else {
            keyStates[Int(stateIndex)] = UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0)
            stateIndex += 1
        }
    }
    
    private var isChanged = false
    
    private func insertD(keyCode: UInt16, isCaps: Bool) {
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookState.backspaceCount += 1
            if chr(i) == VietnameseData.KEY_D {
                // Reverse unicode char
                if (typingWord[i] & VNEngine.TONE_MASK) != 0 {
                    // Restore and disable temporary
                    hookState.code = UInt8(vRestore)
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    // Use getCharacterCode to convert to proper character (not raw key code)
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    tempDisableKey = true
                    break
                } else {
                    typingWord[i] |= VNEngine.TONE_MASK
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                }
                break
            } else {
                // Present old char
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func insertAOE(keyCode: UInt16, isCaps: Bool) {
        findAndCalculateVowel()
        
        logCallback?("insertAOE: keyCode=\(keyCode), index=\(index)")
        logCallback?("  Current buffer: \(getCurrentWord())")
        
        // Remove W tone from all vowels
        for i in vowelStartIndex...vowelEndIndex {
            typingWord[i] &= ~VNEngine.TONEW_MASK
        }
        
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        
        // Check if we need to move mark from previous vowel to this one
        // This handles case: h-i-e-j-e → hịe → hiệ (mark moves from i to ê)
        var shouldMoveMark = false
        var markToMove: UInt32 = 0
        var markSourceIndex = -1
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookState.backspaceCount += 1
            logCallback?("  Loop i=\(i), chr=\(chr(i)), looking for=\(keyCode)")
            if chr(i) == keyCode {
                // Reverse unicode char
                if (typingWord[i] & VNEngine.TONE_MASK) != 0 {
                    // Restore and disable temporary
                    hookState.code = UInt8(vRestore)
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    // Use getCharacterCode to convert to proper character (not raw key code)
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    if keyCode != VietnameseData.KEY_O { // Case thoòng
                        tempDisableKey = true
                    }
                    break
                } else {
                    typingWord[i] |= VNEngine.TONE_MASK
                    if keyCode != VietnameseData.KEY_D {
                        typingWord[i] &= ~VNEngine.TONEW_MASK
                    }
                    
                    // Check if previous vowel has a mark that should move to this vowel
                    // For "iê", "yê" patterns: mark should be on ê, not on i/y
                    if keyCode == VietnameseData.KEY_E && i > 0 {
                        let prevKey = chr(i - 1)
                        if (prevKey == VietnameseData.KEY_I || prevKey == VietnameseData.KEY_Y) &&
                           (typingWord[i - 1] & VNEngine.MARK_MASK) != 0 {
                            // Move mark from i/y to ê
                            markToMove = typingWord[i - 1] & VNEngine.MARK_MASK
                            markSourceIndex = i - 1
                            shouldMoveMark = true
                            logCallback?("  → Will move mark from index \(i-1) to \(i)")
                        }
                    }
                    // For "uô" pattern: mark should be on ô, not on u
                    if keyCode == VietnameseData.KEY_O && i > 0 {
                        let prevKey = chr(i - 1)
                        if prevKey == VietnameseData.KEY_U &&
                           (typingWord[i - 1] & VNEngine.MARK_MASK) != 0 {
                            // Move mark from u to ô
                            markToMove = typingWord[i - 1] & VNEngine.MARK_MASK
                            markSourceIndex = i - 1
                            shouldMoveMark = true
                            logCallback?("  → Will move mark from index \(i-1) to \(i)")
                        }
                    }
                    
                    // Apply mark movement
                    if shouldMoveMark {
                        typingWord[markSourceIndex] &= ~VNEngine.MARK_MASK  // Remove mark from source
                        typingWord[i] |= markToMove  // Add mark to destination (ê/ô)
                        // Need to update backspace count to include the source vowel
                        hookState.backspaceCount = UInt8(Int(index) - markSourceIndex)
                    }
                    
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                }
                break
            } else {
                // Present old char
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        
        // If mark was moved, we need to regenerate charData for all affected vowels
        if shouldMoveMark && markSourceIndex >= 0 {
            let startIdx = markSourceIndex
            hookState.backspaceCount = UInt8(Int(index) - startIdx)
            for i in startIdx..<Int(index) {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func insertW(keyCode: UInt16, isCaps: Bool) {
        var isRestoredW = false
        
        findAndCalculateVowel()
        logCallback?("insertW: vowelCount=\(vowelCount), vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex)")
        
        // Remove ^ tone from all vowels
        for i in vowelStartIndex...vowelEndIndex {
            typingWord[i] &= ~VNEngine.TONE_MASK
        }
        
        if vowelCount > 1 {
            hookState.backspaceCount = UInt8(Int(index) - vowelStartIndex)
            hookState.newCharCount = hookState.backspaceCount
            
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            
            if (v1HasToneW && v2HasToneW) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_I) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_A) {
                // Restore and disable temporary
                hookState.code = UInt8(vRestore)
                
                for i in vowelStartIndex..<Int(index) {
                    typingWord[i] &= ~VNEngine.TONEW_MASK
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i]) & ~VNEngine.STANDALONE_MASK
                }
                isRestoredW = true
                tempDisableKey = true
            } else {
                hookState.code = UInt8(vWillProcess)
                
                // Apply W tone based on vowel combination
                if v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O {
                    // Special case: thuơn
                    if vowelStartIndex >= 2 && chr(vowelStartIndex - 2) == VietnameseData.KEY_T &&
                       chr(vowelStartIndex - 1) == VietnameseData.KEY_H {
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                        if vowelStartIndex + 2 < Int(index) && chr(vowelStartIndex + 2) == VietnameseData.KEY_N {
                            typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        }
                    } else if vowelStartIndex >= 1 && chr(vowelStartIndex - 1) == VietnameseData.KEY_Q {
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    } else {
                        typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    }
                } else if (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_A) ||
                          (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_I) ||
                          (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_U) ||
                          (v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_I) {
                    typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                } else if (v1Key == VietnameseData.KEY_I && v2Key == VietnameseData.KEY_O) ||
                          (v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_A) {
                    typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                } else {
                    // Don't do anything
                    tempDisableKey = true
                    isChanged = false
                    hookState.code = UInt8(vDoNothing)
                }
                
                for i in vowelStartIndex..<Int(index) {
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                }
            }
            
            return
        }
        
        // Single vowel case
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            if i < vowelStartIndex {
                break
            }
            hookState.backspaceCount += 1
            
            let key = chr(i)
            if key == VietnameseData.KEY_A || key == VietnameseData.KEY_U || key == VietnameseData.KEY_O {
                if (typingWord[i] & VNEngine.TONEW_MASK) != 0 {
                    // Restore and disable temporary
                    if (typingWord[i] & VNEngine.STANDALONE_MASK) != 0 {
                        hookState.code = UInt8(vWillProcess)
                        if key == VietnameseData.KEY_U {
                            typingWord[i] = UInt32(VietnameseData.KEY_W) | ((typingWord[i] & VNEngine.CAPS_MASK) != 0 ? VNEngine.CAPS_MASK : 0)
                        } else if key == VietnameseData.KEY_O {
                            hookState.code = UInt8(vRestore)
                            typingWord[i] = UInt32(VietnameseData.KEY_O) | ((typingWord[i] & VNEngine.CAPS_MASK) != 0 ? VNEngine.CAPS_MASK : 0)
                            isRestoredW = true
                        }
                        hookState.charData[Int(index) - 1 - i] = typingWord[i]
                    } else {
                        hookState.code = UInt8(vRestore)
                        typingWord[i] &= ~VNEngine.TONEW_MASK
                        hookState.charData[Int(index) - 1 - i] = typingWord[i]
                        isRestoredW = true
                    }
                    
                    tempDisableKey = true
                } else {
                    typingWord[i] |= VNEngine.TONEW_MASK
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    logCallback?("insertW: Added TONEW_MASK to typingWord[\(i)], now=\(String(format: "0x%X", typingWord[i]))")
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                }
                break
            } else {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func removeMark() {
        findAndCalculateVowel(forGrammar: true)
        isChanged = false
        
        if index > 0 {
            for i in vowelStartIndex...vowelEndIndex {
                if typingWord[i] & VNEngine.MARK_MASK != 0 {
                    typingWord[i] &= ~VNEngine.MARK_MASK
                    isChanged = true
                }
            }
        }
        
        if isChanged {
            hookState.code = UInt8(vWillProcess)
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: vowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
        } else {
            hookState.code = UInt8(vDoNothing)
        }
    }
    
    // MARK: - Vowel Processing
    
    private var vowelCount: UInt8 = 0
    private var vowelStartIndex = 0
    private var vowelEndIndex = 0
    private var vowelWillSetMark = 0
    
    private func findAndCalculateVowel(forGrammar: Bool = false) {
        vowelCount = 0
        vowelStartIndex = 0
        vowelEndIndex = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            let keyCode = UInt16(typingWord[i] & VNEngine.CHAR_MASK)
            if vietnameseData.isConsonant(keyCode) {
                if vowelCount > 0 {
                    break
                }
            } else {
                if vowelCount == 0 {
                    vowelEndIndex = i
                }
                if !forGrammar {
                    // Check gi, qu
                    if i >= 1 {
                        let prevKey = UInt16(typingWord[i - 1] & VNEngine.CHAR_MASK)
                        if (keyCode == VietnameseData.KEY_I && prevKey == VietnameseData.KEY_G) ||
                           (keyCode == VietnameseData.KEY_U && prevKey == VietnameseData.KEY_Q) {
                            break
                        }
                    }
                }
                vowelStartIndex = i
                vowelCount += 1
            }
        }
        
        // Don't count 'u' at 'qu' as vowel
        if vowelStartIndex >= 1 {
            let keyCode = UInt16(typingWord[vowelStartIndex] & VNEngine.CHAR_MASK)
            let prevKey = UInt16(typingWord[vowelStartIndex - 1] & VNEngine.CHAR_MASK)
            if keyCode == VietnameseData.KEY_U && prevKey == VietnameseData.KEY_Q {
                vowelStartIndex += 1
                vowelCount -= 1
            }
        }
    }
    
    // MARK: - Spelling Check
    
    private var spellingOK = false
    private var spellingVowelOK = false
    private var spellingEndIndex: UInt8 = 0
    
    func checkSpelling(forceCheckVowel: Bool = false) {
        spellingOK = false
        spellingVowelOK = true
        spellingEndIndex = index
        
        logCallback?("checkSpelling: index=\(index), word=\(getCurrentWord()), vAllowConsonantZFWJ=\(vAllowConsonantZFWJ)")
        
        if index > 0 && chr(Int(index) - 1) == VietnameseData.KEY_RIGHT_BRACKET {
            spellingEndIndex = index - 1
        }
        
        if spellingEndIndex > 0 {
            var j = 0
            
            // Check first consonant
            if vietnameseData.isConsonant(chr(0)) {
                var foundMatch = false
                for consonant in vietnameseData.consonantTable {
                    // Skip if word is shorter than consonant pattern
                    if spellingEndIndex < consonant.count {
                        continue
                    }
                    
                    var isMatch = true
                    j = 0
                    for keyInConsonant in consonant {
                        if spellingEndIndex > j {
                            let currentKey = chr(j)
                            
                            // Check if this consonant entry requires special permission
                            let hasAllowMask = (keyInConsonant & UInt16(VNEngine.CONSONANT_ALLOW_MASK)) != 0
                            let hasEndMask = (keyInConsonant & UInt16(VNEngine.END_CONSONANT_MASK)) != 0
                            
                            // Get the base key without masks
                            let baseKey = keyInConsonant & ~UInt16(VNEngine.CONSONANT_ALLOW_MASK) & ~UInt16(VNEngine.END_CONSONANT_MASK)
                            
                            // This entry requires CONSONANT_ALLOW_MASK but it's disabled
                            if hasAllowMask && vAllowConsonantZFWJ != 1 {
                                isMatch = false
                                break
                            }
                            // This entry requires END_CONSONANT_MASK but it's disabled
                            if hasEndMask && vQuickStartConsonant != 1 {
                                isMatch = false
                                break
                            }
                            
                            // Check if base key matches current key
                            if baseKey != currentKey {
                                isMatch = false
                                break
                            }
                        }
                        j += 1
                    }
                    
                    if isMatch {
                        foundMatch = true
                        break  // Found a matching consonant pattern
                    }
                }
                
                // If no consonant pattern matched, j stays at 0
                if !foundMatch {
                    j = 0
                }
            }
            
            if j == spellingEndIndex {
                spellingOK = true
            }
            
            // Check vowel
            var k = j
            vowelStartIndex = k
            
            // Fix case "que't"
            if chr(vowelStartIndex) == VietnameseData.KEY_U && k > 0 && k < Int(spellingEndIndex) - 1 &&
               chr(vowelStartIndex - 1) == VietnameseData.KEY_Q {
                k += 1
                j = k
                vowelStartIndex = k
            } else if index >= 2 && chr(0) == VietnameseData.KEY_G &&
                      chr(1) == VietnameseData.KEY_I && vietnameseData.isConsonant(chr(2)) {
                vowelStartIndex = 1
                k = 1
                j = 1
            }
            
            for _ in 0..<3 {
                if k < spellingEndIndex && !vietnameseData.isConsonant(chr(k)) {
                    k += 1
                    vowelEndIndex = k
                }
            }
            
            if k > j { // has vowel
                spellingVowelOK = false
                
                // Check correct combined vowel - OpenKey: forceCheckVowel
                if k - j > 1 && forceCheckVowel {
                    let firstVowelKey = chr(j)
                    if let vowelSet = vietnameseData.vowelCombine[firstVowelKey] {
                        for vowelPattern in vowelSet {
                            var spellingFlag = false
                            var ii = 1
                            while ii < vowelPattern.count {
                                let patternIdx = j + ii - 1
                                if patternIdx < Int(spellingEndIndex) {
                                    let currentChar = UInt32(chr(patternIdx)) |
                                                     (typingWord[patternIdx] & VNEngine.TONEW_MASK) |
                                                     (typingWord[patternIdx] & VNEngine.TONE_MASK)
                                    if vowelPattern[ii] != currentChar {
                                        spellingFlag = true
                                        break
                                    }
                                }
                                ii += 1
                            }
                            
                            // Check if pattern matches and conditions are met
                            let canHaveEndConsonant = vowelPattern[0] == 1
                            let hasMoreChars = k < Int(spellingEndIndex)
                            let nextCharIsConsonant = j + ii - 1 < Int(spellingEndIndex) &&
                                                      vietnameseData.isConsonant(chr(j + ii - 1))
                            
                            if spellingFlag || (hasMoreChars && !canHaveEndConsonant) ||
                               (j + ii - 1 < Int(spellingEndIndex) && !nextCharIsConsonant) {
                                continue
                            }
                            
                            spellingVowelOK = true
                            break
                        }
                    }
                } else if !vietnameseData.isConsonant(chr(j)) {
                    spellingVowelOK = true
                }
                
                // Check last consonant - MUST be inside "if k > j" block (OpenKey behavior)
                for endConsonant in vietnameseData.endConsonantTable {
                    var isMatch = true
                    var jj = 0
                    for keyInConsonant in endConsonant {
                        if Int(spellingEndIndex) > k + jj {
                            let currentKey = chr(k + jj)
                            
                            // Check if this end consonant entry requires quick end consonant
                            let hasEndMask = (keyInConsonant & UInt16(VNEngine.END_CONSONANT_MASK)) != 0
                            let baseKey = keyInConsonant & ~UInt16(VNEngine.END_CONSONANT_MASK)
                            
                            // Skip this entry if it has END_CONSONANT_MASK but vQuickEndConsonant is disabled
                            if hasEndMask && vQuickEndConsonant != 1 {
                                isMatch = false
                                break
                            }
                            
                            if baseKey != currentKey {
                                isMatch = false
                                break
                            }
                        }
                        jj += 1
                    }
                    
                    if !isMatch {
                        continue
                    }
                    
                    if k + jj >= Int(spellingEndIndex) {
                        spellingOK = true
                        break
                    }
                }
                
                // Limit: end consonant "ch", "t" cannot use with "~", "`", "?"
                if spellingOK {
                    if index >= 3 && chr(Int(index) - 1) == VietnameseData.KEY_H &&
                       chr(Int(index) - 2) == VietnameseData.KEY_C {
                        let mark = typingWord[Int(index) - 3] & VNEngine.MARK_MASK
                        if !(mark == VNEngine.MARK1_MASK || mark == VNEngine.MARK5_MASK || mark == 0) {
                            spellingOK = false
                        }
                    } else if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_T {
                        let mark = typingWord[Int(index) - 2] & VNEngine.MARK_MASK
                        if !(mark == VNEngine.MARK1_MASK || mark == VNEngine.MARK5_MASK || mark == 0) {
                            spellingOK = false
                        }
                    }
                }
            }
        } else {
            spellingOK = true
        }
        
        tempDisableKey = !(spellingOK && spellingVowelOK)
        logCallback?("checkSpelling result: spellingOK=\(spellingOK), spellingVowelOK=\(spellingVowelOK), tempDisableKey=\(tempDisableKey)")
    }
    
    func chr(_ idx: Int) -> UInt16 {
        // Match OpenKey behavior: directly access TypingWord without bounds check
        // This is intentional to match the original C++ implementation
        if idx < 0 || idx >= typingWord.count {
            return 0
        }
        return UInt16(typingWord[idx] & VNEngine.CHAR_MASK)
    }
    
    // MARK: - Grammar Check
    
    /// Check and auto-fix vowel combinations like "ưo" → "ươ"
    /// This should always run regardless of vFreeMark setting
    private func checkVowelAutoFix(deltaBackSpace: Int) {
        logCallback?("checkVowelAutoFix: index=\(index), deltaBackSpace=\(deltaBackSpace)")
        
        if index <= 1 || index >= VNEngine.MAX_BUFF {
            return
        }
        
        // Debug: print typingWord contents
        var debugBuffer = "typingWord: "
        for i in 0..<Int(index) {
            debugBuffer += "[\(i)]=\(String(format: "0x%X", typingWord[i])) "
        }
        logCallback?("  → \(debugBuffer)")
        
        findAndCalculateVowel(forGrammar: true)
        logCallback?("  → vowelCount=\(vowelCount), vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex)")
        
        if vowelCount == 0 {
            return
        }
        
        var isFixed = false
        
        // Check for "thuơn", "ưoi", "ưom", "ưoc" cases - auto-fix "ưo" → "ươ"
        if index >= 3 {
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let key = chr(i)
                if key == VietnameseData.KEY_N || key == VietnameseData.KEY_C ||
                   key == VietnameseData.KEY_I || key == VietnameseData.KEY_M ||
                   key == VietnameseData.KEY_P || key == VietnameseData.KEY_T {
                    logCallback?("  → Found end consonant at i=\(i), key=\(key)")
                    if i >= 2 && chr(i - 1) == VietnameseData.KEY_O && chr(i - 2) == VietnameseData.KEY_U {
                        let hasToneW1 = (typingWord[i - 1] & VNEngine.TONEW_MASK) != 0
                        let hasToneW2 = (typingWord[i - 2] & VNEngine.TONEW_MASK) != 0
                        logCallback?("  → Checking ưo pattern: o has TONEW=\(hasToneW1), u has TONEW=\(hasToneW2)")
                        if hasToneW1 != hasToneW2 {
                            typingWord[i - 2] |= VNEngine.TONEW_MASK
                            typingWord[i - 1] |= VNEngine.TONEW_MASK
                            isFixed = true
                            logCallback?("  → Fixed ưo → ươ!")
                            break
                        }
                    }
                }
            }
        }
        
        // Re-arrange data to send back
        if isFixed {
            if hookState.code == UInt8(vDoNothing) {
                hookState.code = UInt8(vWillProcess)
            }
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: vowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
            hookState.backspaceCount = UInt8(Int(hookState.backspaceCount) + deltaBackSpace)
            hookState.extCode = 4
        }
    }
    
    /// Check and auto-adjust mark position
    /// This only runs when vFreeMark is disabled
    private func checkMarkPosition(deltaBackSpace: Int) {
        logCallback?("checkMarkPosition: index=\(index), deltaBackSpace=\(deltaBackSpace)")
        
        if index <= 1 || index >= VNEngine.MAX_BUFF {
            logCallback?("  → Early return: index out of range")
            return
        }
        
        findAndCalculateVowel(forGrammar: true)
        logCallback?("  → vowelCount=\(vowelCount), vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex)")
        
        if vowelCount == 0 {
            logCallback?("  → Early return: no vowels")
            return
        }
        
        var isAdjusted = false
        
        // Check mark position
        if index >= 2 {
            for i in vowelStartIndex...vowelEndIndex {
                logCallback?("  → Checking typingWord[\(i)]=\(String(format: "0x%X", typingWord[i])), hasMark=\((typingWord[i] & VNEngine.MARK_MASK) != 0)")
                if typingWord[i] & VNEngine.MARK_MASK != 0 {
                    let mark = typingWord[i] & VNEngine.MARK_MASK
                    logCallback?("  → Found mark at index \(i), mark=\(String(format: "0x%X", mark))")
                    typingWord[i] &= ~VNEngine.MARK_MASK
                    insertMarkInternal(markMask: mark, canModifyFlag: false)
                    logCallback?("  → After insertMarkInternal: vowelWillSetMark=\(vowelWillSetMark)")
                    if i != vowelWillSetMark {
                        isAdjusted = true
                        logCallback?("  → Mark position adjusted from \(i) to \(vowelWillSetMark)")
                    }
                    break
                }
            }
        }
        logCallback?("  → isAdjusted=\(isAdjusted)")
        
        // Re-arrange data to send back
        if isAdjusted {
            if hookState.code == UInt8(vDoNothing) {
                hookState.code = UInt8(vWillProcess)
            }
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: vowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
            hookState.backspaceCount = UInt8(Int(hookState.backspaceCount) + deltaBackSpace)
            hookState.extCode = 4
        }
    }
    
    /// Legacy function - calls both checkVowelAutoFix and checkMarkPosition
    private func checkGrammar(deltaBackSpace: Int) {
        checkVowelAutoFix(deltaBackSpace: deltaBackSpace)
        if vFreeMark == 0 {
            checkMarkPosition(deltaBackSpace: deltaBackSpace)
        }
    }
    
    private func insertMarkInternal(markMask: UInt32, canModifyFlag: Bool) {
        logCallback?("insertMarkInternal: markMask=\(String(format: "0x%X", markMask)), canModifyFlag=\(canModifyFlag)")
        logCallback?("  Before: typingWord[1]=\(String(format: "0x%X", typingWord[1])), hasTone=\((typingWord[1] & VNEngine.TONE_MASK) != 0)")
        
        vowelCount = 0
        
        if canModifyFlag {
            hookState.code = UInt8(vWillProcess)
        }
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        
        findAndCalculateVowel()
        vowelWillSetMark = 0
        
        // IMPORTANT: Auto-fix "ưo" → "ươ" case (OpenKey checkGrammar logic)
        // If we have "uo" pattern where one has TONEW_MASK but the other doesn't,
        // add TONEW_MASK to both to make "ươ"
        if vowelCount >= 2 {
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            
            // Check for "uo" pattern with mismatched TONEW_MASK
            if v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O {
                if v1HasToneW != v2HasToneW {
                    // Add TONEW_MASK to both to make "ươ"
                    typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                    typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    logCallback?("  Auto-fixed ưo → ươ")
                }
            }
        }
        
        logCallback?("  vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex), vowelCount=\(vowelCount)")
        
        // Detect mark position
        if vowelCount == 1 {
            vowelWillSetMark = vowelEndIndex
            hookState.backspaceCount = UInt8(Int(index) - vowelEndIndex)
            logCallback?("  Single vowel: vowelWillSetMark=\(vowelWillSetMark)")
        } else {
            if vUseModernOrthography == 0 {
                handleOldMark()
                logCallback?("  After handleOldMark: vowelWillSetMark=\(vowelWillSetMark)")
            } else {
                handleModernMark()
                logCallback?("  After handleModernMark: vowelWillSetMark=\(vowelWillSetMark)")
            }
            
            // Check if last vowel has circumflex (^) or horn (ư/ơ)
            let veiHasTone = (typingWord[vowelEndIndex] & VNEngine.TONE_MASK) != 0
            let veiHasToneW = (typingWord[vowelEndIndex] & VNEngine.TONEW_MASK) != 0
            logCallback?("  vowelEndIndex=\(vowelEndIndex), veiHasTone=\(veiHasTone), veiHasToneW=\(veiHasToneW)")
            
            if veiHasTone || veiHasToneW {
                vowelWillSetMark = vowelEndIndex
                logCallback?("  Override: vowelWillSetMark=\(vowelWillSetMark) (last vowel has tone)")
            }
        }
        
        // Send data
        let kk = Int(index) - 1 - vowelStartIndex
        
        // If duplicate same mark -> restore
        if (typingWord[vowelWillSetMark] & markMask) != 0 {
            typingWord[vowelWillSetMark] &= ~VNEngine.MARK_MASK
            if canModifyFlag {
                hookState.code = UInt8(vRestore)
            }
            var kkVar = kk
            for i in vowelStartIndex..<Int(index) {
                typingWord[i] &= ~VNEngine.MARK_MASK
                hookState.charData[kkVar] = getCharacterCode(typingWord[i])
                kkVar -= 1
            }
            // IMPORTANT: Set backspaceCount correctly for restore case
            // This matches OpenKey behavior where backspaceCount is set from handleModernMark/handleOldMark
            // but we need to ensure it matches the actual charData we're sending
            hookState.backspaceCount = UInt8(Int(index) - vowelStartIndex)
            tempDisableKey = true
        } else {
            // Remove other mark
            typingWord[vowelWillSetMark] &= ~VNEngine.MARK_MASK
            
            // Add mark
            typingWord[vowelWillSetMark] |= markMask
            logCallback?("  After adding mark: typingWord[\(vowelWillSetMark)]=\(String(format: "0x%X", typingWord[vowelWillSetMark]))")
            
            var kkVar = kk
            for i in vowelStartIndex..<Int(index) {
                if i != vowelWillSetMark {
                    typingWord[i] &= ~VNEngine.MARK_MASK
                }
                let charCode = getCharacterCode(typingWord[i])
                hookState.charData[kkVar] = charCode
                logCallback?("  charData[\(kkVar)] = getCharacterCode(typingWord[\(i)]) = \(String(format: "0x%X", charCode))")
                kkVar -= 1
            }
            
            hookState.backspaceCount = UInt8(Int(index) - vowelStartIndex)
        }
        hookState.newCharCount = hookState.backspaceCount
        logCallback?("  Result: backspaceCount=\(hookState.backspaceCount), newCharCount=\(hookState.newCharCount)")
    }
    
    // MARK: - Mark Position Rules (Modern Orthography)
    
    private func handleModernMark() {
        // Default
        vowelWillSetMark = vowelEndIndex
        hookState.backspaceCount = UInt8(Int(index) - vowelEndIndex)
        
        // Rule 2: Special 3-vowel combinations
        if vowelCount == 3 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            let v3 = chr(vowelStartIndex + 2)
            
            if (v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_A && v3 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y && v3 == VietnameseData.KEY_U) ||
               (v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_E && v3 == VietnameseData.KEY_O) ||
               (v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y && v3 == VietnameseData.KEY_A) {
                vowelWillSetMark = vowelStartIndex + 1
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
            }
        } else if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            
            // oi, ai, ui -> mark on first vowel
            if (v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_I) {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
            }
            // ay -> mark on 'a'
            else if v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
            }
            // NOTE: "oa", "oe" cases are handled by the general rule below:
            // "If 1st vowel is 'o' or 'u' -> mark on last vowel"
            // This matches OpenKey behavior where "khoa" + r = "khoả" (mark on 'a')
            // The old XKey code incorrectly checked for end consonant, but OpenKey doesn't do that.
            // uo -> mark on 'o'
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelStartIndex + 1
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
            }
            // uy -> mark on 'u' (modern orthography: tùy, quý, thúy)
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
            }
            // If 2nd vowel is 'o' or 'u' -> mark on 1st vowel
            else if v2 == VietnameseData.KEY_O || v2 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex - 1
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark + 1)
            }
            // If 1st vowel is 'o' or 'u' -> mark on last vowel
            else if v1 == VietnameseData.KEY_O || v1 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelEndIndex)
            }
        }
        
        // Rule 3.1: Special combinations with circumflex/horn (iê, yê, uô, ươ)
        // NOTE: This rule applies regardless of vowelCount (2 or 3 vowels)
        // OpenKey: rule 3.1 - checks for iê, yê, uô, ươ patterns
        // Example: "nhiều" (nhieu + f) → dấu huyền đặt vào "ê" không phải "u"
        let rule3v1 = chr(vowelStartIndex)
        let rule3v1Data = typingWord[vowelStartIndex]
        let rule3v2Data = vowelStartIndex + 1 < Int(index) ? typingWord[vowelStartIndex + 1] : UInt32(0)
        let rule3v2 = UInt16(rule3v2Data & VNEngine.CHAR_MASK)
        let rule3v2HasTone = (rule3v2Data & VNEngine.TONE_MASK) != 0
        let rule3v1HasToneW = (rule3v1Data & VNEngine.TONEW_MASK) != 0
        let rule3v2HasToneW = (rule3v2Data & VNEngine.TONEW_MASK) != 0
        
        // Check for: iê, yê, uô, ươ patterns
        // iê: i + ê (e with circumflex)
        let isIE = (rule3v1 == VietnameseData.KEY_I && rule3v2 == VietnameseData.KEY_E && rule3v2HasTone)
        // yê: y + ê
        let isYE = (rule3v1 == VietnameseData.KEY_Y && rule3v2 == VietnameseData.KEY_E && rule3v2HasTone)
        // uô: u + ô (o with circumflex)
        let isUO = (rule3v1 == VietnameseData.KEY_U && rule3v2 == VietnameseData.KEY_O && rule3v2HasTone)
        // ươ: ư + ơ (both with horn)
        let isUwOw = (rule3v1 == VietnameseData.KEY_U && rule3v1HasToneW && rule3v2 == VietnameseData.KEY_O && rule3v2HasToneW)
        
        logCallback?("  Rule 3.1 check: isIE=\(isIE), isYE=\(isYE), isUO=\(isUO), isUwOw=\(isUwOw)")
        logCallback?("    rule3v1=\(rule3v1), rule3v2=\(rule3v2), rule3v2HasTone=\(rule3v2HasTone)")
        
        if isIE || isYE || isUO || isUwOw {
            if vowelStartIndex + 2 < Int(index) {
                let nextKey = chr(vowelStartIndex + 2)
                logCallback?("    nextKey=\(nextKey) at index \(vowelStartIndex + 2)")
                // If followed by certain consonants or vowels, mark goes on 2nd vowel
                if nextKey == VietnameseData.KEY_P || nextKey == VietnameseData.KEY_T ||
                   nextKey == VietnameseData.KEY_M || nextKey == VietnameseData.KEY_N ||
                   nextKey == VietnameseData.KEY_O || nextKey == VietnameseData.KEY_U ||
                   nextKey == VietnameseData.KEY_I || nextKey == VietnameseData.KEY_C {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                    logCallback?("    Rule 3.1 applied: mark on 2nd vowel (index \(vowelWillSetMark))")
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                    logCallback?("    Rule 3.1 applied: mark on 1st vowel (index \(vowelWillSetMark))")
                }
            } else {
                // No character after the vowel pair, mark on 1st vowel
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                logCallback?("    Rule 3.1 applied: no char after, mark on 1st vowel (index \(vowelWillSetMark))")
            }
        }
        // Rule 3.2: ia, ya, ua, ưu patterns - mark on 1st vowel
        else if (rule3v1 == VietnameseData.KEY_I && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_Y && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_U && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_U && rule3v2Data == (UInt32(VietnameseData.KEY_U) | VNEngine.TONEW_MASK)) {
            vowelWillSetMark = vowelStartIndex
            hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
        }
        
        // Rule 4: Special cases for 2 vowels
        if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            
            // ia, iu, io
            if v1 == VietnameseData.KEY_I && (v2 == VietnameseData.KEY_A || v2 == VietnameseData.KEY_U || v2 == VietnameseData.KEY_O) {
                // Check if there's 'g' before 'i'
                if vowelStartIndex > 0 && chr(vowelStartIndex - 1) == VietnameseData.KEY_G {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                }
            }
            // ua
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_A {
                var hasQ = false
                if vowelStartIndex > 0 && chr(vowelStartIndex - 1) == VietnameseData.KEY_Q {
                    hasQ = true
                }
                
                if !hasQ {
                    if vowelEndIndex + 1 >= Int(index) || !canHasEndConsonant() {
                        vowelWillSetMark = vowelStartIndex
                        hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                    }
                } else {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                }
            }
            // oo -> mark on last vowel
            else if v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = UInt8(Int(index) - vowelEndIndex)
            }
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func handleOldMark() {
        // Default
        if vowelCount == 0 && chr(vowelEndIndex) == VietnameseData.KEY_I {
            vowelWillSetMark = vowelEndIndex
        } else {
            vowelWillSetMark = vowelStartIndex
        }
        hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
        
        // Rule 2: 3 vowels or has ending consonant
        // For old style: "hòa" (no ending) vs "hoàn" (has ending 'n')
        if vowelCount == 3 || (vowelEndIndex + 1 < Int(index) && vietnameseData.isConsonant(chr(vowelEndIndex + 1)) && canHasEndConsonant()) {
            vowelWillSetMark = vowelStartIndex + 1
            hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
        }
        
        // Rule 3: For vowels with circumflex/horn (ê, ơ) - tone goes on that vowel
        // This handles: iê (hiện), yê (yến), ươ (người)
        // IMPORTANT: Only check ê and ơ - NOT ư or ô!
        // For "ươ" pattern (like "người"), the tone goes on "ơ", not "ư"
        // For "uô" pattern (like "uống"), rule 2 already handles it (mark on VSI+1)
        // This matches OpenKey behavior exactly
        for i in vowelStartIndex...vowelEndIndex {
            let key = chr(i)
            let hasTone = (typingWord[i] & VNEngine.TONE_MASK) != 0      // Has circumflex (^)
            let hasToneW = (typingWord[i] & VNEngine.TONEW_MASK) != 0    // Has horn (ơ)
            
            // ê (e with circumflex) or ơ (o with horn)
            // NOTE: Do NOT include ư or ô here!
            // - For "ươ" pattern, tone goes on "ơ", not "ư"
            // - For "uô" pattern, rule 2 handles it (3 vowels or end consonant)
            if (key == VietnameseData.KEY_E && hasTone) ||   // ê
               (key == VietnameseData.KEY_O && hasToneW) {   // ơ
                vowelWillSetMark = i
                hookState.backspaceCount = UInt8(Int(index) - vowelWillSetMark)
                break
            }
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func canHasEndConsonant() -> Bool {
        // TODO: Check vowel combine table
        return true
    }
    
    // MARK: - Standalone Character Handling
    
    private func checkForStandaloneChar(data: UInt16, isCaps: Bool, keyWillReverse: UInt16) {
        if index > 0 {
            let lastKey = chr(Int(index) - 1)
            let hasToneW = (typingWord[Int(index) - 1] & VNEngine.TONEW_MASK) != 0
            
            if lastKey == keyWillReverse && hasToneW {
                hookState.code = UInt8(vWillProcess)
                hookState.backspaceCount = 1
                hookState.newCharCount = 1
                typingWord[Int(index) - 1] = UInt32(data) | (isCaps ? VNEngine.CAPS_MASK : 0)
                hookState.charData[0] = getCharacterCode(typingWord[Int(index) - 1])
                return
            }
            
            // Check standalone w -> ư
            if index > 0 && lastKey == VietnameseData.KEY_U && keyWillReverse == VietnameseData.KEY_O {
                insertKey(keyCode: keyWillReverse, isCaps: isCaps)
                reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
                return
            }
        }
        
        if index == 0 {
            insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
            return
        } else if index == 1 {
            for badKey in vietnameseData.standaloneWbad {
                if chr(0) == badKey {
                    insertKey(keyCode: data, isCaps: isCaps)
                    return
                }
            }
            insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
            return
        } else if index == 2 {
            for allowed in vietnameseData.doubleWAllowed {
                if chr(0) == allowed[0] && chr(1) == allowed[1] {
                    insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
                    reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
                    return
                }
            }
            insertKey(keyCode: data, isCaps: isCaps)
            return
        }
        
        insertKey(keyCode: data, isCaps: isCaps)
    }
    
    private func reverseLastStandaloneChar(keyCode: UInt16, isCaps: Bool) {
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        hookState.newCharCount = 1
        hookState.extCode = 4
        typingWord[Int(index) - 1] = UInt32(keyCode) | VNEngine.TONEW_MASK | VNEngine.STANDALONE_MASK | (isCaps ? VNEngine.CAPS_MASK : 0)
        hookState.charData[0] = getCharacterCode(typingWord[Int(index) - 1])
    }
    
    // MARK: - State Management
    
    func saveWord() {
        if hookState.code == UInt8(vReplaceMacro) {
            logCallback?("saveWord: skipped (macro replacement)")
            return
        }
        
        if index > 0 {
            if !longWordHelper.isEmpty {
                var tempData = [UInt32]()
                for i in 0..<longWordHelper.count {
                    if i != 0 && i % VNEngine.MAX_BUFF == 0 {
                        typingStates.append(tempData)
                        tempData.removeAll()
                    }
                    tempData.append(longWordHelper[i])
                }
                typingStates.append(tempData)
                longWordHelper.removeAll()
            }
            
            var tempData = [UInt32]()
            for i in 0..<Int(index) {
                tempData.append(typingWord[i])
            }
            typingStates.append(tempData)
            logCallback?("saveWord: saved '\(getCurrentWord())' to typingStates, total=\(typingStates.count)")
        } else {
            logCallback?("saveWord: nothing to save (index=0)")
        }
    }
    
    func saveWord(keyCode: UInt16, count: Int) {
        var tempData = [UInt32]()
        for _ in 0..<count {
            tempData.append(UInt32(keyCode))
        }
        typingStates.append(tempData)
    }
    
    private func saveSpecialChar() {
        typingStates.append(specialChar)
        specialChar.removeAll()
    }
    
    func restoreLastTypingState() {
        logCallback?("restoreLastTypingState: typingStates.count=\(typingStates.count)")
        
        if typingStates.isEmpty {
            logCallback?("  → typingStates is empty, nothing to restore")
            return
        }
        
        let lastState = typingStates.removeLast()
        if lastState.isEmpty {
            logCallback?("  → lastState is empty")
            return
        }
        
        if lastState[0] == UInt32(VietnameseData.KEY_SPACE) {
            spaceCount = lastState.count
            index = 0
            logCallback?("  → Restored space: spaceCount=\(spaceCount)")
        } else if vietnameseData.charKeyCode.contains(UInt16(lastState[0] & VNEngine.CHAR_MASK)) {
            index = 0
            specialChar = lastState
            checkSpelling()
            logCallback?("  → Restored special char: count=\(specialChar.count)")
        } else {
            for i in 0..<lastState.count {
                typingWord[i] = lastState[i]
                // Also restore to keyStates for checkRestoreIfWrongSpelling
                keyStates[i] = lastState[i]
            }
            index = UInt8(lastState.count)
            stateIndex = UInt8(lastState.count)
            
            // OpenKey behavior: After restoring a normal word, DO NOT call checkSpelling()
            // This is intentional - it enables "free mark" feature by keeping tempDisableKey = false
            // (which was reset by startNewSession() before calling restoreLastTypingState())
            // This allows users to add marks to the restored word freely
            
            // Also reset tempDisableKey to false to ensure free mark works
            // This is needed because startNewSession() may not have been called before this
            // (e.g., when restoring after deleting spaces)
            tempDisableKey = false
            logCallback?("  → Restored word: index=\(index), stateIndex=\(stateIndex), buffer=\(getCurrentWord())")
        }
    }
    
    func startNewSession() {
        index = 0
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.macroKey.removeAll()  // Clear macro key for new word
        tempDisableKey = false
        stateIndex = 0
        hasHandledMacro = false
        hasHandleQuickConsonant = false
        longWordHelper.removeAll()
    }
    
    // MARK: - Character Code Conversion
    
    /// Convert internal code to actual character code based on code table
    func getCharacterCode(_ data: UInt32) -> UInt32 {
        let capsElem = (data & VNEngine.CAPS_MASK) != 0 ? 0 : 1
        var key = data & VNEngine.CHAR_MASK
        
        // Build lookup key with tone/horn flags
        var lookupKey: UInt32 = key
        if (data & VNEngine.TONE_MASK) != 0 {
            lookupKey |= VNEngine.TONE_MASK
        } else if (data & VNEngine.TONEW_MASK) != 0 {
            lookupKey |= VNEngine.TONEW_MASK
        }
        
        // Get code table
        let codeTable = vietnameseData.codeTables[vCodeTable]
        
        if (data & VNEngine.MARK_MASK) != 0 {
            // Has mark - calculate mark element index
            var markElem = -2
            switch data & VNEngine.MARK_MASK {
            case VNEngine.MARK1_MASK: markElem = 0  // Sắc
            case VNEngine.MARK2_MASK: markElem = 2  // Huyền
            case VNEngine.MARK3_MASK: markElem = 4  // Hỏi
            case VNEngine.MARK4_MASK: markElem = 6  // Ngã
            case VNEngine.MARK5_MASK: markElem = 8  // Nặng
            default: break
            }
            markElem += capsElem
            
            // Determine lookup key and markElem offset based on tone/horn presence
            // Code table structure:
            // - KEY_A | TONE_MASK (0x20000): [Â, â, Ă, ă, Á, á, À, à, Ả, ả, Ã, ã, Ạ, ạ] - 14 elements
            //   For marks on vowels WITH circumflex/breve, markElem needs +4 offset
            // - KEY_A | TONE_MASK | 0x80000: [Ấ, ấ, Ầ, ầ, Ẩ, ẩ, Ẫ, ẫ, Ậ, ậ] - 10 elements
            //   For marks on vowels WITH circumflex/breve AND mark, no offset needed
            // - KEY_O | 0x80000: [Ó, ó, Ò, ò, Ỏ, ỏ, Õ, õ, Ọ, ọ] - 10 elements
            //   For marks on PLAIN vowels (no circumflex/horn), no offset needed
            let keyCode = UInt16(key)
            var markLookupKey = lookupKey
            
            if (data & VNEngine.TONE_MASK) != 0 || (data & VNEngine.TONEW_MASK) != 0 {
                // Has circumflex/horn AND mark
                markLookupKey |= VNEngine.MARK1_MASK  // Use MARK1_MASK (0x80000) as base for lookup
                // No offset needed - array has 10 elements for marks only
            } else {
                // Plain vowel with mark (no circumflex/horn) - e.g., "ó", "á", "é", "ú"
                // Lookup key is KEY | MARK1_MASK (0x80000)
                markLookupKey = key | VNEngine.MARK1_MASK
                // No offset needed - array has 10 elements for marks only
            }
            
            logCallback?("getCharacterCode: data=\(String(format: "0x%X", data)), lookupKey=\(String(format: "0x%X", lookupKey)), markLookupKey=\(String(format: "0x%X", markLookupKey)), markElem=\(markElem), vCodeTable=\(vCodeTable)")
            
            // Look up in code table
            if let charArray = codeTable[markLookupKey], markElem >= 0 && markElem < charArray.count {
                let result = charArray[markElem]
                logCallback?("  Found in codeTable: charArray[\(markElem)]=\(String(format: "0x%X", result))")
                return result | VNEngine.CHAR_CODE_MASK
            }
            
            logCallback?("  NOT found in codeTable!")
            // Not found - return as is
            return data
        } else {
            // No mark
            if (data & VNEngine.TONE_MASK) != 0 || (data & VNEngine.TONEW_MASK) != 0 {
                // Has tone/horn but no mark
                // Code table structure for vowels:
                // - [0]: CAPS with ^ (TONE_MASK)
                // - [1]: lowercase with ^
                // - [2]: CAPS with horn (TONEW_MASK)
                // - [3]: lowercase with horn
                var charIndex = capsElem
                
                // Determine the correct lookup key based on character type
                // For O: both ^ (ô) and horn (ơ) are stored at KEY_O | TONE_MASK
                // For U: horn (ư) is stored at KEY_U | TONEW_MASK
                // For A: both ^ (â) and breve (ă) are stored at KEY_A | TONE_MASK
                let keyCode = UInt16(key)
                var actualLookupKey: UInt32
                
                if (data & VNEngine.TONEW_MASK) != 0 {
                    charIndex += 2  // Use index 2 or 3 for horn/breve characters
                    
                    // For O with horn (ơ): lookup at KEY_O | TONE_MASK, index 2,3
                    // For A with breve (ă): lookup at KEY_A | TONE_MASK, index 2,3
                    if keyCode == VietnameseData.KEY_O || keyCode == VietnameseData.KEY_A {
                        actualLookupKey = UInt32(keyCode) | VNEngine.TONE_MASK
                    } else {
                        // For U with horn (ư): lookup at KEY_U | TONEW_MASK
                        actualLookupKey = lookupKey
                    }
                } else {
                    // TONE_MASK (^): lookup at KEY | TONE_MASK
                    actualLookupKey = lookupKey
                }
                
                if let charArray = codeTable[actualLookupKey], charIndex < charArray.count {
                    return charArray[charIndex] | VNEngine.CHAR_CODE_MASK
                }
            }
            
            // No special character - return as is
            return data
        }
    }
    
    // MARK: - Public API
    
    /// Reset engine to initial state
    func reset() {
        startNewSession()
        typingStates.removeAll()
        specialChar.removeAll()
        spaceCount = 0
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false
    }
    
    /// Get current typing word as string (for debugging)
    func getCurrentWord() -> String {
        var result = ""
        for i in 0..<Int(index) {
            let charCode = getCharacterCode(typingWord[i])
            if (charCode & VNEngine.CHAR_CODE_MASK) != 0 {
                // Unicode character
                let unicodeValue = charCode & 0xFFFF
                if let scalar = UnicodeScalar(unicodeValue) {
                    result.append(Character(scalar))
                }
            } else {
                // Key code - convert to character using macOS key code mapping
                let keyCode = UInt16(charCode & VNEngine.CHAR_MASK)
                if let char = keyCodeToCharacter(keyCode) {
                    result.append(char)
                }
            }
        }
        return result
    }
    
    /// Convert macOS key code to character (for debugging)
    private func keyCodeToCharacter(_ keyCode: UInt16) -> Character? {
        switch keyCode {
        case VietnameseData.KEY_A: return "a"
        case VietnameseData.KEY_B: return "b"
        case VietnameseData.KEY_C: return "c"
        case VietnameseData.KEY_D: return "d"
        case VietnameseData.KEY_E: return "e"
        case VietnameseData.KEY_F: return "f"
        case VietnameseData.KEY_G: return "g"
        case VietnameseData.KEY_H: return "h"
        case VietnameseData.KEY_I: return "i"
        case VietnameseData.KEY_J: return "j"
        case VietnameseData.KEY_K: return "k"
        case VietnameseData.KEY_L: return "l"
        case VietnameseData.KEY_M: return "m"
        case VietnameseData.KEY_N: return "n"
        case VietnameseData.KEY_O: return "o"
        case VietnameseData.KEY_P: return "p"
        case VietnameseData.KEY_Q: return "q"
        case VietnameseData.KEY_R: return "r"
        case VietnameseData.KEY_S: return "s"
        case VietnameseData.KEY_T: return "t"
        case VietnameseData.KEY_U: return "u"
        case VietnameseData.KEY_V: return "v"
        case VietnameseData.KEY_W: return "w"
        case VietnameseData.KEY_X: return "x"
        case VietnameseData.KEY_Y: return "y"
        case VietnameseData.KEY_Z: return "z"
        case VietnameseData.KEY_0: return "0"
        case VietnameseData.KEY_1: return "1"
        case VietnameseData.KEY_2: return "2"
        case VietnameseData.KEY_3: return "3"
        case VietnameseData.KEY_4: return "4"
        case VietnameseData.KEY_5: return "5"
        case VietnameseData.KEY_6: return "6"
        case VietnameseData.KEY_7: return "7"
        case VietnameseData.KEY_8: return "8"
        case VietnameseData.KEY_9: return "9"
        case VietnameseData.KEY_SPACE: return " "
        default: return nil
        }
    }
}

// MARK: - Advanced Features (Phase 5)
// TODO: Implement MacroManager, SmartSwitchManager, ConvertTool
/*
extension VNEngine {
    
    // MARK: - Managers
    
    private static var macroManager = MacroManager()
    private static var smartSwitchManager = SmartSwitchManager()
    private static var convertTool = ConvertTool()
    
    // MARK: - Macro Support
    
    /// Add a macro
    func addMacro(text: String, content: String) -> Bool {
        return VNEngine.macroManager.addMacro(text: text, content: content)
    }
    
    /// Delete a macro
    func deleteMacro(text: String) -> Bool {
        return VNEngine.macroManager.deleteMacro(text: text)
    }
    
    /// Check if macro exists
    func hasMacro(text: String) -> Bool {
        return VNEngine.macroManager.hasMacro(text: text)
    }
    
    /// Get all macros
    func getAllMacros() -> [(key: [UInt32], text: String, content: String)] {
        return VNEngine.macroManager.getAllMacros()
    }
    
    /// Save macros to file
    func saveMacrosToFile(path: String) -> Bool {
        return VNEngine.macroManager.saveToFile(path: path)
    }
    
    /// Load macros from file
    func loadMacrosFromFile(path: String, append: Bool = true) -> Bool {
        return VNEngine.macroManager.loadFromFile(path: path, append: append)
    }
    
    /// Configure macro settings
    func configureMacro(codeTable: Int, autoCapsMacro: Bool) {
        VNEngine.macroManager.setCodeTable(codeTable)
        VNEngine.macroManager.setAutoCapsMacro(autoCapsMacro)
    }
    
    // MARK: - Smart Switch Key
    
    /// Get language for app
    func getAppLanguage(bundleId: String, currentLanguage: Int) -> Int {
        return VNEngine.smartSwitchManager.getAppLanguage(bundleId: bundleId, currentLanguage: currentLanguage)
    }
    
    /// Set language for app
    func setAppLanguage(bundleId: String, language: Int) {
        VNEngine.smartSwitchManager.setAppLanguage(bundleId: bundleId, language: language)
    }
    
    /// Get all app settings
    func getAllAppLanguages() -> [(bundleId: String, language: Int)] {
        return VNEngine.smartSwitchManager.getAllApps()
    }
    
    /// Save smart switch data to file
    func saveSmartSwitchToFile(path: String) -> Bool {
        return VNEngine.smartSwitchManager.saveToFile(path: path)
    }
    
    /// Load smart switch data from file
    func loadSmartSwitchFromFile(path: String) -> Bool {
        return VNEngine.smartSwitchManager.loadFromFile(path: path)
    }
    
    // MARK: - Convert Tool
    
    /// Convert text with specified settings
    func convertText(_ text: String, settings: ConvertSettings) -> String {
        let tool = VNEngine.convertTool
        tool.toAllCaps = settings.toAllCaps
        tool.toAllNonCaps = settings.toAllNonCaps
        tool.toCapsFirstLetter = settings.toCapsFirstLetter
        tool.toCapsEachWord = settings.toCapsEachWord
        tool.removeMark = settings.removeMark
        tool.fromCode = settings.fromCode
        tool.toCode = settings.toCode
        
        return tool.convert(text)
    }
    
    /// Convert settings structure
    struct ConvertSettings {
        var toAllCaps = false
        var toAllNonCaps = false
        var toCapsFirstLetter = false
        var toCapsEachWord = false
        var removeMark = false
        var fromCode: UInt8 = 0
        var toCode: UInt8 = 0
    }
}
*/

// MARK: - Public API for KeyboardEventHandler Integration

extension VNEngine {
    
    /// Processing result structure
    struct ProcessResult {
        var shouldConsume: Bool = false
        var backspaceCount: Int = 0
        var newCharacters: [VNCharacter] = []
        
        // Static helper for common cases
        static let doNothing = ProcessResult(shouldConsume: false, backspaceCount: 0, newCharacters: [])
    }
    
    // Alias for compatibility
    typealias ProcessingResult = ProcessResult
    
    /// Process a key press
    func processKey(character: Character, keyCode: CGKeyCode, isUppercase: Bool) -> ProcessResult {
        let result = handleKeyEvent(keyCode: keyCode, character: character, isUppercase: isUppercase, hasOtherModifier: false)
        return convertHookStateToResult(result, currentKeyCode: keyCode, currentCharacter: character, isUppercase: isUppercase)
    }
    
    /// Process backspace key
    func processBackspace() -> ProcessResult {
        handleDelete()
        return convertHookStateToResult(hookState, currentKeyCode: nil, currentCharacter: nil, isUppercase: false)
    }
    
    /// Process word break (space, punctuation, etc.)
    /// Returns ProcessResult with macro replacement if found
    func processWordBreak(character: Character) -> ProcessResult {
        logCallback?("processWordBreak: char='\(character)', vUseMacro=\(vUseMacro), index=\(index), buffer=\(getCurrentWord())")
        
        // Check macro before resetting
        if vUseMacro == 1 && !hasHandledMacro {
            logCallback?("  → Checking macro, macroKey has \(hookState.macroKey.count) chars")
            if findAndReplaceMacro() {
                logCallback?("  → Macro found! backspace=\(hookState.backspaceCount), newChars=\(hookState.newCharCount)")
                let result = convertHookStateToResult(hookState, currentKeyCode: nil, currentCharacter: character, isUppercase: false)
                // Reset after macro replacement
                reset()
                return result
            }
        }
        
        // IMPORTANT: Save current word to typingStates BEFORE resetting
        // This enables "free mark" feature - user can add marks to previous word after backspace
        // OpenKey behavior: saveWord() is called before startNewSession()
        
        // If we already have spaces saved, save them first
        if spaceCount > 0 {
            logCallback?("  → Saving previous spaces: count=\(spaceCount)")
            saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
            spaceCount = 0
        }
        
        // Save current word
        logCallback?("  → Saving current word...")
        saveWord()
        
        // Increment space count for the current space
        spaceCount = 1
        logCallback?("  → Set spaceCount=1, typingStates.count=\(typingStates.count)")
        
        // Start new session but DON'T clear typingStates
        startNewSession()
        
        // Reset spell checking to original setting
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false
        
        return ProcessResult() // Empty result, no consumption
    }
    
    /// Debug: Read word before cursor (for testing)
    /// This reads the actual text from the focused application using Accessibility API
    func debugReadWordBeforeCursor() {
        logCallback?("=== DEBUG: Read Word Before Cursor ===")
        
        // 1. Log internal buffer state
        logCallback?("[Internal Buffer]")
        logCallback?("  Buffer index: \(index)")
        logCallback?("  Buffer word: \(getCurrentWord())")
        
        // Log each character in buffer
        for i in 0..<Int(index) {
            let isCaps = (typingWord[i] & VNEngine.CAPS_MASK) != 0
            let hasTone = (typingWord[i] & VNEngine.TONE_MASK) != 0
            let hasToneW = (typingWord[i] & VNEngine.TONEW_MASK) != 0
            let hasMark = (typingWord[i] & VNEngine.MARK_MASK) != 0
            
            logCallback?("  [\(i)]: keyCode=\(chr(i)) caps=\(isCaps) tone=\(hasTone) toneW=\(hasToneW) mark=\(hasMark)")
        }
        
        // 2. Read actual text from focused application using Accessibility API
        logCallback?("[Accessibility - Focused App]")
        
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            logCallback?("  ❌ No frontmost application")
            return
        }
        
        logCallback?("  App: \(focusedApp.localizedName ?? "Unknown") (\(focusedApp.bundleIdentifier ?? ""))")
        
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        
        // Get focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard focusResult == .success, let element = focusedElement else {
            logCallback?("  ❌ Cannot get focused element (error: \(focusResult.rawValue))")
            return
        }
        
        let axElement = element as! AXUIElement
        
        // Get role
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "Unknown"
        logCallback?("  Role: \(role)")
        
        // Get selected text range
        var selectedRangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        if rangeResult == .success, let rangeValue = selectedRangeValue {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                logCallback?("  Cursor position: \(range.location), selection length: \(range.length)")
                
                // Get full text value
                var textValue: CFTypeRef?
                let textResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &textValue)
                
                if textResult == .success, let text = textValue as? String {
                    let cursorPos = range.location
                    
                    // Find word before cursor
                    if cursorPos > 0 && cursorPos <= text.count {
                        let textBeforeCursor = String(text.prefix(cursorPos))
                        
                        // Find last word (split by whitespace)
                        let words = textBeforeCursor.components(separatedBy: .whitespacesAndNewlines)
                        let lastWord = words.last ?? ""
                        
                        logCallback?("  Text before cursor: \"\(textBeforeCursor.suffix(50))\"")
                        logCallback?("  ✅ Last word: \"\(lastWord)\"")
                        
                        // Show Unicode code points
                        if !lastWord.isEmpty {
                            let codePoints = lastWord.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                            logCallback?("  Unicode: \(codePoints)")
                        }
                    } else {
                        logCallback?("  Cursor at position 0 or invalid")
                    }
                } else {
                    logCallback?("  ❌ Cannot get text value (error: \(textResult.rawValue))")
                }
            }
        } else {
            logCallback?("  ❌ Cannot get selected text range (error: \(rangeResult.rawValue))")
            
            // Try alternative: get selected text directly
            var selectedTextValue: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
            if selectedResult == .success, let selectedText = selectedTextValue as? String {
                logCallback?("  Selected text: \"\(selectedText)\"")
            }
        }
        
        logCallback?("=== End Read Word ===")
    }
    
    /// Convert HookState to ProcessResult
    private func convertHookStateToResult(_ hookState: HookState, currentKeyCode: CGKeyCode?, currentCharacter: Character?, isUppercase: Bool) -> ProcessResult {
        var result = ProcessResult()
        
        // Check if we should consume the key
        // IMPORTANT: In OpenKey, normal keys (consonants, vowels) are consumed and stored in buffer
        // but they are NOT injected immediately (vDoNothing with extCode=3)
        // They are only injected when a special key triggers processing (vWillProcess)
        // 
        // However, in XKey's architecture, we need to either:
        // 1. Pass through (let OS display) - for normal keys
        // 2. Consume and inject - for processed keys
        //
        // So we should ONLY consume when engine has output to inject
        result.shouldConsume = hookState.code == UInt8(vWillProcess) || 
                               hookState.code == UInt8(vRestore) ||
                               hookState.code == UInt8(vReplaceMacro)
        
        result.backspaceCount = Int(hookState.backspaceCount)
        
        // Convert character data to VNCharacter array
        // IMPORTANT: In OpenKey, charData is stored in reverse order (last character at index 0)
        // So we need to read it in reverse order to get the correct sequence
        // This matches OpenKey's SendNewCharString which reads from newCharCount-1 down to 0
        for i in stride(from: Int(hookState.newCharCount) - 1, through: 0, by: -1) {
            let charData = hookState.charData[i]
            let vnChar = convertToVNCharacter(charData)
            result.newCharacters.append(vnChar)
        }
        
        // IMPORTANT: When vRestore, OpenKey adds the current key to the output
        // This is how toggle works: restore the original character AND add the current key
        // See OpenKey's SendNewCharString: "if is restore" block
        if hookState.code == UInt8(vRestore) || hookState.code == UInt8(vRestoreAndStartNewSession) {
            if let character = currentCharacter {
                // Add the current key to output
                let vnChar = VNCharacter(character: isUppercase ? Character(String(character).uppercased()) : character)
                result.newCharacters.append(vnChar)
            }
        }
        
        return result
    }
    
    /// Convert internal character data to VNCharacter
    private func convertToVNCharacter(_ data: UInt32) -> VNCharacter {
        let isCaps = (data & VNEngine.CAPS_MASK) != 0
        
        // Check if it's a character code (converted character)
        if (data & VNEngine.CHAR_CODE_MASK) != 0 {
            // This is a Unicode character - get the actual character
            let unicodeValue = data & 0xFFFF
            if let scalar = UnicodeScalar(unicodeValue) {
                let char = Character(scalar)
                return VNCharacter(character: char)
            }
        }
        
        // It's a key code - convert to character
        let keyCode = UInt16(data & VNEngine.CHAR_MASK)
        
        // Check if it's a vowel with tone/mark
        let hasTone = (data & VNEngine.TONE_MASK) != 0
        let hasToneW = (data & VNEngine.TONEW_MASK) != 0
        let markMask = data & VNEngine.MARK_MASK
        
        // Determine tone
        var tone = VNTone.none
        if markMask != 0 {
            switch markMask {
            case VNEngine.MARK1_MASK: tone = .acute
            case VNEngine.MARK2_MASK: tone = .grave
            case VNEngine.MARK3_MASK: tone = .hookAbove
            case VNEngine.MARK4_MASK: tone = .tilde
            case VNEngine.MARK5_MASK: tone = .dotBelow
            default: break
            }
        }
        
        // Map key code to vowel/consonant
        if let vnChar = mapKeyCodeToVNCharacter(keyCode, hasTone: hasTone, hasToneW: hasToneW, tone: tone, isCaps: isCaps) {
            return vnChar
        }
        
        // Fallback: use keyCodeToCharacter to properly convert macOS key codes
        // This handles special keys like W, Z, F, J, etc. that are not vowels/consonants
        if let char = keyCodeToCharacter(keyCode) {
            let finalChar = isCaps ? Character(String(char).uppercased()) : char
            return VNCharacter(character: finalChar)
        }
        
        return VNCharacter(character: "?")
    }
    
    /// Map key code to VNCharacter
    private func mapKeyCodeToVNCharacter(_ keyCode: UInt16, hasTone: Bool, hasToneW: Bool, tone: VNTone, isCaps: Bool) -> VNCharacter? {
        // Map key codes to vowels
        switch keyCode {
        case VietnameseData.KEY_A:
            if hasTone {
                return VNCharacter(vowel: .aCircumflex, tone: tone, isUppercase: isCaps)
            } else if hasToneW {
                return VNCharacter(vowel: .aBreve, tone: tone, isUppercase: isCaps)
            } else {
                return VNCharacter(vowel: .a, tone: tone, isUppercase: isCaps)
            }
        case VietnameseData.KEY_E:
            if hasTone {
                return VNCharacter(vowel: .eCircumflex, tone: tone, isUppercase: isCaps)
            } else {
                return VNCharacter(vowel: .e, tone: tone, isUppercase: isCaps)
            }
        case VietnameseData.KEY_I:
            return VNCharacter(vowel: .i, tone: tone, isUppercase: isCaps)
        case VietnameseData.KEY_O:
            if hasTone {
                return VNCharacter(vowel: .oCircumflex, tone: tone, isUppercase: isCaps)
            } else if hasToneW {
                return VNCharacter(vowel: .oHorn, tone: tone, isUppercase: isCaps)
            } else {
                return VNCharacter(vowel: .o, tone: tone, isUppercase: isCaps)
            }
        case VietnameseData.KEY_U:
            if hasToneW {
                return VNCharacter(vowel: .uHorn, tone: tone, isUppercase: isCaps)
            } else {
                return VNCharacter(vowel: .u, tone: tone, isUppercase: isCaps)
            }
        case VietnameseData.KEY_Y:
            return VNCharacter(vowel: .y, tone: tone, isUppercase: isCaps)
        case VietnameseData.KEY_D:
            // Only return đ if hasTone is set (TONE_MASK indicates đ)
            if hasTone {
                return VNCharacter(consonant: .dd, isUppercase: isCaps)
            } else {
                return VNCharacter(consonant: .d, isUppercase: isCaps)
            }
        default:
            // Map other consonants
            if let consonant = mapKeyCodeToConsonant(keyCode) {
                return VNCharacter(consonant: consonant, isUppercase: isCaps)
            }
        }
        
        return nil
    }
    
    /// Map key code to consonant
    private func mapKeyCodeToConsonant(_ keyCode: UInt16) -> VNConsonant? {
        switch keyCode {
        case VietnameseData.KEY_B: return .b
        case VietnameseData.KEY_C: return .c
        case VietnameseData.KEY_D: return .d
        case VietnameseData.KEY_G: return .g
        case VietnameseData.KEY_H: return .h
        case VietnameseData.KEY_K: return .k
        case VietnameseData.KEY_L: return .l
        case VietnameseData.KEY_M: return .m
        case VietnameseData.KEY_N: return .n
        case VietnameseData.KEY_P: return .p
        case VietnameseData.KEY_Q: return .q
        case VietnameseData.KEY_R: return .r
        case VietnameseData.KEY_S: return .s
        case VietnameseData.KEY_T: return .t
        case VietnameseData.KEY_V: return .v
        case VietnameseData.KEY_X: return .x
        default: return nil
        }
    }
}
