//
//  KeyboardEventHandler.swift
//  XKey
//
//  Handles keyboard events and coordinates between engine and injector
//

import Cocoa
import Combine

class KeyboardEventHandler: EventTapManager.EventTapDelegate {
    
    // MARK: - Properties

    private let session: InputSession
    private let transport: CGEventTransport
    var engine: VNEngine { session.engine }
    private var isVietnameseEnabled = true
    var durableVietnameseEnabled: Bool { isVietnameseEnabled }
    private var appPolicyDecision: AppPolicyDecision = .keepCurrentLanguage

    // Debug logging callback
    var debugLogCallback: ((String) -> Void)?
    
    /// Enable verbose engine logging (causes lag when enabled!)
    /// Only turn on for debugging specific issues
    var verboseEngineLogging: Bool = false {
        didSet { updateEngineLogWiring() }
    }

    /// Frontmost app bundle ID, updated from NSWorkspace.didActivateApplicationNotification
    /// (same boundary the rest of the pipeline uses for app-switch state: engine reset,
    /// confirmed injection method). Avoids an NSWorkspace IPC query on every keystroke.
    /// nil → isCurrentAppExcluded falls back to a live NSWorkspace query.
    private var cachedFrontmostBundleId: String?

    /// Record the current frontmost app. Call from the app-activation observer
    /// (pass the bundle ID from the notification's userInfo) and once at startup.
    func noteFrontmostApp(bundleId: String?) {
        cachedFrontmostBundleId = bundleId
    }
    
    /// Flag to skip updateEngineSettings() during batch updates
    /// This prevents multiple redundant engine updates when applying all settings at once
    private var isBatchUpdating = false

    // Settings
    @Published var inputMethod: InputMethod = .telex {
        didSet { updateEngineSettings() }
    }
    
    @Published var codeTable: CodeTable = .unicode {
        didSet { updateEngineSettings() }
    }
    
    @Published var modernStyle: Bool = true {
        didSet { updateEngineSettings() }
    }
    
    @Published var spellCheckEnabled: Bool = true {
        didSet { updateEngineSettings() }
    }
    

    
    // Advanced features
    @Published var quickTelexEnabled: Bool = true {
        didSet { updateEngineSettings() }
    }
    
    @Published var quickStartConsonantEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var quickEndConsonantEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var upperCaseFirstChar: Bool = false {
        didSet { updateEngineSettings() }
    }

    @Published var capitalizeOnlyAfterSpace: Bool = true {
        didSet { updateEngineSettings() }
    }

    @Published var restoreIfWrongSpelling: Bool = true {
        didSet { updateEngineSettings() }
    }

    @Published var skipRestoreForUppercaseVietnameseAbbreviations: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var customConsonants: Set<UInt16> = [] {
        didSet { updateEngineSettings() }
    }
    
    // Macro settings
    @Published var macroEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var macroInEnglishMode: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var autoCapsMacro: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    @Published var addSpaceAfterMacro: Bool = false {
        didSet { updateEngineSettings() }
    }

    @Published var yieldMacroToSystemReplacement: Bool = false {
        didSet { updateEngineSettings() }
    }
    
    // Smart switch
    @Published var smartSwitchEnabled: Bool = true {
        didSet { updateEngineSettings() }
    }
    
    // Excluded apps
    @Published var excludedApps: [ExcludedApp] = [] {
        didSet {
            excludedBundleIds = Set(excludedApps.map(\.bundleIdentifier))
        }
    }
    /// Membership cache for the per-keystroke exclusion check. The published array remains
    /// the source of truth for UI/persistence and its observer covers assignment and mutation.
    private var excludedBundleIds: Set<String> = []
    @Published var exclusionRulesEnabled: Bool = true  // Master switch for user-defined exclusion rules

    // Undo typing with Esc key
    @Published var undoTypingEnabled: Bool = false {
        didSet { updateEngineSettings() }
    }

    // Managers
    private let macroManager: MacroManager
    private let smartSwitchManager: SmartSwitchManager
    
    // MARK: - Initialization
    
    init(session: InputSession? = nil, transport: CGEventTransport? = nil) {
        let macroManager = MacroManager()
        let smartSwitchManager = SmartSwitchManager()
        VNEngine.setSharedMacroManager(macroManager)
        VNEngine.setSharedSmartSwitchManager(smartSwitchManager)

        let defaultPreferences = RuntimePreferences(
            preferences: Preferences(),
            vietnameseEnabled: true,
            windowTitleRulesEnabled: true,
            remoteDesktopInjectMode: false
        )
        if let session {
            self.session = session
            session.apply(session.preferences)
        } else {
            self.session = InputSession(preferences: defaultPreferences)
        }
        self.transport = transport ?? CGEventTransport()
        self.macroManager = macroManager
        self.smartSwitchManager = smartSwitchManager

        // Set up engine/injector logging (callbacks stay nil while verbose
        // logging is off — see updateEngineLogWiring)
        updateEngineLogWiring()

        // The managers shared with VNEngine above are process-wide statics (see
        // VNEngineMacro.swift / VNEngineSmartSwitch.swift), so this write is
        // visible to every VNEngine instance in the process — including one
        // created before this handler existed, e.g. XKeyIMController's own
        // marked-text engine in XKeyIM, which is built well before the tap
        // ever arms and constructs a KeyboardEventHandler.
        //
        // That sharing is intentional, not a leak: there is exactly one set
        // of user-defined macros and one per-app language map, and every
        // engine in the process should see the same one, regardless of
        // which channel (tap or marked text) is currently typing. The two
        // channels are also mutually exclusive at any instant (XKeyIMController
        // stops processing keys while TapController.isArmed), so this never
        // races two engines against each other.
        //
        // Both physical and marked-text paths use this manager through InputSession;
        // see EngineManagerSharingTests for the convergence guard.
        // Macro manager logging disabled for cleaner output
        // macroManager.logCallback = { [weak self] message in
        //     self?.debugLogCallback?("📦 Macro: \(message)")
        // }
        
        // Load smart switch data from file
        loadSmartSwitchData()
        
        // Listen for macro changes from UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMacrosDidChange),
            name: .macrosDidChange,
            object: nil
        )
        

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleMacrosDidChange() {
        session.reloadMacros()
        
        // Reset engine to clear buffer when macros change
        // This prevents stale buffer from interfering with new macro matching
        session.reset()
        transport.reset(cursorMoved: false, preserveMidSentence: true)
    }
    
    // MARK: - Smart Switch Data Loading
    
    private func loadSmartSwitchData() {
        smartSwitchManager.loadFromPlist()
    }
    
    // MARK: - Vietnamese Toggle
    
    func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        session.setEffectiveVietnameseEnabled(isVietnameseEnabled)
        if !isVietnameseEnabled {
            session.reset()
        }
    }
    
    func setVietnamese(_ enabled: Bool) {
        isVietnameseEnabled = enabled
        session.setEffectiveVietnameseEnabled(enabled)
        if !enabled {
            session.reset()
        }
    }

    func applyAppPolicyDecision(_ decision: AppPolicyDecision,
                                currentVietnameseEnabled: Bool) {
        appPolicyDecision = decision
        switch decision {
        case .keepCurrentLanguage:
            session.setEffectiveVietnameseEnabled(currentVietnameseEnabled)
        case .overrideVietnamese(let enabled):
            session.setEffectiveVietnameseEnabled(enabled)
            if !enabled { session.reset() }
        case .restoreVietnamese(let enabled):
            setVietnamese(enabled)
        case .disableTransformation:
            session.setEffectiveVietnameseEnabled(false)
            session.reset()
        }
    }

    /// Effective Vietnamese state for the current context: a window-title rule may force
    /// enable/disable (InputMethodPolicy), otherwise fall back to the global toggle.
    /// The policy lookup is O(1) (cached in AppBehaviorDetector, refreshed on focus/title/app
    /// changes), so it is safe to call multiple times per keystroke.
    private func effectiveVietnameseEnabled() -> Bool {
        switch appPolicyDecision {
        case .keepCurrentLanguage:
            return isVietnameseEnabled
        case .overrideVietnamese(let enabled), .restoreVietnamese(let enabled):
            return enabled
        case .disableTransformation:
            return false
        }
    }
    
    // MARK: - Undo Typing
    
    /// Perform undo typing operation when triggered by EventTapManager hotkey callback
    /// Returns true if undo was performed (event should be consumed), false otherwise
    func performUndoTyping(event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        guard let effectiveVietnameseEnabled = activeInputContext() else { return false }
        session.setEffectiveVietnameseEnabled(effectiveVietnameseEnabled)
        let inputEvent = InputEvent(kind: .undo,
                                    keyCode: nil,
                                    characters: nil,
                                    modifiers: [],
                                    isRepeat: false)
        let action = session.handle(inputEvent)
        guard case .replacement(let replacement) = action else { return false }
        debugLogCallback?("🔙 Undo typing: backspaces=\(replacement.backspaces), text=\"\(replacement.text)\"")
        _ = transport.apply(action,
                            event: inputEvent,
                            originalEvent: event,
                            proxy: proxy)
        return true
    }
    
    // MARK: - EventTapDelegate

    func waitForPendingInjection() {
        transport.waitForPendingInjection()
    }

    func releaseOwnership(afterPendingInjection release: () -> Void) {
        waitForPendingInjection()
        release()
    }
    
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        guard let effectiveVietnameseEnabled = activeInputContext() else { return false }
        guard type == .keyDown || type == .flagsChanged else { return false }

        session.setEffectiveVietnameseEnabled(effectiveVietnameseEnabled)
        return true
    }

    /// Resolve every host/app/injection gate before InputSession can mutate.
    private func activeInputContext() -> Bool? {
        // Another process's XKeyIM tap is armed for the app in front. Two taps must
        // never both transform one keystroke. This is per-app-accurate: the flag
        // only exists while XKeyIM is the active IME, so switching to an ABC app
        // hands control straight back to us (the global input-source suspend cannot
        // do that). isXKeyIMTapOwningInput is PID-relative, so this is never true
        // inside XKeyIM's own handler for its own tap.
        if SharedSettings.shared.isXKeyIMTapOwningInput {
            return nil
        }

        if appPolicyDecision == .disableTransformation || isCurrentAppExcluded() {
            return nil
        }

        // Confirm passthrough before any session mutation. Inactive/excluded hosts must
        // never accumulate typing state for events owned by another pipeline.
        let confirmedMethod = AppBehaviorDetector.shared.getConfirmedInjectionMethod()
        if confirmedMethod.method == .passthrough {
            return nil
        }

        let effectiveVietnameseEnabled = effectiveVietnameseEnabled()
        let shouldProcessInEnglishMode = !effectiveVietnameseEnabled && macroEnabled && macroInEnglishMode
        guard effectiveVietnameseEnabled || shouldProcessInEnglishMode else {
            return nil
        }
        return effectiveVietnameseEnabled
    }
    
    /// Wire or unwire engine/injector log closures.
    /// While verbose logging is off the callbacks are nil, so the engine and the
    /// injector skip building log strings entirely (they run on every keystroke).
    private func updateEngineLogWiring() {
        if verboseEngineLogging {
            engine.logCallback = { [weak self] message in
                self?.debugLogCallback?("Engine: \(message)")
            }
            transport.debugCallback = { [weak self] message in
                self?.debugLogCallback?("Injector: \(message)")
            }
        } else {
            engine.logCallback = nil
            transport.debugCallback = nil
            // Drop the stale copy CharacterInjector forwarded before verbose was
            // turned off (it is only refreshed right before each AX injection).
            AdvancedInjectionMethods.shared.debugCallback = nil
        }
    }

    /// Shared formatter — creating a DateFormatter per log line is expensive
    /// and this runs on the event tap hot path.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // Helper to get timestamp for debug logging
    private func getTimestamp() -> String {
        return Self.timestampFormatter.string(from: Date())
    }
    
    func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent? {
        // Modifier-only hotkeys trigger on release. Physical flagsChanged events must
        // not clear undo state before EventTapManager observes that release.
        guard type == .keyDown else { return event }
        guard let inputEvent = transport.normalize(event, type: type) else {
            return event
        }

        let action = session.handle(inputEvent)
        if case .replacement(let replacement) = action {
            debugLogCallback?("[\(getTimestamp())] CONSUME: bs=\(replacement.backspaces), text=\"\(replacement.text)\"")
        }
        return transport.apply(action,
                               event: inputEvent,
                               originalEvent: event,
                               proxy: proxy)
    }
    // MARK: - Settings Update
    
    private func updateEngineSettings() {
        // Skip if we're in batch update mode (prevents 16+ redundant updates)
        guard !isBatchUpdating else { return }
        
        var settings = VNEngine.EngineSettings()
        settings.inputMethod = inputMethod
        settings.codeTable = codeTable
        settings.modernStyle = modernStyle
        settings.spellCheckEnabled = spellCheckEnabled
        
        // Advanced features
        settings.quickTelexEnabled = quickTelexEnabled
        settings.quickStartConsonantEnabled = quickStartConsonantEnabled
        settings.quickEndConsonantEnabled = quickEndConsonantEnabled
        settings.upperCaseFirstChar = upperCaseFirstChar
        settings.capitalizeOnlyAfterSpace = capitalizeOnlyAfterSpace
        settings.restoreIfWrongSpelling = restoreIfWrongSpelling
        settings.skipRestoreForUppercaseVietnameseAbbreviations = skipRestoreForUppercaseVietnameseAbbreviations

        settings.customConsonants = customConsonants
        
        // Macro settings
        settings.macroEnabled = macroEnabled
        settings.macroInEnglishMode = macroInEnglishMode
        settings.autoCapsMacro = autoCapsMacro
        settings.addSpaceAfterMacro = addSpaceAfterMacro
        
        // Smart switch
        settings.smartSwitchEnabled = smartSwitchEnabled
        
        session.update(engineSettings: settings,
                       yieldMacroToSystemReplacement: yieldMacroToSystemReplacement,
                       undoTypingEnabled: undoTypingEnabled)
        
        // Debug: Log spell check setting sync
        debugLogCallback?("⚙️ Settings sync: spellCheckEnabled=\(spellCheckEnabled) → vCheckSpelling=\(engine.vCheckSpelling)")

    }

    func apply(_ runtimePreferences: RuntimePreferences) {
        let settings = runtimePreferences.engineSettings
        refreshDictionary(for: settings)
        isBatchUpdating = true

        inputMethod = settings.inputMethod
        codeTable = settings.codeTable
        modernStyle = settings.modernStyle
        spellCheckEnabled = settings.spellCheckEnabled
        quickTelexEnabled = settings.quickTelexEnabled
        quickStartConsonantEnabled = settings.quickStartConsonantEnabled
        quickEndConsonantEnabled = settings.quickEndConsonantEnabled
        upperCaseFirstChar = settings.upperCaseFirstChar
        capitalizeOnlyAfterSpace = settings.capitalizeOnlyAfterSpace
        restoreIfWrongSpelling = settings.restoreIfWrongSpelling
        skipRestoreForUppercaseVietnameseAbbreviations = settings.skipRestoreForUppercaseVietnameseAbbreviations
        customConsonants = settings.customConsonants
        macroEnabled = settings.macroEnabled
        macroInEnglishMode = settings.macroInEnglishMode
        autoCapsMacro = settings.autoCapsMacro
        addSpaceAfterMacro = settings.addSpaceAfterMacro
        yieldMacroToSystemReplacement = runtimePreferences.yieldMacroToSystemReplacement
        smartSwitchEnabled = settings.smartSwitchEnabled
        excludedApps = runtimePreferences.excludedApps
        exclusionRulesEnabled = runtimePreferences.exclusionRulesEnabled
        undoTypingEnabled = runtimePreferences.undoTypingEnabled

        isBatchUpdating = false
        session.apply(runtimePreferences)
        debugLogCallback?("⚙️ Settings sync: spellCheckEnabled=\(spellCheckEnabled) → vCheckSpelling=\(engine.vCheckSpelling)")
        if isVietnameseEnabled != runtimePreferences.vietnameseEnabled {
            setVietnamese(runtimePreferences.vietnameseEnabled)
        }
    }

    private func refreshDictionary(for settings: VNEngine.EngineSettings) {
        let style: VNDictionaryManager.DictionaryStyle = settings.modernStyle ? .dauMoi : .dauCu
        let result = DictionaryRuntime.shared.refresh(enabled: settings.spellCheckEnabled, style: style)
        guard result.didChange else { return }

        switch result.newState {
        case .unavailable(let style):
            debugLogCallback?("Dictionary unavailable: \(style.rawValue)")
        case .failed(let style):
            let diagnostic = result.diagnostic.map { ": \($0)" } ?? ""
            debugLogCallback?("Dictionary load failed: \(style.rawValue)\(diagnostic)")
        case .disabled, .loaded:
            break
        }
    }
    
    // MARK: - Macro Management

    func getMacroManager() -> MacroManager {
        return macroManager
    }

    // MARK: - Reset
    
    func reset() {
        session.reset()
        transport.reset(cursorMoved: false, preserveMidSentence: true)
    }
    
    /// Reset engine and mark that cursor was moved (by mouse click or arrow keys)
    /// This disables autocomplete fix to avoid deleting text on the right of cursor
    /// Also sets engine flag to skip restore logic (user may be editing mid-word)
    func resetWithCursorMoved() {
        _ = session.handle(InputEvent(kind: .focusChanged,
                                      keyCode: nil,
                                      characters: nil,
                                      modifiers: [],
                                      isRepeat: false))
        transport.reset(cursorMoved: true, preserveMidSentence: false)
    }

    /// Reset engine when app switches
    /// Assumes user will likely click into middle of text, so enables mid-sentence mode
    /// This prevents Forward Delete from deleting text on the right of cursor
    func resetForAppSwitch() {
        _ = session.handle(InputEvent(kind: .focusChanged,
                                      keyCode: nil,
                                      characters: nil,
                                      modifiers: [],
                                      isRepeat: false))
        transport.reset(cursorMoved: true, preserveMidSentence: false)
    }
    
    /// Reset engine state when user session becomes active after Fast User Switch.
    /// While off-console, the HID event tap passes through all events untouched,
    /// but the engine buffer may have accumulated stale state. This ensures a
    /// clean slate when the user returns to this session.
    func sessionDidBecomeActive() {
        _ = session.handle(InputEvent(kind: .focusChanged,
                                      keyCode: nil,
                                      characters: nil,
                                      modifiers: [],
                                      isRepeat: false))
        transport.reset(cursorMoved: true, preserveMidSentence: false)
        debugLogCallback?("🖥️ Session active — engine/injector reset for clean Vietnamese input")
    }

    /// Reset mid-sentence flag only (without resetting engine)
    /// Used when clicking into overlay app (Spotlight/Raycast/Alfred) with empty input field
    /// Since the field is empty, Forward Delete is safe (nothing to delete on right)
    func resetMidSentenceFlag() {
        transport.resetMidSentenceFlag()
    }

    // MARK: - Excluded Apps Check
    
    /// Apps that ALWAYS pass through all keys regardless of user setting.
    /// Currently only iOS Simulator — iOS handles its own input internally.
    private static let alwaysPassthroughApps: Set<String> = [
        // "com.apple.screencontinuity",  // iPhone Mirroring - iOS device handles text input
        "com.apple.iphonesimulator",   // Simulator - iOS simulator handles text input
    ]

    /// Check if an app should be in passthrough mode.
    /// Always passthrough: alwaysPassthroughApps (iOS Simulator).
    /// Conditionally passthrough: remote desktop clients — when
    /// `remoteDesktopInjectMode` is OFF (default), remote desktop apps pass through
    /// so the remote machine handles Vietnamese input. When ON, XKey injects
    /// Vietnamese via clipboard paste into the remote desktop client.
    private func isPassthroughApp(bundleId: String) -> Bool {
        let id = bundleId.lowercased()
        if Self.alwaysPassthroughApps.contains(id) { return true }
        if RemoteDesktopBundleIds.all.contains(id) {
            // Passthrough unless user opted into inject mode
            return !SharedSettings.shared.remoteDesktopInjectMode
        }
        return false
    }
    
    /// Check if the current frontmost app is in the excluded list
    /// IMPORTANT: Overlay apps (Spotlight, Raycast, Alfred) are NEVER excluded,
    /// even when the underlying app is in the excluded list.
    /// This allows Vietnamese typing in overlays regardless of the excluded app beneath.
    private func isCurrentAppExcluded() -> Bool {
        // PRIORITY 1: Check if overlay app is active (Spotlight, Raycast, Alfred)
        // Overlay apps use floating panels that don't become frontmostApplication,
        // so NSWorkspace.shared.frontmostApplication would return the excluded app underneath.
        // We must check overlay visibility FIRST to avoid blocking Vietnamese in overlays.
        //
        // The cache, never the probe. This runs inside the CGEventTap callback, and
        // isOverlayAppVisible() would ask the FRONTMOST app's focused element four
        // questions plus AXHelper.getFocusedElement() — up to five blocking round-trips
        // per keystroke, into the app the user is typing in. TapEventSource answers
        // OverlayAppDetector.onProbeArmed and runs those reads on its AX queue instead,
        // so this value is what that work settled on.
        //
        // The injection method that used to be re-detected here — synchronously, on this
        // thread, whenever the confirmed one did not describe an overlay — is now set by
        // the same transition that turns this cache positive. cachedOverlayVisible only
        // ever goes false→true inside OverlayAppDetector.handleOverlayFound, which fires
        // onOverlayVisibilityChanged in that same main-thread turn (the only other writer
        // that can put a true there, applyDismissCheck, runs only while an overlay is
        // ALREADY visible), and TapEventSource's handler for it re-detects and confirms
        // the method from an off-main snapshot with the overlay name resolved.
        if OverlayAppDetector.shared.lastKnownOverlayVisible {
            return false  // Overlay apps are never excluded - allow Vietnamese typing
        }
        
        // PRIORITY 2: Check frontmost application for regular apps.
        // Use the bundle ID cached from didActivateApplicationNotification to avoid
        // an NSWorkspace IPC round-trip per keystroke; fall back to a live query
        // when the cache is empty (startup, missing notification userInfo).
        guard let bundleId = cachedFrontmostBundleId
                ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        
        return isAppExcluded(bundleIdentifier: bundleId)
    }
    
    /// Check if a specific bundle identifier is excluded from XKey processing.
    /// Same policy as the per-keystroke check minus the overlay exemption, so the
    /// Smart Switch paths in AppDelegate agree with the tap on which apps XKey stays
    /// out of: an excluded app must neither restore nor record an E/V state.
    func isAppExcluded(bundleIdentifier: String) -> Bool {
        // Exclude passthrough apps (iOS Simulator + remote desktop clients when
        // remoteDesktopInjectMode is disabled). Case-insensitive bundle ID match.
        if isPassthroughApp(bundleId: bundleIdentifier) {
            return true
        }
        
        // Check user-defined excluded apps (respects master switch)
        guard exclusionRulesEnabled, !excludedBundleIds.isEmpty else { return false }
        return excludedBundleIds.contains(bundleIdentifier)
    }
}
