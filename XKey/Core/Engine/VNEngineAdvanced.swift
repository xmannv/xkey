//
//  VNEngineAdvanced.swift
//  XKey
//
//  Advanced features implementation for VNEngine
//  Ported from OpenKey Engine.cpp
//

import Foundation

extension VNEngine {
    
    // MARK: - Quick Telex
    
    /// Handle Quick Telex conversion (cc→ch, gg→gi, etc.)
    func handleQuickTelex(keyCode: UInt16, isCaps: Bool) {
        guard !buffer.isEmpty else {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }

        // Quick Telex mappings
        var replacementKey: UInt16 = 0

        switch keyCode {
        case VietnameseData.KEY_C: replacementKey = VietnameseData.KEY_H  // cc → ch
        case VietnameseData.KEY_G: replacementKey = VietnameseData.KEY_I  // gg → gi
        case VietnameseData.KEY_K: replacementKey = VietnameseData.KEY_H  // kk → kh
        case VietnameseData.KEY_N: replacementKey = VietnameseData.KEY_G  // nn → ng
        case VietnameseData.KEY_P: replacementKey = VietnameseData.KEY_H  // pp → ph
        case VietnameseData.KEY_Q: replacementKey = VietnameseData.KEY_U  // qq → qu
        case VietnameseData.KEY_T: replacementKey = VietnameseData.KEY_H  // tt → th
        default:
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }

        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        hookState.newCharCount = 1

        // Append the replacement key
        buffer.append(keyCode: replacementKey, isCaps: isCaps)

        hookState.charData[0] = getCharacterCode(buffer.last!.processedData)
        logCallback?("Quick Telex: \(keyCode)\(keyCode) → \(keyCode)\(replacementKey)")
    }
    
    // MARK: - Quick Consonant
    
    /// Check and handle Quick Start/End Consonant
    func checkQuickConsonant() {
        hasHandleQuickConsonant = false

        guard !buffer.isEmpty else { return }

        // Quick Start Consonant: f→ph, j→gi, w→qu
        if vQuickStartConsonant == 1 && buffer.count >= 1 {
            let firstKey = chr(0)
            var replacement: (UInt16, UInt16)? = nil

            switch firstKey {
            case VietnameseData.KEY_F: replacement = (VietnameseData.KEY_P, VietnameseData.KEY_H)
            case VietnameseData.KEY_J: replacement = (VietnameseData.KEY_G, VietnameseData.KEY_I)
            case VietnameseData.KEY_W: replacement = (VietnameseData.KEY_Q, VietnameseData.KEY_U)
            default: break
            }

            if let (first, second) = replacement {
                let isCaps = buffer[0].isCaps

                // Insert new entry at position 1, shift others
                let secondEntry = CharacterEntry(keyCode: second, isCaps: isCaps)
                buffer[0].processedData = UInt32(first) | (isCaps ? VNEngine.CAPS_MASK : 0)

                // Insert second character after first
                var entries = buffer.getAllEntries()
                entries.insert(secondEntry, at: 1)
                buffer.clear()
                for entry in entries { buffer.append(entry) }

                hookState.code = UInt8(vWillProcess)
                hookState.backspaceCount = buffer.count
                hookState.newCharCount = buffer.count

                for i in 0..<buffer.count {
                    hookState.charData[buffer.count - 1 - i] = getCharacterCode(buffer[i].processedData)
                }

                hasHandleQuickConsonant = true
                logCallback?("Quick Start Consonant: \(firstKey) → \(first)\(second)")
                return
            }
        }

        // Quick End Consonant: g→ng, h→nh, k→ch
        if vQuickEndConsonant == 1 && buffer.count >= 2 {
            let lastKey = chr(buffer.count - 1)
            var replacement: (UInt16, UInt16)? = nil

            let prevKey = chr(buffer.count - 2)
            let isVowel = !vietnameseData.isConsonant(prevKey)

            if isVowel {
                switch lastKey {
                case VietnameseData.KEY_G: replacement = (VietnameseData.KEY_N, VietnameseData.KEY_G)
                case VietnameseData.KEY_H: replacement = (VietnameseData.KEY_N, VietnameseData.KEY_H)
                case VietnameseData.KEY_K: replacement = (VietnameseData.KEY_C, VietnameseData.KEY_H)
                default: break
                }
            }

            if let (first, second) = replacement {
                let isCaps = buffer[buffer.count - 1].isCaps

                // Replace last and append new
                buffer[buffer.count - 1].processedData = UInt32(first) | (isCaps ? VNEngine.CAPS_MASK : 0)
                buffer.append(keyCode: second, isCaps: isCaps)

                hookState.code = UInt8(vWillProcess)
                hookState.backspaceCount = 1
                hookState.newCharCount = 2

                hookState.charData[0] = getCharacterCode(buffer[buffer.count - 1].processedData)
                hookState.charData[1] = getCharacterCode(buffer[buffer.count - 2].processedData)

                hasHandleQuickConsonant = true
                logCallback?("Quick End Consonant: \(lastKey) → \(first)\(second)")
            }
        }
    }
    
    // MARK: - Upper Case First Character
    
    /// Auto capitalize first character after sentence end
    func upperCaseFirstCharacter() {
        guard buffer.count >= 1 else { return }

        let firstEntry = buffer[0]
        let keyCode = firstEntry.keyCode

        guard vietnameseData.isLetter(keyCode) else { return }
        guard !firstEntry.isCaps else { return }

        // Set uppercase flag
        buffer[0].isCaps = true

        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = buffer.count
        hookState.newCharCount = buffer.count

        for i in 0..<buffer.count {
            hookState.charData[buffer.count - 1 - i] = getCharacterCode(buffer[i].processedData)
        }

        logCallback?("Upper Case First Char: Applied")
    }
    
    // MARK: - Restore If Wrong Spelling

    /// Check and restore if word has wrong spelling
    @discardableResult
    func checkRestoreIfWrongSpelling(handleCode: Int) -> Bool {
        guard tempDisableKey else { return false }
        guard !buffer.isEmpty else { return false }

        if shouldSkipRestoreForSpecialPattern() {
            logCallback?("Restore Wrong Spelling: Skipping (special pattern)")
            return false
        }

        // Get all raw keystrokes from buffer
        let originalKeystrokes = buffer.getAllRawKeystrokes()
        guard !originalKeystrokes.isEmpty else { return false }

        hookState.code = UInt8(handleCode)
        hookState.backspaceCount = buffer.count
        hookState.newCharCount = originalKeystrokes.count

        // Set original characters to send
        for (i, keystroke) in originalKeystrokes.enumerated() {
            var charCode = UInt32(keystroke.keyCode)
            if keystroke.isCaps {
                charCode |= VNEngine.CAPS_MASK
            }
            hookState.charData[originalKeystrokes.count - 1 - i] = charCode
        }

        logCallback?("Restore Wrong Spelling: Restoring \(originalKeystrokes.count) chars")

        if handleCode == vRestoreAndStartNewSession {
            reset()
        }

        return true
    }

    // MARK: - Special Pattern Detection

    /// Check if current buffer looks like an emoji autocomplete pattern
    private func shouldSkipRestoreForSpecialPattern() -> Bool {
        guard !buffer.isEmpty else { return false }

        // Single character - skip restore
        if buffer.count == 1 {
            logCallback?("Special Pattern: Single char, skipping")
            return true
        }

        // First char not a letter - likely emoji shortcut
        let firstKeyCode = buffer.keyCode(at: 0)
        if !vietnameseData.isLetter(firstKeyCode) {
            logCallback?("Special Pattern: First char not letter, skipping")
            return true
        }

        return false
    }
}
