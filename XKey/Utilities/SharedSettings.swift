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
    case undoTypingHotkeyCode = "XKey.undoTypingHotkeyCode"
    case undoTypingHotkeyModifiers = "XKey.undoTypingHotkeyModifiers"
    case undoTypingHotkeyIsModifierOnly = "XKey.undoTypingHotkeyIsModifierOnly"
    case beepOnToggle = "XKey.beepOnToggle"

    // Input settings
    case inputMethod = "XKey.inputMethod"
    case codeTable = "XKey.codeTable"
    case modernStyle = "XKey.modernStyle"
    case spellCheckEnabled = "XKey.spellCheckEnabled"

    // Advanced settings
    case quickTelexEnabled = "XKey.quickTelexEnabled"
    case quickStartConsonantEnabled = "XKey.quickStartConsonantEnabled"
    case quickEndConsonantEnabled = "XKey.quickEndConsonantEnabled"
    case upperCaseFirstChar = "XKey.upperCaseFirstChar"
    case capitalizeOnlyAfterSpace = "XKey.capitalizeOnlyAfterSpace"
    case restoreIfWrongSpelling = "XKey.restoreIfWrongSpelling"
    case instantRestoreOnWrongSpelling = "XKey.instantRestoreOnWrongSpelling"
    case skipRestoreForUppercaseVietnameseAbbreviations = "XKey.skipRestoreForUppercaseVietnameseAbbreviations"

    case customConsonantEnabled = "XKey.customConsonantEnabled"
    case customConsonants = "XKey.customConsonants"
    case tempOffToolbarEnabled = "XKey.tempOffToolbarEnabled"
    case tempOffToolbarHotkeyCode = "XKey.tempOffToolbarHotkeyCode"
    case tempOffToolbarHotkeyModifiers = "XKey.tempOffToolbarHotkeyModifiers"
    case convertToolHotkeyCode = "XKey.convertToolHotkeyCode"
    case convertToolHotkeyModifiers = "XKey.convertToolHotkeyModifiers"

    // Macro settings
    case macroEnabled = "XKey.macroEnabled"
    case macroInEnglishMode = "XKey.macroInEnglishMode"
    case autoCapsMacro = "XKey.autoCapsMacro"
    case addSpaceAfterMacro = "XKey.addSpaceAfterMacro"
    case yieldMacroToSystemReplacement = "XKey.yieldMacroToSystemReplacement"
    case macros = "XKey.macros"

    // Smart switch settings
    case smartSwitchEnabled = "XKey.smartSwitchEnabled"
    case smartSwitchData = "XKey.smartSwitchData"          // JSON-encoded [String: Int] per-app language map

    // Debug settings
    case debugModeEnabled = "XKey.debugModeEnabled"
    case debugHotkeyCode = "XKey.debugHotkeyCode"
    case debugHotkeyModifiers = "XKey.debugHotkeyModifiers"
    case openDebugOnLaunch = "XKey.openDebugOnLaunch"

    // IMKit settings
    case imkitUseMarkedText = "XKey.imkitUseMarkedText"
    case switchToXKeyHotkeyCode = "XKey.switchToXKeyHotkeyCode"
    case switchToXKeyHotkeyModifiers = "XKey.switchToXKeyHotkeyModifiers"
    case switchToXKeyHotkeyIsModifierOnly = "XKey.switchToXKeyHotkeyIsModifierOnly"

    // UI settings
    case showDockIcon = "XKey.showDockIcon"
    case startAtLogin = "XKey.startAtLogin"
    case menuBarIconStyle = "XKey.menuBarIconStyle"
    case statusBarClickToToggle = "XKey.statusBarClickToToggle"
    case appLanguage = "XKey.appLanguage"
    case autoCheckForUpdates = "XKey.autoCheckForUpdates"

    // Excluded apps
    case excludedApps = "XKey.excludedApps"
    case exclusionRulesEnabled = "XKey.exclusionRulesEnabled"
    case toggleExclusionHotkeyCode = "XKey.toggleExclusionHotkeyCode"
    case toggleExclusionHotkeyModifiers = "XKey.toggleExclusionHotkeyModifiers"

    // Remote desktop injection mode
    case remoteDesktopInjectMode = "XKey.remoteDesktopInjectMode"

    // Remote desktop target mode (this machine is being remoted into)
    case isRemoteDesktopTarget = "XKey.isRemoteDesktopTarget"
    
    // Window Title Rules toggle
    case windowTitleRulesEnabled = "XKey.windowTitleRulesEnabled"
    case toggleWindowRulesHotkeyCode = "XKey.toggleWindowRulesHotkeyCode"
    case toggleWindowRulesHotkeyModifiers = "XKey.toggleWindowRulesHotkeyModifiers"

    // Input Source Management
    case inputSourceConfig = "XKey.inputSourceConfig"
    
    // Local data (macros, window title rules)
    case macrosData = "XKey.macrosData"
    case windowTitleRules = "XKey.windowTitleRules"
    case disabledBuiltInRules = "XKey.disabledBuiltInRules"        // Rules enabled by default, now disabled by user
    case enabledBuiltInRules = "XKey.enabledBuiltInRules"          // Rules disabled by default, now enabled by user
    
    // User dictionary (custom words to skip spell check)
    case userDictionaryWords = "XKey.userDictionaryWords"
    
    // Translation settings
    case translationEnabled = "XKey.translationEnabled"
    case translationHotkeyCode = "XKey.translationHotkeyCode"
    case translationHotkeyModifiers = "XKey.translationHotkeyModifiers"
    case translationSourceLanguage = "XKey.translationSourceLanguage"
    case translationTargetLanguage = "XKey.translationTargetLanguage"
    case translationReplaceOriginal = "XKey.translationReplaceOriginal"
    case translationCopyToClipboard = "XKey.translationCopyToClipboard"
    case translationShowPopup = "XKey.translationShowPopup"                            // Show popup for target direction
    case translationToolbarEnabled = "XKey.translationToolbarEnabled"
    case translateToSourceHotkeyCode = "XKey.translateToSourceHotkeyCode"
    case translateToSourceHotkeyModifiers = "XKey.translateToSourceHotkeyModifiers"
    case translateToSourceReplaceOriginal = "XKey.translateToSourceReplaceOriginal"    // Replace text for source direction
    case translateToSourceCopyToClipboard = "XKey.translateToSourceCopyToClipboard"    // Copy to clipboard for source direction
    case translateToSourceShowPopup = "XKey.translateToSourceShowPopup"                // Show popup for source direction
    case translateToSourceAutoHideSeconds = "XKey.translateToSourceAutoHideSeconds"    // Auto-hide seconds for source popup
    case translationResultAutoHideSeconds = "XKey.translationResultAutoHideSeconds"
    
    // Translation provider configs
    case translationProviderConfigs = "XKey.translationProviderConfigs"  // JSON-encoded [TranslationProviderConfig]
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
        SharedSettingsKey.capitalizeOnlyAfterSpace.rawValue: true,
        SharedSettingsKey.smartSwitchEnabled.rawValue: true,
        SharedSettingsKey.imkitUseMarkedText.rawValue: true,
        SharedSettingsKey.translationCopyToClipboard.rawValue: true,
        SharedSettingsKey.translateToSourceShowPopup.rawValue: true,
        SharedSettingsKey.translateToSourceAutoHideSeconds.rawValue: 4,
        SharedSettingsKey.exclusionRulesEnabled.rawValue: true,
        SharedSettingsKey.windowTitleRulesEnabled.rawValue: true
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
    
    // MARK: - In-Memory Cache

    /// Guards cachedPlistDict / cachedUserDictionaryWords (NSLock is NOT reentrant —
    /// never call another locking method while holding it).
    private let cacheLock = NSLock()

    /// Cached plist dictionary so per-keystroke setting reads (spell check, engine
    /// flags, ...) don't hit disk. The main app is the only writer; writes update
    /// this cache directly. XKeyIM only reads and refreshes via the distributed
    /// settings-changed notification that accompanies every write.
    private var cachedPlistDict: [String: Any]?

    /// Cached decoded user dictionary so per-word spell checks don't re-decode JSON.
    private var cachedUserDictionaryWords: Set<String>?

    /// Bumped on every write/invalidation (under cacheLock). Lets
    /// getUserDictionaryWords detect that the data changed while it was
    /// decoding outside the lock, so it never caches a stale Set.
    private var cacheGeneration = 0

    /// Identifies this process in distributed settings notifications so our own
    /// observer can skip invalidating the cache that writePlistDict just updated.
    private static let processTag = "xkey-\(ProcessInfo.processInfo.processIdentifier)"

    // MARK: - Initialization

    private init() {
        // Refresh cache when settings change in another process
        // (XKeyIM receives main-app writes; the main app receiving its own
        // notification just causes one extra disk read per settings change).
        // Block-based observer: SharedSettings is not an NSObject, so the
        // selector-based API is unavailable. The singleton never deallocates,
        // so the observation token is intentionally not removed.
        DistributedNotificationCenter.default().addObserver(
            forName: .xkeySettingsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Skip our own writes — writePlistDict already updated the cache
            if (notification.object as? String) == Self.processTag { return }
            self?.invalidateCache()
        }
    }

    /// Drop all cached values; the next read reloads from disk
    func invalidateCache() {
        cacheLock.lock()
        cachedPlistDict = nil
        cachedUserDictionaryWords = nil
        cacheGeneration += 1
        cacheLock.unlock()
    }
    
    /// Public read-only access to the plist file path (for debug/diagnostics)
    var settingsFilePath: String {
        plistURL?.path ?? "(unavailable)"
    }

    // MARK: - Plist Read/Write Helpers
    
    /// Read the entire plist dictionary (served from the in-memory cache when warm)
    private func readPlistDict() -> [String: Any] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedPlistDict {
            return cached
        }

        guard let url = plistURL,
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            // Don't cache failures (missing file on fresh install, transient
            // read error) — keep retrying from disk until a successful read/write.
            return [:]
        }

        cachedPlistDict = dict
        return dict
    }

    /// Write the entire plist dictionary
    private func writePlistDict(_ dict: [String: Any]) {
        guard let url = plistURL else { return }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)

            // Disk write + cache update under one lock hold so a concurrent
            // reader can never observe cache/disk divergence. On write failure
            // the cache is left untouched (still matches disk).
            cacheLock.lock()
            defer { cacheLock.unlock() }
            try data.write(to: url)
            cachedPlistDict = dict
            cachedUserDictionaryWords = nil
            cacheGeneration += 1
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

    var undoTypingHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.undoTypingHotkeyCode.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.undoTypingHotkeyCode.rawValue) }
    }

    var undoTypingHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.undoTypingHotkeyModifiers.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.undoTypingHotkeyModifiers.rawValue) }
    }

    var undoTypingHotkeyIsModifierOnly: Bool {
        get { readBool(forKey: SharedSettingsKey.undoTypingHotkeyIsModifierOnly.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.undoTypingHotkeyIsModifierOnly.rawValue) }
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

    var capitalizeOnlyAfterSpace: Bool {
        get { readBool(forKey: SharedSettingsKey.capitalizeOnlyAfterSpace.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.capitalizeOnlyAfterSpace.rawValue) }
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

    var skipRestoreForUppercaseVietnameseAbbreviations: Bool {
        get { readBool(forKey: SharedSettingsKey.skipRestoreForUppercaseVietnameseAbbreviations.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.skipRestoreForUppercaseVietnameseAbbreviations.rawValue)
            notifySettingsChanged()
        }
    }


    var customConsonantEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.customConsonantEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.customConsonantEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var customConsonants: String {
        get { readString(forKey: SharedSettingsKey.customConsonants.rawValue) ?? Preferences.defaultCustomConsonants }
        set {
            writeString(newValue, forKey: SharedSettingsKey.customConsonants.rawValue)
            notifySettingsChanged()
        }
    }
    
    var tempOffToolbarEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.tempOffToolbarEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.tempOffToolbarEnabled.rawValue)
            notifyToolbarChanged()
        }
    }

    var tempOffToolbarHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.tempOffToolbarHotkeyCode.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.tempOffToolbarHotkeyCode.rawValue)
            notifyToolbarChanged()
        }
    }

    var tempOffToolbarHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.tempOffToolbarHotkeyModifiers.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.tempOffToolbarHotkeyModifiers.rawValue)
            notifyToolbarChanged()
        }
    }

    var convertToolHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.convertToolHotkeyCode.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.convertToolHotkeyCode.rawValue)
            notifyConvertToolHotkeyChanged()
        }
    }

    var convertToolHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.convertToolHotkeyModifiers.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.convertToolHotkeyModifiers.rawValue)
            notifyConvertToolHotkeyChanged()
        }
    }

    /// Notify that convert tool hotkey has changed
    private func notifyConvertToolHotkeyChanged() {
        guard !isBatchUpdating else { return }
        NotificationCenter.default.post(
            name: .convertToolHotkeyDidChange,
            object: nil
        )
    }

    /// Notify that toolbar settings have changed
    private func notifyToolbarChanged() {
        guard !isBatchUpdating else { return }
        NotificationCenter.default.post(
            name: .tempOffToolbarSettingsDidChange,
            object: nil
        )
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

    var addSpaceAfterMacro: Bool {
        get { readBool(forKey: SharedSettingsKey.addSpaceAfterMacro.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.addSpaceAfterMacro.rawValue) }
    }

    var yieldMacroToSystemReplacement: Bool {
        get { readBool(forKey: SharedSettingsKey.yieldMacroToSystemReplacement.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.yieldMacroToSystemReplacement.rawValue) }
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
    
    // MARK: - Smart Switch Data
    
    func getSmartSwitchData() -> Data? {
        return readData(forKey: SharedSettingsKey.smartSwitchData.rawValue)
    }
    
    func setSmartSwitchData(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.smartSwitchData.rawValue)
    }

    // MARK: - Debug Settings

    var debugModeEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.debugModeEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.debugModeEnabled.rawValue)
            notifyDebugSettingsChanged()
        }
    }

    var debugHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.debugHotkeyCode.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.debugHotkeyCode.rawValue)
            notifyDebugSettingsChanged()
        }
    }

    var debugHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.debugHotkeyModifiers.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.debugHotkeyModifiers.rawValue)
            notifyDebugSettingsChanged()
        }
    }

    /// Open debug window automatically when app launches
    var openDebugOnLaunch: Bool {
        get { readBool(forKey: SharedSettingsKey.openDebugOnLaunch.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.openDebugOnLaunch.rawValue) }
    }

    /// Notify that debug settings have changed
    private func notifyDebugSettingsChanged() {
        guard !isBatchUpdating else { return }
        NotificationCenter.default.post(
            name: .debugSettingsDidChange,
            object: nil
        )
    }

    // MARK: - IMKit Settings

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

    var statusBarClickToToggle: Bool {
        get { readBool(forKey: SharedSettingsKey.statusBarClickToToggle.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.statusBarClickToToggle.rawValue) }
    }

    var appLanguage: String {
        // Default to Vietnamese on first launch — matches Preferences.appLanguage default
        // so loadPreferences() from an empty plist yields the same value as a fresh
        // Preferences() struct.
        get { readString(forKey: SharedSettingsKey.appLanguage.rawValue) ?? AppLanguage.vi.rawValue }
        set { writeString(newValue, forKey: SharedSettingsKey.appLanguage.rawValue) }
    }

    var autoCheckForUpdates: Bool {
        get {
            let dict = readPlistDict()
            // Default to true if key not found
            if let value = dict[SharedSettingsKey.autoCheckForUpdates.rawValue] as? Bool {
                return value
            }
            return true
        }
        set { writeBool(newValue, forKey: SharedSettingsKey.autoCheckForUpdates.rawValue) }
    }

    // MARK: - Translation Settings

    var translationEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.translationEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.translationEnabled.rawValue)
            notifyTranslationSettingsChanged()
        }
    }

    var translationHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.translationHotkeyCode.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.translationHotkeyCode.rawValue)
            notifyTranslationSettingsChanged()
        }
    }

    var translationHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.translationHotkeyModifiers.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.translationHotkeyModifiers.rawValue)
            notifyTranslationSettingsChanged()
        }
    }

    var translationSourceLanguage: String {
        get { readString(forKey: SharedSettingsKey.translationSourceLanguage.rawValue) ?? "auto" }
        set { writeString(newValue, forKey: SharedSettingsKey.translationSourceLanguage.rawValue) }
    }

    var translationTargetLanguage: String {
        get { readString(forKey: SharedSettingsKey.translationTargetLanguage.rawValue) ?? "vi" }
        set { writeString(newValue, forKey: SharedSettingsKey.translationTargetLanguage.rawValue) }
    }

    var translationReplaceOriginal: Bool {
        get { readBool(forKey: SharedSettingsKey.translationReplaceOriginal.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translationReplaceOriginal.rawValue) }
    }

    var translationCopyToClipboard: Bool {
        get { readBool(forKey: SharedSettingsKey.translationCopyToClipboard.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translationCopyToClipboard.rawValue) }
    }

    var translationShowPopup: Bool {
        get { readBool(forKey: SharedSettingsKey.translationShowPopup.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translationShowPopup.rawValue) }
    }

    var translateToSourceReplaceOriginal: Bool {
        get { readBool(forKey: SharedSettingsKey.translateToSourceReplaceOriginal.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translateToSourceReplaceOriginal.rawValue) }
    }

    var translateToSourceCopyToClipboard: Bool {
        get { readBool(forKey: SharedSettingsKey.translateToSourceCopyToClipboard.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translateToSourceCopyToClipboard.rawValue) }
    }

    var translateToSourceShowPopup: Bool {
        get { readBool(forKey: SharedSettingsKey.translateToSourceShowPopup.rawValue) }
        set { writeBool(newValue, forKey: SharedSettingsKey.translateToSourceShowPopup.rawValue) }
    }

    var translateToSourceAutoHideSeconds: Int {
        get { readInt(forKey: SharedSettingsKey.translateToSourceAutoHideSeconds.rawValue) }
        set { writeInt(newValue, forKey: SharedSettingsKey.translateToSourceAutoHideSeconds.rawValue) }
    }

    var translationToolbarEnabled: Bool {
        get {
            readBool(forKey: SharedSettingsKey.translationToolbarEnabled.rawValue)
        }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.translationToolbarEnabled.rawValue)
            notifyTranslationToolbarSettingsChanged()
        }
    }

    var translateToSourceHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.translateToSourceHotkeyCode.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.translateToSourceHotkeyCode.rawValue)
            notifyTranslationSettingsChanged()
        }
    }

    var translateToSourceHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.translateToSourceHotkeyModifiers.rawValue)) }
        set {
            writeInt(Int(newValue), forKey: SharedSettingsKey.translateToSourceHotkeyModifiers.rawValue)
            notifyTranslationSettingsChanged()
        }
    }

    var translationResultAutoHideSeconds: Int {
        get {
            let dict = readPlistDict()
            if dict[SharedSettingsKey.translationResultAutoHideSeconds.rawValue] == nil {
                return 4  // Default: 4 seconds
            }
            return readInt(forKey: SharedSettingsKey.translationResultAutoHideSeconds.rawValue)
        }
        set { writeInt(newValue, forKey: SharedSettingsKey.translationResultAutoHideSeconds.rawValue) }
    }

    /// Notify that translation toolbar settings have changed
    private func notifyTranslationToolbarSettingsChanged() {
        guard !isBatchUpdating else { return }
        NotificationCenter.default.post(
            name: .translationToolbarSettingsDidChange,
            object: nil
        )
    }

    /// Notify that translation settings have changed
    private func notifyTranslationSettingsChanged() {
        guard !isBatchUpdating else { return }
        NotificationCenter.default.post(
            name: .translationSettingsDidChange,
            object: nil
        )
    }

    // MARK: - Excluded Apps

    func getExcludedApps() -> Data? {
        return readData(forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    func setExcludedApps(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.excludedApps.rawValue)
    }

    var exclusionRulesEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.exclusionRulesEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.exclusionRulesEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var remoteDesktopInjectMode: Bool {
        get { readBool(forKey: SharedSettingsKey.remoteDesktopInjectMode.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.remoteDesktopInjectMode.rawValue)
            notifySettingsChanged()
        }
    }

    var isRemoteDesktopTarget: Bool {
        get { readBool(forKey: SharedSettingsKey.isRemoteDesktopTarget.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.isRemoteDesktopTarget.rawValue)
            notifySettingsChanged()
        }
    }

    var toggleExclusionHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.toggleExclusionHotkeyCode.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleExclusionHotkeyCode.rawValue) }
    }

    var toggleExclusionHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.toggleExclusionHotkeyModifiers.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleExclusionHotkeyModifiers.rawValue) }
    }

    // MARK: - Window Title Rules Toggle

    var windowTitleRulesEnabled: Bool {
        get { readBool(forKey: SharedSettingsKey.windowTitleRulesEnabled.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.windowTitleRulesEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    var toggleWindowRulesHotkeyCode: UInt16 {
        get { UInt16(readInt(forKey: SharedSettingsKey.toggleWindowRulesHotkeyCode.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleWindowRulesHotkeyCode.rawValue) }
    }

    var toggleWindowRulesHotkeyModifiers: UInt {
        get { UInt(readInt(forKey: SharedSettingsKey.toggleWindowRulesHotkeyModifiers.rawValue)) }
        set { writeInt(Int(newValue), forKey: SharedSettingsKey.toggleWindowRulesHotkeyModifiers.rawValue) }
    }

    // MARK: - Input Source Management

    func getInputSourceConfig() -> Data? {
        return readData(forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }

    func setInputSourceConfig(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.inputSourceConfig.rawValue)
    }
    
    // MARK: - Translation Provider Configs
    
    func getTranslationProviderConfigs() -> Data? {
        return readData(forKey: SharedSettingsKey.translationProviderConfigs.rawValue)
    }
    
    func setTranslationProviderConfigs(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.translationProviderConfigs.rawValue)
    }
    
    // MARK: - Macros Data
    
    func getMacrosData() -> Data? {
        return readData(forKey: SharedSettingsKey.macrosData.rawValue)
    }
    
    func setMacrosData(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.macrosData.rawValue)
        // Macro list content lives in a dedicated sync category. Editing it must notify
        // observers so iCloudSyncManager schedules a push — writeData alone is silent.
        // During sync apply, isBatchUpdating suppresses this to avoid a push echo.
        notifySettingsChanged()
    }
    
    // MARK: - Window Title Rules
    
    func getWindowTitleRulesData() -> Data? {
        return readData(forKey: SharedSettingsKey.windowTitleRules.rawValue)
    }
    
    func setWindowTitleRulesData(_ data: Data) {
        writeData(data, forKey: SharedSettingsKey.windowTitleRules.rawValue)
        // Window Title Rules live in a dedicated sync category. Editing them must notify
        // observers so iCloudSyncManager schedules a push — writeData alone is silent.
        // During sync apply, isBatchUpdating suppresses this to avoid a push echo.
        notifySettingsChanged()
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
    
    /// Get the list of enabled built-in rule names (for rules that are disabled by default)
    func getEnabledBuiltInRules() -> Set<String> {
        guard let data = readData(forKey: SharedSettingsKey.enabledBuiltInRules.rawValue),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }
    
    /// Set the list of enabled built-in rule names (for rules that are disabled by default)
    func setEnabledBuiltInRules(_ names: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(names)) {
            writeData(data, forKey: SharedSettingsKey.enabledBuiltInRules.rawValue)
        }
    }
    
    // MARK: - User Dictionary (Custom Words)
    
    /// Get the list of user-defined words (to skip spell check)
    func getUserDictionaryWords() -> Set<String> {
        cacheLock.lock()
        let cached = cachedUserDictionaryWords
        let generation = cacheGeneration
        cacheLock.unlock()
        if let cached = cached {
            return cached
        }

        // Decode outside the lock — readData() takes cacheLock internally.
        let words: Set<String>
        if let data = readData(forKey: SharedSettingsKey.userDictionaryWords.rawValue),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            words = Set(list)
        } else {
            words = []
        }

        cacheLock.lock()
        // Only cache if no write/invalidation happened while we were decoding —
        // otherwise this Set may be stale and would be served indefinitely.
        if cacheGeneration == generation {
            cachedUserDictionaryWords = words
        }
        cacheLock.unlock()
        return words
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
        let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
        var words = getUserDictionaryWords()
        words.insert(normalized)
        setUserDictionaryWords(words)
        // Re-adding a previously deleted word clears its tombstone so the addition isn't
        // shadowed on next sync.
        SyncTombstoneStore.shared.remove(category: .userDict, id: normalized)
    }

    /// Remove a word from the user dictionary
    func removeUserDictionaryWord(_ word: String) {
        let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
        var words = getUserDictionaryWords()
        words.remove(normalized)
        setUserDictionaryWords(words)
        SyncTombstoneStore.shared.record(category: .userDict, id: normalized)
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

        // Post distributed notification for cross-app communication.
        // object carries the sender's process tag so our own observer can skip
        // the redundant cache invalidation (XKeyIM observes with object: nil
        // and is unaffected by the object value).
        // deliverImmediately: XKeyIM is a background IMK process — without it
        // the notification can be coalesced/held and its settings cache would
        // stay stale until the next delivery.
        DistributedNotificationCenter.default().postNotificationName(
            .xkeySettingsDidChange,
            object: Self.processTag,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    // MARK: - iCloud Sync Helpers (per-category)

    /// Keys excluded from the scalar payload because they are owned by dedicated sync categories
    /// (macros / rules / excluded apps / user dictionary). Keeping them out prevents double-writes.
    /// Also excludes device-specific keys that must not sync across machines.
    private static let scalarsExcludedKeys: Set<String> = [
        SharedSettingsKey.macrosData.rawValue,
        SharedSettingsKey.excludedApps.rawValue,
        SharedSettingsKey.windowTitleRules.rawValue,
        SharedSettingsKey.userDictionaryWords.rawValue,
        // Device-specific: machine B (remote target) ≠ machine A (controller).
        // Syncing this would break Notion/Kiro on the controller machine.
        SharedSettingsKey.isRemoteDesktopTarget.rawValue,
    ]

    /// Sensitive keys that must never leave the device. Currently empty — translation providers
    /// do not store API keys in the shared plist — but kept as a defensive scaffold.
    private static let sensitiveScalarKeys: Set<String> = []

    // MARK: Scalars

    func exportScalarsForSync() -> Data? {
        var dict = readPlistDict()
        for k in Self.scalarsExcludedKeys { dict.removeValue(forKey: k) }
        for k in Self.sensitiveScalarKeys { dict.removeValue(forKey: k) }
        guard !dict.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    func importScalarsForSync(from data: Data) {
        guard let incoming = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }

        var merged = readPlistDict()
        let preserve = Self.scalarsExcludedKeys.union(Self.sensitiveScalarKeys)
        for (k, v) in incoming where !preserve.contains(k) {
            merged[k] = v
        }

        isBatchUpdating = true
        writePlistDict(merged)
        isBatchUpdating = false

        if let langRaw = merged[SharedSettingsKey.appLanguage.rawValue] as? String,
           AppLanguage(rawValue: langRaw) != nil {
            UserDefaults.standard.set(langRaw, forKey: "appLanguage")
        }

        notifySettingsChanged()
        NotificationCenter.default.post(name: .tempOffToolbarSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .convertToolHotkeyDidChange, object: nil)
        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .translationToolbarSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .debugSettingsDidChange, object: nil)
    }

    // MARK: Macros
    //
    // List helpers operate on the raw JSON Data already persisted in the plist so they don't depend
    // on model types that may not exist in every build target (e.g. MacroItem is UI-only).

    func snapshotMacrosForSync(timestampProvider: (String, Data) -> Date) -> [SyncEntry] {
        // Use the macro abbreviation (`text`) as the sync identity, not the per-device UUID.
        // The UI already enforces `text` uniqueness, so this is the natural key: it lets a
        // delete on one Mac match the same macro on another (even if each typed it locally
        // with a different UUID) and collapses accidental duplicates on merge.
        Self.jsonArraySnapshot(getMacrosData(), idField: "text", timestampProvider: timestampProvider)
    }

    func applyMacrosFromSync(liveEntries: [SyncEntry]) {
        guard let encoded = Self.jsonArrayReassemble(liveEntries) else { return }
        isBatchUpdating = true
        setMacrosData(encoded)
        isBatchUpdating = false
        notifySettingsChanged()
        // The typing engine and the macro list observe .macrosDidChange, not
        // .sharedSettingsDidChange. Without this post, a synced delete stays "live" in the
        // engine (keeps expanding) and in any open Macro tab until the app restarts.
        // Raw string keeps this file usable from targets that don't define the symbol (XKeyIM).
        NotificationCenter.default.post(name: Notification.Name("XKey.macrosDidChange"), object: nil)
    }

    // MARK: Window title rules

    func snapshotRulesForSync(timestampProvider: (String, Data) -> Date) -> [SyncEntry] {
        Self.jsonArraySnapshot(getWindowTitleRulesData(), idField: "id", timestampProvider: timestampProvider)
    }

    func applyRulesFromSync(liveEntries: [SyncEntry]) {
        guard let encoded = Self.jsonArrayReassemble(liveEntries) else { return }
        isBatchUpdating = true
        setWindowTitleRulesData(encoded)
        isBatchUpdating = false
        notifySettingsChanged()
        // The typing engine matches against AppBehaviorDetector's in-memory customRules, and the
        // Settings tab shows its own copy — both must reload, or a synced edit/delete stays stale
        // until app restart. Raw string keeps this usable from targets without the symbol (XKeyIM).
        NotificationCenter.default.post(name: Notification.Name("XKey.windowTitleRulesDidChange"), object: nil)
    }

    // MARK: Excluded apps

    func snapshotExcludedAppsForSync(timestampProvider: (String, Data) -> Date) -> [SyncEntry] {
        Self.jsonArraySnapshot(getExcludedApps(), idField: "bundleIdentifier", timestampProvider: timestampProvider)
    }

    func applyExcludedAppsFromSync(liveEntries: [SyncEntry]) {
        guard let encoded = Self.jsonArrayReassemble(liveEntries) else { return }
        isBatchUpdating = true
        setExcludedApps(encoded)
        isBatchUpdating = false
        notifySettingsChanged()
    }

    // MARK: JSON array helpers

    /// Generic snapshot: read a JSON-encoded array of objects from Data, derive a per-object
    /// SyncEntry using `idField` as the stable identifier. Skips entries without the field.
    private static func jsonArraySnapshot(_ data: Data?,
                                          idField: String,
                                          timestampProvider: (String, Data) -> Date) -> [SyncEntry] {
        guard let data = data,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { obj in
            let rawId: String?
            switch obj[idField] {
            case let s as String: rawId = s
            case let uuid as UUID: rawId = uuid.uuidString
            default: rawId = nil
            }
            guard let id = rawId,
                  let encoded = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return SyncEntry(id: id, updatedAt: timestampProvider(id, encoded), deleted: false, data: encoded)
        }
    }

    /// Reassemble live entries into a JSON-encoded array suitable for the original storage slot.
    private static func jsonArrayReassemble(_ liveEntries: [SyncEntry]) -> Data? {
        let objects: [[String: Any]] = liveEntries.compactMap { entry in
            guard let data = entry.data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return dict
        }
        return try? JSONSerialization.data(withJSONObject: objects)
    }

    // MARK: User dictionary

    func snapshotUserDictForSync(timestampProvider: (String, Data) -> Date) -> [SyncEntry] {
        let words = getUserDictionaryWords()
        return words.map { word in
            let data = Data(word.utf8)
            return SyncEntry(id: word, updatedAt: timestampProvider(word, data), deleted: false, data: data)
        }
    }

    func applyUserDictFromSync(liveEntries: [SyncEntry]) {
        let words = Set(liveEntries.compactMap { entry -> String? in
            guard let data = entry.data,
                  let word = String(data: data, encoding: .utf8) else { return nil }
            return word
        })
        isBatchUpdating = true
        if let encoded = try? JSONEncoder().encode(Array(words).sorted()) {
            writeData(encoded, forKey: SharedSettingsKey.userDictionaryWords.rawValue)
        }
        isBatchUpdating = false
        notifySettingsChanged()
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

            // Sync app language to UserDefaults.standard so AppLanguage.applyLanguage()
            // picks up the imported value on next launch (it reads from standard defaults,
            // not from the shared plist, for early-launch access).
            if let langRaw = importDict[SharedSettingsKey.appLanguage.rawValue] as? String,
               AppLanguage(rawValue: langRaw) != nil {
                UserDefaults.standard.set(langRaw, forKey: "appLanguage")
            }

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
    
    // MARK: - Reset to Factory Default
    
    /// Reset all settings to factory defaults by deleting the plist file.
    /// All getters will automatically fall back to `defaultValues`.
    /// This is the only method needed since ALL config is now centralized in the plist.
    @discardableResult
    func resetToDefaults() -> Bool {
        // Delete the plist file — all getters auto-fallback to defaultValues
        if let url = plistURL {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                sharedLogError("Failed to delete plist file: \(error)")
                return false
            }
        }

        // Cache must not outlive the deleted plist
        invalidateCache()

        // Notify all observers that settings have been reset
        notifySettingsChanged()
        notifyToolbarChanged()
        notifyConvertToolHotkeyChanged()
        notifyTranslationSettingsChanged()
        notifyTranslationToolbarSettingsChanged()
        notifyDebugSettingsChanged()
        
        sharedLogSuccess("Settings reset to factory defaults")
        return true
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
        
        // Undo typing hotkey
        let undoHotkeyCode = undoTypingHotkeyCode
        let undoHotkeyModifiers = undoTypingHotkeyModifiers
        if undoHotkeyCode != 0 || undoHotkeyModifiers != 0 {
            prefs.undoTypingHotkey = Hotkey(
                keyCode: undoHotkeyCode,
                modifiers: ModifierFlags(rawValue: undoHotkeyModifiers),
                isModifierOnly: undoTypingHotkeyIsModifierOnly
            )
        }
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

        // Advanced settings
        prefs.quickTelexEnabled = quickTelexEnabled
        prefs.quickStartConsonantEnabled = quickStartConsonantEnabled
        prefs.quickEndConsonantEnabled = quickEndConsonantEnabled
        prefs.upperCaseFirstChar = upperCaseFirstChar
        prefs.capitalizeOnlyAfterSpace = capitalizeOnlyAfterSpace
        prefs.restoreIfWrongSpelling = restoreIfWrongSpelling
        prefs.instantRestoreOnWrongSpelling = instantRestoreOnWrongSpelling
        prefs.skipRestoreForUppercaseVietnameseAbbreviations = skipRestoreForUppercaseVietnameseAbbreviations

        // Custom consonants (2-prop: enabled + list)
        prefs.customConsonantEnabled = customConsonantEnabled
        prefs.customConsonants = customConsonants
        prefs.tempOffToolbarEnabled = tempOffToolbarEnabled

        // Temp off toolbar hotkey
        let toolbarHotkeyCode = tempOffToolbarHotkeyCode
        let toolbarHotkeyModifiers = tempOffToolbarHotkeyModifiers
        if toolbarHotkeyCode != 0 || toolbarHotkeyModifiers != 0 {
            prefs.tempOffToolbarHotkey = Hotkey(
                keyCode: toolbarHotkeyCode,
                modifiers: ModifierFlags(rawValue: toolbarHotkeyModifiers)
            )
        }

        // Convert tool hotkey
        let convertHotkeyCode = convertToolHotkeyCode
        let convertHotkeyModifiers = convertToolHotkeyModifiers
        if convertHotkeyCode != 0 || convertHotkeyModifiers != 0 {
            prefs.convertToolHotkey = Hotkey(
                keyCode: convertHotkeyCode,
                modifiers: ModifierFlags(rawValue: convertHotkeyModifiers)
            )
        }

        // Macro settings
        prefs.macroEnabled = macroEnabled
        prefs.macroInEnglishMode = macroInEnglishMode
        prefs.autoCapsMacro = autoCapsMacro
        prefs.addSpaceAfterMacro = addSpaceAfterMacro
        prefs.yieldMacroToSystemReplacement = yieldMacroToSystemReplacement

        prefs.smartSwitchEnabled = smartSwitchEnabled

        // Debug
        prefs.debugModeEnabled = debugModeEnabled

        // IMKit
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
        prefs.statusBarClickToToggle = statusBarClickToToggle
        if let lang = AppLanguage(rawValue: appLanguage) {
            prefs.appLanguage = lang
        }
        prefs.autoCheckForUpdates = autoCheckForUpdates

        // Excluded apps
        if let data = getExcludedApps(),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            prefs.excludedApps = apps
        }
        prefs.exclusionRulesEnabled = exclusionRulesEnabled
        prefs.remoteDesktopInjectMode = remoteDesktopInjectMode
        prefs.isRemoteDesktopTarget = isRemoteDesktopTarget
        let exclHotkeyCode = toggleExclusionHotkeyCode
        let exclHotkeyModifiers = toggleExclusionHotkeyModifiers
        if exclHotkeyCode != 0 || exclHotkeyModifiers != 0 {
            prefs.toggleExclusionHotkey = Hotkey(
                keyCode: exclHotkeyCode,
                modifiers: ModifierFlags(rawValue: exclHotkeyModifiers)
            )
        }

        // Window Title Rules toggle
        prefs.windowTitleRulesEnabled = windowTitleRulesEnabled
        let wtrHotkeyCode = toggleWindowRulesHotkeyCode
        let wtrHotkeyModifiers = toggleWindowRulesHotkeyModifiers
        if wtrHotkeyCode != 0 || wtrHotkeyModifiers != 0 {
            prefs.toggleWindowRulesHotkey = Hotkey(
                keyCode: wtrHotkeyCode,
                modifiers: ModifierFlags(rawValue: wtrHotkeyModifiers)
            )
        }

        // Translation settings
        prefs.translationEnabled = translationEnabled
        let transHotkeyCode = translationHotkeyCode
        let transHotkeyModifiers = translationHotkeyModifiers
        if transHotkeyCode != 0 || transHotkeyModifiers != 0 {
            prefs.translationHotkey = Hotkey(
                keyCode: transHotkeyCode,
                modifiers: ModifierFlags(rawValue: transHotkeyModifiers)
            )
        }
        // Translation language codes (stored as String)
        prefs.translationSourceLanguageCode = translationSourceLanguage
        prefs.translationTargetLanguageCode = translationTargetLanguage
        prefs.translationReplaceOriginal = translationReplaceOriginal
        prefs.translationCopyToClipboard = translationCopyToClipboard
        prefs.translationShowPopup = translationShowPopup
        prefs.translationToolbarEnabled = translationToolbarEnabled
        let transToSrcHotkeyCode = translateToSourceHotkeyCode
        let transToSrcHotkeyModifiers = translateToSourceHotkeyModifiers
        if transToSrcHotkeyCode != 0 || transToSrcHotkeyModifiers != 0 {
            prefs.translateToSourceHotkey = Hotkey(
                keyCode: transToSrcHotkeyCode,
                modifiers: ModifierFlags(rawValue: transToSrcHotkeyModifiers)
            )
        }
        prefs.translateToSourceReplaceOriginal = translateToSourceReplaceOriginal
        prefs.translateToSourceCopyToClipboard = translateToSourceCopyToClipboard
        prefs.translateToSourceShowPopup = translateToSourceShowPopup
        prefs.translateToSourceAutoHideSeconds = translateToSourceAutoHideSeconds
        prefs.translationResultAutoHideSeconds = translationResultAutoHideSeconds

        // Debug settings
        prefs.debugModeEnabled = debugModeEnabled
        prefs.openDebugOnLaunch = openDebugOnLaunch
        let dbgHotkeyCode = debugHotkeyCode
        let dbgHotkeyModifiers = debugHotkeyModifiers
        if dbgHotkeyCode != 0 || dbgHotkeyModifiers != 0 {
            prefs.debugHotkey = Hotkey(
                keyCode: dbgHotkeyCode,
                modifiers: ModifierFlags(rawValue: dbgHotkeyModifiers)
            )
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
        
        // Undo typing hotkey (optional)
        if let undoHotkey = prefs.undoTypingHotkey {
            undoTypingHotkeyCode = undoHotkey.keyCode
            undoTypingHotkeyModifiers = undoHotkey.modifiers.rawValue
            undoTypingHotkeyIsModifierOnly = undoHotkey.isModifierOnly
        } else {
            // Clear the hotkey settings when nil (use default Esc)
            undoTypingHotkeyCode = 0
            undoTypingHotkeyModifiers = 0
            undoTypingHotkeyIsModifierOnly = false
        }
        beepOnToggle = prefs.beepOnToggle

        // Input settings
        inputMethod = prefs.inputMethod.rawValue
        codeTable = prefs.codeTable.rawValue
        modernStyle = prefs.modernStyle
        spellCheckEnabled = prefs.spellCheckEnabled

        // Advanced settings
        quickTelexEnabled = prefs.quickTelexEnabled
        quickStartConsonantEnabled = prefs.quickStartConsonantEnabled
        quickEndConsonantEnabled = prefs.quickEndConsonantEnabled
        upperCaseFirstChar = prefs.upperCaseFirstChar
        capitalizeOnlyAfterSpace = prefs.capitalizeOnlyAfterSpace
        restoreIfWrongSpelling = prefs.restoreIfWrongSpelling
        instantRestoreOnWrongSpelling = prefs.instantRestoreOnWrongSpelling
        skipRestoreForUppercaseVietnameseAbbreviations = prefs.skipRestoreForUppercaseVietnameseAbbreviations

        customConsonantEnabled = prefs.customConsonantEnabled
        customConsonants = prefs.customConsonants
        tempOffToolbarEnabled = prefs.tempOffToolbarEnabled
        tempOffToolbarHotkeyCode = prefs.tempOffToolbarHotkey.keyCode
        tempOffToolbarHotkeyModifiers = prefs.tempOffToolbarHotkey.modifiers.rawValue
        convertToolHotkeyCode = prefs.convertToolHotkey.keyCode
        convertToolHotkeyModifiers = prefs.convertToolHotkey.modifiers.rawValue

        // Macro settings
        macroEnabled = prefs.macroEnabled
        macroInEnglishMode = prefs.macroInEnglishMode
        autoCapsMacro = prefs.autoCapsMacro
        addSpaceAfterMacro = prefs.addSpaceAfterMacro
        yieldMacroToSystemReplacement = prefs.yieldMacroToSystemReplacement

        smartSwitchEnabled = prefs.smartSwitchEnabled

        // Debug
        debugModeEnabled = prefs.debugModeEnabled
        openDebugOnLaunch = prefs.openDebugOnLaunch

        // IMKit
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
        statusBarClickToToggle = prefs.statusBarClickToToggle
        appLanguage = prefs.appLanguage.rawValue
        autoCheckForUpdates = prefs.autoCheckForUpdates

        // Excluded apps
        if let data = try? JSONEncoder().encode(prefs.excludedApps) {
            setExcludedApps(data)
        }
        exclusionRulesEnabled = prefs.exclusionRulesEnabled
        toggleExclusionHotkeyCode = prefs.toggleExclusionHotkey.keyCode
        toggleExclusionHotkeyModifiers = prefs.toggleExclusionHotkey.modifiers.rawValue
        remoteDesktopInjectMode = prefs.remoteDesktopInjectMode
        isRemoteDesktopTarget = prefs.isRemoteDesktopTarget

        // Window Title Rules toggle
        windowTitleRulesEnabled = prefs.windowTitleRulesEnabled
        toggleWindowRulesHotkeyCode = prefs.toggleWindowRulesHotkey.keyCode
        toggleWindowRulesHotkeyModifiers = prefs.toggleWindowRulesHotkey.modifiers.rawValue

        // Translation settings
        translationEnabled = prefs.translationEnabled
        translationHotkeyCode = prefs.translationHotkey.keyCode
        translationHotkeyModifiers = prefs.translationHotkey.modifiers.rawValue
        translationSourceLanguage = prefs.translationSourceLanguageCode
        translationTargetLanguage = prefs.translationTargetLanguageCode
        translationReplaceOriginal = prefs.translationReplaceOriginal
        translationCopyToClipboard = prefs.translationCopyToClipboard
        translationShowPopup = prefs.translationShowPopup
        translationToolbarEnabled = prefs.translationToolbarEnabled
        translateToSourceHotkeyCode = prefs.translateToSourceHotkey.keyCode
        translateToSourceHotkeyModifiers = prefs.translateToSourceHotkey.modifiers.rawValue
        translateToSourceReplaceOriginal = prefs.translateToSourceReplaceOriginal
        translateToSourceCopyToClipboard = prefs.translateToSourceCopyToClipboard
        translateToSourceShowPopup = prefs.translateToSourceShowPopup
        translateToSourceAutoHideSeconds = prefs.translateToSourceAutoHideSeconds
        translationResultAutoHideSeconds = prefs.translationResultAutoHideSeconds

        // Debug settings — written BEFORE the notifications below so observers
        // (XKeyIM) never re-read the plist while these are still unwritten
        debugModeEnabled = prefs.debugModeEnabled
        debugHotkeyCode = prefs.debugHotkey.keyCode
        debugHotkeyModifiers = prefs.debugHotkey.modifiers.rawValue

        // Batch update is done - settings are already written to plist via setters
        isBatchUpdating = false

        // Send ONE notification to notify observers
        notifySettingsChanged()

        // Also notify toolbar settings changed (so toolbar can be enabled/disabled immediately)
        notifyToolbarChanged()

        // Also notify convert tool hotkey changed
        notifyConvertToolHotkeyChanged()

        // Also notify translation settings changed
        notifyTranslationSettingsChanged()

        // Also notify debug settings changed
        notifyDebugSettingsChanged()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when shared settings change (local)
    static let sharedSettingsDidChange = Notification.Name("XKey.sharedSettingsDidChange")
    
    /// Posted when settings change (distributed, cross-app)
    static let xkeySettingsDidChange = Notification.Name("XKey.settingsDidChange")
    
    /// Posted when temp off toolbar settings change (enabled/disabled or hotkey)
    static let tempOffToolbarSettingsDidChange = Notification.Name("XKey.tempOffToolbarSettingsDidChange")

    /// Posted after an iCloud pull rewrites the Window Title Rules store, so the typing engine
    /// (AppBehaviorDetector.customRules) and any open Settings tab reload instead of staying stale.
    static let windowTitleRulesDidChange = Notification.Name("XKey.windowTitleRulesDidChange")

    /// Posted when convert tool hotkey changes
    static let convertToolHotkeyDidChange = Notification.Name("XKey.convertToolHotkeyDidChange")

    /// Posted when translation settings change
    static let translationSettingsDidChange = Notification.Name("XKey.translationSettingsDidChange")

    /// Posted when debug settings change
    static let debugSettingsDidChange = Notification.Name("XKey.debugSettingsDidChange")
    
    /// Posted when translation toolbar settings change (enabled/disabled)
    static let translationToolbarSettingsDidChange = Notification.Name("XKey.translationToolbarSettingsDidChange")
}
