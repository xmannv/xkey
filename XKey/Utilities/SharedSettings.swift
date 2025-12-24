//
//  SharedSettings.swift
//  XKey
//
//  Shared settings between XKey (menu bar) and XKeyIM (Input Method)
//  Uses App Group for cross-app communication
//

import Foundation

/// App Group identifier for sharing data between XKey and XKeyIM
/// Note: macOS Sequoia+ requires TeamID prefix for native apps distributed outside App Store
let kXKeyAppGroup = "7E6Z9B4F2H.com.codetay.inputmethod.XKey"

/// Keys for shared settings
enum SharedSettingsKey: String {
    // Hotkey settings
    case toggleHotkeyCode = "XKey.toggleHotkeyCode"
    case toggleHotkeyModifiers = "XKey.toggleHotkeyModifiers"
    case toggleHotkeyIsModifierOnly = "XKey.toggleHotkeyIsModifierOnly"
    case undoTypingEnabled = "XKey.undoTypingEnabled"
    case beepOnToggle = "XKey.beepOnToggle"

    // Input settings
    case inputMethod = "XKey.inputMethod"
    case codeTable = "XKey.codeTable"
    case modernStyle = "XKey.modernStyle"
    case spellCheckEnabled = "XKey.spellCheckEnabled"
    case fixAutocomplete = "XKey.fixAutocomplete"

    // Advanced settings
    case quickTelexEnabled = "XKey.quickTelexEnabled"
    case quickStartConsonantEnabled = "XKey.quickStartConsonantEnabled"
    case quickEndConsonantEnabled = "XKey.quickEndConsonantEnabled"
    case upperCaseFirstChar = "XKey.upperCaseFirstChar"
    case restoreIfWrongSpelling = "XKey.restoreIfWrongSpelling"
    case instantRestoreOnWrongSpelling = "XKey.instantRestoreOnWrongSpelling"

    case allowConsonantZFWJ = "XKey.allowConsonantZFWJ"
    case freeMarkEnabled = "XKey.freeMarkEnabled"
    case tempOffSpellingEnabled = "XKey.tempOffSpellingEnabled"
    case tempOffEngineEnabled = "XKey.tempOffEngineEnabled"

    // Macro settings
    case macroEnabled = "XKey.macroEnabled"
    case macroInEnglishMode = "XKey.macroInEnglishMode"
    case autoCapsMacro = "XKey.autoCapsMacro"
    case macros = "XKey.macros"

    // Smart switch settings
    case smartSwitchEnabled = "XKey.smartSwitchEnabled"
    case detectOverlayApps = "XKey.detectOverlayApps"

    // Debug settings
    case debugModeEnabled = "XKey.debugModeEnabled"

    // IMKit settings
    case imkitEnabled = "XKey.imkitEnabled"
    case imkitUseMarkedText = "XKey.imkitUseMarkedText"
    case switchToXKeyHotkeyCode = "XKey.switchToXKeyHotkeyCode"
    case switchToXKeyHotkeyModifiers = "XKey.switchToXKeyHotkeyModifiers"
    case switchToXKeyHotkeyIsModifierOnly = "XKey.switchToXKeyHotkeyIsModifierOnly"

    // UI settings
    case showDockIcon = "XKey.showDockIcon"
    case startAtLogin = "XKey.startAtLogin"
    case menuBarIconStyle = "XKey.menuBarIconStyle"

    // Excluded apps
    case excludedApps = "XKey.excludedApps"

    // Input Source Management
    case inputSourceConfig = "XKey.inputSourceConfig"
    
    // Local data (macros, window title rules)
    case macrosData = "XKey.macrosData"
    case windowTitleRules = "XKey.windowTitleRules"
    case disabledBuiltInRules = "XKey.disabledBuiltInRules"
    
    // User dictionary (custom words to skip spell check)
    case userDictionaryWords = "XKey.userDictionaryWords"
}

// Note: Logging functions (logError, logWarning, etc.) are provided by Shared/DebugLogger.swift

/// Manager for shared settings between XKey and XKeyIM
/// ARCHITECTURE: Uses plist file directly for reliable cross-process sync
class SharedSettings {
    
    // MARK: - Singleton
    
    static let shared = SharedSettings()
    
    // MARK: - Properties

    /// Flag to prevent notification spam during batch updates
    private var isBatchUpdating: Bool = false
    
    /// Default values for settings
    private let defaultValues: [String: Any] = [
        SharedSettingsKey.inputMethod.rawValue: InputMethod.telex.rawValue,
        SharedSettingsKey.codeTable.rawValue: CodeTable.unicode.rawValue,
        SharedSettingsKey.modernStyle.rawValue: false,
        SharedSettingsKey.spellCheckEnabled.rawValue: false,
        SharedSettingsKey.quickTelexEnabled.rawValue: false,
        SharedSettingsKey.restoreIfWrongSpelling.rawValue: true,
        SharedSettingsKey.freeMarkEnabled.rawValue: false,
        SharedSettingsKey.imkitUseMarkedText.rawValue: true,
        SharedSettingsKey.fixAutocomplete.rawValue: true
    ]
    
    /// Cache of plist URL (computed once)
    private lazy var plistURL: URL? = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kXKeyAppGroup) else {
            sharedLogWarning("Cannot get App Group container URL")
            return nil
        }
        
        let prefsDir = containerURL.appendingPathComponent("Library/Preferences")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        
        return prefsDir.appendingPathComponent("\(kXKeyAppGroup).plist")
    }()
    
    // MARK: - Initialization

    private init() {
        // No migration needed - plist is the only source of truth
    }

    // MARK: - Plist Read/Write Helpers
    
    /// Read the entire plist dictionary
    private func readPlistDict() -> [String: Any] {
        guard let url = plistURL,
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return dict
    }
    
    /// Write the entire plist dictionary
    private func writePlistDict(_ dict: [String: Any]) {
        guard let url = plistURL else { return }
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
            try data.write(to: url)
        } catch {
            sharedLogError("Failed to write plist: \(error)")
        }
    }
    
    /// Read a Bool value from plist
    private func readBool(forKey key: String) -> Bool {
        let dict = readPlistDict()
        
        if let value = dict[key] as? Bool {
            return value
        }
        if let value = dict[key] as? Int {
            return value != 0
        }
        
        // Return default value if key not found
        return defaultValues[key] as? Bool ?? false
    }
    
    /// Write a Bool value to plist
    private func writeBool(_ value: Bool, forKey key: String) {
        var dict = readPlistDict()
        dict[key] = value
        writePlistDict(dict)
    }
    
    /// Read an Int value from plist
    private func readInt(forKey key: String) -> Int {
        let dict = readPlistDict()
        
        if let value = dict[key] as? Int {
            return value
        }
        
        // Return default value if key not found
        return defaultValues[key] as? Int ?? 0
    }
    
    /// Write an Int value to plist
    private func writeInt(_ value: Int, forKey key: String) {
        var dict = readPlistDict()
        dict[key] = value
        writePlistDict(dict)
    }
    
    /// Read a String value from plist
    private func readString(forKey key: String) -> String? {
        let dict = readPlistDict()
        return dict[key] as? String
    }
    
    /// Write a String value to plist
    private func writeString(_ value: String, forKey key: String) {
        var dict = readPlistDict()
        dict[key] = value
        writePlistDict(dict)
    }
    
    /// Read a Data value from plist
    private func readData(forKey key: String) -> Data? {
        let dict = readPlistDict()
        return dict[key] as? Data
    }
    
    /// Write a Data value to plist
    private func writeData(_ value: Data, forKey key: String) {
        var dict = readPlistDict()
        dict[key] = value
        writePlistDict(dict)
    }
    
    // MARK: - Hotkey Settings

    var toggleHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.toggleHotkeyCode.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleHotkeyCode.rawValue) }
    }

    var toggleHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.toggleHotkeyModifiers.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleHotkeyModifiers.rawValue) }
    }

    var toggleHotkeyIsModifierOnly: Bool {
        get { readBool(forKey: SharedSettingsKey.toggleHotkeyIsModifierOnly.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.toggleHotkeyIsModifierOnly.rawValue) }
    }

    var undoTypingEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.undoTypingEnabled.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.undoTypingEnabled.rawValue) }
    }

    var beepOnToggle: Bool {
        get { readBool(forKey: SharedSettingsKey.beepOnToggle.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.beepOnToggle.rawValue) }
    }

    // MARK: - Input Method Settings

    var inputMethod: Int {
        get { readInt(forKey: SharedSettingsKey.inputMethod.rawValue) }
        set {
            writeInt(newValue, forKey: SharedSettingsKey.inputMethod.rawValue)
            notifySettingsChanged()
        }
    }

    var codeTable: Int {
        get { readInt(forKey: SharedSettingsKey.codeTable.rawValue) }
        set {
            writeInt(newValue, forKey: SharedSettingsKey.codeTable.rawValue)
            notifySettingsChanged()
        }
    }

    var modernStyle: Bool {
        get { readBool(forKey: SharedSettingsKey.modernStyle.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.modernStyle.rawValue)
            notifySettingsChanged()
        }
    }

    var spellCheckEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.spellCheckEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.spellCheckEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var fixAutocomplete: Bool {
        get { readBool(forKey: SharedSettingsKey.fixAutocomplete.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.fixAutocomplete.rawValue) }
    }

    // MARK: - Advanced Settings

    var quickTelexEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.quickTelexEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.quickTelexEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var quickStartConsonantEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.quickStartConsonantEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.quickStartConsonantEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var quickEndConsonantEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.quickEndConsonantEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.quickEndConsonantEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var upperCaseFirstChar: Bool {
        get { readBool(forKey: SharedSettingsKey.upperCaseFirstChar.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.upperCaseFirstChar.rawValue) }
    }

    var restoreIfWrongSpelling: Bool {
        get { readBool(forKey: SharedSettingsKey.restoreIfWrongSpelling.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.restoreIfWrongSpelling.rawValue)
            notifySettingsChanged()
        }
    }

    var instantRestoreOnWrongSpelling: Bool {
        get { readBool(forKey: SharedSettingsKey.instantRestoreOnWrongSpelling.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.instantRestoreOnWrongSpelling.rawValue)
            notifySettingsChanged()
        }
    }



    var allowConsonantZFWJ: Bool {
        get { readBool(forKey: SharedSettingsKey.allowConsonantZFWJ.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.allowConsonantZFWJ.rawValue) }
    }

    var freeMarkEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.freeMarkEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.freeMarkEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var tempOffSpellingEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.tempOffSpellingEnabled.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.tempOffSpellingEnabled.rawValue) }
    }

    var tempOffEngineEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.tempOffEngineEnabled.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.tempOffEngineEnabled.rawValue) }
    }

    // MARK: - Macro Settings

    var macroEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.macroEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.macroEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var macroInEnglishMode: Bool {
        get { readBool(forKey: SharedSettingsKey.macroInEnglishMode.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.macroInEnglishMode.rawValue) }
    }

    var autoCapsMacro: Bool {
        get { readBool(forKey: SharedSettingsKey.autoCapsMacro.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.autoCapsMacro.rawValue) }
    }

    func getMacros() -> Data? {
        return readData(forKey: SharedSettingsKey.macros.rawValue)
    }

    func setMacros(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.macros.rawValue)
        notifySettingsChanged()
    }

    // MARK: - Smart Switch Settings

    var smartSwitchEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.smartSwitchEnabled.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.smartSwitchEnabled.rawValue) }
    }

    var detectOverlayApps: Bool {
        get { readBool(forKey: SharedSettingsKey.detectOverlayApps.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.detectOverlayApps.rawValue) }
    }

    // MARK: - Debug Settings

    var debugModeEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.debugModeEnabled.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.debugModeEnabled.rawValue) }
    }

    // MARK: - IMKit Settings

    var imkitEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.imkitEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.imkitEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var imkitUseMarkedText: Bool {
        get { readBool(forKey: SharedSettingsKey.imkitUseMarkedText.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.imkitUseMarkedText.rawValue)
            notifySettingsChanged()
        }
    }

    var switchToXKeyHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.switchToXKeyHotkeyCode.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.switchToXKeyHotkeyCode.rawValue) }
    }

    var switchToXKeyHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.switchToXKeyHotkeyModifiers.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.switchToXKeyHotkeyModifiers.rawValue) }
    }

    var switchToXKeyHotkeyIsModifierOnly: Bool {
        get { readBool(forKey: SharedSettingsKey.switchToXKeyHotkeyIsModifierOnly.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.switchToXKeyHotkeyIsModifierOnly.rawValue) }
    }

    // MARK: - UI Settings

    var showDockIcon: Bool {
        get { readBool(forKey: SharedSettingsKey.showDockIcon.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.showDockIcon.rawValue) }
    }

    var startAtLogin: Bool {
        get { readBool(forKey: SharedSettingsKey.startAtLogin.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.startAtLogin.rawValue) }
    }

    var menuBarIconStyle: String {
        get { readString(forKey: SharedSettingsKey.menuBarIconStyle.rawValue) ?? "X" }
        set { writeString(newValue, forKey: SharedSettingsKey.menuBarIconStyle.rawValue) }
    }

    // MARK: - Excluded Apps

    func getExcludedApps() -> Data? {
        return readData(forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    func setExcludedApps(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    // MARK: - Input Source Management

    func getInputSourceConfig() -> Data? {
        return readData(forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }

    func setInputSourceConfig(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }
    
    // MARK: - Macros Data
    
    func getMacrosData() -> Data? {
        return readData(forKey: SharedSettingsKey.macrosData.rawValue)
    }
    
    func setMacrosData(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.macrosData.rawValue)
    }
    
    // MARK: - Window Title Rules
    
    func getWindowTitleRulesData() -> Data? {
        return readData(forKey: SharedSettingsKey.windowTitleRules.rawValue)
    }
    
    func setWindowTitleRulesData(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.windowTitleRules.rawValue)
    }
    
    // MARK: - Disabled Built-in Rules
    
    /// Get the list of disabled built-in rule names
    func getDisabledBuiltInRules() -> Set<String> {
        guard let data = readData(forKey: SharedSettingsKey.disabledBuiltInRules.rawValue),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }
    
    /// Set the list of disabled built-in rule names
    func setDisabledBuiltInRules(_ names: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(names)) {
            writeData(data, forKey: SharedSettingsKey.disabledBuiltInRules.rawValue)
        }
    }
    
    // MARK: - User Dictionary (Custom Words)
    
    /// Get the list of user-defined words (to skip spell check)
    func getUserDictionaryWords() -> Set<String> {
        guard let data = readData(forKey: SharedSettingsKey.userDictionaryWords.rawValue),
              let words = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(words)
    }
    
    /// Set the list of user-defined words
    func setUserDictionaryWords(_ words: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(words).sorted()) {
            writeData(data, forKey: SharedSettingsKey.userDictionaryWords.rawValue)
            notifySettingsChanged()
        }
    }
    
    /// Add a word to the user dictionary
    func addUserDictionaryWord(_ word: String) {
        var words = getUserDictionaryWords()
        words.insert(word.lowercased().trimmingCharacters(in: .whitespaces))
        setUserDictionaryWords(words)
    }
    
    /// Remove a word from the user dictionary
    func removeUserDictionaryWord(_ word: String) {
        var words = getUserDictionaryWords()
        words.remove(word.lowercased().trimmingCharacters(in: .whitespaces))
        setUserDictionaryWords(words)
    }
    
    /// Check if a word exists in the user dictionary
    func isWordInUserDictionary(_ word: String) -> Bool {
        let words = getUserDictionaryWords()
        return words.contains(word.lowercased().trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Sync

    /// Synchronize settings to disk
    /// Note: With plist-only approach, settings are written immediately
    /// This function is kept for compatibility but does nothing
    func synchronize() {
        // No-op: plist writes are immediate
    }
    
    /// Force write all current settings to plist file
    /// This is used before Sparkle restarts the app after an update
    /// to ensure settings are saved to the current App Group container
    /// In case of App Group path change between versions, this ensures
    /// settings are written to the correct location
    func forceWriteCurrentSettings() {
        // Read the current plist dictionary
        let currentDict = readPlistDict()
        
        // If nothing to save, skip
        guard !currentDict.isEmpty else {
            sharedLogWarning("forceWriteCurrentSettings: No settings to save")
            return
        }
        
        // Force write it back to ensure the file exists and is up-to-date
        writePlistDict(currentDict)
        
        sharedLogSuccess("Force saved \(currentDict.count) settings to plist")
    }

    /// Notify that settings have changed (for observers)
    private func notifySettingsChanged() {
        // Skip notification if we're in batch update mode
        guard !isBatchUpdating else { return }

        // Post notification for local observers
        NotificationCenter.default.post(
            name: .sharedSettingsDidChange,
            object: nil
        )

        // Post distributed notification for cross-app communication
        DistributedNotificationCenter.default().post(
            name: .xkeySettingsDidChange,
            object: nil
        )
    }
    
    // MARK: - Export/Import Settings
    
    /// Export all settings to a plist file
    /// - Returns: The exported plist data (XML format for human readability), or nil if export failed
    func exportSettings() -> Data? {
        var exportDict = readPlistDict()
        
        // Add metadata for version tracking
        exportDict["_exportVersion"] = 1
        exportDict["_exportDate"] = ISO8601DateFormatter().string(from: Date())
        exportDict["_appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        // Convert to XML plist for human readability
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: exportDict, format: .xml, options: 0)
            return data
        } catch {
            sharedLogError("Failed to export settings: \(error)")
            return nil
        }
    }
    
    /// Import settings from a plist file
    /// - Parameter data: The plist data to import
    /// - Returns: True if import was successful
    @discardableResult
    func importSettings(from data: Data) -> Bool {
        do {
            guard var importDict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                sharedLogError("Invalid plist format")
                return false
            }
            
            // Remove metadata keys before writing
            importDict.removeValue(forKey: "_exportVersion")
            importDict.removeValue(forKey: "_exportDate")
            importDict.removeValue(forKey: "_appVersion")
            
            // Write all settings
            writePlistDict(importDict)
            sharedLogSuccess("Imported settings successfully")
            
            // Notify observers
            notifySettingsChanged()
            // Post macros notification if available (XKey only, not XKeyIM)
            if let macrosNotification = Notification.Name(rawValue: "XKey.macrosDidChange") as Notification.Name? {
                NotificationCenter.default.post(name: macrosNotification, object: nil)
            }
            
            return true
        } catch {
            sharedLogError("Failed to import settings: \(error)")
            return false
        }
    }
    
    /// Get the suggested filename for export
    func getExportFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return "XKey-Settings-\(dateString).plist"
    }
    
    // MARK: - Load/Save Preferences Object

    /// Load all settings as a Preferences object
    func loadPreferences() -> Preferences {
        var prefs = Preferences()

        // Hotkey settings
        let hotkeyCode = toggleHotkeyCode
        let hotkeyModifiers = toggleHotkeyModifiers
        if hotkeyCode != 0 || hotkeyModifiers != 0 {
            prefs.toggleHotkey = Hotkey(
                keyCode: hotkeyCode,
                modifiers: ModifierFlags(rawValue: hotkeyModifiers),
                isModifierOnly: toggleHotkeyIsModifierOnly
            )
        }
        prefs.undoTypingEnabled = undoTypingEnabled
        prefs.beepOnToggle = beepOnToggle

        // Input settings
        if let method = InputMethod(rawValue: inputMethod) {
            prefs.inputMethod = method
        }
        if let table = CodeTable(rawValue: codeTable) {
            prefs.codeTable = table
        }
        prefs.modernStyle = modernStyle
        prefs.spellCheckEnabled = spellCheckEnabled
        prefs.fixAutocomplete = fixAutocomplete

        // Advanced settings
        prefs.quickTelexEnabled = quickTelexEnabled
        prefs.quickStartConsonantEnabled = quickStartConsonantEnabled
        prefs.quickEndConsonantEnabled = quickEndConsonantEnabled
        prefs.upperCaseFirstChar = upperCaseFirstChar
        prefs.restoreIfWrongSpelling = restoreIfWrongSpelling
        prefs.instantRestoreOnWrongSpelling = instantRestoreOnWrongSpelling

        prefs.allowConsonantZFWJ = allowConsonantZFWJ
        prefs.freeMarkEnabled = freeMarkEnabled
        prefs.tempOffSpellingEnabled = tempOffSpellingEnabled
        prefs.tempOffEngineEnabled = tempOffEngineEnabled

        // Macro settings
        prefs.macroEnabled = macroEnabled
        prefs.macroInEnglishMode = macroInEnglishMode
        prefs.autoCapsMacro = autoCapsMacro

        // Smart switch
        prefs.smartSwitchEnabled = smartSwitchEnabled
        prefs.detectOverlayApps = detectOverlayApps

        // Debug
        prefs.debugModeEnabled = debugModeEnabled

        // IMKit
        prefs.imkitEnabled = imkitEnabled
        prefs.imkitUseMarkedText = imkitUseMarkedText

        // Switch to XKey hotkey (optional)
        let switchHotkeyCode = switchToXKeyHotkeyCode
        let switchHotkeyModifiers = switchToXKeyHotkeyModifiers
        if switchHotkeyCode != 0 || switchHotkeyModifiers != 0 {
            prefs.switchToXKeyHotkey = Hotkey(
                keyCode: switchHotkeyCode,
                modifiers: ModifierFlags(rawValue: switchHotkeyModifiers),
                isModifierOnly: switchToXKeyHotkeyIsModifierOnly
            )
        }

        // UI settings
        prefs.showDockIcon = showDockIcon
        prefs.startAtLogin = startAtLogin
        if let style = MenuBarIconStyle(rawValue: menuBarIconStyle) {
            prefs.menuBarIconStyle = style
        }

        // Excluded apps
        if let data = getExcludedApps(),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            prefs.excludedApps = apps
        }

        return prefs
    }

    /// Save a Preferences object to shared settings
    func savePreferences(_ prefs: Preferences) {
        // Enable batch mode to prevent notification spam
        isBatchUpdating = true
        defer {
            // Always disable batch mode when done, even if error occurs
            isBatchUpdating = false
        }

        // Hotkey settings
        toggleHotkeyCode = prefs.toggleHotkey.keyCode
        toggleHotkeyModifiers = prefs.toggleHotkey.modifiers.rawValue
        toggleHotkeyIsModifierOnly = prefs.toggleHotkey.isModifierOnly
        undoTypingEnabled = prefs.undoTypingEnabled
        beepOnToggle = prefs.beepOnToggle

        // Input settings
        inputMethod = prefs.inputMethod.rawValue
        codeTable = prefs.codeTable.rawValue
        modernStyle = prefs.modernStyle
        spellCheckEnabled = prefs.spellCheckEnabled
        fixAutocomplete = prefs.fixAutocomplete

        // Advanced settings
        quickTelexEnabled = prefs.quickTelexEnabled
        quickStartConsonantEnabled = prefs.quickStartConsonantEnabled
        quickEndConsonantEnabled = prefs.quickEndConsonantEnabled
        upperCaseFirstChar = prefs.upperCaseFirstChar
        restoreIfWrongSpelling = prefs.restoreIfWrongSpelling
        instantRestoreOnWrongSpelling = prefs.instantRestoreOnWrongSpelling

        allowConsonantZFWJ = prefs.allowConsonantZFWJ
        freeMarkEnabled = prefs.freeMarkEnabled
        tempOffSpellingEnabled = prefs.tempOffSpellingEnabled
        tempOffEngineEnabled = prefs.tempOffEngineEnabled

        // Macro settings
        macroEnabled = prefs.macroEnabled
        macroInEnglishMode = prefs.macroInEnglishMode
        autoCapsMacro = prefs.autoCapsMacro

        // Smart switch
        smartSwitchEnabled = prefs.smartSwitchEnabled
        detectOverlayApps = prefs.detectOverlayApps

        // Debug
        debugModeEnabled = prefs.debugModeEnabled

        // IMKit
        imkitEnabled = prefs.imkitEnabled
        imkitUseMarkedText = prefs.imkitUseMarkedText

        // Switch to XKey hotkey (optional)
        if let switchHotkey = prefs.switchToXKeyHotkey {
            switchToXKeyHotkeyCode = switchHotkey.keyCode
            switchToXKeyHotkeyModifiers = switchHotkey.modifiers.rawValue
            switchToXKeyHotkeyIsModifierOnly = switchHotkey.isModifierOnly
        } else {
            // Clear the hotkey if nil
            switchToXKeyHotkeyCode = 0
            switchToXKeyHotkeyModifiers = 0
            switchToXKeyHotkeyIsModifierOnly = false
        }

        // UI settings
        showDockIcon = prefs.showDockIcon
        startAtLogin = prefs.startAtLogin
        menuBarIconStyle = prefs.menuBarIconStyle.rawValue

        // Excluded apps
        if let data = try? JSONEncoder().encode(prefs.excludedApps) {
            setExcludedApps(data)
        }

        // Batch update is done - settings are already written to plist via setters
        isBatchUpdating = false

        // Send ONE notification to notify observers
        notifySettingsChanged()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when shared settings change (local)
    static let sharedSettingsDidChange = Notification.Name("XKey.sharedSettingsDidChange")
    
    /// Posted when settings change (distributed, cross-app)
    static let xkeySettingsDidChange = Notification.Name("XKey.settingsDidChange")
}
