//
//  TranslationToolbarViewModel.swift
//  XKey
//
//  ViewModel for the Translation Toolbar
//

import Foundation
import Combine

class TranslationToolbarViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Current source language code
    @Published var sourceLanguageCode: String = "auto"
    
    /// Current target language code
    @Published var targetLanguageCode: String = "vi"
    
    /// Whether the translation is in progress
    @Published var isTranslating: Bool = false
    
    /// Whether to show source language picker popover
    @Published var showSourcePicker: Bool = false
    
    /// Whether to show target language picker popover
    @Published var showTargetPicker: Bool = false
    
    // MARK: - Computed Properties
    
    /// Current source language
    var sourceLanguage: TranslationLanguage {
        TranslationLanguage.find(byCode: sourceLanguageCode)
    }
    
    /// Current target language
    var targetLanguage: TranslationLanguage {
        TranslationLanguage.find(byCode: targetLanguageCode)
    }
    
    /// Language presets for source (includes auto-detect)
    var sourcePresets: [TranslationLanguage] {
        TranslationLanguage.sourcePresets
    }
    
    /// Language presets for target (excludes auto-detect)
    var targetPresets: [TranslationLanguage] {
        TranslationLanguage.targetPresets
    }
    
    // MARK: - Callbacks
    
    /// Called when source language changes
    var onSourceLanguageChange: ((String) -> Void)?
    
    /// Called when target language changes
    var onTargetLanguageChange: ((String) -> Void)?
    
    /// Called when translate button is pressed
    var onTranslateRequested: (() -> Void)?
    
    /// Called when swap languages is requested
    var onSwapLanguages: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Don't load preferences here - they will be loaded by the controller
        // when show() is called. This avoids unnecessary SharedSettings access
        // if the toolbar is never used.
    }
    
    func loadFromPreferences() {
        let preferences = SharedSettings.shared.loadPreferences()
        sourceLanguageCode = preferences.translationSourceLanguageCode
        targetLanguageCode = preferences.translationTargetLanguageCode
    }
    
    // MARK: - Actions
    
    func setSourceLanguage(_ code: String) {
        sourceLanguageCode = code
        onSourceLanguageChange?(code)
        
        // Save to preferences
        var preferences = SharedSettings.shared.loadPreferences()
        preferences.translationSourceLanguageCode = code
        SharedSettings.shared.savePreferences(preferences)
    }
    
    func setTargetLanguage(_ code: String) {
        targetLanguageCode = code
        onTargetLanguageChange?(code)
        
        // Save to preferences
        var preferences = SharedSettings.shared.loadPreferences()
        preferences.translationTargetLanguageCode = code
        SharedSettings.shared.savePreferences(preferences)
    }
    
    func swapLanguages() {
        // Can't swap if source is auto-detect
        guard sourceLanguageCode != "auto" else { return }
        
        let temp = sourceLanguageCode
        sourceLanguageCode = targetLanguageCode
        targetLanguageCode = temp
        
        // Save to preferences
        var preferences = SharedSettings.shared.loadPreferences()
        preferences.translationSourceLanguageCode = sourceLanguageCode
        preferences.translationTargetLanguageCode = targetLanguageCode
        SharedSettings.shared.savePreferences(preferences)
        
        onSwapLanguages?()
    }
    
    func translate() {
        onTranslateRequested?()
    }
    
    func toggleSourcePicker() {
        showSourcePicker.toggle()
        showTargetPicker = false
    }
    
    func toggleTargetPicker() {
        showTargetPicker.toggle()
        showSourcePicker = false
    }
    
    func closePickers() {
        showSourcePicker = false
        showTargetPicker = false
    }
}
