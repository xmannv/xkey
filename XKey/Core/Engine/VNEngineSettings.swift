//
//  VNEngineSettings.swift
//  XKey
//
//  Settings structure for VNEngine
//

import Foundation

extension VNEngine {
    
    /// Settings structure for configuring the engine
    struct EngineSettings {
        // Basic settings
        var inputMethod: InputMethod = .telex
        var codeTable: CodeTable = .unicode
        var modernStyle: Bool = true
        var spellCheckEnabled: Bool = true
        var fixAutocomplete: Bool = true
        var freeMarking: Bool = false
        
        // Advanced features
        var quickTelexEnabled: Bool = true
        var quickStartConsonantEnabled: Bool = false
        var quickEndConsonantEnabled: Bool = false
        var upperCaseFirstChar: Bool = false
        var restoreIfWrongSpelling: Bool = true
        var allowConsonantZFWJ: Bool = false
        var tempOffSpellingEnabled: Bool = false
        var tempOffEngineEnabled: Bool = false
        
        // Macro settings
        var macroEnabled: Bool = false
        var macroInEnglishMode: Bool = false
        var autoCapsMacro: Bool = false
        
        // Smart switch
        var smartSwitchEnabled: Bool = false
    }
    
    /// Update engine settings
    func updateSettings(_ settings: EngineSettings) {
        // Map InputMethod to vInputType
        switch settings.inputMethod {
        case .telex:
            vInputType = 0
        case .vni:
            vInputType = 1
        case .simpleTelex1:
            vInputType = 2
        case .simpleTelex2:
            vInputType = 3
        }
        
        // Map CodeTable to vCodeTable
        vCodeTable = settings.codeTable.rawValue
        
        // Basic settings
        vUseModernOrthography = settings.modernStyle ? 1 : 0
        vCheckSpelling = settings.spellCheckEnabled ? 1 : 0
        vFixRecommendBrowser = settings.fixAutocomplete ? 1 : 0
        
        // Advanced features
        vQuickTelex = settings.quickTelexEnabled ? 1 : 0
        vQuickStartConsonant = settings.quickStartConsonantEnabled ? 1 : 0
        vQuickEndConsonant = settings.quickEndConsonantEnabled ? 1 : 0
        vUpperCaseFirstChar = settings.upperCaseFirstChar ? 1 : 0
        vRestoreIfWrongSpelling = settings.restoreIfWrongSpelling ? 1 : 0
        vAllowConsonantZFWJ = settings.allowConsonantZFWJ ? 1 : 0
        vFreeMark = settings.freeMarking ? 1 : 0
        vTempOffSpelling = settings.tempOffSpellingEnabled ? 1 : 0
        vTempOffOpenKey = settings.tempOffEngineEnabled ? 1 : 0
        
        // Macro settings
        vUseMacro = settings.macroEnabled ? 1 : 0
        vUseMacroInEnglishMode = settings.macroInEnglishMode ? 1 : 0
        vAutoCapsMacro = settings.autoCapsMacro ? 1 : 0
        
        // Smart switch
        vUseSmartSwitchKey = settings.smartSwitchEnabled ? 1 : 0
    }
    
    /// Get current settings
    var settings: EngineSettings {
        var settings = EngineSettings()
        
        // Map vInputType to InputMethod
        switch vInputType {
        case 0:
            settings.inputMethod = .telex
        case 1:
            settings.inputMethod = .vni
        case 2:
            settings.inputMethod = .simpleTelex1
        case 3:
            settings.inputMethod = .simpleTelex2
        default:
            settings.inputMethod = .telex
        }
        
        // Map vCodeTable to CodeTable
        settings.codeTable = CodeTable(rawValue: vCodeTable) ?? .unicode
        
        // Basic settings
        settings.modernStyle = vUseModernOrthography == 1
        settings.spellCheckEnabled = vCheckSpelling == 1
        settings.fixAutocomplete = vFixRecommendBrowser == 1
        
        // Advanced features
        settings.quickTelexEnabled = vQuickTelex == 1
        settings.quickStartConsonantEnabled = vQuickStartConsonant == 1
        settings.quickEndConsonantEnabled = vQuickEndConsonant == 1
        settings.upperCaseFirstChar = vUpperCaseFirstChar == 1
        settings.restoreIfWrongSpelling = vRestoreIfWrongSpelling == 1
        settings.allowConsonantZFWJ = vAllowConsonantZFWJ == 1
        settings.freeMarking = vFreeMark == 1
        settings.tempOffSpellingEnabled = vTempOffSpelling == 1
        settings.tempOffEngineEnabled = vTempOffOpenKey == 1
        
        // Macro settings
        settings.macroEnabled = vUseMacro == 1
        settings.macroInEnglishMode = vUseMacroInEnglishMode == 1
        settings.autoCapsMacro = vAutoCapsMacro == 1
        
        // Smart switch
        settings.smartSwitchEnabled = vUseSmartSwitchKey == 1
        
        return settings
    }
}
