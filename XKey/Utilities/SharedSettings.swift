//
//  SharedSettings.swift
//  XKey
//
//  Shared settings between XKey (menu bar) and XKeyIM (Input Method)
//  Uses App Group for cross-app communication
//

import Foundation

/// App Group identifier for sharing data between XKey and XKeyIM
let kXKeyAppGroup = "group.com.codetay.inputmethod.XKey"

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

    // Debug settings
    case debugModeEnabled = "XKey.debugModeEnabled"

    // IMKit settings
    case imkitEnabled = "XKey.imkitEnabled"
    case imkitUseMarkedText = "XKey.imkitUseMarkedText"

    // UI settings
    case showDockIcon = "XKey.showDockIcon"
    case startAtLogin = "XKey.startAtLogin"
    case menuBarIconStyle = "XKey.menuBarIconStyle"

    // Excluded apps
    case excludedApps = "XKey.excludedApps"

    // Input Source Management
    case inputSourceConfig = "XKey.inputSourceConfig"
}

/// Manager for shared settings between XKey and XKeyIM
class SharedSettings {
    
    // MARK: - Singleton
    
    static let shared = SharedSettings()
    
    // MARK: - Properties
    
    /// Shared UserDefaults using App Group
    private let sharedDefaults: UserDefaults?
    
    /// Local UserDefaults (fallback)
    private let localDefaults = UserDefaults.standard
    
    /// Whether App Group is available
    var isAppGroupAvailable: Bool {
        return sharedDefaults != nil
    }
    
    // MARK: - Initialization

    private init() {
        // Try to use App Group UserDefaults
        sharedDefaults = UserDefaults(suiteName: kXKeyAppGroup)

        // Register default values
        registerDefaults()

        // Restore settings from backup if App Group is empty
        restoreFromBackupIfNeeded()
    }

    /// Register default values for settings
    private func registerDefaults() {
        let defaultValues: [String: Any] = [
            SharedSettingsKey.fixAutocomplete.rawValue: true
        ]

        defaults.register(defaults: defaultValues)
    }

    /// Restore settings from UserDefaults.standard backup if App Group is empty
    private func restoreFromBackupIfNeeded() {
        // Only restore if we're using App Group
        guard let shared = sharedDefaults else { return }

        // Check if App Group has settings (check a key that should always exist)
        let hasSettings = shared.object(forKey: SharedSettingsKey.inputMethod.rawValue) != nil

        // If App Group is empty but standard defaults has backup, restore it
        if !hasSettings {
            let hasBackup = localDefaults.object(forKey: SharedSettingsKey.inputMethod.rawValue) != nil

            if hasBackup {
                print("📦 SharedSettings: Restoring from backup...")

                // Restore all settings from standard defaults to App Group
                for key in getAllSettingsKeys() {
                    if let value = localDefaults.object(forKey: key) {
                        shared.set(value, forKey: key)
                    }
                }

                shared.synchronize()
                print("✅ SharedSettings: Restored from backup successfully")
            }
        }
    }

    /// Get all settings keys for backup/restore
    private func getAllSettingsKeys() -> [String] {
        return [
            SharedSettingsKey.toggleHotkeyCode.rawValue,
            SharedSettingsKey.toggleHotkeyModifiers.rawValue,
            SharedSettingsKey.toggleHotkeyIsModifierOnly.rawValue,
            SharedSettingsKey.undoTypingEnabled.rawValue,
            SharedSettingsKey.beepOnToggle.rawValue,
            SharedSettingsKey.inputMethod.rawValue,
            SharedSettingsKey.codeTable.rawValue,
            SharedSettingsKey.modernStyle.rawValue,
            SharedSettingsKey.spellCheckEnabled.rawValue,
            SharedSettingsKey.fixAutocomplete.rawValue,
            SharedSettingsKey.quickTelexEnabled.rawValue,
            SharedSettingsKey.quickStartConsonantEnabled.rawValue,
            SharedSettingsKey.quickEndConsonantEnabled.rawValue,
            SharedSettingsKey.upperCaseFirstChar.rawValue,
            SharedSettingsKey.restoreIfWrongSpelling.rawValue,
            SharedSettingsKey.allowConsonantZFWJ.rawValue,
            SharedSettingsKey.freeMarkEnabled.rawValue,
            SharedSettingsKey.tempOffSpellingEnabled.rawValue,
            SharedSettingsKey.tempOffEngineEnabled.rawValue,
            SharedSettingsKey.macroEnabled.rawValue,
            SharedSettingsKey.macroInEnglishMode.rawValue,
            SharedSettingsKey.autoCapsMacro.rawValue,
            SharedSettingsKey.macros.rawValue,
            SharedSettingsKey.smartSwitchEnabled.rawValue,
            SharedSettingsKey.debugModeEnabled.rawValue,
            SharedSettingsKey.imkitEnabled.rawValue,
            SharedSettingsKey.imkitUseMarkedText.rawValue,
            SharedSettingsKey.showDockIcon.rawValue,
            SharedSettingsKey.startAtLogin.rawValue,
            SharedSettingsKey.menuBarIconStyle.rawValue,
            SharedSettingsKey.excludedApps.rawValue,
            SharedSettingsKey.inputSourceConfig.rawValue
        ]
    }

    // MARK: - Defaults Access

    /// Get the appropriate UserDefaults (shared if available, local otherwise)
    private var defaults: UserDefaults {
        return sharedDefaults ?? localDefaults
    }
    
    // MARK: - Hotkey Settings

    var toggleHotkeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: SharedSettingsKey.toggleHotkeyCode.rawValue)) }
        set { defaults.set(Int(newValue), forKey: SharedSettingsKey.toggleHotkeyCode.rawValue) }
    }

    var toggleHotkeyModifiers: UInt {
        get { UInt(defaults.integer(forKey: SharedSettingsKey.toggleHotkeyModifiers.rawValue)) }
        set { defaults.set(Int(newValue), forKey: SharedSettingsKey.toggleHotkeyModifiers.rawValue) }
    }

    var toggleHotkeyIsModifierOnly: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.toggleHotkeyIsModifierOnly.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.toggleHotkeyIsModifierOnly.rawValue) }
    }

    var undoTypingEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.undoTypingEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.undoTypingEnabled.rawValue) }
    }

    var beepOnToggle: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.beepOnToggle.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.beepOnToggle.rawValue) }
    }

    // MARK: - Input Method Settings

    var inputMethod: Int {
        get { defaults.integer(forKey: SharedSettingsKey.inputMethod.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.inputMethod.rawValue)
            notifySettingsChanged()
        }
    }

    var codeTable: Int {
        get { defaults.integer(forKey: SharedSettingsKey.codeTable.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.codeTable.rawValue)
            notifySettingsChanged()
        }
    }

    var modernStyle: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.modernStyle.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.modernStyle.rawValue)
            notifySettingsChanged()
        }
    }

    var spellCheckEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.spellCheckEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.spellCheckEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var fixAutocomplete: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.fixAutocomplete.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.fixAutocomplete.rawValue) }
    }

    // MARK: - Advanced Settings

    var quickTelexEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.quickTelexEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.quickTelexEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var quickStartConsonantEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.quickStartConsonantEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.quickStartConsonantEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var quickEndConsonantEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.quickEndConsonantEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.quickEndConsonantEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var upperCaseFirstChar: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.upperCaseFirstChar.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.upperCaseFirstChar.rawValue) }
    }

    var restoreIfWrongSpelling: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.restoreIfWrongSpelling.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.restoreIfWrongSpelling.rawValue)
            notifySettingsChanged()
        }
    }

    var allowConsonantZFWJ: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.allowConsonantZFWJ.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.allowConsonantZFWJ.rawValue) }
    }

    var freeMarkEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.freeMarkEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.freeMarkEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var tempOffSpellingEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.tempOffSpellingEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.tempOffSpellingEnabled.rawValue) }
    }

    var tempOffEngineEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.tempOffEngineEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.tempOffEngineEnabled.rawValue) }
    }

    // MARK: - Macro Settings

    var macroEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.macroEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.macroEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var macroInEnglishMode: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.macroInEnglishMode.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.macroInEnglishMode.rawValue) }
    }

    var autoCapsMacro: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.autoCapsMacro.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.autoCapsMacro.rawValue) }
    }

    func getMacros() -> Data? {
        return defaults.data(forKey: SharedSettingsKey.macros.rawValue)
    }

    func setMacros(_ data: Data) {
        defaults.set(data, forKey: SharedSettingsKey.macros.rawValue)
        notifySettingsChanged()
    }

    // MARK: - Smart Switch Settings

    var smartSwitchEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.smartSwitchEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.smartSwitchEnabled.rawValue) }
    }

    // MARK: - Debug Settings

    var debugModeEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.debugModeEnabled.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.debugModeEnabled.rawValue) }
    }

    // MARK: - IMKit Settings

    var imkitEnabled: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.imkitEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.imkitEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var imkitUseMarkedText: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.imkitUseMarkedText.rawValue) }
        set {
            defaults.set(newValue, forKey: SharedSettingsKey.imkitUseMarkedText.rawValue)
            
            // CRITICAL: Also write directly to plist file to bypass cfprefsd caching
            // This ensures XKeyIM will read the latest value
            writeDirectlyToPlist(key: SharedSettingsKey.imkitUseMarkedText.rawValue, value: newValue)
            
            notifySettingsChanged()
        }
    }

    // MARK: - UI Settings

    var showDockIcon: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.showDockIcon.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.showDockIcon.rawValue) }
    }

    var startAtLogin: Bool {
        get { defaults.bool(forKey: SharedSettingsKey.startAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: SharedSettingsKey.startAtLogin.rawValue) }
    }

    var menuBarIconStyle: String {
        get { defaults.string(forKey: SharedSettingsKey.menuBarIconStyle.rawValue) ?? "X" }
        set { defaults.set(newValue, forKey: SharedSettingsKey.menuBarIconStyle.rawValue) }
    }

    // MARK: - Excluded Apps

    func getExcludedApps() -> Data? {
        return defaults.data(forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    func setExcludedApps(_ data: Data) {
        defaults.set(data, forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    // MARK: - Input Source Management

    func getInputSourceConfig() -> Data? {
        return defaults.data(forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }

    func setInputSourceConfig(_ data: Data) {
        defaults.set(data, forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }

    // MARK: - Sync

    /// Synchronize settings to disk with dual backup
    func synchronize() {
        // Save to primary storage (App Group or local)
        defaults.synchronize()
        
        // Force flush using CFPreferences for cross-process sync
        // This is more aggressive than UserDefaults.synchronize() alone
        CFPreferencesAppSynchronize(kXKeyAppGroup as CFString)

        // CRITICAL: Also backup to UserDefaults.standard as failsafe
        // This ensures settings persist even if App Group container changes
        backupToStandardDefaults()
    }

    /// Backup all settings to UserDefaults.standard as failsafe
    private func backupToStandardDefaults() {
        // Only backup if we're using App Group (otherwise we'd create duplicate)
        guard sharedDefaults != nil else { return }

        // Backup all settings to standard UserDefaults
        for key in getAllSettingsKeys() {
            if let value = sharedDefaults?.object(forKey: key) {
                localDefaults.set(value, forKey: key)
            }
        }

        localDefaults.synchronize()
    }
    
    /// Write directly to plist file to bypass cfprefsd caching
    /// This is needed because cfprefsd doesn't always flush to disk in time for XKeyIM to read
    private func writeDirectlyToPlist(key: String, value: Any) {
        // Get the plist file path in App Group container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kXKeyAppGroup) else {
            print("⚠️ SharedSettings: Cannot get App Group container URL")
            return
        }
        
        let prefsURL = containerURL.appendingPathComponent("Library/Preferences/\(kXKeyAppGroup).plist")
        
        // Read existing plist or create new one
        var plistDict: [String: Any] = [:]
        if let data = try? Data(contentsOf: prefsURL),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            plistDict = dict
        }
        
        // Update the value
        plistDict[key] = value
        
        // Write back to file
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .binary, options: 0)
            try data.write(to: prefsURL)
            print("✅ SharedSettings: Wrote \(key)=\(value) directly to plist")
        } catch {
            print("❌ SharedSettings: Failed to write plist: \(error)")
        }
    }

    /// Notify that settings have changed (for observers)
    private func notifySettingsChanged() {
        // IMPORTANT: Synchronize BEFORE notifying!
        // This ensures XKeyIM receives the latest values when it reloads
        defaults.synchronize()
        
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

        // Debug
        prefs.debugModeEnabled = debugModeEnabled

        // IMKit
        prefs.imkitEnabled = imkitEnabled
        prefs.imkitUseMarkedText = imkitUseMarkedText

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

        // Debug
        debugModeEnabled = prefs.debugModeEnabled

        // IMKit
        imkitEnabled = prefs.imkitEnabled
        imkitUseMarkedText = prefs.imkitUseMarkedText

        // UI settings
        showDockIcon = prefs.showDockIcon
        startAtLogin = prefs.startAtLogin
        menuBarIconStyle = prefs.menuBarIconStyle.rawValue

        // Excluded apps
        if let data = try? JSONEncoder().encode(prefs.excludedApps) {
            setExcludedApps(data)
        }

        synchronize()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when shared settings change (local)
    static let sharedSettingsDidChange = Notification.Name("XKey.sharedSettingsDidChange")
    
    /// Posted when settings change (distributed, cross-app)
    static let xkeySettingsDidChange = Notification.Name("XKey.settingsDidChange")
}
