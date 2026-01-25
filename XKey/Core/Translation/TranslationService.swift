//
//  TranslationService.swift
//  XKey
//
//  Main Translation Service - Manages providers and handles translation requests
//

import Foundation
import Cocoa

// MARK: - Translation Service

class TranslationService {
    
    // MARK: - Singleton
    
    static let shared = TranslationService()
    
    // MARK: - Properties
    
    /// All available providers - lazily initialized to reduce memory footprint
    private(set) lazy var providers: [TranslationProvider] = {
        // Create providers only when first accessed
        let providerList: [TranslationProvider] = [
            GoogleTranslateProvider(),
            TencentTransmartProvider(),
            VolcanoEngineProvider()
        ]
        
        // Setup default configs for each provider
        for (index, provider) in providerList.enumerated() {
            if self._providerConfigs[provider.id] == nil {
                self._providerConfigs[provider.id] = TranslationProviderConfig(
                    id: provider.id,
                    isEnabled: provider.isEnabled,
                    priority: index
                )
            }
            log("Registered translation provider: \(provider.name)")
        }
        
        return providerList
    }()
    
    /// Provider configurations storage (for enable/disable state)
    private var _providerConfigs: [String: TranslationProviderConfig] = [:]
    
    /// Provider configurations accessor
    private var providerConfigs: [String: TranslationProviderConfig] {
        get {
            // Ensure configs are loaded
            if !_configsLoaded {
                loadProviderConfigs()
            }
            return _providerConfigs
        }
        set {
            _providerConfigs = newValue
        }
    }
    
    /// Whether configs have been loaded from UserDefaults
    private var _configsLoaded = false
    
    /// Callback for logging (optional)
    var logCallback: ((String) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        // Lazy initialization - providers will be created when first accessed
        // This saves ~20-30MB of memory until translation is actually needed
    }
    
    // MARK: - Provider Management
    
    /// Register a new translation provider
    func registerProvider(_ provider: TranslationProvider) {
        // Remove existing provider with same ID
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        
        // Create default config if not exists
        if providerConfigs[provider.id] == nil {
            providerConfigs[provider.id] = TranslationProviderConfig(
                id: provider.id,
                isEnabled: provider.isEnabled,
                priority: providers.count - 1
            )
        }
        
        log("Registered translation provider: \(provider.name)")
    }
    
    /// Get all providers sorted by priority
    var sortedProviders: [TranslationProvider] {
        return providers.sorted { provider1, provider2 in
            let priority1 = providerConfigs[provider1.id]?.priority ?? Int.max
            let priority2 = providerConfigs[provider2.id]?.priority ?? Int.max
            return priority1 < priority2
        }
    }
    
    /// Get enabled providers sorted by priority
    var enabledProviders: [TranslationProvider] {
        return sortedProviders.filter { provider in
            return providerConfigs[provider.id]?.isEnabled ?? provider.isEnabled
        }
    }
    
    /// Check if a provider is enabled
    func isProviderEnabled(_ providerId: String) -> Bool {
        return providerConfigs[providerId]?.isEnabled ?? true
    }
    
    /// Enable/disable a provider
    func setProviderEnabled(_ providerId: String, enabled: Bool) {
        if var config = providerConfigs[providerId] {
            config.isEnabled = enabled
            providerConfigs[providerId] = config
        } else {
            providerConfigs[providerId] = TranslationProviderConfig(id: providerId, isEnabled: enabled)
        }
        saveProviderConfigs()
        log("Provider \(providerId) enabled: \(enabled)")
    }
    
    // MARK: - Translation
    
    /// Translate text using the first available enabled provider
    /// - Parameters:
    ///   - text: The text to translate
    ///   - sourceLanguageCode: ISO 639-1 source language code (default: "auto")
    ///   - targetLanguageCode: ISO 639-1 target language code
    func translate(
        text: String,
        from sourceLanguageCode: String = "auto",
        to targetLanguageCode: String
    ) async throws -> TranslationResult {
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyText
        }
        
        let enabled = enabledProviders
        guard !enabled.isEmpty else {
            throw TranslationError.providerDisabled
        }
        
        log("Translating '\(text.prefix(50))...' from \(sourceLanguageCode) to \(targetLanguageCode)")
        
        // Try each provider in order until one succeeds
        var lastError: Error?
        for provider in enabled {
            do {
                let result = try await provider.translate(
                    text: text,
                    from: sourceLanguageCode,
                    to: targetLanguageCode
                )
                log("Translation successful via \(provider.name): '\(result.translatedText.prefix(50))...'")
                return result
            } catch {
                log("Provider \(provider.name) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        throw lastError ?? TranslationError.unknown("All providers failed")
    }
    
    /// Translate using TranslationLanguage objects (convenience method)
    func translate(
        text: String,
        from sourceLanguage: TranslationLanguage,
        to targetLanguage: TranslationLanguage
    ) async throws -> TranslationResult {
        return try await translate(
            text: text,
            from: sourceLanguage.code,
            to: targetLanguage.code
        )
    }
    
    // MARK: - AX Text Reading
    
    /// Source of the retrieved text
    enum TextSource {
        case selection       // Text was selected by user
        case clipboard       // Text was copied via Cmd+C
        case fullValue       // Entire text field value (no selection)
    }
    
    /// Result of text retrieval including source information
    struct TextRetrievalResult {
        let text: String
        let source: TextSource
        
        /// Whether to use select-all before paste when replacing
        var needsSelectAllForReplace: Bool {
            return source == .fullValue
        }
    }
    
    /// Read selected text from the focused application using Accessibility API
    /// Falls back to Cmd+C (copy) if AX fails
    func getSelectedText() -> String? {
        return getSelectedTextWithSource()?.text
    }
    
    /// Read selected text with source information
    /// Returns both the text and how it was retrieved
    func getSelectedTextWithSource() -> TextRetrievalResult? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            log("Cannot get focused element, trying clipboard fallback")
            if let text = getTextViaClipboard() {
                return TextRetrievalResult(text: text, source: .clipboard)
            }
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // First, try to get selected text directly via AX
        var selectedTextValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let selectedText = selectedTextValue as? String,
           !selectedText.isEmpty {
            log("Got selected text via AX: '\(selectedText.prefix(50))...'")
            return TextRetrievalResult(text: selectedText, source: .selection)
        }
        
        // If no selection via AX, try clipboard fallback (Cmd+C)
        log("No AX selection, trying clipboard fallback")
        if let text = getTextViaClipboard() {
            return TextRetrievalResult(text: text, source: .clipboard)
        }
        
        // Last resort: get entire value (for text fields/areas)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
           let fullText = valueRef as? String,
           !fullText.isEmpty {
            log("Got full text value: '\(fullText.prefix(50))...'")
            return TextRetrievalResult(text: fullText, source: .fullValue)
        }
        
        log("No text found in focused element")
        return nil
    }
    
    /// Get text by simulating Cmd+C and reading clipboard
    private func getTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        
        // Get frontmost app PID
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            log("Clipboard fallback: no frontmost app")
            return nil
        }
        let pid = frontmostApp.processIdentifier
        log("Clipboard fallback: targeting \(frontmostApp.bundleIdentifier ?? "Unknown") (PID: \(pid))")
        
        // Save current clipboard
        let oldContent = pasteboard.string(forType: .string)
        log("Clipboard fallback: saved old content (\(oldContent?.count ?? 0) chars)")
        
        // Clear clipboard
        pasteboard.clearContents()
        
        // Simulate Cmd+C - use combinedSessionState for better compatibility
        let source = CGEventSource(stateID: .combinedSessionState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            log("Clipboard fallback: failed to create CGEvent")
            return nil
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post directly to the frontmost app's PID
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        
        log("Clipboard fallback: Cmd+C posted to PID \(pid), waiting...")
        
        // Wait for clipboard to update (longer for slower apps)
        Thread.sleep(forTimeInterval: 0.2)
        
        // Get text from clipboard
        let copiedText = pasteboard.string(forType: .string)
        log("Clipboard fallback: got '\(copiedText?.prefix(30) ?? "nil")' (\(copiedText?.count ?? 0) chars)")
        
        // Restore old clipboard
        if let old = oldContent {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
            log("Clipboard fallback: restored old content")
        }
        
        if let text = copiedText, !text.isEmpty {
            log("Got text via clipboard copy: '\(text.prefix(50))...'")
            return text
        }
        
        log("Clipboard fallback: no text copied (nothing selected?)")
        return nil
    }
    
    // MARK: - Case Preservation
    
    /// Preserve the case pattern from original text to translated text
    func preserveCase(original: String, translated: String) -> String {
        guard !original.isEmpty && !translated.isEmpty else {
            return translated
        }
        
        // Detect case pattern of original text
        let isAllUppercase = original == original.uppercased() && original != original.lowercased()
        let isAllLowercase = original == original.lowercased() && original != original.uppercased()
        let isCapitalized = original.first?.isUppercase == true && 
                           original.dropFirst().lowercased() == String(original.dropFirst())
        
        if isAllUppercase {
            // "ĐƯỢC" -> "OKAY"
            return translated.uppercased()
        } else if isAllLowercase {
            // "được" -> "okay"
            return translated.lowercased()
        } else if isCapitalized {
            // "Được" -> "Okay"
            return translated.prefix(1).uppercased() + translated.dropFirst().lowercased()
        } else {
            // Mixed case - keep as-is from translation
            return translated
        }
    }
    
    /// Replace selected text with translated text
    /// Uses clipboard + Cmd+V for maximum compatibility across all apps
    /// Note: AX methods return success but don't actually work for Chrome/Electron DOM-based inputs
    /// - Parameters:
    ///   - newText: The text to replace with
    ///   - selectAllBeforePaste: If true, performs Cmd+A before paste (for full text replacement)
    func replaceSelectedText(with newText: String, selectAllBeforePaste: Bool = false) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            log("Cannot get focused element for replacement")
            return false
        }
        
        let axElement = element as! AXUIElement
        
        // Get role and app info for debugging
        var roleRef: CFTypeRef?
        var role = "Unknown"
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let roleStr = roleRef as? String {
            role = roleStr
        }
        
        // Get frontmost app bundle ID
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "Unknown"
        log("Replacing text in \(bundleId), role: \(role), selectAll: \(selectAllBeforePaste)")
        
        // Check if there's a selection
        var selectedRangeValue: CFTypeRef?
        var hasSelection = false
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
            var range = CFRange()
            if let rangeValue = selectedRangeValue, AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                hasSelection = range.length > 0
                log("Selection range: location=\(range.location), length=\(range.length)")
            }
        }
        
        // If selectAllBeforePaste is requested, skip AX method and go straight to clipboard
        if selectAllBeforePaste {
            log("Using select all + clipboard paste method")
            return replaceViaClipboardPaste(newText, selectAllFirst: true)
        }
        
        // UNIVERSAL APPROACH: Try AX first, then verify, then fallback
        if hasSelection {
            // Try AX method
            let result = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
            log("AX set selected text: \(result == .success ? "reported success" : "failed (\(result.rawValue))")")
            
            if result == .success {
                // VERIFY: Check if the text actually changed
                // Some apps (Chrome, Electron) report success but don't apply the change
                Thread.sleep(forTimeInterval: 0.05) // Small delay to let the change propagate
                
                var verifyTextRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &verifyTextRef) == .success,
                   let verifyText = verifyTextRef as? String {
                    
                    // Check if selected text now matches what we set
                    // Note: After replacement, selection might be empty or contain the new text
                    if verifyText == newText || verifyText.isEmpty {
                        log("AX replacement VERIFIED - text changed")
                        return true
                    } else {
                        log("AX replacement NOT verified - text unchanged ('\(verifyText.prefix(20))...' != '\(newText.prefix(20))...')")
                        log("Falling back to clipboard + paste")
                    }
                } else {
                    // Can't verify - assume success if result was .success and we can't read selected text anymore
                    // This happens when selection is cleared after replacement
                    log("AX replacement - cannot verify (selection cleared), assuming success")
                    return true
                }
            }
        }
        
        // Fallback: Use clipboard + paste (most reliable)
        log("Using clipboard + paste method")
        return replaceViaClipboardPaste(newText, selectAllFirst: false)
    }
    
    /// Replace text using clipboard and Cmd+V paste
    /// - Parameters:
    ///   - text: The text to paste
    ///   - selectAllFirst: If true, performs Cmd+A before paste to select all text
    private func replaceViaClipboardPaste(_ text: String, selectAllFirst: Bool) -> Bool {
        // Get frontmost app PID
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            log("Paste fallback: no frontmost app")
            return false
        }
        let pid = frontmostApp.processIdentifier
        
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Use combinedSessionState for better compatibility
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // If selectAllFirst is true, perform Cmd+A first
        if selectAllFirst {
            guard let selectAllDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true),
                  let selectAllUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false) else {
                log("Failed to create Cmd+A event")
                return false
            }
            
            selectAllDown.flags = .maskCommand
            selectAllUp.flags = .maskCommand
            
            selectAllDown.postToPid(pid)
            selectAllUp.postToPid(pid)
            
            log("Cmd+A (select all) posted to PID \(pid)")
            
            // Small delay to let select all complete
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Key down V with Command
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            log("Failed to create keyDown event")
            return false
        }
        keyDown.flags = .maskCommand
        
        // Key up V with Command
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            log("Failed to create keyUp event")
            return false
        }
        keyUp.flags = .maskCommand
        
        // Post events directly to the frontmost app's PID
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        
        log("Clipboard paste executed to PID \(pid)")
        
        // Optionally restore old clipboard after a delay
        if let old = oldContent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
        
        return true
    }
    
    // MARK: - Persistence
    
    private func loadProviderConfigs() {
        guard !_configsLoaded else { return }
        _configsLoaded = true
        
        if let data = UserDefaults.standard.data(forKey: "TranslationProviderConfigs"),
           let configs = try? JSONDecoder().decode([TranslationProviderConfig].self, from: data) {
            _providerConfigs = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
            log("Loaded \(configs.count) provider configs")
        }
    }
    
    private func saveProviderConfigs() {
        let configs = Array(_providerConfigs.values)
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "TranslationProviderConfigs")
        }
    }
    
    // MARK: - Logging
    
    private func log(_ message: String) {
        logCallback?("[Translation] \(message)")
    }
}
