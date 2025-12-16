//
//  VNEngineMacro.swift
//  XKey
//
//  Macro integration for VNEngine
//  Ported from OpenKey Engine.cpp macro handling
//

import Foundation

extension VNEngine {
    
    // MARK: - Macro Manager
    
    /// Shared macro manager instance
    private static var _macroManager: MacroManager?
    
    var macroManager: MacroManager {
        if VNEngine._macroManager == nil {
            VNEngine._macroManager = MacroManager()
        }
        return VNEngine._macroManager!
    }
    
    /// Set shared macro manager (for integration with KeyboardEventHandler)
    static func setSharedMacroManager(_ manager: MacroManager) {
        _macroManager = manager
    }
    
    // MARK: - Macro Processing
    
    /// Find and replace macro in current typing buffer
    /// Called when word break or space is pressed
    /// - Returns: true if macro was found and replaced
    func findAndReplaceMacro() -> Bool {
        guard vUseMacro == 1 else { 
            logCallback?("Macro: vUseMacro is OFF")
            return false 
        }
        guard !hookState.macroKey.isEmpty else { 
            logCallback?("Macro: macroKey is empty")
            return false 
        }
        guard !hasHandledMacro else { 
            logCallback?("Macro: already handled")
            return false 
        }
        
        logCallback?("Macro: searching for key with \(hookState.macroKey.count) chars")
        
        // Try to find macro
        if let macroContent = macroManager.findMacro(key: hookState.macroKey) {
            // Found macro - prepare replacement
            hookState.code = UInt8(vReplaceMacro)
            hookState.backspaceCount = UInt8(hookState.macroKey.count)
            hookState.newCharCount = UInt8(macroContent.count)
            
            // Copy macro content to charData
            for i in 0..<min(macroContent.count, VNEngine.MAX_BUFF) {
                hookState.charData[macroContent.count - 1 - i] = macroContent[i]
            }
            
            // Store macro data for reference
            hookState.macroData = macroContent
            
            hasHandledMacro = true
            logCallback?("Macro found: '\(hookState.macroKey)' → \(macroContent.count) chars")
            
            return true
        }
        
        return false
    }
    
    /// Check if should use macro in current mode
    func shouldUseMacro() -> Bool {
        if vUseMacro != 1 {
            return false
        }
        
        // Check if in English mode
        if vLanguage == 0 {
            // English mode - check if macro in English mode is enabled
            return vUseMacroInEnglishMode == 1
        }
        
        // Vietnamese mode - always use macro if enabled
        return true
    }
    
    /// Process macro on word break
    /// Called from handleWordBreak and handleSpace
    func processMacroOnBreak() -> Bool {
        guard shouldUseMacro() else { return false }
        return findAndReplaceMacro()
    }
    
    /// Add key to macro buffer
    func addKeyToMacroBuffer(keyCode: UInt16, isCaps: Bool) {
        guard vUseMacro == 1 else { return }
        hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
    }
    
    /// Clear macro buffer
    func clearMacroBuffer() {
        hookState.macroKey.removeAll()
        hasHandledMacro = false
    }
    
    /// Update macro buffer after backspace
    func updateMacroBufferOnBackspace() {
        guard vUseMacro == 1 else { return }
        if !hookState.macroKey.isEmpty {
            hookState.macroKey.removeLast()
        }
    }
    
    /// Update macro buffer after character replacement
    func updateMacroBufferOnReplace(backspaceCount: Int, newChars: [UInt32]) {
        guard vUseMacro == 1 else { return }
        
        // Remove backspaced characters
        for _ in 0..<backspaceCount {
            if !hookState.macroKey.isEmpty {
                hookState.macroKey.removeLast()
            }
        }
        
        // Add new characters
        hookState.macroKey.append(contentsOf: newChars)
    }
}

// MARK: - Macro Result

extension VNEngine {
    
    /// Result of macro processing
    struct MacroResult {
        let found: Bool
        let backspaceCount: Int
        let replacementText: String
        let replacementCodes: [UInt32]
    }
    
    /// Get macro result for current buffer
    func getMacroResult() -> MacroResult {
        guard shouldUseMacro() else {
            return MacroResult(found: false, backspaceCount: 0, replacementText: "", replacementCodes: [])
        }
        
        if let macroContent = macroManager.findMacro(key: hookState.macroKey) {
            // Convert codes to string
            var text = ""
            for code in macroContent {
                let charValue = code & 0xFFFF
                if let scalar = UnicodeScalar(charValue) {
                    text.append(Character(scalar))
                }
            }
            
            return MacroResult(
                found: true,
                backspaceCount: hookState.macroKey.count,
                replacementText: text,
                replacementCodes: macroContent
            )
        }
        
        return MacroResult(found: false, backspaceCount: 0, replacementText: "", replacementCodes: [])
    }
}
