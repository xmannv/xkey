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
    
    /// Convert macOS virtual key code to printable character for logging
    static func keyCodeToChar(_ keyCode: UInt16) -> Character? {
        // Mapping based on VietnameseData key codes (macOS virtual key codes)
        let mapping: [UInt16: Character] = [
            0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
            0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q",
            0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "o", 0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p",
            0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
            0x32: "`", 0x31: " "  // space
        ]
        return mapping[keyCode]
    }
    
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
    var vAddSpaceAfterMacro = 0    // 0: No, 1: Yes (add space after macro expansion)
    var vUseSmartSwitchKey = 0     // 0: No, 1: Yes
    var vUpperCaseFirstChar = 0    // 0: No, 1: Yes
    var vTempOffSpelling = 0       // 0: No, 1: Yes (temp off spell check via toolbar)
    var vTempOffEngine = 0         // 0: No, 1: Yes (temp off engine via toolbar)
    var vAllowConsonantZFWJ = 0    // 0: No, 1: Yes
    var vQuickStartConsonant = 0   // 0: No, 1: Yes (f->ph, j->gi, w->qu)
    var vQuickEndConsonant = 0     // 0: No, 1: Yes (g->ng, h->nh, k->ch)
    var vTempOffOpenKey = 0        // 0: No, 1: Yes (temp off engine with Option key)
    
    // MARK: - Unified Buffer System
    //
    // Single source of truth for typing state.
    // Each CharacterEntry contains both raw keystrokes and processed output.

    /// Primary typing buffer
    let buffer = TypingBuffer()

    /// History of typed words for restore functionality
    let history = TypingHistory()

    // MARK: - Buffer Accessors
    //
    // Wrapper types provide array-like access to buffer while using
    // unified buffer as single source of truth.

    /// Wrapper for accessing processed character data with array syntax
    struct ProcessedDataAccessor {
        let buffer: TypingBuffer

        subscript(i: Int) -> UInt32 {
            get {
                guard i >= 0 && i < buffer.count else { return 0 }
                return buffer[i].processedData
            }
            nonmutating set {
                guard i >= 0 && i < buffer.count else { return }
                buffer[i].processedData = newValue
            }
        }

        var count: Int { buffer.count }
    }

    /// Wrapper for accessing raw keystrokes with array syntax
    struct RawKeystrokeAccessor {
        let buffer: TypingBuffer

        subscript(i: Int) -> UInt32 {
            get {
                // Use direct access instead of creating array each time
                guard let keystroke = buffer.getRawKeystroke(at: i) else { return 0 }
                return keystroke.asUInt32
            }
            nonmutating set {
                // Raw keystrokes are managed through buffer operations
            }
        }

        var count: Int { buffer.totalKeystrokeCount }
    }

    /// Access to processed data (typingWord replacement)
    var typingWord: ProcessedDataAccessor {
        ProcessedDataAccessor(buffer: buffer)
    }

    /// Access to raw keystrokes (keyStates replacement)
    var keyStates: RawKeystrokeAccessor {
        RawKeystrokeAccessor(buffer: buffer)
    }

    /// Number of characters in buffer
    var index: UInt8 {
        UInt8(min(buffer.count, Int(UInt8.max)))
    }

    /// Total raw keystrokes count
    var stateIndex: UInt8 {
        UInt8(min(buffer.totalKeystrokeCount, Int(UInt8.max)))
    }

    /// Get key code at index
    func chr(_ idx: Int) -> UInt16 {
        buffer.keyCode(at: idx)
    }

    // MARK: - Engine State

    var tempDisableKey = false
    var spaceCount = 0
    var hasHandledMacro = false
    var upperCaseStatus: UInt8 = 0
    var specialChar = [UInt32]()
    var useSpellCheckingBefore = false
    var hasHandleQuickConsonant = false
    var willTempOffEngine = false

    /// Flag to track when cursor was moved by mouse click or arrow keys
    /// When true, restore logic is skipped because engine doesn't have full context
    /// of the word being edited (user may be editing middle of an existing word)
    var cursorMovedSinceReset = false

    /// Flag to track when focus change occurred during typing session
    /// This can happen when suggestion popups appear, causing keystrokes to go to popup
    /// instead of target input, causing buffer desync. When true, restore is skipped
    /// at word break/backspace to avoid incorrect output.
    var focusChangedDuringTyping = false

    /// Flag to track when buffer-screen desync was detected
    /// When true, spelling check and restore are disabled until new session starts.
    /// This prevents incorrect restore when engine doesn't have full context (e.g., user
    /// clicked mid-word and continued typing, or backspaced across word boundary).
    var bufferDesyncDetected = false

    
    // MARK: - Logging

    /// Logging callback
    var logCallback: ((String) -> Void)?

    // MARK: - Hook State (result to send back)
    
    struct HookState {
        var code: UInt8 = 0           // 0: DoNothing, 1: Process, 2: WordBreak, 3: Restore, 4: ReplaceMacro
        var backspaceCount: Int = 0   // Changed from UInt8 to Int to support longer macros
        var newCharCount: Int = 0     // Changed from UInt8 to Int to support longer macros
        var extCode: UInt8 = 0        // 1: WordBreak, 2: Delete, 3: Normal, 4: ShouldNotSendEmpty, 5: InstantRestore
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
        // Debug: Log Space key
        if keyCode == VietnameseData.KEY_SPACE {
            logCallback?("SPACE KEY RECEIVED: keyCode=\(keyCode), index=\(index)")
        }
        
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
        
        // NOTE: Space is handled by processWordBreak() which is called directly by handlers
        
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

    private func isMacroBreakCode(keyCode: UInt16, isCaps: Bool) -> Bool {
        // Check if it's in the standard macro break code list
        if vietnameseData.macroBreakCode.contains(keyCode) {
            return true
        }

        // Special case: number keys with Shift produce special characters (@, !, #, etc.)
        // and should also trigger macro replacement
        if isCaps && vietnameseData.isNumberKey(keyCode) {
            return true
        }

        return false
    }

    private func handleWordBreak(keyCode: UInt16, character: Character, isCaps: Bool) {
        hookState.code = UInt8(vDoNothing)
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.extCode = 1 // word break

        // For special characters that can be part of a macro (like @, !, #, ~),
        // just add them to macroKey WITHOUT triggering macro replacement.
        // Macro replacement should only happen when user presses SPACE.
        let isCharKeyCode = vietnameseData.charKeyCode.contains(keyCode)
        if shouldUseMacro() && isMacroBreakCode(keyCode: keyCode, isCaps: isCaps) && !hasHandledMacro {
            if isCharKeyCode {
                // Add character to macroKey for building macros like "you@" or "!bb"
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            }
            // NOTE: Do NOT call findAndReplaceMacro() here
            // Macro replacement only happens on SPACE (in processWordBreak)
        }
        
        // Check quick consonant
        if (vQuickStartConsonant == 1 || vQuickEndConsonant == 1) && !tempDisableKey && isMacroBreakCode(keyCode: keyCode, isCaps: isCaps) {
            checkQuickConsonant()
        }
        
        // Check restore if wrong spelling
        // IMPORTANT: Skip restore if cursor was moved (editing mid-word)
        // Also skip if spelling is temporarily off via toolbar
        if vRestoreIfWrongSpelling == 1 && vTempOffSpelling == 0 && isWordBreak(keyCode: keyCode) && !cursorMovedSinceReset {
            if !tempDisableKey && vCheckSpelling == 1 {
                checkSpelling(forceCheckVowel: true)
            }
            if tempDisableKey {
                checkRestoreIfWrongSpelling(handleCode: vRestoreAndStartNewSession)
            }
        } else if cursorMovedSinceReset && isWordBreak(keyCode: keyCode) {
            logCallback?("handleWordBreak: Skip restore because cursor was moved (editing mid-word)")
        }
        
        // Handle special char saving
        if !isCharKeyCode {
            specialChar.removeAll()
            history.clear()
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
        
        // Handle session management
        // For special characters (charKeyCode), preserve macroKey to allow building macros
        if hookState.code == UInt8(vDoNothing) {
            if isCharKeyCode {
                // Save and restore macroKey around startNewSession
                let savedMacroKey = hookState.macroKey
                startNewSession()
                hookState.macroKey = savedMacroKey
            } else {
                // For non-char word breaks, clear macroKey
                startNewSession()
            }
            vCheckSpelling = useSpellCheckingBefore ? 1 : 0
            willTempOffEngine = false
        } else if hookState.code == UInt8(vReplaceMacro) || hasHandleQuickConsonant {
            buffer.clear()
        }
        
        // IMPORTANT: Reset cursorMovedSinceReset after word break
        // This allows backspace to restore words from history even if user clicked before typing
        // The user has now typed a complete word (saved to history), so backspace should work
        // Same logic as processWordBreak() at the end
        cursorMovedSinceReset = false
        
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
    
    
    // MARK: - Delete Handling

    /// Handle delete/backspace key
    private func handleDelete() {
        let currentWord = !buffer.isEmpty ? getCurrentWord() : "(empty)"
        logCallback?("handleDelete: count=\(buffer.count), spaceCount=\(spaceCount), specialChar=\(specialChar.count), word='\(currentWord)'")

        hookState.code = UInt8(vDoNothing)
        hookState.extCode = 2

        if !specialChar.isEmpty {
            specialChar.removeLast()
            logCallback?("  → Removed special char, remaining=\(specialChar.count)")
            if specialChar.isEmpty {
                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    logCallback?("  → SKIP restore: cursor/focus changed, clearing history")
                    clearWithoutRestore()
                } else {
                    restoreLastTypingState()
                }
            }
        } else if spaceCount > 0 {
            spaceCount -= 1
            logCallback?("  → Removed space, remaining=\(spaceCount)")
            if spaceCount == 0 {
                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    logCallback?("  → SKIP restore: cursor/focus changed, clearing history")
                    clearWithoutRestore()
                } else {
                    restoreLastTypingState()
                }
            }
        } else {
            if !buffer.isEmpty {
                buffer.removeLast()
                logCallback?("  → Removed char, count=\(buffer.count)")

                // CRITICAL FIX: Reset tempDisableKey when user backspaces
                // This fixes bug where Vietnamese processing is skipped after:
                // 1. User types mark key twice to undo (e.g., "nhầm" + "f" → "nhâmf")
                //    → tempDisableKey = true is set during undo
                // 2. User backspaces to remove the raw key (e.g., "nhâmf" → "nhâm")
                // 3. User types mark key again (e.g., "f")
                //    → Without this fix, tempDisableKey is still true
                //    → Vietnamese processing is skipped, resulting in "nhâmf" instead of "nhầm"
                tempDisableKey = false
                logCallback?("  → Reset tempDisableKey=false (allow Vietnamese processing after backspace)")

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

            if buffer.isEmpty {
                logCallback?("  → Buffer empty, checking restore conditions...")
                startNewSession()
                specialChar.removeAll()

                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    logCallback?("  → SKIP restore: cursor/focus changed, clearing history")
                    history.clear()
                    bufferDesyncDetected = true
                } else {
                    // Normal backspace - trust history without AX verify
                    // REASON: AX query has race condition - it may return stale data
                    // because we process backspace event BEFORE OS updates the screen.
                    // When user is backspacing continuously without focus/cursor change,
                    // history is reliable and we should restore directly.
                    logCallback?("  → Normal backspace: restoring from history")
                    restoreLastTypingState()
                }
            } else {
                checkGrammar(deltaBackSpace: 1)
            }
        }
    }

    /// Clear session without restoring from history
    /// Used when desync is detected to prevent incorrect text insertion
    private func clearWithoutRestore() {
        startNewSession()
        history.clear()
        specialChar.removeAll()
        spaceCount = 0
        // Set desync flag to disable spellcheck/restore until new session
        bufferDesyncDetected = true
        logCallback?("clearWithoutRestore: Session cleared due to desync, bufferDesyncDetected=true")
    }
    

    // MARK: - Normal Key Handling
    
    private func handleNormalKey(keyCode: UInt16, character: Character, isCaps: Bool) {

        if willTempOffEngine {
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            return
        }

        // Temp off engine via toolbar - just insert key without Vietnamese processing
        if vTempOffEngine == 1 {
            hookState.code = UInt8(vDoNothing)
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 3
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }

        if spaceCount > 0 {
            // Save macroKey before reset - it may contain special chars like "!" for macro matching
            let savedMacroKey = hookState.macroKey
            
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 0
            startNewSession()
            saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
            spaceCount = 0
            
            // Restore macroKey if it had content (allows macros like "!bb" to work)
            if !savedMacroKey.isEmpty {
                hookState.macroKey = savedMacroKey
            }
        } else if !specialChar.isEmpty {
            saveSpecialChar()
        }

        // NOTE: Removed unconditional insertState() call here.
        // insertState was adding EVERY keystroke as a modifier to the last entry,
        // causing getRawInputString() to return duplicate keystrokes (e.g., "ly" → "lyy").
        // This led to false English pattern detection (e.g., "ltyyyyys" instead of "lys")
        // and prevented Vietnamese typing like "lý".
        // 
        // If modifier tracking is needed for Telex sequences (aa→â, dd→đ, etc.),
        // it should be added in the specific handlers (insertAOE, insertD, handleMarkKey)
        // ONLY when a key actually modifies an existing entry.
        
        let isSpecial = isSpecialKey(keyCode: keyCode)
        
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
            }
        } else {
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            handleMainKey(keyCode: keyCode, isCaps: isCaps)
        }
        
        // Always check for vowel auto-fix (ưo → ươ) regardless of vFreeMark
        // This is important for correct Vietnamese typing
        // Skip if instant restore has occurred (extCode == 5) - word is being discarded
        if !isKeyD(keyCode: keyCode, inputType: vInputType) && hookState.extCode != 5 {
            let deltaBS = hookState.code == UInt8(vDoNothing) ? -1 : 0
            checkVowelAutoFix(deltaBackSpace: deltaBS)
        }
        
        // Check mark position - ALWAYS check when typing end consonant or adding vowel to marked word
        // Vietnamese spelling rule: with end consonant, tone must be on the vowel closest to it
        // Example: "hoạt" - tone on 'a', not 'o'; "hiện" - tone on 'ê', not 'i'
        // Additional rule: when adding vowels after a mark, position may need adjustment
        // Example: "ngò" + "a" → "ngoà" (mark moves from 'o' to 'a')
        // This rule applies regardless of vFreeMark setting
        // Skip if instant restore has occurred (extCode == 5) - word is being discarded
        if !isKeyD(keyCode: keyCode, inputType: vInputType) && hookState.extCode != 5 {
            // Check if this key is an end consonant
            let isEndConsonant = vietnameseData.isConsonant(keyCode) && index > 1
            
            // Check if this key is a vowel and the word already has a mark
            var isVowelWithExistingMark = false
            if !vietnameseData.isConsonant(keyCode) && index > 1 {
                // Check if any existing vowel has a mark
                for i in 0..<Int(index) - 1 {
                    if (typingWord[i] & VNEngine.MARK_MASK) != 0 {
                        isVowelWithExistingMark = true
                        break
                    }
                }
            }
            
            // Always check mark position if:
            // 1. vFreeMark is disabled, OR
            // 2. This is an end consonant (Vietnamese spelling rule), OR
            // 3. This is a vowel added to a word with existing mark (mark position may need adjustment)
            if vFreeMark == 0 || isEndConsonant || isVowelWithExistingMark {
                // IMPORTANT: Determine deltaBackSpace correctly
                // If checkVowelAutoFix has run (extCode=4), the last character hasn't been
                // sent to screen yet, so we need deltaBackSpace=-1 even if hookState.code != vDoNothing
                let deltaBS: Int
                if hookState.code == UInt8(vDoNothing) {
                    deltaBS = -1
                } else if hookState.extCode == 4 {
                    // checkVowelAutoFix has run, last char not on screen yet
                    deltaBS = -1
                } else {
                    deltaBS = 0
                }
                checkMarkPosition(deltaBackSpace: deltaBS)
            }
        }
        
        // Note: extCode == 5 means instant restore - key is already included in restored keystrokes
        // so we should NOT insert it again. Only insert key for normal restore (undo mark).
        if hookState.code == UInt8(vRestore) && hookState.extCode != 5 {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            // NOTE: We do NOT remove modifier here because raw keystrokes should reflect
            // what user actually typed. E.g., "ass" should have raw keystrokes ["a", "s", "s"]
            // The modifier "s" on entry "á" represents the first "s", and the new entry "s"
            // from insertKey represents the second "s" that triggered restore.
        }
        
        // Insert or replace key for macro
        if vUseMacro == 1 {
            let macroKeyBefore = hookState.macroKey
            if hookState.code == UInt8(vDoNothing) {
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            } else if hookState.code == UInt8(vWillProcess) || hookState.code == UInt8(vRestore) {
                for _ in 0..<hookState.backspaceCount {
                    if !hookState.macroKey.isEmpty {
                        hookState.macroKey.removeLast()
                    }
                }
                let startIdx = Int(index) - hookState.backspaceCount
                for i in startIdx..<(hookState.newCharCount + startIdx) {
                    if i >= 0 && i < Int(index) {
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
            let effectiveCount = buffer.count - (hookState.code == UInt8(vWillProcess) ? hookState.backspaceCount : 0)
            if effectiveCount > 0 {
                buffer.removeLast()
                saveWord()
            }
            buffer.clear()
            tempDisableKey = false
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
            // FREE MARK CHECK: When vFreeMark is OFF, only allow đ if last char is 'd'
            // Example: "d + d" → "đ" OK, "d + i + d" → NOT OK (must type "d + d + i")
            if vFreeMark == 0 && index > 0 {
                let lastChar = chr(Int(index) - 1)
                if lastChar != VietnameseData.KEY_D {
                    logCallback?("handleMainKey: Free Mark OFF - D key rejected, last char is not 'd'")
                    insertKey(keyCode: keyCode, isCaps: isCaps)
                    return
                }
            }
            
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
        
        // ============================================
        // EARLY ENGLISH DETECTION: Skip Vietnamese processing for words that
        // are definitely NOT Vietnamese
        // ============================================
        // Uses comprehensive detection that checks:
        // 1. Start pattern - impossible prefixes like "str", "bl", "gr"
        // 2. End pattern - Vietnamese NEVER ends with 's', 'b', 'd', etc.
        // 3. Middle pattern - impossible consonant clusters like "cr", "br"
        //
        // This excludes valid Vietnamese input sequences like:
        // - "dd" → đ, "cc" → ch, "gg" → gi (Telex/Quick Telex)
        // - "d9" → đ (VNI)
        //
        // Examples caught:
        // - "street" (starts with "str")
        // - "micros" (ends with "s")
        // - "micro" (has "cr" in middle)
        // NOTE: Use getRawInputStringForEnglishDetection() which EXCLUDES overflow entries
        // to avoid false positives after restoreLastTypingState()
        let rawInput = getRawInputStringForEnglishDetection()
        let allowZFWJ = vAllowConsonantZFWJ == 1
        if rawInput.isDefinitelyNotVietnameseForRawInput(inputType: vInputType, allowZFWJ: allowZFWJ) {
            // ENHANCED LOGGING: Log full context when English pattern is detected
            // This helps debug buffer desync issues
            logCallback?("⚠️ ENGLISH PATTERN DETECTED:")
            logCallback?("   rawInput='\(rawInput)', bufferCount=\(buffer.count), historyCount=\(history.count)")
            logCallback?("   tempDisableKey=\(tempDisableKey), cursorMovedSinceReset=\(cursorMovedSinceReset)")
            let charDisplay = Self.keyCodeToChar(keyCode).map { String($0) } ?? "?"
            logCallback?("   Adding keyCode=\(keyCode) '\(charDisplay)'")
            
            insertKey(keyCode: keyCode, isCaps: isCaps)
            
            // Set tempDisableKey so subsequent keys don't get processed as Vietnamese
            // until word break occurs
            tempDisableKey = true
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
        
        let charDisplay = Self.keyCodeToChar(keyCode).map { " '\($0)'" } ?? ""
        logCallback?("handleMarkKey: keyCode=\(keyCode)\(charDisplay), index=\(index), buffer=\(getCurrentWord()), vFreeMark=\(vFreeMark)")
        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q {
            logCallback?("  → Skipping: qu case")
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // FREE MARK CHECK: When vFreeMark is OFF (0), only allow placing tone marks
        // if the last character is a vowel (mark must be typed immediately after vowel)
        // Example: "a + s" → OK, "a + n + h + s" → NOT OK (must type "a + s + n + h")
        if vFreeMark == 0 && index > 0 {
            let lastChar = chr(Int(index) - 1)
            let isLastCharVowel = vietnameseData.isVowelKey(lastChar)
            logCallback?("  → Free Mark OFF: lastChar=\(lastChar), isVowel=\(isLastCharVowel)")
            
            if !isLastCharVowel {
                // Last character is not a vowel, cannot place mark here in non-free-mark mode
                logCallback?("  → Rejected: Free Mark is OFF and last char is not a vowel")
                insertKey(keyCode: keyCode, isCaps: isCaps)
                return
            }
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
                    
                    insertMarkInternal(markMask: markMask, canModifyFlag: true, deltaBackSpace: 0)
                    
                    // Track modifier keystroke for restore functionality
                    // Only add if not a restore operation (duplicate mark key)
                    // Add to the ACTUAL modified vowel (vowelWillSetMark), not the last entry
                    if hookState.code != UInt8(vRestore) {
                        insertStateAt(index: vowelWillSetMark, keyCode: keyCode, isCaps: isCaps)
                    }
                    break
                }
            }
            
            if isCorrect {
                break
            }
        }
        
        if !isChanged {
            logCallback?("  → No pattern matched, checking for VNI fallback...")
            
            // VNI fallback: For keys 1-5, if pattern didn't match but we have vowels,
            // try to apply tone anyway. Note: This only runs when Free Mark is ON
            // or when last char is a vowel (we return early above otherwise).
            if vInputType == 1 && (keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4 ||
                                   keyCode == VietnameseData.KEY_5) {
                findAndCalculateVowel()
                
                if vowelCount > 0 {
                    logCallback?("  → VNI fallback: found vowels, applying tone via insertMarkInternal()")
                    
                    // Determine which mark to insert
                    var markMask: UInt32 = 0
                    switch keyCode {
                    case VietnameseData.KEY_1: markMask = VNEngine.MARK1_MASK  // Sắc
                    case VietnameseData.KEY_2: markMask = VNEngine.MARK2_MASK  // Huyền
                    case VietnameseData.KEY_3: markMask = VNEngine.MARK3_MASK  // Hỏi
                    case VietnameseData.KEY_4: markMask = VNEngine.MARK4_MASK  // Ngã
                    case VietnameseData.KEY_5: markMask = VNEngine.MARK5_MASK  // Nặng
                    default: break
                    }
                    
                    if markMask != 0 {
                        insertMarkInternal(markMask: markMask, canModifyFlag: true, deltaBackSpace: 0)
                        
                        // Track modifier keystroke for restore functionality
                        // Add to the ACTUAL modified vowel (vowelWillSetMark), not the last entry
                        if hookState.code != UInt8(vRestore) {
                            insertStateAt(index: vowelWillSetMark, keyCode: keyCode, isCaps: isCaps)
                        }
                        return
                    }
                }
            }
            
            logCallback?("  → No fallback, inserting key as-is")
            insertKey(keyCode: keyCode, isCaps: isCaps)
        }
    }
    
    private func handleVowelKey(keyCode: UInt16, isCaps: Bool) {
        let charDisplay = Self.keyCodeToChar(keyCode).map { " '\($0)'" } ?? ""
        logCallback?("handleVowelKey: keyCode=\(keyCode)\(charDisplay), index=\(index), tempDisableKey=\(tempDisableKey), buffer=\(getCurrentWord()), vFreeMark=\(vFreeMark)")
        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // FREE MARK CHECK: When vFreeMark is OFF, only allow vowel modifiers
        // if the last character is the corresponding vowel
        // Example for Telex: "a + a" → "â" OK, "a + n + a" → NOT OK (must type "a + a + n")
        // Example for VNI: "a + 6" → "â" OK, "a + n + 6" → NOT OK
        if vFreeMark == 0 && index > 0 {
            let lastChar = chr(Int(index) - 1)
            var expectedVowels: [UInt16] = []
            var needsExtraVowelCheck = false  // For W key, need additional check
            
            if vInputType != 1 { // Telex
                switch keyCode {
                case VietnameseData.KEY_A:
                    expectedVowels = [VietnameseData.KEY_A]  // aa → â
                case VietnameseData.KEY_O:
                    expectedVowels = [VietnameseData.KEY_O]  // oo → ô
                case VietnameseData.KEY_E:
                    expectedVowels = [VietnameseData.KEY_E]  // ee → ê
                case VietnameseData.KEY_W:
                    expectedVowels = [VietnameseData.KEY_U, VietnameseData.KEY_O, VietnameseData.KEY_A]  // w → ư, ơ, ă
                    needsExtraVowelCheck = true
                default:
                    break
                }
            } else { // VNI
                switch keyCode {
                case VietnameseData.KEY_6:
                    expectedVowels = [VietnameseData.KEY_A, VietnameseData.KEY_E, VietnameseData.KEY_O]  // 6 → ^
                    needsExtraVowelCheck = true
                case VietnameseData.KEY_7:
                    expectedVowels = [VietnameseData.KEY_U, VietnameseData.KEY_O]  // 7 → móc (ư, ơ)
                    needsExtraVowelCheck = true
                case VietnameseData.KEY_8:
                    expectedVowels = [VietnameseData.KEY_A]  // 8 → trăng (ă)
                    needsExtraVowelCheck = true
                default:
                    break
                }
            }
            
            // If this key adds a vowel modifier, check if last char is expected
            if !expectedVowels.isEmpty && !expectedVowels.contains(lastChar) {
                logCallback?("  → Free Mark OFF: lastChar=\(lastChar), expectedVowels=\(expectedVowels) - REJECTED")
                insertKey(keyCode: keyCode, isCaps: isCaps)
                return
            }
            
            // Additional check for W key (and VNI 6/7/8): reject only if insertW() would modify
            // an earlier vowel that is NOT the lastChar (true "free mark" behavior)
            //
            // insertW() logic for 2 vowels (from insertW function):
            // - U + O → both get TONEW_MASK (ươ) - OK, standard pattern
            // - U + A, U + I, U + U, O + I → only first vowel (v1) gets modified - REJECT (free mark)
            // - I + O, O + A → only second vowel (v2) gets modified - OK, modifies lastChar
            // - Other combinations → do nothing
            //
            // So we only reject when: there are 2 unmodified vowels AND insertW would modify v1 only
            // Patterns that modify v1 only: U+A, U+I, U+U, O+I
            if needsExtraVowelCheck && expectedVowels.contains(lastChar) {
                // Find unmodified vowels and their keys
                var unmodifiedVowels: [(index: Int, key: UInt16)] = []
                for i in 0..<Int(index) {
                    if vietnameseData.isVowelKey(chr(i)) {
                        let isAlreadyModified = (typingWord[i] & VNEngine.TONEW_MASK) != 0 ||
                                                (typingWord[i] & VNEngine.TONE_MASK) != 0
                        if !isAlreadyModified {
                            unmodifiedVowels.append((index: i, key: chr(i)))
                        }
                    }
                }

                // insertW() uses vowelStartIndex and vowelStartIndex+1 (first 2 vowels)
                // So we check if the first 2 unmodified vowels would trigger "free mark" behavior
                if unmodifiedVowels.count >= 2 {
                    let v1Key = unmodifiedVowels[0].key
                    let v2Key = unmodifiedVowels[1].key

                    // These patterns would modify v1 only (the earlier vowel) - this is "free mark" behavior
                    // U+A → ư+a, U+I → ư+i, U+U → ư+u, O+I → ơ+i
                    let wouldModifyV1Only =
                        (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_A) ||
                        (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_I) ||
                        (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_U) ||
                        (v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_I)

                    if wouldModifyV1Only {
                        logCallback?("  → Free Mark OFF: W key would modify earlier vowel (v1=\(v1Key), v2=\(v2Key)) - REJECTED")
                        insertKey(keyCode: keyCode, isCaps: isCaps)
                        return
                    }

                    logCallback?("  → Free Mark OFF: W key with \(unmodifiedVowels.count) vowels (v1=\(v1Key), v2=\(v2Key)) - ALLOWED (modifies lastChar or both)")
                }
            }
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
                        // First, find the vowel range in the word (like Telex does)
                        findAndCalculateVowel()
                        
                        if keyCode == VietnameseData.KEY_7 {
                            // Key 7: horn (móc) - search for ANY 'o' or 'u' in the VOWEL group
                            // This matches Telex behavior where insertW() handles vowel combinations
                            // like "ua" → "ưa", "uo" → "ươ" intelligently
                            var hasValidVowel = false
                            if vowelCount > 0 {
                                for i in vowelStartIndex...vowelEndIndex {
                                    let key = chr(i)
                                    if key == VietnameseData.KEY_O || key == VietnameseData.KEY_U {
                                        hasValidVowel = true
                                        break
                                    }
                                }
                            }
                            shouldProcess = hasValidVowel
                        } else if keyCode == VietnameseData.KEY_8 {
                            // Key 8: breve (trăng) only for 'a' → 'ă'
                            // Search for 'a' in the VOWEL group
                            var hasValidVowel = false
                            if vowelCount > 0 {
                                for i in vowelStartIndex...vowelEndIndex {
                                    let key = chr(i)
                                    if key == VietnameseData.KEY_A {
                                        hasValidVowel = true
                                        break
                                    }
                                }
                            }
                            shouldProcess = hasValidVowel
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
            
            // VNI fallback: For key 7/8, if pattern didn't match but we have valid vowels,
            // try to apply horn/breve anyway (free-mark style like Telex)
            if vInputType == 1 && (keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8) {
                findAndCalculateVowel()
                var hasValidVowel = false
                
                if vowelCount > 0 {
                    for i in vowelStartIndex...vowelEndIndex {
                        let key = chr(i)
                        if keyCode == VietnameseData.KEY_7 {
                            // Key 7: horn - need 'o' or 'u'
                            if key == VietnameseData.KEY_O || key == VietnameseData.KEY_U {
                                hasValidVowel = true
                                break
                            }
                        } else if keyCode == VietnameseData.KEY_8 {
                            // Key 8: breve - need 'a'
                            if key == VietnameseData.KEY_A {
                                hasValidVowel = true
                                break
                            }
                        }
                    }
                }
                
                if hasValidVowel {
                    logCallback?("handleVowelKey: VNI fallback - applying horn/breve via insertW()")
                    insertW(keyCode: VietnameseData.KEY_W, isCaps: isCaps)
                    return
                }
            }
            
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
    
    // MARK: - Public Key Classification
    
    /// Check if a character is a Vietnamese special key that needs engine processing
    /// This centralizes the logic for determining which non-letter characters should be processed
    /// - Parameters:
    ///   - character: The character to check
    ///   - inputMethod: The current input method (Telex, VNI, Simple Telex 1, Simple Telex 2)
    /// - Returns: true if this character should be processed by Vietnamese engine
    ///
    /// Special keys by input method:
    /// - Telex: w, a, e, o, s, f, r, x, j, z, d, [, ]
    /// - VNI: 0-9
    /// - Simple Telex 1: w, a, e, o, s, f, r, x, j, z, d (NO [ ])
    /// - Simple Telex 2: w, a, e, o, s, f, r, x, j, z, d (NO [ ])
    static func isVietnameseSpecialKey(character: Character, inputMethod: InputMethod) -> Bool {
        // Letters are always processed (Vietnamese engine handles them)
        if character.isLetter {
            return true
        }
        
        // Numbers: only in VNI mode (0-9 are tone marks)
        if character.isNumber {
            return inputMethod == .vni
        }
        
        // Bracket keys: only in Telex mode ([ → ơ, ] → ư)
        if character == "[" || character == "]" {
            return inputMethod == .telex
        }
        
        // Other characters are not Vietnamese special keys
        return false
    }
    
    /// Check if a character is a word break in the context of Vietnamese typing
    /// Word breaks reset the engine buffer
    /// - Parameters:
    ///   - character: The character to check
    ///   - inputMethod: The current input method
    /// - Returns: true if this character is a word break
    ///
    /// Note: In Telex mode, [ and ] are NOT word breaks (they produce ơ and ư)
    static func isWordBreak(character: Character, inputMethod: InputMethod) -> Bool {
        // Whitespace and common punctuation
        let baseWordBreaks: Set<Character> = [
            " ", ",", ".", "!", "?", ";", ":",
            "\n", "\r", "\t",
            "(", ")", "{", "}", "<", ">",
            "/", "\\", "|",
            "@", "#", "$", "%", "^", "&", "*",
            "~", "`", "-", "_", "=", "+",
            "'", "\""
        ]
        
        if baseWordBreaks.contains(character) {
            return true
        }
        
        // Bracket keys: word break in all modes EXCEPT Telex
        if character == "[" || character == "]" {
            return inputMethod != .telex
        }
        
        return false
    }
    
    // MARK: - Insert Functions

    /// Insert a new character into the buffer
    func insertKey(keyCode: UInt16, isCaps: Bool, isCheckSpelling: Bool = true) {
        let charDisplay = Self.keyCodeToChar(keyCode).map { " '\($0)'" } ?? ""
        logCallback?("insertKey: keyCode=\(keyCode)\(charDisplay), isCaps=\(isCaps), count=\(buffer.count)")

        buffer.append(keyCode: keyCode, isCaps: isCaps)
        
        // Record keystroke in actual typing order (for restore at word break)
        buffer.recordKeystroke(RawKeystroke(keyCode: keyCode, isCaps: isCaps))

        logCallback?("  → After insert: count=\(buffer.count)")

        if vCheckSpelling == 1 && isCheckSpelling {
            checkSpelling()
        }

        // Allow d after consonant
        if keyCode == VietnameseData.KEY_D && buffer.count >= 2 {
            let prevKey = buffer.keyCode(at: buffer.count - 2)
            if vietnameseData.isConsonant(prevKey) {
                tempDisableKey = false
            }
        }
    }

    /// Set processed data at a specific index
    func setKeyData(at index: Int, keyCode: UInt16, isCaps: Bool) {
        guard index >= 0 && index < buffer.count else { return }
        buffer[index].processedData = UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0)
    }

    /// Record a raw keystroke as modifier (for Telex sequences like aa→â)
    /// Adds to the LAST entry in buffer
    /// Also records to keystrokeSequence for correct restore order
    func insertState(keyCode: UInt16, isCaps: Bool) {
        let keystroke = RawKeystroke(keyCode: keyCode, isCaps: isCaps)
        buffer.addModifierToLast(keystroke)
        buffer.recordKeystroke(keystroke)  // Record in actual typing order
    }
    
    /// Record a raw keystroke as modifier at a specific buffer index
    /// Use this when the modified entry is NOT the last one (e.g., mark on first vowel of "ưa")
    /// Also records to keystrokeSequence for correct restore order
    func insertStateAt(index: Int, keyCode: UInt16, isCaps: Bool) {
        let keystroke = RawKeystroke(keyCode: keyCode, isCaps: isCaps)
        buffer.addModifier(at: index, keystroke: keystroke)
        buffer.recordKeystroke(keystroke)  // Record in actual typing order
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
                    
                    // Track modifier keystroke for restore functionality (dd→đ)
                    // Add to the ACTUAL modified 'D' (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
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
        logCallback?("  vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex)")

        // Check if vowel sequence is valid before adding circumflex
        // Invalid sequences like "ee", "eee", "aa", "aaa" should NOT get circumflex added
        // This prevents "nhée" + "e" from becoming "nhéê" (should stay as "nhéee")
        if vowelCount >= 2 {
            let vowelSequence = getCurrentVowelSequence()
            if !VowelSequenceValidator.isValid(vowelSequence) {
                logCallback?("  → Invalid vowel sequence \(vowelSequence), inserting key normally instead of adding circumflex")
                insertKey(keyCode: keyCode, isCaps: isCaps)
                return
            }
        }

        // Track which vowels had TONEW_MASK removed (e.g., ư → u, ơ → o)
        // This is needed to update the output for ALL affected vowels, not just the one getting ^
        // Example: "cươi" + "o" → need to update both ư→u AND ơ→ô
        var earliestAffectedIndex = Int(index)  // Start with no affected vowels
        
        // Remove W tone from all vowels and track the earliest affected vowel
        for i in vowelStartIndex...vowelEndIndex {
            if (typingWord[i] & VNEngine.TONEW_MASK) != 0 {
                typingWord[i] &= ~VNEngine.TONEW_MASK
                if i < earliestAffectedIndex {
                    earliestAffectedIndex = i
                }
                logCallback?("  Removed TONEW_MASK from index \(i), key=\(chr(i))")
            }
        }
        
        hookState.code = UInt8(vWillProcess)

        hookState.backspaceCount = 0
        
        // Check if we need to move mark from previous vowel to this one
        // This handles case: h-i-e-j-e → hịe → hiệ (mark moves from i to ê)
        var shouldMoveMark = false
        var markToMove: UInt32 = 0
        var markSourceIndex = -1
        
        // Track the index where we found the target vowel (a, o, or e)
        var targetVowelIndex = -1
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookState.backspaceCount += 1
            logCallback?("  Loop i=\(i), chr=\(chr(i)), looking for=\(keyCode)")
            if chr(i) == keyCode {
                targetVowelIndex = i
                
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
                        hookState.backspaceCount = Int(index) - markSourceIndex
                    }
                    
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    
                    // Track modifier keystroke for restore functionality (aa→â, oo→ô, ee→ê)
                    // Add to the ACTUAL modified vowel (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
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
            hookState.backspaceCount = Int(index) - startIdx
            for i in startIdx..<Int(index) {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        
        // FIX: If TONEW_MASK was removed from vowels BEFORE the target vowel,
        // we need to extend backspaceCount and regenerate charData for those vowels too.
        // Example: "cươi" + "o" → target is ơ (index 2), but ư (index 1) also needs update
        // Without this fix, we would output "cưôi" instead of "cuôi"
        if earliestAffectedIndex < targetVowelIndex && targetVowelIndex >= 0 {
            logCallback?("  FIX: Extending output to include vowel at index \(earliestAffectedIndex) (TONEW removed)")
            let startIdx = earliestAffectedIndex
            hookState.backspaceCount = Int(index) - startIdx
            hookState.newCharCount = hookState.backspaceCount
            for i in startIdx..<Int(index) {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            return  // Early return since we've already set newCharCount
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
            hookState.backspaceCount = Int(index) - vowelStartIndex
            hookState.newCharCount = hookState.backspaceCount
            
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            
            if (v1HasToneW && v2HasToneW) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_I) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_A) ||
               (v2HasToneW && v1Key == VietnameseData.KEY_I) ||  // iơ -> io + w
               (v2HasToneW && v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_A) ||  // oă -> oa + w
               (v2HasToneW && v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O) {  // uơ -> uo + w (for "thuơ" case)
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
                
                // Track modifier keystroke for restore functionality (w→ư/ơ for multi-vowel)
                // Add to the FIRST modified vowel (vowelStartIndex), not the last entry
                if hookState.code != UInt8(vDoNothing) {
                    insertStateAt(index: vowelStartIndex, keyCode: keyCode, isCaps: isCaps)
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
                            // When undoing standalone "ư" → "w", remove the modifier from the ACTUAL entry (index i)
                            isRestoredW = true
                            buffer.removeLastModifier(at: i)
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
                    
                    // Track modifier keystroke for restore functionality (w→ư/ơ/ă for single vowel)
                    // Add to the ACTUAL modified vowel (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
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

    /// Convert typingWord data at given index to VNVowel
    /// Returns nil if the character is not a vowel or cannot be converted
    private func convertToVNVowel(at index: Int) -> VNVowel? {
        let data = typingWord[index]
        let keyCode = UInt16(data & VNEngine.CHAR_MASK)
        let hasTone = (data & VNEngine.TONE_MASK) != 0      // circumflex (^)
        let hasToneW = (data & VNEngine.TONEW_MASK) != 0    // horn (ơ, ư) or breve (ă)

        switch keyCode {
        case VietnameseData.KEY_A:
            if hasTone { return .aCircumflex }      // â
            if hasToneW { return .aBreve }          // ă
            return .a
        case VietnameseData.KEY_E:
            if hasTone { return .eCircumflex }      // ê
            return .e
        case VietnameseData.KEY_I:
            return .i
        case VietnameseData.KEY_O:
            if hasTone { return .oCircumflex }      // ô
            if hasToneW { return .oHorn }           // ơ
            return .o
        case VietnameseData.KEY_U:
            if hasToneW { return .uHorn }           // ư
            return .u
        case VietnameseData.KEY_Y:
            return .y
        default:
            return nil
        }
    }

    /// Get vowel sequence from current vowelStartIndex to vowelEndIndex
    /// Returns array of VNVowel or empty array if conversion fails
    private func getCurrentVowelSequence() -> [VNVowel] {
        guard vowelCount > 0, vowelStartIndex <= vowelEndIndex else {
            return []
        }

        var vowels: [VNVowel] = []
        for i in vowelStartIndex...vowelEndIndex {
            if let vowel = convertToVNVowel(at: i) {
                vowels.append(vowel)
            }
        }
        return vowels
    }

    // MARK: - Spelling Check
    
    private var spellingOK = false
    private var spellingVowelOK = false
    private var spellingEndIndex: UInt8 = 0
    
    /// Check spelling using phonetic rules (like OpenKey's checkSpelling)
    /// This verifies the word structure matches valid Vietnamese patterns:
    /// 1. First consonant must match consonantTable
    /// 2. After vowel, consonant must match endConsonantTable
    ///
    /// If phonetic check fails, tempDisableKey = true, preventing diacritics
    /// This is how OpenKey handles "micros" - "cr" is not in endConsonantTable
    func checkSpelling(forceCheckVowel: Bool = false) {
        // Defensive check: Respect vCheckSpelling setting
        guard vCheckSpelling == 1 else {
            // When spell check is disabled, don't modify spelling state
            return
        }
        
        // Temporary off spelling via toolbar - skip spell check
        if vTempOffSpelling == 1 {
            tempDisableKey = false
            return
        }
        
        logCallback?("checkSpelling: index=\(index), word=\(getCurrentWord()), forceCheckVowel=\(forceCheckVowel)")
        
        // Reset spelling state
        spellingOK = false
        spellingVowelOK = true
        spellingEndIndex = index
        
        // Skip if empty word
        guard index > 0 else {
            tempDisableKey = false
            return
        }
        
        // Handle ] key at end (standalone key)
        if index > 0 && chr(Int(index) - 1) == VietnameseData.KEY_RIGHT_BRACKET {
            spellingEndIndex = index - 1
        }
        
        guard spellingEndIndex > 0 else {
            spellingOK = true
            tempDisableKey = false
            return
        }
        
        var j = 0
        
        // ============================================
        // Check first consonant (with consonantTable)
        // ============================================
        if vietnameseData.isConsonant(chr(0)) {
            var foundMatch = false
            
            for consonantPattern in vietnameseData.consonantTable {
                // Check if word starts with this consonant pattern
                if Int(spellingEndIndex) < consonantPattern.count {
                    continue  // Word too short for this pattern
                }
                
                var matches = true
                for (idx, patternKey) in consonantPattern.enumerated() {
                    let actualKey = chr(idx)
                    // Handle CONSONANT_ALLOW_MASK and END_CONSONANT_MASK
                    // When vAllowConsonantZFWJ == 1, REMOVE the mask to allow matching z, f, w, j
                    // When vQuickStartConsonant == 1, REMOVE the END_CONSONANT_MASK to allow quick consonant
                    let patternKeyMasked = patternKey & ~(
                        (vAllowConsonantZFWJ == 1 ? VietnameseData.CONSONANT_ALLOW_MASK : 0) |
                        (vQuickStartConsonant == 1 ? VietnameseData.END_CONSONANT_MASK : 0)
                    )
                    
                    if Int(spellingEndIndex) > idx && patternKeyMasked != actualKey {
                        matches = false
                        break
                    }
                    j = idx + 1
                }
                
                if matches {
                    foundMatch = true
                    break
                }
            }
            
            if !foundMatch && index > 0 {
                // If first consonant doesn't match any pattern, mark as invalid
                tempDisableKey = true
                return
            }
        }
        
        // If first char is the whole consonant part (like "d")
        if j == Int(spellingEndIndex) {
            spellingOK = true
        }
        
        // ============================================
        // Check vowel position
        // ============================================
        var k = j
        var vowelStartIdx = k
        
        // Special case: "que't" - u after q is not counted as vowel
        if chr(vowelStartIdx) == VietnameseData.KEY_U &&
           k > 0 && k < Int(spellingEndIndex) - 1 &&
           chr(vowelStartIdx - 1) == VietnameseData.KEY_Q {
            k += 1
            j = k
            vowelStartIdx = k
        }
        // Special case: "gìn" - i after g at start
        else if index >= 2 &&
                chr(0) == VietnameseData.KEY_G &&
                chr(1) == VietnameseData.KEY_I &&
                index >= 3 && vietnameseData.isConsonant(chr(2)) {
            vowelStartIdx = 1
            k = 1
            j = 1
        }
        
        // Count vowels (up to 3)
        for _ in 0..<3 {
            if k < Int(spellingEndIndex) && !vietnameseData.isConsonant(chr(k)) {
                k += 1
            }
        }
        let vowelEndIdx = k
        
        // ============================================
        // Check end consonant (with endConsonantTable)
        // ============================================
        if k > j {
            // Has vowel, now check end consonant
            spellingVowelOK = false
            
            // Check vowel combination if forceCheckVowel
            if k - j > 1 && forceCheckVowel {
                // Complex vowel check (similar to OpenKey's vowel combine check)
                // For now, we assume vowel is OK
                spellingVowelOK = true
            } else if !vietnameseData.isConsonant(chr(j)) {
                spellingVowelOK = true
            }
            
            // Continue check last consonant
            for endPattern in vietnameseData.endConsonantTable {
                var matches = true
                
                for (patternIdx, patternKey) in endPattern.enumerated() {
                    let patternKeyMasked = patternKey & ~(vQuickEndConsonant == 1 ? VietnameseData.END_CONSONANT_MASK : 0)
                    
                    if Int(spellingEndIndex) > k + patternIdx {
                        if patternKeyMasked != chr(k + patternIdx) {
                            matches = false
                            break
                        }
                    }
                }
                
                if !matches {
                    continue
                }
                
                // Check if pattern covers rest of word
                if k + endPattern.count >= Int(spellingEndIndex) {
                    spellingOK = true
                    break
                }
            }
            
            // If there are remaining characters after vowel that don't match any end consonant
            // This is the key check that catches "micros" - "cr" is not in endConsonantTable!
            if !spellingOK && k < Int(spellingEndIndex) {
                // Has characters after vowel that don't match end consonant patterns
                spellingOK = false
            }
            
            // Limit: end consonant "ch", "t" cannot use with "~", "`", "?"
            if spellingOK {
                if index >= 3 &&
                   chr(Int(index) - 1) == VietnameseData.KEY_H &&
                   chr(Int(index) - 2) == VietnameseData.KEY_C {
                    // Check if vowel before "ch" has invalid mark
                    let vowelData = typingWord[Int(index) - 3]
                    let hasMark1 = (vowelData & VNEngine.MARK1_MASK) != 0
                    let hasMark5 = (vowelData & VNEngine.MARK5_MASK) != 0
                    let hasAnyMark = (vowelData & VNEngine.MARK_MASK) != 0
                    if !hasMark1 && !hasMark5 && hasAnyMark {
                        spellingOK = false
                    }
                } else if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_T {
                    let vowelData = typingWord[Int(index) - 2]
                    let hasMark1 = (vowelData & VNEngine.MARK1_MASK) != 0
                    let hasMark5 = (vowelData & VNEngine.MARK5_MASK) != 0
                    let hasAnyMark = (vowelData & VNEngine.MARK_MASK) != 0
                    if !hasMark1 && !hasMark5 && hasAnyMark {
                        spellingOK = false
                    }
                }
            }
        } else {
            // No vowel yet, only consonant - OK
            spellingOK = true
        }
        
        // Final decision
        tempDisableKey = !(spellingOK && spellingVowelOK)
        logCallback?("checkSpelling result: spellingOK=\(spellingOK), spellingVowelOK=\(spellingVowelOK), tempDisableKey=\(tempDisableKey)")
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
            
            logCallback?("  → Before deltaBackSpace adjustment: backspaceCount=\(hookState.backspaceCount), deltaBackSpace=\(deltaBackSpace)")
            
            // IMPORTANT: deltaBackSpace handling
            // When deltaBackSpace = -1, it means the last character hasn't been sent to screen yet
            // In this case, we need to delete one less character from the screen
            // Example: Screen has "thuở" (4 chars), we want to send "ưởn" (3 chars)
            // - backspaceCount = 3 (for u, ở, n in buffer)
            // - But 'n' hasn't been sent yet, so screen only has "thuở"
            // - We need to delete "uở" (2 chars) from screen, not 3
            // - So: backspaceCount = 3 + (-1) = 2 ✓
            //
            // When deltaBackSpace = 0, the last character has been sent
            // - backspaceCount already correct, no adjustment needed
            if deltaBackSpace == -1 {
                // Last char not on screen yet, delete one less
                hookState.backspaceCount = hookState.backspaceCount + deltaBackSpace
            }
            // If deltaBackSpace = 0, don't adjust (last char already on screen)
            
            logCallback?("  → After deltaBackSpace adjustment: backspaceCount=\(hookState.backspaceCount), newCharCount=\(hookState.newCharCount)")
            
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

        // Check if vowel sequence is valid before attempting to move mark
        // Invalid sequences like "ee", "eee", "aa", "aaa" should NOT cause mark movement
        // This prevents the issue where typing "nheseee" incorrectly becomes "nheế"
        // instead of "nhéee" (mark should stay on first 'e')
        if vowelCount >= 2 {
            let vowelSequence = getCurrentVowelSequence()
            if !VowelSequenceValidator.isValid(vowelSequence) {
                logCallback?("  → Early return: invalid vowel sequence \(vowelSequence), not moving mark")
                return
            }
        }

        var isAdjusted = false
        
        // IMPORTANT: Save vowelStartIndex before calling insertMarkInternal
        // insertMarkInternal calls findAndCalculateVowel() internally which may
        // return different results (e.g., for "gi" case where forGrammar affects results)
        // We need the original vowelStartIndex for the final loop that sends charData
        let savedVowelStartIndex = vowelStartIndex
        
        // Check mark position
        if index >= 2 {
            // IMPORTANT: Save current hookState before calling insertMarkInternal
            // If mark position doesn't need adjustment (isAdjusted=false), we should
            // preserve the hookState calculated by checkVowelAutoFix
            let savedBackspaceCount = hookState.backspaceCount
            let savedNewCharCount = hookState.newCharCount
            let savedCode = hookState.code
            
            for i in vowelStartIndex...vowelEndIndex {
                logCallback?("  → Checking typingWord[\(i)]=\(String(format: "0x%X", typingWord[i])), hasMark=\((typingWord[i] & VNEngine.MARK_MASK) != 0)")
                if typingWord[i] & VNEngine.MARK_MASK != 0 {
                    let mark = typingWord[i] & VNEngine.MARK_MASK
                    logCallback?("  → Found mark at index \(i), mark=\(String(format: "0x%X", mark))")
                    typingWord[i] &= ~VNEngine.MARK_MASK
                    insertMarkInternal(markMask: mark, canModifyFlag: false, deltaBackSpace: deltaBackSpace)
                    logCallback?("  → After insertMarkInternal: vowelWillSetMark=\(vowelWillSetMark)")
                    if i != vowelWillSetMark {
                        isAdjusted = true
                        logCallback?("  → Mark position adjusted from \(i) to \(vowelWillSetMark)")
                    } else {
                        // Mark position is correct, restore saved hookState
                        // This prevents insertMarkInternal from overwriting the correct
                        // backspaceCount calculated by checkVowelAutoFix
                        hookState.backspaceCount = savedBackspaceCount
                        hookState.newCharCount = savedNewCharCount
                        hookState.code = savedCode
                        logCallback?("  → Mark position already correct, restored hookState (bs=\(savedBackspaceCount), chars=\(savedNewCharCount))")
                    }
                    break
                }
            }
        }
        logCallback?("  → isAdjusted=\(isAdjusted)")
        
        // Re-arrange data to send back
        // IMPORTANT: Use savedVowelStartIndex here because insertMarkInternal may have
        // changed vowelStartIndex (it calls findAndCalculateVowel with forGrammar: false
        // which treats "gi" differently). For "gisup" -> "giúp", we need to include
        // the "i" in "gi" when sending charData to remove the mark that was on it.
        if isAdjusted {
            if hookState.code == UInt8(vDoNothing) {
                hookState.code = UInt8(vWillProcess)
            }
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: savedVowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
            hookState.backspaceCount = hookState.backspaceCount + deltaBackSpace
            hookState.extCode = 4
        }
    }
    
    /// Legacy function - calls both checkVowelAutoFix and checkMarkPosition
    private func checkGrammar(deltaBackSpace: Int) {
        checkVowelAutoFix(deltaBackSpace: deltaBackSpace)
        // When deleting a character (deltaBackSpace > 0), ALWAYS check mark position
        // regardless of vFreeMark setting. This is because deleting an ending consonant
        // changes the "terminated" status of the vowel sequence, which affects where
        // the tone mark should be placed according to Vietnamese spelling rules.
        // Example: "bưãn" (mark on 'a') -> delete 'n' -> "bữa" (mark should move to 'ư')
        // This is NOT a free marking choice - it's a spelling rule.
        if vFreeMark == 0 || deltaBackSpace > 0 {
            checkMarkPosition(deltaBackSpace: deltaBackSpace)
        }
    }
    
    private func insertMarkInternal(markMask: UInt32, canModifyFlag: Bool, deltaBackSpace: Int) {
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
        // BUT: Only apply this when there's an ending consonant (like "thương", "người")
        // Do NOT apply to words without ending consonant (like "thuở")
        if vowelCount >= 2 {
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            
            // Check for "uo" pattern with mismatched TONEW_MASK
            if v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O {
                if v1HasToneW != v2HasToneW {
                    // Check if there's an ending consonant after the vowel pair
                    var hasEndConsonant = false
                    if vowelEndIndex + 1 < Int(index) {
                        let nextKey = chr(vowelEndIndex + 1)
                        // Check for common ending consonants: n, c, i, m, p, t
                        if nextKey == VietnameseData.KEY_N || nextKey == VietnameseData.KEY_C ||
                           nextKey == VietnameseData.KEY_I || nextKey == VietnameseData.KEY_M ||
                           nextKey == VietnameseData.KEY_P || nextKey == VietnameseData.KEY_T {
                            hasEndConsonant = true
                        }
                    }
                    
                    // Only auto-fix if there's an ending consonant
                    if hasEndConsonant {
                        // Add TONEW_MASK to both to make "ươ"
                        typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                        logCallback?("  Auto-fixed ưo → ươ (has ending consonant)")
                    } else {
                        logCallback?("  Skipped auto-fix ưo → ươ (no ending consonant, e.g., 'thuở')")
                    }
                }
            }
        }
        
        logCallback?("  vowelStartIndex=\(vowelStartIndex), vowelEndIndex=\(vowelEndIndex), vowelCount=\(vowelCount)")
        
        // Detect mark position
        if vowelCount == 1 {
            vowelWillSetMark = vowelEndIndex
            hookState.backspaceCount = Int(index) - vowelEndIndex
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
            hookState.backspaceCount = Int(index) - vowelStartIndex
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
            
            hookState.backspaceCount = Int(index) - vowelStartIndex
            // Apply deltaBackSpace adjustment if last char not on screen yet
            if deltaBackSpace == -1 {
                hookState.backspaceCount += deltaBackSpace
            }
        }
        hookState.newCharCount = hookState.backspaceCount
        logCallback?("  Result: backspaceCount=\(hookState.backspaceCount), newCharCount=\(hookState.newCharCount)")

        // Dictionary check after adding mark - ONLY for instant restore feature
        // When instant restore is OFF, we should NOT block typing here
        // because the word is still being typed (e.g., "vịe" is incomplete, will become "việt")
        // Dictionary validation will happen when user presses Space
        // Hierarchy: instantRestore requires restoreIfWrongSpelling requires spellCheckEnabled
        //
        // IMPORTANT: Only check when ADDING a new mark, not when REMOVING (duplicate/undo)
        // When user presses same mark key twice (e.g., 'ỏ' + 'r' → 'o'), this is normal restore
        // and should not trigger instant restore. Check by seeing if hookState.code is NOT vRestore.
        let isDuplicateMark = (hookState.code == UInt8(vRestore))
        
        if !isDuplicateMark &&
           SharedSettings.shared.spellCheckEnabled && 
           SharedSettings.shared.restoreIfWrongSpelling &&
           SharedSettings.shared.instantRestoreOnWrongSpelling &&
           canModifyFlag {
            let style: VNDictionaryManager.DictionaryStyle = SharedSettings.shared.modernStyle ? .dauMoi : .dauCu
            if VNDictionaryManager.shared.isDictionaryLoaded(style: style) {
                let wordWithMark = getCurrentWord()
                let isValid = isCurrentWordValid()
                logCallback?("  → Dictionary check after mark (instant restore): word='\(wordWithMark)', valid=\(isValid)")

                // If word with mark is invalid and instant restore is enabled
                if !isValid {
                    // IMPORTANT: Only instant restore if the raw keystrokes look like English
                    // This prevents incomplete Vietnamese words like "tiê" from being restored to "tiee"
                    // Vietnamese words in progress should NOT be instantly restored
                    
                    // Get raw input for English pattern detection
                    // Use hasEnglishStartPattern which only checks beginning/middle of word
                    // This avoids false positives from Telex mark keys (s/f/r/x/j) at the end
                    // NOTE: Use getRawInputStringForEnglishDetection() which EXCLUDES overflow
                    let rawInput = getRawInputStringForEnglishDetection()
                    let isEnglishPattern = rawInput.hasEnglishStartPattern
                    
                    logCallback?("  → Word invalid, checking if English: rawInput='\(rawInput)', isEnglish=\(isEnglishPattern)")
                    
                    if isEnglishPattern {
                        logCallback?("  → Detected English pattern, INSTANT RESTORE enabled - restoring now!")
                        
                        // Perform immediate restore - restore to original keystrokes
                        var originalWord = [UInt32]()
                        for i in 0..<Int(stateIndex) {
                            originalWord.append(keyStates[i])
                        }
                        
                        if !originalWord.isEmpty {
                            hookState.code = UInt8(vRestore)
                            hookState.backspaceCount = Int(index)
                            hookState.newCharCount = originalWord.count
                            
                            // Set original characters to send
                            for i in 0..<originalWord.count {
                                let keyData = originalWord[i]
                                let keyCode = UInt16(keyData & VNEngine.CHAR_MASK)
                                let isCaps = (keyData & VNEngine.CAPS_MASK) != 0
                                
                                var charCode = UInt32(keyCode)
                                if isCaps {
                                    charCode |= VNEngine.CAPS_MASK
                                }
                                hookState.charData[originalWord.count - 1 - i] = charCode
                            }
                            
                            // Mark as instant restore (extCode = 5) so handleNormalKey won't insert key again
                            hookState.extCode = 5
                            logCallback?("  → Instant restore: bs=\(hookState.backspaceCount), chars=\(hookState.newCharCount), extCode=5")
                            
                            // Reset engine after instant restore
                            buffer.clear()
                        }
                        
                        // Set tempDisableKey so subsequent keys don't get processed as Vietnamese
                        tempDisableKey = true
                    } else {
                        logCallback?("  → Not detected as English, skipping instant restore (allow Vietnamese typing to continue)")
                    }
                }
            }
        }
    }
    
    // MARK: - Mark Position Rules (Modern Orthography)
    
    private func handleModernMark() {
        // Default
        vowelWillSetMark = vowelEndIndex
        hookState.backspaceCount = Int(index) - vowelEndIndex
        
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
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
        } else if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            
            // oi, ai, ui -> mark on first vowel
            if (v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_I) {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // ay -> mark on 'a'
            else if v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // NOTE: "oa", "oe" cases are handled by the general rule below:
            // "If 1st vowel is 'o' or 'u' -> mark on last vowel"
            // This matches OpenKey behavior where "khoa" + r = "khoả" (mark on 'a')
            // The old XKey code incorrectly checked for end consonant, but OpenKey doesn't do that.
            // uo -> mark on 'o'
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelStartIndex + 1
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // uy -> mark on 'y' (modern orthography: tuý, quý, thuý)
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex + 1  // Đặt dấu vào 'y' cho kiểu hiện đại
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // If 2nd vowel is 'o' or 'u' -> mark on 1st vowel
            else if v2 == VietnameseData.KEY_O || v2 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex - 1
                hookState.backspaceCount = Int(index) - vowelWillSetMark + 1
            }
            // If 1st vowel is 'o' or 'u' -> mark on last vowel
            else if v1 == VietnameseData.KEY_O || v1 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = Int(index) - vowelEndIndex
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
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                    logCallback?("    Rule 3.1 applied: mark on 2nd vowel (index \(vowelWillSetMark))")
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                    logCallback?("    Rule 3.1 applied: mark on 1st vowel (index \(vowelWillSetMark))")
                }
            } else {
                // No character after the vowel pair, mark on 1st vowel
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
                logCallback?("    Rule 3.1 applied: no char after, mark on 1st vowel (index \(vowelWillSetMark))")
            }
        }
        // Rule 3.2: ia, ya, ua, ưu patterns - mark on 1st vowel
        else if (rule3v1 == VietnameseData.KEY_I && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_Y && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_U && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                (rule3v1 == VietnameseData.KEY_U && rule3v2Data == (UInt32(VietnameseData.KEY_U) | VNEngine.TONEW_MASK)) {
            vowelWillSetMark = vowelStartIndex
            hookState.backspaceCount = Int(index) - vowelWillSetMark
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
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
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
                        hookState.backspaceCount = Int(index) - vowelWillSetMark
                    }
                } else {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                }
            }
            // oo -> mark on last vowel
            else if v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = Int(index) - vowelEndIndex
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
        hookState.backspaceCount = Int(index) - vowelWillSetMark
        
        // Rule 2: 3 vowels or has ending consonant
        // For old style: "hòa" (no ending) vs "hoàn" (has ending 'n')
        if vowelCount == 3 || (vowelEndIndex + 1 < Int(index) && vietnameseData.isConsonant(chr(vowelEndIndex + 1)) && canHasEndConsonant()) {
            vowelWillSetMark = vowelStartIndex + 1
            hookState.backspaceCount = Int(index) - vowelWillSetMark
        }
        
        // Rule for "uy" in old style: mark on 'u' (úy)
        // Old style: túy, húy, qúy
        // BUT: If there's an ending consonant (like "huynh"), mark should be on 'y' (huỳnh)
        if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            let hasEndConsonant = vowelEndIndex + 1 < Int(index) &&
                                  vietnameseData.isConsonant(chr(vowelEndIndex + 1)) &&
                                  canHasEndConsonant()

            if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y && !hasEndConsonant {
                vowelWillSetMark = vowelStartIndex  // Đặt dấu vào 'u' cho kiểu cũ (chỉ khi KHÔNG có phụ âm cuối)
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
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
                hookState.backspaceCount = Int(index) - vowelWillSetMark
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
    
    /// Save current word to history for restore functionality
    /// Save current word to history
    func saveWord() {
        if hookState.code == UInt8(vReplaceMacro) || hookState.code == UInt8(vRestore) {
            logCallback?("saveWord: Skipping (macro or restore)")
            return
        }

        guard !buffer.isEmpty else {
            logCallback?("saveWord: nothing to save (empty)")
            return
        }

        let snapshot = buffer.createSnapshot()
        history.save(snapshot)
        logCallback?("saveWord: saved '\(getCurrentWord())' to history, count=\(history.count)")
    }

    /// Save spaces to history
    func saveWord(keyCode: UInt16, count: Int) {
        history.saveSpaces(count: count, keyCode: keyCode)
    }

    /// Save special characters to history
    private func saveSpecialChar() {
        guard !specialChar.isEmpty else { return }

        var entries: [CharacterEntry] = []
        for data in specialChar {
            entries.append(CharacterEntry(fromLegacy: data))
        }
        let snapshot = BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: [])
        history.save(snapshot)
        specialChar.removeAll()
    }

    /// Restore last word from history
    func restoreLastTypingState() {
        logCallback?("restoreLastTypingState: history.count=\(history.count)")

        guard let lastSnapshot = history.popLast() else {
            logCallback?("  → history empty, nothing to restore")
            cursorMovedSinceReset = true
            return
        }

        guard !lastSnapshot.entries.isEmpty else {
            logCallback?("  → snapshot empty")
            return
        }

        let firstKeyCode = lastSnapshot.firstKeyCode ?? 0

        if firstKeyCode == VietnameseData.KEY_SPACE {
            spaceCount = lastSnapshot.count
            buffer.clear()
            logCallback?("  → Restored spaces: \(spaceCount)")
        } else if vietnameseData.charKeyCode.contains(firstKeyCode) {
            buffer.clear()
            specialChar = lastSnapshot.allProcessedData
            if vCheckSpelling == 1 {
                checkSpelling()
            }
            logCallback?("  → Restored special chars: \(specialChar.count)")
        } else {
            buffer.restore(from: lastSnapshot)
            tempDisableKey = false
            logCallback?("  → Restored word: count=\(buffer.count), word='\(getCurrentWord())'")
        }
    }

    /// Start a new typing session
    func startNewSession() {
        let prevWord = !buffer.isEmpty ? getCurrentWord() : ""
        let prevCount = buffer.count

        buffer.clear()

        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.macroKey.removeAll()

        tempDisableKey = false
        hasHandledMacro = false
        hasHandleQuickConsonant = false
        // Reset desync flag on new session - fresh start
        bufferDesyncDetected = false

        logCallback?("startNewSession: cleared (prev='\(prevWord)', count=\(prevCount))")
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
        history.clear()
        specialChar.removeAll()
        spaceCount = 0
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false
        cursorMovedSinceReset = false
        focusChangedDuringTyping = false
    }

    /// Reset engine with cursor movement flag set
    /// This indicates that user moved cursor (via mouse/arrow keys) and may be editing
    /// in the middle of an existing word. Restore logic will be skipped in this case.
    func resetWithCursorMoved() {
        reset()
        cursorMovedSinceReset = true
        logCallback?("resetWithCursorMoved: cursor moved flag set")
    }

    /// Clear history (for terminal apps after Enter key)
    /// This prevents backspace from restoring words from previous command lines
    func clearHistory() {
        history.clear()
        logCallback?("clearHistory: history cleared for terminal")
    }

    /// Notify engine that focus changed during typing session
    /// This can happen when suggestion popups appear - keystrokes may go to popup
    /// causing buffer desync. Restore will be skipped at next word break/backspace.
    func notifyFocusChanged() {
        // Only set flag if we're currently typing (have content in buffer)
        if !buffer.isEmpty {
            focusChangedDuringTyping = true
            logCallback?("notifyFocusChanged: focus changed during typing, will skip restore")
        }
    }


    /// Get current typing word as string (for debugging and display)
    func getCurrentWord() -> String {
        var result = ""
        for i in 0..<Int(index) {
            let data = typingWord[i]
            let charCode = getCharacterCode(data)
            let isCaps = (data & VNEngine.CAPS_MASK) != 0

            if (charCode & VNEngine.CHAR_CODE_MASK) != 0 {
                // Unicode character
                let unicodeValue = charCode & 0xFFFF
                if let scalar = UnicodeScalar(unicodeValue) {
                    var char = String(Character(scalar))
                    if isCaps {
                        char = char.uppercased()
                    }
                    result.append(char)
                }
            } else {
                // Key code - convert to character using macOS key code mapping
                let keyCode = UInt16(charCode & VNEngine.CHAR_MASK)
                if let char = keyCodeToCharacter(keyCode) {
                    if isCaps {
                        result.append(Character(String(char).uppercased()))
                    } else {
                        result.append(char)
                    }
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
        case VietnameseData.KEY_LEFT_BRACKET: return "["
        case VietnameseData.KEY_RIGHT_BRACKET: return "]"
        default: return nil
        }
    }
}

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
    
    /// Check if there's something to undo
    /// Returns true if engine has Vietnamese-processed text that can be reverted
    /// Only returns true when the word contains actual Vietnamese modifications (diacritics)
    /// For plain text like "thu", ESC should pass through. For "thử", ESC should undo.
    func canUndoTyping() -> Bool {
        // Must have both current word and original keystrokes
        guard index > 0 && stateIndex > 0 else {
            return false
        }
        
        // Check if any character has Vietnamese modification (mark, tone, or horn/breve)
        for i in 0..<Int(index) {
            let charData = typingWord[i]
            let hasMark = (charData & VNEngine.MARK_MASK) != 0      // Dấu thanh (sắc, huyền, hỏi, ngã, nặng)
            let hasTone = (charData & VNEngine.TONE_MASK) != 0      // Dấu mũ (â, ê, ô)
            let hasToneW = (charData & VNEngine.TONEW_MASK) != 0    // Dấu móc/ngoắc (ư, ơ, ă)
            
            if hasMark || hasTone || hasToneW {
                // Found Vietnamese modification - can undo
                return true
            }
        }
        
        // No Vietnamese modification found - nothing to undo
        return false
    }
    
    /// Undo Vietnamese typing - restore original keystrokes
    /// This restores the raw keystrokes before Vietnamese processing
    /// Example: "tiếng" → "tieesng"
    func undoTyping() -> ProcessResult {
        logCallback?("undoTyping: index=\(index), stateIndex=\(stateIndex)")
        
        // Check if there's anything to undo
        guard index > 0 && stateIndex > 0 else {
            logCallback?("  → Nothing to undo (index=\(index), stateIndex=\(stateIndex))")
            return ProcessResult.doNothing
        }
        
        // Get original typed keys from keyStates
        var originalKeys = [UInt32]()
        for i in 0..<Int(stateIndex) {
            originalKeys.append(keyStates[i])
        }
        
        guard !originalKeys.isEmpty else {
            logCallback?("  → No original keys found")
            return ProcessResult.doNothing
        }
        
        logCallback?("  → Restoring \(originalKeys.count) original keys")
        
        // Build result
        var result = ProcessResult()
        result.shouldConsume = true
        result.backspaceCount = Int(index)  // Delete current Vietnamese word
        
        // Convert original key codes to VNCharacters
        for keyData in originalKeys {
            let keyCode = UInt16(keyData & VNEngine.CHAR_MASK)
            let isCaps = (keyData & VNEngine.CAPS_MASK) != 0
            
            // Convert key code to character
            if let char = keyCodeToCharacter(keyCode) {
                let finalChar = isCaps ? Character(String(char).uppercased()) : char
                result.newCharacters.append(VNCharacter(character: finalChar))
                logCallback?("    → Key \(keyCode) → '\(finalChar)'")
            }
        }
        
        // Reset engine state after undo
        startNewSession()
        
        return result
    }
    
    /// Process word break (space, punctuation, etc.)
    /// Returns ProcessResult with macro replacement if found
    func processWordBreak(character: Character) -> ProcessResult {
        // Only trigger macro on SPACE - not on other word break characters
        // This prevents macros like "you@" from triggering immediately when typing "@"
        // User needs to press space to trigger macro replacement
        let isSpace = (character == " ")
        
        // Flag to track if word was already saved to history during this function
        // This prevents duplicate saves (e.g., in "Skipping restore" block + saveWord())
        var wordAlreadySavedToHistory = false
        
        // Restore trigger: space, comma, or period
        // These are the characters that will trigger spell check restore
        let isRestoreTrigger = isSpace || character == "," || character == "."
        
        logCallback?("processWordBreak: char='\(character)', isSpace=\(isSpace), isRestoreTrigger=\(isRestoreTrigger), tempDisableKey=\(tempDisableKey), index=\(index), cursorMovedSinceReset=\(cursorMovedSinceReset)")
        
        // IMPORTANT: Check macro FIRST before spell check
        // This ensures that macros like "dc" get replaced instead of being restored as invalid spelling
        // Macro check takes priority because user explicitly defined these shortcuts
        // Trigger macro on restore trigger characters (space, comma, period)
        if isRestoreTrigger && shouldUseMacro() && !hasHandledMacro {
            let macroFound = findAndReplaceMacro()

            if macroFound {
                logCallback?("processWordBreak: Macro found, replacing")
                let result = convertHookStateToResult(hookState, currentKeyCode: nil, currentCharacter: character, isUppercase: false)
                // Reset after macro replacement - clears history because macro output
                // can be very large (code snippets, templates) and shouldn't be stored
                reset()
                return result
            }
        }
        
        // Check spelling AFTER macro check (for restore if wrong spelling feature)
        // Only run if BOTH spell check AND restore if wrong spelling are enabled
        // AND no macro was found above
        // Also skip if spelling is temporarily off via toolbar
        // Trigger restore on space, comma, or period
        //
        // Skip restore when potentially desynced:
        // 1. bufferDesyncDetected=true (previous desync was detected)
        // 2. cursorMovedSinceReset=true (user clicked/moved cursor)
        // 3. focusChangedDuringTyping=true (suggestion popup stole focus)
        // Normal typing: buffer is correct, proceed with restore check
        if isRestoreTrigger && vCheckSpelling == 1 && vRestoreIfWrongSpelling == 1 && vTempOffSpelling == 0 {
            // Check if we should proceed with restore check
            var shouldCheckRestore = true
            
            // CASE 0: Buffer-screen desync was previously detected
            // This happens when AX detected mismatch during backspace operations
            // Engine doesn't have full context, so disable restore to prevent wrong output
            // Example: Screen has "tu", buffer="" after mismatch, user types "ij" → buffer="ụi"
            // Without this check, "ụi" would be restored to "uij" instead of keeping "tụi"
            if bufferDesyncDetected {
                logCallback?("processWordBreak: bufferDesyncDetected=true, skipping restore (engine lacks full context)")
                shouldCheckRestore = false
            }
            // CASE 1: Cursor was moved (mouse click, arrow keys, etc.)
            // Buffer was reset and doesn't have full context of existing word on screen
            // Example: Screen has "ch", user types "ính" → buffer="ính" but screen="chính"
            // Restoring "ính" would produce "chinhs" which is wrong!
            else if cursorMovedSinceReset {
                logCallback?("processWordBreak: cursorMovedSinceReset=true, skipping restore (buffer doesn't have full context)")
                shouldCheckRestore = false
            }
            // CASE 2: Focus changed during typing (suggestion popup scenario)
            // Skip restore to avoid potential desync issues - safer than slow AX calls
            else if focusChangedDuringTyping {
                logCallback?("processWordBreak: focusChangedDuringTyping=true, skipping restore")
                shouldCheckRestore = false
                // Reset flag
                focusChangedDuringTyping = false
            }
            // CASE 3: Normal typing - buffer is correct

            
            if shouldCheckRestore {
                let wordToCheck = getCurrentWord()
                
                // Check if the word is valid Vietnamese
                let isValidWord = checkWordSpelling(word: wordToCheck)
                logCallback?("processWordBreak: wordToCheck='\(wordToCheck)', isValid=\(isValidWord)")

                if !isValidWord {
                    // Not using AX - check if word has Vietnamese processing
                    // If word has tone marks/diacritics and is not in dictionary, restore it
                    // This fixes the issue where phonetically valid but meaningless words
                    // like "xỷ" weren't being restored because checkSpelling() only checks phonetic
                    let hasVietnameseChars = hasVietnameseProcessing()
                    if hasVietnameseChars {
                        // Word has Vietnamese characters but is not valid - restore it
                        tempDisableKey = true
                        logCallback?("processWordBreak: Dictionary check failed for Vietnamese word '\(wordToCheck)', forcing restore")
                    } else if !tempDisableKey {
                        // Word doesn't have Vietnamese characters, use phonetic check
                        checkSpelling(forceCheckVowel: true)
                    }

                    // IMPORTANT: Skip restore if word has no Vietnamese processing
                    // This handles the case where user manually restored via toggle key (e.g., 'd' to revert 'đ' to 'd')
                    // In this case, tempDisableKey=true but the word is now plain text - no need to restore again
                    // Example: "ddi" -> user typed 'd' to restore 'đ' -> "did" (plain text) -> space should NOT restore to "ddi"
                    let hasVNProcessing = hasVietnameseProcessing()
                    if tempDisableKey && hasVNProcessing {
                        logCallback?("processWordBreak: Word invalid, attempting restore...")
                        if checkRestoreIfWrongSpelling(handleCode: vRestore) {
                            logCallback?("processWordBreak: Restore successful")

                            // IMPORTANT: After restore, check if restored word is a macro
                            // Example: "intẻ" (invalid) restored to "inter" which may be a macro
                            if shouldUseMacro() {
                                // Rebuild macroKey from keyStates (original keystrokes)
                                var restoredMacroKey = [UInt32]()
                                for i in 0..<Int(stateIndex) {
                                    restoredMacroKey.append(keyStates[i])
                                }

                                if !restoredMacroKey.isEmpty {
                                    // Save the original backspace count from restore operation
                                    // This is the number of characters on screen (transformed text like "intẻ")
                                    let originalBackspaceCount = hookState.backspaceCount

                                    hookState.macroKey = restoredMacroKey
                                    logCallback?("processWordBreak: After restore, checking macro with keyStates (count=\(restoredMacroKey.count))")

                                    if findAndReplaceMacro() {
                                        // Macro found - need to fix backspaceCount
                                        // findAndReplaceMacro sets backspaceCount = macroKey.count (original keystrokes)
                                        // But text on screen is transformed text, so we need original backspaceCount
                                        hookState.backspaceCount = originalBackspaceCount
                                        logCallback?("processWordBreak: Macro found after restore! Using backspaceCount=\(originalBackspaceCount)")

                                        let result = convertHookStateToResult(hookState, currentKeyCode: nil, currentCharacter: character, isUppercase: false)
                                        // Reset after macro replacement - clears history because macro output
                                        // can be very large and shouldn't be stored
                                        reset()
                                        return result
                                    }
                                }
                            }

                            // No macro found, return restore result
                            logCallback?("processWordBreak: No macro, returning restore result")
                            let result = convertHookStateToResult(hookState, currentKeyCode: nil, currentCharacter: character, isUppercase: false)
                            
                            // FIX: Save the RESTORED word to history for proper backspace support
                            // The restored word (plain text like "bieet") is what's now on screen.
                            // If user backspaces, we need to restore this word into buffer to stay in sync.
                            //
                            // Previous bug: reset() was called which clears history, so backspace
                            // had nothing to restore, causing desync.
                            //
                            // Solution: Save restored word to history, then use startNewSession()
                            // instead of reset() to preserve history.
                            //
                            // Note: We save the RESTORED keyStates, not the Vietnamese buffer,
                            // because that's what was injected to screen.
                            if stateIndex > 0 {
                                // Create a snapshot from keyStates (the restored characters)
                                var restoredBuffer = TypingBuffer()
                                for i in 0..<Int(stateIndex) {
                                    let keyCode = UInt16(keyStates[i] & 0xFF)
                                    let isCaps = (keyStates[i] & VNEngine.CAPS_MASK) != 0
                                    _ = restoredBuffer.append(keyCode: keyCode, isCaps: isCaps)
                                }
                                let snapshot = restoredBuffer.createSnapshot()
                                history.save(snapshot)
                                logCallback?("  → Saved restored word to history (count=\(stateIndex))")
                            }
                            
                            // Use startNewSession() to clear buffer but preserve history
                            startNewSession()
                            spaceCount = 1
                            return result
                        }
                    } else if tempDisableKey && !hasVNProcessing {
                        // User manually restored via toggle key (e.g., 'd' to revert 'đ' to 'd')
                        // Word is now plain text, no need to restore again
                        logCallback?("processWordBreak: Skipping restore - word has no Vietnamese processing (manually restored)")
                        
                        // FIX: Save current word to history for proper backspace restore
                        // 
                        // Problem: saveWord() skips when hookState.code == vRestore (set during undo)
                        // This causes the current word to NOT be saved, leaving old unrelated words
                        // in history. When user backspaces, the old word gets restored → DESYNC!
                        //
                        // Solution: Manually save the current buffer to history here.
                        // The word is valid (just plain text without Vietnamese), and user expects
                        // backspace to restore it properly.
                        //
                        // Example with this fix:
                        // 1. User types "biete" (undo circumflex) → plain "biete" on screen
                        // 2. User presses space → "biete" SAVED to history ← NEW!
                        // 3. User backspaces → restores "biete" into buffer
                        // 4. Buffer = "biete", Screen = "biete" → SYNC!
                        if !buffer.isEmpty {
                            let snapshot = buffer.createSnapshot()
                            history.save(snapshot)
                            wordAlreadySavedToHistory = true
                            logCallback?("  → Saved '\(getCurrentWord())' to history for backspace restore")
                        }
                    }
                }
            }
        }
        
        // For non-space word break characters, add them to macroKey for building macros
        // This allows macros like "you@" or "!bb" to be built character by character
        if !isSpace && shouldUseMacro() {
            let wordBreakCharToKeyCode: [Character: UInt16] = [
                "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15, "%": 0x17,
                "^": 0x16, "&": 0x1A, "*": 0x1C, "(": 0x19, ")": 0x1D,
                "~": 0x32, "`": 0x32, "-": 0x1B, "_": 0x1B, "=": 0x18, "+": 0x18,
                "[": 0x21, "{": 0x21, "]": 0x1E, "}": 0x1E,
                "\\": 0x2A, "|": 0x2A, ";": 0x29, ":": 0x29,
                "'": 0x27, "\"": 0x27, ",": 0x2B, "<": 0x2B,
                ".": 0x2F, ">": 0x2F, "/": 0x2C, "?": 0x2C
            ]
            
            if let keyCode = wordBreakCharToKeyCode[character], vietnameseData.charKeyCode.contains(keyCode) {
                // Check if it's a shifted special character
                let isShiftedChar = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "~", "_", "+", "{", "}", "|", ":", "\"", "<", ">", "?"].contains(character)
                hookState.macroKey.append(UInt32(keyCode) | (isShiftedChar ? VNEngine.CAPS_MASK : 0))
            }
        }
        
        // IMPORTANT: Save current word to typingStates BEFORE resetting
        // This enables "free mark" feature - user can add marks to previous word after backspace
        // OpenKey behavior: saveWord() is called before startNewSession()

        // If we already have spaces saved, save them first
        if spaceCount > 0 {
            saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
            spaceCount = 0
        }

        // Save current word (skip if already saved earlier in this function)
        if !wordAlreadySavedToHistory {
            saveWord()
        }

        // Only reset session and clear macroKey for SPACE
        // For other special characters (!, @, #, etc.), we preserve macroKey
        // to allow macros like "!bb" or "@hello"
        if isSpace {
            // Increment space count for the current space
            spaceCount = 1

            // Start new session and clear macroKey
            // This ensures each word after SPACE starts fresh
            startNewSession()
            
            // macroKey is cleared by startNewSession()
            // This allows macros like "hello" -> "hello world" to work correctly
        } else {
            // For non-space word breaks (!, @, #, etc.), we still need to reset the buffer
            // but preserve macroKey to build macros like "!bb"
            // 
            // IMPORTANT: We must reset index here to prevent double-processing.
            // Example: Typing "space" - when " is pressed, saveWord() saves "space"
            // If we don't reset index, when space is pressed next, engine still sees
            // index=5 and tries to restore "space", deleting the opening " incorrectly.
            spaceCount = 1

            // Reset buffer but preserve macroKey
            buffer.clear()
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            tempDisableKey = false
            hasHandledMacro = false
            hasHandleQuickConsonant = false
        }
        
        // Reset spell checking to original setting
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false

        // Reset cursor moved flag after word break
        // This allows restore logic to work normally for the next word
        cursorMovedSinceReset = false

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
            logCallback?("  No frontmost application")
            return
        }
        
        logCallback?("  App: \(focusedApp.localizedName ?? "Unknown") (\(focusedApp.bundleIdentifier ?? ""))")
        
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        
        // Get focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard focusResult == .success, let element = focusedElement else {
            logCallback?("  Cannot get focused element (error: \(focusResult.rawValue))")
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
                        logCallback?("  Last word: \"\(lastWord)\"")
                        
                        // Show Unicode code points
                        if !lastWord.isEmpty {
                            let codePoints = lastWord.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                            logCallback?("  Unicode: \(codePoints)")
                        }
                    } else {
                        logCallback?("  Cursor at position 0 or invalid")
                    }
                } else {
                    logCallback?("  Cannot get text value (error: \(textResult.rawValue))")
                }
            }
        } else {
            logCallback?("  Cannot get selected text range (error: \(rangeResult.rawValue))")
            
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
        
        result.backspaceCount = hookState.backspaceCount

        // For macro replacement, use macroData directly (no length limit)
        if hookState.code == UInt8(vReplaceMacro) && !hookState.macroData.isEmpty {
            // macroData is already in correct order, just convert to VNCharacter
            for charData in hookState.macroData {
                let vnChar = convertToVNCharacter(charData)
                result.newCharacters.append(vnChar)
            }
            
            // Add space after macro if enabled
            // The trigger character (space, comma, period) is passed as currentCharacter
            // We add it after the macro content if addSpaceAfterMacro is enabled
            if vAddSpaceAfterMacro == 1 {
                if let character = currentCharacter {
                    // Add the trigger character (space, comma, or period) after macro
                    result.newCharacters.append(VNCharacter(character: character))
                }
            }
        } else {
            // Convert character data to VNCharacter array
            // IMPORTANT: In OpenKey, charData is stored in reverse order (last character at index 0)
            // So we need to read it in reverse order to get the correct sequence
            // This matches OpenKey's SendNewCharString which reads from newCharCount-1 down to 0
            for i in stride(from: Int(hookState.newCharCount) - 1, through: 0, by: -1) {
                let charData = hookState.charData[i]
                let vnChar = convertToVNCharacter(charData)
                result.newCharacters.append(vnChar)
            }
        }
        
        // IMPORTANT: When vRestore, OpenKey adds the current key to the output
        // This is how toggle works: restore the original character AND add the current key
        // See OpenKey's SendNewCharString: "if is restore" block
        // EXCEPTION: For instant restore (extCode == 5), the current key is already included
        // in keyStates (the original keystrokes). We should NOT append it again.
        if hookState.code == UInt8(vRestore) || hookState.code == UInt8(vRestoreAndStartNewSession) {
            // Skip for instant restore - current key already in keyStates
            if hookState.extCode != 5 {
                if let character = currentCharacter {
                    // Add the current key to output
                    let vnChar = VNCharacter(character: isUppercase ? Character(String(character).uppercased()) : character)
                    result.newCharacters.append(vnChar)
                }
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
