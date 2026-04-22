//
//  AppDelegate.swift
//  XKey
//
//  Application delegate managing lifecycle and coordination
//

import Cocoa
import SwiftUI
import Sparkle

// MARK: - AXObserver Callback (C function)

/// C callback for AXObserver notifications (focus change + title change)
/// Must be outside class since AXObserver requires a C function pointer
/// Dispatches to appropriate handler based on notification type
private func axNotificationCallback(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    // Get AppDelegate instance from refcon
    guard let refcon = refcon else { return }
    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    let name = notificationName as String
    
    // Handle on main thread — dispatch to appropriate handler
    DispatchQueue.main.async {
        if name == kAXFocusedUIElementChangedNotification as String {
            appDelegate.handleAXFocusChanged(element)
        } else if name == kAXTitleChangedNotification as String {
            appDelegate.handleAXTitleChanged()
        }
    }
}

// MARK: - Focused Element Info (typealias to AppBehaviorDetector)

/// Use the unified FocusedElementInfo struct from AppBehaviorDetector
/// to avoid redundant struct definitions and AX queries
private typealias FocusedElementInfo = AppBehaviorDetector.FocusedElementInfo

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Shared Instance
    
    /// Shared instance for access from SwiftUI views
    static var shared: AppDelegate?
    
    // MARK: - Properties

    private var statusBarManager: StatusBarManager?
    private var eventTapManager: EventTapManager?
    private var keyboardHandler: KeyboardEventHandler?
    private var debugWindowController: DebugWindowController?
    @available(macOS 13.0, *)
    private var settingsWindowController: SettingsWindowController? {
        get { _settingsWindowController as? SettingsWindowController }
        set { _settingsWindowController = newValue }
    }
    private var _settingsWindowController: NSWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var readWordHotKeyMonitor: Any?
    private var readWordGlobalHotKeyMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var mouseClickMonitor: Any?
    private var permissionAlertShown = false
    private var permissionCheckTimer: Timer?
    private var inputSourceManager: InputSourceManager?
    private var switchXKeyHotkeyMonitor: Any?
    private var switchXKeyGlobalHotkeyMonitor: Any?
    private var tempOffToolbarHotkeyMonitor: Any?
    private var tempOffToolbarGlobalHotkeyMonitor: Any?
    private var focusObserver: AXObserver?
    private var focusObserverPID: pid_t = 0
    private var lastFocusedElement: AXUIElement?
    private var updaterController: SPUStandardUpdaterController?
    private var sparkleUpdateDelegate: SparkleUpdateDelegate?
    
    /// Store the input source ID BEFORE a Window Title Rule switched it
    /// Used to restore when leaving the rule-controlled context
    private var preRuleInputSourceId: String? = nil
    
    /// Track the last focused element's signature for injection detection
    /// Used to detect when user switches from web content to address bar, etc.
    /// Signature includes role, subrole, and description/identifier
    private var lastFocusedElementSignature: String = ""
    
    /// Throttle AXObserver focus change callbacks to prevent rapid-fire AX queries
    /// When apps have animations or autocomplete, AXObserver can fire many times per second
    private var lastAXFocusChangeTime: CFAbsoluteTime = 0
    private let axFocusChangeThrottleInterval: CFAbsoluteTime = 0.1 // 100ms
    
    /// Delayed title verification after AXObserver focus change (Layer 2)
    /// Catches stale window titles when apps update title AFTER focus change notification
    private var titleVerificationWorkItem: DispatchWorkItem?
    
    /// Window title used in last detection — for comparing in delayed verification
    private var lastDetectedTitle: String?
    
    /// Debounce for kAXTitleChangedNotification (Layer 1)
    /// Apps may fire multiple title changes during a single navigation (e.g., "Loading..." → final title)
    private var titleChangeDebounceWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    override init() {
        super.init()
    }
    
    // MARK: - Public Accessors

    /// Get the keyboard handler for external access
    func getKeyboardHandler() -> KeyboardEventHandler? {
        return keyboardHandler
    }

    /// Get the macro manager for external access
    func getMacroManager() -> MacroManager? {
        if keyboardHandler == nil {
            logToDebugWindow("AppDelegate.getMacroManager: keyboardHandler is nil!")
            return nil
        }
        return keyboardHandler?.getMacroManager()
    }

    /// Log message to debug window (for external access)
    func logToDebugWindow(_ message: String) {
        debugWindowController?.logEvent(message)
    }

    /// Get the Sparkle updater for external access
    func getSparkleUpdater() -> SPUUpdater? {
        return updaterController?.updater
    }

    // MARK: - Application Lifecycle
    
    /// Check if app is running under unit tests
    private var isRunningTests: Bool {
        return NSClassFromString("XCTestCase") != nil
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SINGLE INSTANCE GUARD: Terminate if another instance is already running
        // This prevents duplicate status bar icons when opening from both
        // /Applications and build directory simultaneously
        if !isRunningTests {
            if let bundleId = Bundle.main.bundleIdentifier {
                let runningApps = NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleId
                )
                // Filter to only OTHER instances (exclude self)
                let otherInstances = runningApps.filter { $0 != NSRunningApplication.current }
                if !otherInstances.isEmpty {
                    // Other instance(s) running — terminate them, new instance takes over
                    for oldInstance in otherInstances {
                        NSLog("[XKey] Terminating old instance (PID: %d)", oldInstance.processIdentifier)
                        oldInstance.terminate()
                    }
                    // Brief delay to allow old instance(s) to fully clean up
                    // (release status bar icon, event tap, etc.)
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
        }
        
        // Set shared instance for access from SwiftUI views
        AppDelegate.shared = self
        
        // Skip most setup when running under unit tests
        // Tests only need access to VNEngine and related classes
        if isRunningTests {
            // Minimal setup for tests - just create the handler without event tap
            keyboardHandler = KeyboardEventHandler()
            return
        }
        
        // Create debug window first
        setupDebugWindow()
        
        // Load and apply preferences
        let preferences = SharedSettings.shared.loadPreferences()
        
        // Load custom Window Title Rules
        AppBehaviorDetector.shared.loadCustomRules()
        debugWindowController?.logEvent("Loaded \(AppBehaviorDetector.shared.getCustomRules().count) custom Window Title Rules")
        
        // Inject OverlayAppDetector into AppBehaviorDetector
        // This allows Shared/AppBehaviorDetector to detect overlay apps without direct dependency
        AppBehaviorDetector.shared.overlayAppNameProvider = {
            return OverlayAppDetector.shared.getVisibleOverlayAppName()
        }
        
        // Connect debug logging from AppBehaviorDetector to Debug Window
        AppBehaviorDetector.shared.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // Initialize components
        setupKeyboardHandling()
        setupStatusBar()
        
        // Apply loaded preferences
        applyPreferences(preferences)

        // Check permissions
        checkAndRequestPermissions()

        // Setup global hotkey
        setupGlobalHotkey()
        
        // Setup read word hotkey
        setupReadWordHotkey()

        // Setup app switch observer
        setupAppSwitchObserver()
        
        // Setup mouse click monitor
        setupMouseClickMonitor()

        // Setup input source manager
        setupInputSourceManager()

        // Setup temp off toolbar (also handles focus change monitoring for injection detection)
        setupTempOffToolbar()

        // Setup convert tool hotkey
        setupConvertToolHotkey()

        // Setup translation hotkey
        setupTranslationHotkey()

        // Setup debug hotkey
        setupDebugHotkey()

        // Setup toggle exclusion rules hotkey
        setupToggleExclusionHotkey()

        // Setup toggle window title rules hotkey
        setupToggleWindowRulesHotkey()

        // Setup Sparkle auto-update
        setupSparkleUpdater()

        // Check and update XKeyIM if needed (on app startup)
        checkXKeyIMUpdate()

        // Load Vietnamese dictionary if spell checking is enabled
        setupSpellCheckDictionary()

        // Initialize AudioManager to handle wake-from-sleep audio issues
        // This must be done at startup to register for system sleep/wake notifications
        _ = AudioManager.shared
        debugWindowController?.logEvent("AudioManager initialized for wake-from-sleep handling")

        // Check for Secure Input mode — this blocks ALL CGEvent taps from receiving keyDown events.
        // Common cause: 1Password, Terminal, browser password fields holding Secure Input ON.
        checkAndWarnSecureInput()

        debugWindowController?.updateStatus("XKey started successfully")
        debugWindowController?.logEvent("XKey started successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugWindowController?.logEvent("👋 XKey terminating...")
        eventTapManager?.stop()

        // Remove read word hotkey monitors
        if let monitor = readWordHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = readWordGlobalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Remove switch XKey hotkey monitors
        if let monitor = switchXKeyHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = switchXKeyGlobalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Remove temp off toolbar hotkey monitors
        if let monitor = tempOffToolbarHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = tempOffToolbarGlobalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Stop focus observer
        removeAXObserver()

        // Remove app switch observer
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        
        // Stop permission check timer
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - URL Scheme Handler
    
    /// Handle URL scheme: xkey://settings opens preferences
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "xkey" else { continue }
            
            switch url.host {
            case "settings", "preferences":
                // Open settings window
                debugWindowController?.logEvent("Received URL: \(url.absoluteString) - opening settings")
                openPreferences()
            default:
                // Just activate the app
                debugWindowController?.logEvent("Received URL: \(url.absoluteString)")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // MARK: - Setup

    private func setupDebugWindow() {
        // Check if debug mode is enabled in preferences
        let preferences = SharedSettings.shared.loadPreferences()
        
        // Show debug window if:
        // 1. debugModeEnabled is true (user explicitly enabled debug mode), OR
        // 2. openDebugOnLaunch is true (user wants to open debug on every launch)
        let shouldShowDebug = preferences.debugModeEnabled || preferences.openDebugOnLaunch

        // Show debug window only if enabled in settings
        if shouldShowDebug {
            debugWindowController = DebugWindowController()
            debugWindowController?.showWindow(nil)

            // Connect DebugLogger to debug window
            DebugLogger.shared.debugWindowController = debugWindowController

            // Setup read word callback
            debugWindowController?.setupReadWordCallback { [weak self] in
                self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
            }
            
            // Setup verbose logging callback - sync with keyboardHandler
            debugWindowController?.setupVerboseLoggingCallback { [weak self] isVerbose in
                self?.keyboardHandler?.verboseEngineLogging = isVerbose
                self?.debugWindowController?.logEvent(isVerbose ? "Verbose engine logging ENABLED (may cause lag)" : "Verbose engine logging DISABLED")
            }
            
            // Trigger callback immediately with current value to sync initial state
            // (didSet is not called during property initialization)
            if let controller = debugWindowController, controller.isVerboseLogging {
                keyboardHandler?.verboseEngineLogging = true
                debugWindowController?.logEvent("Verbose engine logging ENABLED (initial state)")
            }
            
            // Setup window close callback - disable debug mode when window is closed via Close button
            debugWindowController?.onWindowClose = { [weak self] in
                self?.handleDebugWindowClosed()
            }
        }
    }

    private func setupKeyboardHandling() {
        // Create keyboard handler
        keyboardHandler = KeyboardEventHandler()
        debugWindowController?.logEvent("Keyboard handler created")
        
        // Connect debug logging (only if logging is enabled)
        // Filter to reduce log spam
        keyboardHandler?.debugLogCallback = { [weak self] message in
            guard let self = self,
                  let debugWindow = self.debugWindowController,
                  debugWindow.isLoggingEnabled else { return }
            
            // Filter out verbose messages to reduce lag (unless verbose mode)
            if debugWindow.isVerboseLogging {
                debugWindow.logEvent(message)
            } else {
                // Always log important messages
                let shouldLog = message.contains("KEY:") ||
                               message.contains("CONSUME") ||
                               message.contains("Inject:") ||
                               message.contains("BACKSPACE") ||
                               message.contains("WORD BREAK") ||
                               message.contains("CURSOR MOVEMENT") ||
                               message.contains("===") ||
                               message.contains("DEBUG:") ||  // Read Word logs
                               message.contains("Text:") ||
                               message.contains("Word:") ||
                               message.contains("Valid:") ||
                               message.contains("Chrome") ||  // Chrome fix logs
                               message.contains("[AX]")  // Accessibility logs
                
                if shouldLog {
                    debugWindow.logEvent(message)
                }
            }
        }

        // Create event tap manager
        eventTapManager = EventTapManager()
        eventTapManager?.delegate = keyboardHandler
        debugWindowController?.logEvent("Event tap manager created, delegate set")
        
        // Connect debug logging (only if logging is enabled)
        // EventTap logs are very verbose, skip most of them
        eventTapManager?.debugLogCallback = { [weak self] message in
            guard let self = self,
                  let debugWindow = self.debugWindowController,
                  debugWindow.isLoggingEnabled else { return }
            
            // Log important EventTap messages (setup, errors, status changes)
            let shouldLog = message.contains("No delegate") ||
                           message.contains("disabled") ||
                           message.contains("started") ||   // Start
                           message.contains("[OK]") ||      // Success
                           message.contains("[ERROR]") ||   // Error
                           message.contains("stopped")      // Stop
            
            if shouldLog {
                debugWindow.logEvent(message)
            }
        }
        
        // Setup ForceAccessibilityManager log callback
        ForceAccessibilityManager.shared.logCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // IMPORTANT: Sync verboseEngineLogging AFTER keyboardHandler is created
        // setupDebugWindow() runs before setupKeyboardHandling(), so keyboardHandler is nil
        // when the verbose logging callback tries to set verboseEngineLogging.
        // We must sync it here after keyboardHandler exists.
        if let controller = debugWindowController, controller.isVerboseLogging {
            keyboardHandler?.verboseEngineLogging = true
            debugWindowController?.logEvent("Verbose engine logging synced after keyboardHandler creation")
        }

        // Check permission BEFORE trying to start event tap
        // This prevents macOS system dialog from appearing
        guard let manager = eventTapManager else { return }

        // Check if current input source is XKeyIM
        // If so, don't start event tap yet (will be started when switching away)
        if let currentSource = InputSourceManager.getCurrentInputSource(),
           InputSourceManager.isXKeyInputSource(currentSource) {
            debugWindowController?.logEvent("  Current input source is XKeyIM - event tap will NOT start")
            debugWindowController?.logEvent("     Event tap will start automatically when switching away from XKeyIM")
            return
        }

        if manager.checkAccessibilityPermission() {
            // Permission already granted, start event tap
            do {
                try manager.start()
                debugWindowController?.updateStatus("Event tap started - Ready to type!")
            } catch {
                debugWindowController?.updateStatus("ERROR: Failed to start event tap")
            }
        } else {
            // No permission yet - don't call start() to avoid system dialog
            debugWindowController?.updateStatus("Waiting for accessibility permission...")
        }
    }
    
    private func setupStatusBar() {
        statusBarManager = StatusBarManager(
            keyboardHandler: keyboardHandler,
            eventTapManager: eventTapManager
        )
        statusBarManager?.viewModel.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        statusBarManager?.viewModel.onOpenMacroManagement = { [weak self] in
            self?.openMacroManagement()
        }
        statusBarManager?.viewModel.onOpenConvertTool = { [weak self] in
            self?.openConvertTool()
        }
        statusBarManager?.viewModel.onOpenDebugWindow = { [weak self] in
            self?.openDebugWindow()
        }
        statusBarManager?.viewModel.onToggleDebugWindow = { [weak self] in
            self?.toggleDebugWindowFromMenu()
        }
        statusBarManager?.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }

        // Sync initial debug mode state
        let prefs = SharedSettings.shared.loadPreferences()
        statusBarManager?.viewModel.debugModeEnabled = prefs.debugModeEnabled
        statusBarManager?.setupStatusBar()
    }
    
    // MARK: - Preferences
    
    func openPreferences() {
        if #available(macOS 13.0, *) {
            openSettings()
        } else {
            openLegacyPreferences()
        }
    }
    
    @available(macOS 13.0, *)
    func openSettings(selectedSection: SettingsSection = .general) {
        // Close existing window if section is different
        if let existingController = settingsWindowController {
            existingController.close()
            settingsWindowController = nil
        }
        
        let controller = SettingsWindowController(selectedSection: selectedSection) { [weak self] preferences in
            self?.applyPreferences(preferences)
        }
        
        // Handle window close to release memory
        controller.onWindowClosed = { [weak self] in
            self?.settingsWindowController = nil
        }
        
        settingsWindowController = controller
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openLegacyPreferences(selectedTab: Int = 0) {
        // Close existing window if tab is different
        if let existingController = preferencesWindowController {
            existingController.close()
            preferencesWindowController = nil
        }
        
        let controller = PreferencesWindowController(selectedTab: selectedTab) { [weak self] preferences in
            self?.applyPreferences(preferences)
        }
        
        // Handle window close to release memory
        controller.onWindowClosed = { [weak self] in
            self?.preferencesWindowController = nil
        }
        
        preferencesWindowController = controller
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openMacroManagement() {
        if #available(macOS 13.0, *) {
            openSettings(selectedSection: .macro)
        } else {
            openLegacyPreferences(selectedTab: 6) // Tab 6 = Macro
        }
    }
    
    func openConvertTool() {
        if #available(macOS 13.0, *) {
            openSettings(selectedSection: .convertTool)
        } else {
            openLegacyPreferences(selectedTab: 7) // Tab 7 = Chuyển đổi
        }
    }
    
    func openDebugWindow() {
        // Enable debug mode in preferences if not already enabled
        var prefs = SharedSettings.shared.loadPreferences()
        if !prefs.debugModeEnabled {
            prefs.debugModeEnabled = true
            SharedSettings.shared.savePreferences(prefs)
        }
        
        // Enable debug window and show it
        toggleDebugWindow(enabled: true)
        
        // Connect status bar's debugWindowController
        statusBarManager?.debugWindowController = debugWindowController
        
        debugWindowController?.logEvent("🛠️ Debug window opened via menu")
    }
    
    private func applyPreferences(_ preferences: Preferences) {
        // Apply all engine settings at once (batch update - only 1 log message instead of 16+)
        keyboardHandler?.applyAllSettings(
            inputMethod: preferences.inputMethod,
            codeTable: preferences.codeTable,
            modernStyle: preferences.modernStyle,
            spellCheckEnabled: preferences.spellCheckEnabled,
            quickTelexEnabled: preferences.quickTelexEnabled,
            quickStartConsonantEnabled: preferences.quickStartConsonantEnabled,
            quickEndConsonantEnabled: preferences.quickEndConsonantEnabled,
            upperCaseFirstChar: preferences.upperCaseFirstChar,
            restoreIfWrongSpelling: preferences.restoreIfWrongSpelling,
            customConsonants: preferences.customConsonantEnabled ? preferences.customConsonants : "",
            macroEnabled: preferences.macroEnabled,
            macroInEnglishMode: preferences.macroInEnglishMode,
            autoCapsMacro: preferences.autoCapsMacro,
            addSpaceAfterMacro: preferences.addSpaceAfterMacro,
            smartSwitchEnabled: preferences.smartSwitchEnabled,
            excludedApps: preferences.excludedApps,
            undoTypingEnabled: preferences.undoTypingEnabled
        )
        
        // Apply debug mode (toggle debug window)
        // Keep debug window open if either debugModeEnabled OR openDebugOnLaunch is true
        let shouldShowDebug = preferences.debugModeEnabled || preferences.openDebugOnLaunch
        toggleDebugWindow(enabled: shouldShowDebug)
        
        // Update status bar manager
        statusBarManager?.viewModel.currentInputMethod = preferences.inputMethod
        statusBarManager?.viewModel.currentCodeTable = preferences.codeTable
        
        // Update hotkey display in menu
        statusBarManager?.updateHotkeyDisplay(preferences.toggleHotkey)
        
        // Update menu bar icon style
        statusBarManager?.updateMenuBarIconStyle(preferences.menuBarIconStyle)
        
        // Update auto-check for updates setting
        updaterController?.updater.automaticallyChecksForUpdates = preferences.autoCheckForUpdates
        
        // Update Dock icon visibility
        updateDockIconVisibility(show: preferences.showDockIcon)
        
        // Update hotkey
        setupGlobalHotkey(with: preferences.toggleHotkey)
        
        // Update switch XKey hotkey
        setupSwitchXKeyHotkey(with: preferences.switchToXKeyHotkey)
        
        // Update undo typing hotkey
        setupUndoTypingHotkey(with: preferences.undoTypingHotkey, enabled: preferences.undoTypingEnabled)
        
        if preferences.undoTypingEnabled {
            if let hotkey = preferences.undoTypingHotkey {
                debugWindowController?.logEvent("Undo typing enabled with hotkey: \(hotkey.displayString)")
            } else {
                debugWindowController?.logEvent("Undo typing enabled (default: Esc key)")
            }
        } else {
            debugWindowController?.logEvent("Undo typing disabled")
        }


        // Apply toggle states
        keyboardHandler?.exclusionRulesEnabled = preferences.exclusionRulesEnabled
        AppBehaviorDetector.shared.windowTitleRulesEnabled = preferences.windowTitleRulesEnabled

        // Update toggle exclusion hotkey (pass hotkey directly to avoid re-loading preferences)
        updateToggleExclusionHotkey(hotkey: preferences.toggleExclusionHotkey)

        // Update toggle window rules hotkey (pass hotkey directly to avoid re-loading preferences)
        updateToggleWindowRulesHotkey(hotkey: preferences.toggleWindowRulesHotkey)

        debugWindowController?.logEvent("Preferences applied (including advanced features)")
    }

    
    // MARK: - Debug Window Management

    /// Toggle debug window from menu bar (open if closed, close if open)
    private func toggleDebugWindowFromMenu() {
        var prefs = SharedSettings.shared.loadPreferences()
        let newEnabled = !prefs.debugModeEnabled

        prefs.debugModeEnabled = newEnabled
        SharedSettings.shared.savePreferences(prefs)

        // Update viewModel
        statusBarManager?.viewModel.debugModeEnabled = newEnabled

        // Toggle the window
        toggleDebugWindow(enabled: newEnabled)

        // Connect status bar's debugWindowController if enabled
        if newEnabled {
            statusBarManager?.debugWindowController = debugWindowController
            debugWindowController?.logEvent("🛠️ Debug window opened via menu")
        }
    }

    private func toggleDebugWindow(enabled: Bool) {
        // Respect the debug mode setting
        if enabled {
            // Enable debug window
            if debugWindowController == nil {
                debugWindowController = DebugWindowController()
                debugWindowController?.setupReadWordCallback { [weak self] in
                    self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
                }
                // Setup verbose logging callback - sync with keyboardHandler
                debugWindowController?.setupVerboseLoggingCallback { [weak self] isVerbose in
                    self?.keyboardHandler?.verboseEngineLogging = isVerbose
                    self?.debugWindowController?.logEvent(isVerbose ? "Verbose engine logging ENABLED (may cause lag)" : "Verbose engine logging DISABLED")
                }
                
                // Trigger callback immediately with current value to sync initial state
                // (didSet is not called during property initialization)
                if let controller = debugWindowController, controller.isVerboseLogging {
                    keyboardHandler?.verboseEngineLogging = true
                    debugWindowController?.logEvent("Verbose engine logging ENABLED (initial state)")
                }
                // Setup window close callback - disable debug mode when window is closed via Close button
                debugWindowController?.onWindowClose = { [weak self] in
                    self?.handleDebugWindowClosed()
                }
                // Setup memory release callback - nil out reference when window closes
                debugWindowController?.onWindowClosed = { [weak self] in
                    self?.debugWindowController = nil
                    DebugLogger.shared.debugWindowController = nil
                }
                debugWindowController?.logEvent("Debug window enabled via settings")
            }
            debugWindowController?.showWindow(nil)
        } else {
            // Disable debug window - also disable verbose logging
            keyboardHandler?.verboseEngineLogging = false
            if let window = debugWindowController?.window {
                window.close()
                debugWindowController = nil
            }
        }
    }
    
    /// Handle when debug window is closed via Close button on title bar
    private func handleDebugWindowClosed() {
        // Disable debug mode in preferences
        var prefs = SharedSettings.shared.loadPreferences()
        prefs.debugModeEnabled = false
        SharedSettings.shared.savePreferences(prefs)

        // Update viewModel to sync menu
        statusBarManager?.viewModel.debugModeEnabled = false

        // Cleanup
        keyboardHandler?.verboseEngineLogging = false
        debugWindowController = nil

        // Disconnect from DebugLogger
        DebugLogger.shared.debugWindowController = nil

        // Log to file (window is closing, but file logging still works)
        DebugLogger.shared.log("🛠️ Debug window closed - Debug mode disabled")
    }
    
    // MARK: - Permissions
    
    private func checkAndRequestPermissions() {
        guard let manager = eventTapManager else { return }
        
        if !manager.checkAccessibilityPermission() {
            showPermissionAlert()
            // Start monitoring for permission changes
            startPermissionMonitoring()
        }
    }
    
    private func showPermissionAlert() {
        // Only show alert once
        guard !permissionAlertShown else { return }
        permissionAlertShown = true
        
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        XKey needs accessibility permission to function as a Vietnamese input method.
        
        Please grant permission in System Settings > Privacy & Security > Accessibility.
        
        After granting permission, XKey will automatically start working.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openAccessibilityPreferences()
            // Don't show alert again after opening settings
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        
        debugWindowController?.logEvent("Opening System Settings for Accessibility permission")
    }
    
    private func startPermissionMonitoring() {
        // Check permission every 2 seconds
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let manager = self.eventTapManager else { return }
            
            if manager.checkAccessibilityPermission() {
                // Permission granted! Try to start event tap
                self.debugWindowController?.logEvent("Accessibility permission granted!")
                
                do {
                    try manager.start()
                    self.debugWindowController?.updateStatus("Event tap started - Ready to type!")
                    self.debugWindowController?.logEvent("Event tap started successfully after permission grant")
                    
                    // Stop monitoring
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    
                } catch {
                    self.debugWindowController?.logEvent("Failed to start event tap: \(error)")
                }
            }
        }
        
        debugWindowController?.logEvent("Started monitoring for permission changes")
    }

    private func setupGlobalHotkey() {
        let preferences = SharedSettings.shared.loadPreferences()
        setupGlobalHotkey(with: preferences.toggleHotkey)
    }
    
    private func setupGlobalHotkey(with hotkey: Hotkey) {
        // Configure EventTapManager to handle toggle hotkey
        // This ensures the hotkey is consumed at the lowest level
        // and doesn't reach other applications
        eventTapManager?.toggleHotkey = hotkey
        eventTapManager?.onToggleHotkey = { [weak self] in
            // If using Fn key or Ctrl+Space, temporarily ignore input source changes
            // This prevents macOS's input source switching from interfering
            if hotkey.modifiers.contains(.function) || 
               (hotkey.modifiers == [.control] && hotkey.keyCode == 49) { // Space keyCode
                self?.inputSourceManager?.temporarilyIgnoreInputSourceChanges(forSeconds: 0.5)
            }
            
            self?.statusBarManager?.viewModel.toggleVietnamese()
            
            self?.debugWindowController?.logEvent("Toggled Vietnamese mode via hotkey (\(hotkey.displayString))")
        }

        debugWindowController?.logEvent("Toggle hotkey configured: \(hotkey.displayString)")
    }
    
    private func setupUndoTypingHotkey(with hotkey: Hotkey?, enabled: Bool) {
        // If undo typing is disabled, clear the hotkey
        guard enabled else {
            eventTapManager?.undoTypingHotkey = nil
            eventTapManager?.onUndoTypingHotkey = nil
            return
        }
        
        // If custom hotkey is set, configure EventTapManager to handle it
        // Otherwise, default Esc behavior is handled in KeyboardEventHandler
        if let hotkey = hotkey {
            eventTapManager?.undoTypingHotkey = hotkey
            eventTapManager?.onUndoTypingHotkey = { [weak self] in
                guard let handler = self?.keyboardHandler else { return false }
                return handler.performUndoTyping()
            }
            debugWindowController?.logEvent("Undo typing hotkey configured: \(hotkey.displayString)")
        } else {
            // Use default Esc key - set a default Esc hotkey
            let defaultEscHotkey = Hotkey(keyCode: VietnameseData.KEY_ESC, modifiers: [], isModifierOnly: false)
            eventTapManager?.undoTypingHotkey = defaultEscHotkey
            eventTapManager?.onUndoTypingHotkey = { [weak self] in
                guard let handler = self?.keyboardHandler else { return false }
                return handler.performUndoTyping()
            }
            debugWindowController?.logEvent("Undo typing hotkey configured: Esc (default)")
        }
    }
    
    private func setupReadWordHotkey() {
        // Remove existing monitors
        if let monitor = readWordHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = readWordGlobalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Shortcut: Cmd+Shift+R for "Read Word Before Cursor" (changed from Z to avoid Redo conflict)
        let keyCode: UInt16 = 0x0F // R key
        
        // Helper to check modifiers (only Cmd+Shift, no other modifiers)
        let checkModifiers: (NSEvent) -> Bool = { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return flags.contains(.command) && flags.contains(.shift) && 
                   !flags.contains(.option) && !flags.contains(.control)
        }
        
        // Global monitor - catches hotkey in ALL apps
        readWordGlobalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == keyCode && checkModifiers(event) {
                DispatchQueue.main.async {
                    self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
                    
                    self?.debugWindowController?.logEvent("Read Word triggered via hotkey (Cmd+Shift+R)")
                }
            }
        }
        
        // Local monitor - catches hotkey when XKey app is focused
        readWordHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == keyCode && checkModifiers(event) {
                DispatchQueue.main.async {
                    self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
                    
                    self?.debugWindowController?.logEvent("Read Word triggered via hotkey (Cmd+Shift+R)")
                }
                // Return nil to consume the event
                return nil
            }
            return event
        }
        
        debugWindowController?.logEvent("Read Word hotkey: Cmd+Shift+R")
    }
    
    // State tracking for modifier-only switch XKey hotkey
    private var switchXKeyModifierState: (targetReached: Bool, hasTriggered: Bool) = (false, false)
    private var switchXKeyFlagsMonitor: Any?
    private var switchXKeyGlobalFlagsMonitor: Any?
    
    private func setupSwitchXKeyHotkey(with hotkey: Hotkey?) {
        // Remove existing monitors
        if let monitor = switchXKeyHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            switchXKeyHotkeyMonitor = nil
        }
        if let monitor = switchXKeyGlobalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            switchXKeyGlobalHotkeyMonitor = nil
        }
        if let monitor = switchXKeyFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            switchXKeyFlagsMonitor = nil
        }
        if let monitor = switchXKeyGlobalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            switchXKeyGlobalFlagsMonitor = nil
        }
        
        // Reset modifier state
        switchXKeyModifierState = (false, false)
        
        guard let hotkey = hotkey else {
            debugWindowController?.logEvent("  Switch XKey hotkey disabled")
            return
        }
        
        let keyCode = hotkey.keyCode
        
        // Helper to check modifiers match exactly
        let checkModifiers: (NSEvent) -> Bool = { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var requiredFlags: NSEvent.ModifierFlags = []
            
            if hotkey.modifiers.contains(.command) { requiredFlags.insert(.command) }
            if hotkey.modifiers.contains(.control) { requiredFlags.insert(.control) }
            if hotkey.modifiers.contains(.option) { requiredFlags.insert(.option) }
            if hotkey.modifiers.contains(.shift) { requiredFlags.insert(.shift) }
            
            // Check if flags match exactly (only required modifiers, no extras)
            let significantFlags = NSEvent.ModifierFlags([.command, .control, .option, .shift])
            let actualFlags = flags.intersection(significantFlags)
            return actualFlags == requiredFlags
        }
        
        // Perform the actual toggle
        let performToggle: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                // Check state BEFORE toggle
                let wasXKey = InputSourceSwitcher.shared.isXKeyActive
                let action = wasXKey ? "XKey → ABC" : "ABC → XKey"

                // Perform toggle
                let success = InputSourceSwitcher.shared.toggleXKey()
                self?.debugWindowController?.logEvent("Toggle input source via hotkey (\(hotkey.displayString)) [\(action)]: \(success ? "success" : "failed")")
            }
        }
        
        // Handle modifier-only hotkey (e.g., Ctrl+Shift)
        if hotkey.isModifierOnly {
            // Helper to handle flagsChanged events
            let handleFlagsChanged: (NSEvent) -> Void = { [weak self] event in
                guard let self = self else { return }
                
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var requiredFlags: NSEvent.ModifierFlags = []
                
                if hotkey.modifiers.contains(.command) { requiredFlags.insert(.command) }
                if hotkey.modifiers.contains(.control) { requiredFlags.insert(.control) }
                if hotkey.modifiers.contains(.option) { requiredFlags.insert(.option) }
                if hotkey.modifiers.contains(.shift) { requiredFlags.insert(.shift) }
                if hotkey.modifiers.contains(.function) { requiredFlags.insert(.function) }
                
                // Check if all required modifiers are currently pressed
                let significantFlags = NSEvent.ModifierFlags([.command, .control, .option, .shift, .function])
                let actualFlags = flags.intersection(significantFlags)
                let hasAllRequiredModifiers = actualFlags == requiredFlags
                
                if hasAllRequiredModifiers {
                    // All required modifiers are pressed
                    if !self.switchXKeyModifierState.targetReached {
                        self.switchXKeyModifierState.targetReached = true
                        self.switchXKeyModifierState.hasTriggered = false
                        self.debugWindowController?.logEvent("  → Switch XKey target modifiers REACHED: \(hotkey.displayString)")
                    }
                } else {
                    // Modifiers changed (released)
                    if self.switchXKeyModifierState.targetReached && !self.switchXKeyModifierState.hasTriggered {
                        // Was holding target modifiers, now released - TRIGGER!
                        self.switchXKeyModifierState.hasTriggered = true
                        self.debugWindowController?.logEvent("  → SWITCH XKEY MODIFIER-ONLY HOTKEY TRIGGERED on release: \(hotkey.displayString)")
                        performToggle()
                    }
                    // Reset state
                    self.switchXKeyModifierState.targetReached = false
                }
            }
            
            // Global monitor for flagsChanged
            switchXKeyGlobalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                handleFlagsChanged(event)
            }
            
            // Local monitor for flagsChanged
            switchXKeyFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                handleFlagsChanged(event)
                return event  // Pass through flagsChanged events
            }
            
            // Also need keyDown monitors to cancel modifier-only hotkey if a key is pressed
            switchXKeyGlobalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                // If user presses any key while holding modifiers, cancel the modifier-only hotkey
                if self?.switchXKeyModifierState.targetReached == true {
                    self?.debugWindowController?.logEvent("  → Key pressed while holding modifiers - canceling switch XKey modifier-only hotkey")
                    self?.switchXKeyModifierState.targetReached = false
                    self?.switchXKeyModifierState.hasTriggered = true  // Prevent trigger on release
                }
            }
            
            switchXKeyHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // If user presses any key while holding modifiers, cancel the modifier-only hotkey
                if self?.switchXKeyModifierState.targetReached == true {
                    self?.debugWindowController?.logEvent("  → Key pressed while holding modifiers - canceling switch XKey modifier-only hotkey")
                    self?.switchXKeyModifierState.targetReached = false
                    self?.switchXKeyModifierState.hasTriggered = true  // Prevent trigger on release
                }
                return event  // Pass through keyDown events
            }
            
            debugWindowController?.logEvent("Switch XKey hotkey (modifier-only): \(hotkey.displayString)")
        } else {
            // Regular hotkey (e.g., Cmd+Shift+V)
            
            // Global monitor - catches hotkey in ALL apps
            switchXKeyGlobalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == keyCode && checkModifiers(event) {
                    performToggle()
                }
            }

            // Local monitor - catches hotkey when XKey app is focused
            switchXKeyHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == keyCode && checkModifiers(event) {
                    performToggle()
                    // Return nil to consume the event
                    return nil
                }
                return event
            }
            
            debugWindowController?.logEvent("Switch XKey hotkey: \(hotkey.displayString)")
        }
    }

    private func setupAppSwitchObserver() {
        // Listen for app activation changes to reset engine buffer
        // This prevents buffer from previous app affecting typing in new app
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            // Reset keyboard handler engine when switching apps
            // Use resetForAppSwitch() which assumes typing mid-sentence to prevent
            // Forward Delete from deleting text on the right of cursor
            self.keyboardHandler?.resetForAppSwitch()

            AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
            
            // Cancel pending title verifications from previous app
            self.titleVerificationWorkItem?.cancel()
            self.titleChangeDebounceWorkItem?.cancel()
            self.lastDetectedTitle = nil

            // Apply Force Accessibility (AXManualAccessibility) FIRST if matching rule exists
            // This MUST happen BEFORE detectInjectionMethod() because:
            // 1. Force AX enables enhanced accessibility for Electron/Chromium apps
            // 2. detectInjectionMethod() may need to read AX values
            // 3. AX values won't be available without Force AX enabled first
            ForceAccessibilityManager.shared.applyForCurrentApp()
            
            // Small delay to allow AX tree to update after setting AXManualAccessibility
            // Electron/Chromium apps need a moment to refresh their accessibility tree
            // NOTE: handleSmartSwitch is also inside this delay because it evaluates window
            // title rules via getTargetInputSourceOverride() → getMergedRuleResult().
            // Without the delay, window title may not be available yet (AX timing issue).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                
                // Handle Smart Switch - auto switch language per app
                // Moved INSIDE delay to ensure window title is available for rule-based
                // input source switching (targetInputSourceId in rules)
                self.handleSmartSwitch(notification: notification)
                
                // Detect and set confirmed injection method for the new app
                // This ensures keystrokes use correct method immediately after app switch
                let detector = AppBehaviorDetector.shared
                let focusedInfo = detector.getFocusedElementInfo()
                let injectionInfo = detector.detectInjectionMethod(focusedInfo: focusedInfo)
                detector.setConfirmedInjectionMethod(injectionInfo)

                // DEBUG: Log window title available at app switch time
                let switchWindowTitle = focusedInfo.windowTitle ?? "(nil)"
                self.debugWindowController?.logEvent("App switched - engine reset, mid-sentence mode")
                self.debugWindowController?.logEvent("   Window: \(switchWindowTitle)")
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                self.debugWindowController?.logEvent("   Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
                
                // Setup AXObserver for the new app to monitor focus changes (CMD+T, etc.)
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.setupAXObserverForApp(app)
                }
                
                // Check Secure Input on app switch — password managers often enable it when focused
                self.checkAndWarnSecureInput()
            }
            
            // Reset intra-app focus tracking (new app = new baseline)
            self.lastFocusedElementSignature = ""
        }

        debugWindowController?.logEvent("App switch observer registered")

        // Setup overlay detector callback to restore language when overlay closes
        setupOverlayDetectorCallback()
    }

    /// Setup callback for overlay visibility changes
    private func setupOverlayDetectorCallback() {
        OverlayAppDetector.shared.onOverlayVisibilityChanged = { [weak self] isVisible in
            guard let self = self else { return }
            
            let detector = AppBehaviorDetector.shared
            let injectionInfo = detector.detectInjectionMethod()
            detector.setConfirmedInjectionMethod(injectionInfo)

            if isVisible {
                // When overlay opens (hidden → visible):
                // 1. Detect and set injection method for overlay (Spotlight/Raycast/Alfred)
                // 2. Enable Vietnamese for overlay unless overlay has its own disable rule
                // 3. Reset mid-sentence flag (overlay apps start with empty/fresh input)
                self.debugWindowController?.logEvent("Overlay opened - checking overlay rules")
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                self.debugWindowController?.logEvent("   Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
                self.enableVietnameseForOverlay()
                
                // CRITICAL FIX: When overlay opens (e.g., CMD+Space for Spotlight),
                // reset mid-sentence flag. The resetForAppSwitch() called earlier sets isTypingMidSentence=true
                // to protect text in normal apps, but overlay apps always start fresh.
                // If user clicks into existing text, mouse click handler will set mid-sentence appropriately.
                self.keyboardHandler?.resetMidSentenceFlag()
                let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() ?? "Overlay"
                self.debugWindowController?.logEvent("'\(overlayName)' opened → reset mid-sentence flag")
            } else {
                // When overlay closes (visible → hidden):
                // 1. Detect and set injection method for the underlying app
                // 2. Restore language for current app
                // 3. Set mid-sentence flag (protect text in underlying app)
                self.debugWindowController?.logEvent("Overlay closed - restoring language for current app")
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                self.debugWindowController?.logEvent("   Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
                self.restoreLanguageForCurrentApp()
                
                // When overlay closes, user returns to previous app where cursor position is unknown.
                // Set mid-sentence flag to protect text on the right of cursor.
                // Note: Overlay close doesn't trigger didActivateApplicationNotification since
                // frontmost app is still the original app (Spotlight runs as overlay, not frontmost).
                self.keyboardHandler?.resetWithCursorMoved()
                self.debugWindowController?.logEvent("Overlay closed → set mid-sentence flag (protect underlying app)")
            }
        }
    }
    
    /// Enable Vietnamese when overlay opens (Spotlight/Raycast/Alfred)
    /// This ensures user can type Vietnamese in overlay, regardless of previous app's rule
    private func enableVietnameseForOverlay() {
        guard keyboardHandler != nil else { return }
        
        // Check Input Source config first - it takes priority
        if let currentSource = InputSourceManager.getCurrentInputSource() {
            let inputSourceEnabled = InputSourceManager.shared.isEnabled(for: currentSource.id)
            if !inputSourceEnabled {
                return
            }
        }
        
        let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() ?? "Unknown"
        debugWindowController?.logEvent("Overlay '\(overlayName)' opened - keeping current state")
    }

    /// Restore language for the current frontmost app from Smart Switch
    private func restoreLanguageForCurrentApp() {
        guard let handler = keyboardHandler else { return }

        // IMPORTANT: Check Input Source config first - it takes priority
        // If current Input Source is configured as disabled, don't restore Vietnamese
        if let currentSource = InputSourceManager.getCurrentInputSource() {
            let inputSourceEnabled = InputSourceManager.shared.isEnabled(for: currentSource.id)
            if !inputSourceEnabled {
                return
            }
        }

        // Get current frontmost app
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        // Smart Switch (if enabled)
        guard handler.smartSwitchEnabled else { return }

        // Get current language state
        let currentLanguage = statusBarManager?.viewModel.isVietnameseEnabled == true ? 1 : 0

        // Check if should restore language using Smart Switch logic
        let result = handler.engine.checkSmartSwitchForApp(bundleId: bundleId, currentLanguage: currentLanguage)

        // If should switch, restore the saved language
        if result.shouldSwitch {
            let newEnabled = result.newLanguage == 1
            statusBarManager?.viewModel.isVietnameseEnabled = newEnabled
            handler.setVietnamese(newEnabled)

            debugWindowController?.logEvent("Restored '\(bundleId)' → \(newEnabled ? "Vietnamese" : "English")")
        }
    }
    
    // MARK: - Dock Icon
    
    private func updateDockIconVisibility(show: Bool) {
        if show {
            // Show Dock icon - regular app mode
            NSApp.setActivationPolicy(.regular)
            debugWindowController?.logEvent("Dock icon: visible")
        } else {
            // Hide Dock icon - accessory/background app mode
            NSApp.setActivationPolicy(.accessory)
            debugWindowController?.logEvent("Dock icon: hidden")
        }
    }
    
    /// Handle Smart Switch when app changes
    private func handleSmartSwitch(notification: Notification) {
        guard let handler = keyboardHandler else { return }
        
        // IMPORTANT: Check Input Source config first - it takes priority over everything
        // If current Input Source is configured as disabled, don't allow Vietnamese to be enabled
        if let currentSource = InputSourceManager.getCurrentInputSource() {
            let inputSourceEnabled = InputSourceManager.shared.isEnabled(for: currentSource.id)
            if !inputSourceEnabled {
                return
            }
        }
        
        // Get the new active app
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        // PRIORITY 1: Check for target input source in Window Title Rules
        let detector = AppBehaviorDetector.shared
        let inputSourceOverride = detector.getTargetInputSourceOverride()
        
        if inputSourceOverride.hasTarget, let targetId = inputSourceOverride.inputSourceId {
            // Save current input source BEFORE switching (for restore later)
            if preRuleInputSourceId == nil {
                preRuleInputSourceId = InputSourceSwitcher.shared.getCurrentInputSourceId()
                debugWindowController?.logEvent("Saved pre-rule input source: \(preRuleInputSourceId ?? "nil")")
            }
            
            // Only switch if not already using the target
            let currentId = InputSourceSwitcher.shared.getCurrentInputSourceId()
            if currentId != targetId {
                let success = InputSourceSwitcher.shared.selectInputSource(bundleId: targetId)
                if success {
                    debugWindowController?.logEvent("Rule '\(inputSourceOverride.ruleName ?? "Unknown")': Switched to \(targetId)")
                } else {
                    debugWindowController?.logEvent("Rule '\(inputSourceOverride.ruleName ?? "Unknown")': Failed to switch to \(targetId)")
                }
            }
            // Don't proceed to Smart Switch - rule takes priority
            return
        } else {
            // No rule matches - restore pre-rule input source if we have one
            if let savedInputSourceId = preRuleInputSourceId {
                let currentId = InputSourceSwitcher.shared.getCurrentInputSourceId()
                if currentId != savedInputSourceId {
                    let success = InputSourceSwitcher.shared.selectInputSource(bundleId: savedInputSourceId)
                    if success {
                        debugWindowController?.logEvent("No rule match: Restored input source to \(savedInputSourceId)")
                    } else {
                        debugWindowController?.logEvent("No rule match: Failed to restore input source \(savedInputSourceId)")
                    }
                }
                preRuleInputSourceId = nil
            }
        }
        
        // PRIORITY 2: Smart Switch (if enabled)
        guard handler.smartSwitchEnabled else { return }
        
        // Get current language from UI (StatusBar) - this is the source of truth
        let currentLanguage = statusBarManager?.viewModel.isVietnameseEnabled == true ? 1 : 0
        
        // Check if should switch language, passing the actual current language
        let result = handler.engine.checkSmartSwitchForApp(bundleId: bundleId, currentLanguage: currentLanguage)
        
        if result.shouldSwitch {
            // Switch language
            let newEnabled = result.newLanguage == 1
            statusBarManager?.viewModel.isVietnameseEnabled = newEnabled
            handler.setVietnamese(newEnabled)
            
            debugWindowController?.logEvent("Smart Switch: '\(bundleId)' → \(newEnabled ? "Vietnamese" : "English")")
        } else {
            // App is new or language hasn't changed - save current language
            handler.engine.saveAppLanguage(bundleId: bundleId, language: currentLanguage)
        }
    }
    
    private func setupMouseClickMonitor() {
        // Monitor mouse up events to detect focus changes
        // Using mouseUp instead of mouseDown to avoid triggering during drag operations
        // When user releases mouse, they have completed a click or drag selection
        
        // Global monitor - catches clicks in OTHER apps
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            // Arm overlay probe — mouse clicks can dismiss overlays (Spotlight, Raycast, Alfred)
            OverlayAppDetector.shared.armProbe()
            
            // Reset engine when mouse is released (click completed or drag finished)
            // Mark as cursor moved to disable autocomplete fix (avoid deleting text on right)
            self?.keyboardHandler?.resetWithCursorMoved()

            // Log detailed input detection info (ONLY when debug window is visible)
            // This avoids expensive AX calls during normal usage
            // PERF: Skip when debug window is hidden to fix spring-loaded tools lag
            // Note: Overlay mid-sentence reset is handled by OverlayAppDetector's timer callback
            if self?.debugWindowController?.window?.isVisible == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.logMouseClickInputDetection()
                }
            }

            // Reset lastFocusedElement to allow toolbar to re-show after auto-hide
            // When user clicks, they might be moving cursor within same field
            self?.lastFocusedElement = nil

            // Trigger toolbar check with slight delay to allow focus to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.handleFocusCheck()
            }
        }
    }

    /// Log detailed information about the input type when mouse is clicked
    /// Uses 3x retry detection with 0.15s interval to handle AX API timing issues
    /// This fixes false positive overlay detection when clicking another app while Spotlight is visible
    private func logMouseClickInputDetection() {
        // Start 3x retry detection to handle AX API timing issues
        // When user clicks, focused element may still report Spotlight (stale data)
        // After 300ms (0.15s x 2), AX API should have updated to the new focused element
        detectBehaviorWithRetry(attempt: 1, maxAttempts: 3, interval: 0.15)
    }
    
    /// Perform behavior detection with retry to handle AX API timing issues
    /// - Parameters:
    ///   - attempt: Current attempt number (1-based)
    ///   - maxAttempts: Maximum number of attempts
    ///   - interval: Time interval between attempts in seconds
    private func detectBehaviorWithRetry(attempt: Int, maxAttempts: Int, interval: TimeInterval) {
        let detector = AppBehaviorDetector.shared
        
        // OPTIMIZED: Query focusedInfo ONCE, pass to detectInjectionMethod
        let focusedInfo = detector.getFocusedElementInfo()
        
        // Detect injection method from current snapshot
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: focusedInfo)
        
        // IMMEDIATELY set confirmed injection method so keystrokes use this method
        // This applies the best available method at each retry attempt
        detector.setConfirmedInjectionMethod(injectionInfo)
        
        // Check if an overlay app is still visible (may be stale AX data after click)
        // Uses OverlayAppDetector which queries actual AX state, not bundle-cached detect()
        let isOverlayVisible = OverlayAppDetector.shared.isOverlayAppVisible()
        
        if attempt < maxAttempts && isOverlayVisible {
            // Overlay still visible - might be AX timing issue, retry after interval
            let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() ?? "overlay"
            if attempt == 1 {
                debugWindowController?.logEvent("Mouse click detected (checking for AX timing...)")
            }
            debugWindowController?.logEvent("   Attempt \(attempt): \(overlayName) → \(injectionInfo.method) (applying...)")
            
            // Schedule next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.detectBehaviorWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts, interval: interval)
            }
            return
        }
        
        // Final attempt OR no overlay - log the result
        // OPTIMIZED: Pass pre-queried data to avoid redundant AX queries in logging
        logFinalMouseClickDetection(attempt: attempt, wasRetried: attempt > 1, injectionInfo: injectionInfo, focusedInfo: focusedInfo)
    }
    
    /// Log final mouse click detection result
    /// OPTIMIZED: Accepts pre-queried injectionInfo and focusedInfo to avoid redundant AX queries
    /// This is a pure logging function — all detection is already done by detectBehaviorWithRetry
    private func logFinalMouseClickDetection(attempt: Int, wasRetried: Bool, injectionInfo: InjectionMethodInfo, focusedInfo: FocusedElementInfo) {
        // Early return if debug window is not open — pure logging function
        // Injection method is already set by detectBehaviorWithRetry, no need to re-detect
        guard debugWindowController != nil else { return }
        
        // Get frontmost app info
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else {
            debugWindowController?.logEvent("Mouse click - engine reset, mid-sentence mode")
            return
        }

        let appName = app.localizedName ?? "Unknown"
        let detector = AppBehaviorDetector.shared

        // OPTIMIZED: Use pre-queried focusedInfo instead of re-querying AX API
        let elementRole = focusedInfo.role ?? "Unknown"
        let elementSubrole = focusedInfo.subrole
        let axDescription = focusedInfo.description
        let axIdentifier = focusedInfo.identifier
        let domClasses = focusedInfo.domClasses
        
        // Get window title from focusedInfo (already queried) or cache
        let windowTitle = focusedInfo.windowTitle ?? detector.getCachedWindowTitle()

        // Get app behavior type (cached, no AX query)
        let behavior = detector.detect()
        let behaviorName = getBehaviorName(behavior)

        // OPTIMIZED: Use pre-queried injectionInfo instead of calling detectInjectionMethod() again
        let injectionMethodName = getInjectionMethodName(injectionInfo.method)

        // Get current input source
        let inputSource = InputSourceManager.getCurrentInputSource()
        let inputSourceName = inputSource?.displayName ?? "Unknown"
        
        // OPTIMIZED: Pass pre-queried focusedInfo to avoid redundant AX queries
        let matchedRule = detector.findMatchingRule(focusedInfo: focusedInfo)
        let imkitBehavior = detector.detectIMKitBehavior(focusedInfo: focusedInfo)

        // Log everything with nice formatting
        if wasRetried {
            debugWindowController?.logEvent("Mouse click detected (after \(attempt) AX checks)")
        } else {
            debugWindowController?.logEvent("Mouse click detected")
        }
        debugWindowController?.logEvent("   App: \(appName) (\(bundleId))")
        debugWindowController?.logEvent("   Window: \(windowTitle.isEmpty ? "(no title)" : windowTitle)")
        
        // Log AX element info (similar to Text Test tab)
        var inputTypeStr = elementRole
        if let subrole = elementSubrole, !subrole.isEmpty {
            inputTypeStr += " / \(subrole)"
        }
        debugWindowController?.logEvent("   AXRole: \(inputTypeStr)")
        
        if let desc = axDescription, !desc.isEmpty {
            debugWindowController?.logEvent("   AXDescription: \(desc)")
        }
        if let identifier = axIdentifier, !identifier.isEmpty {
            debugWindowController?.logEvent("   AXIdentifier: \(identifier)")
        }
        if let classes = domClasses, !classes.isEmpty {
            debugWindowController?.logEvent("   AXDOMClassList: \(classes.joined(separator: ", "))")
        }
        
        debugWindowController?.logEvent("   Behavior: \(behaviorName)")
        let textMethodName: String = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
        debugWindowController?.logEvent("   Injection: \(injectionMethodName) [bs:\(injectionInfo.delays.backspace)µs, wait:\(injectionInfo.delays.wait)µs, txt:\(injectionInfo.delays.text)µs] [\(textMethodName)] ✓ confirmed")
        debugWindowController?.logEvent("   IMKit: markedText=\(imkitBehavior.useMarkedText), issues=\(imkitBehavior.hasMarkedTextIssues), delay=\(imkitBehavior.commitDelay)µs")
        debugWindowController?.logEvent("   Input Source: \(inputSourceName)")
        
        // Log matched rule if any
        if let rule = matchedRule {
            debugWindowController?.logEvent("   Rule: \(rule.name) (pattern: \"\(rule.titlePattern)\")")
        }
        
        debugWindowController?.logEvent("   → Engine reset, mid-sentence mode")
    }
    
    /// Get human-readable behavior name
    private func getBehaviorName(_ behavior: AppBehavior) -> String {
        switch behavior {
        case .standard:
            return "Standard"
        case .terminal:
            return "Terminal"
        case .browserAddressBar:
            return "Browser Address Bar"
        case .jetbrainsIDE:
            return "JetBrains IDE"
        case .microsoftOffice:
            return "Microsoft Office"
        case .spotlight:
            return "Spotlight"
        case .overlayLauncher:
            return "Overlay Launcher (Raycast/Alfred)"
        case .electronApp:
            return "Electron App"
        case .codeEditor:
            return "Code Editor"
        }
    }
    
    /// Get human-readable injection method name
    private func getInjectionMethodName(_ method: InjectionMethod) -> String {
        switch method {
        case .fast: return "Fast"
        case .slow: return "Slow"
        case .selection: return "Selection"
        case .autocomplete: return "Autocomplete"
        case .axDirect: return "AX Direct"
        case .passthrough: return "Passthrough"
        }
    }

    private func setupInputSourceManager() {
        inputSourceManager = InputSourceManager.shared

        // Connect debug logging
        inputSourceManager?.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }

        // Handle input source changes
        inputSourceManager?.onInputSourceChanged = { [weak self] source, shouldEnable in
            self?.handleInputSourceChange(source: source, shouldEnable: shouldEnable)
        }

        debugWindowController?.logEvent("Input Source Manager initialized")

        // IMPORTANT: Check current input source on startup and apply config
        if let currentSource = InputSourceManager.getCurrentInputSource() {
            let shouldEnable = inputSourceManager?.isEnabled(for: currentSource.id) ?? true
            debugWindowController?.logEvent("Initial Input Source: \(currentSource.displayName)")
            debugWindowController?.logEvent("   Should enable XKey: \(shouldEnable)")
            handleInputSourceChange(source: currentSource, shouldEnable: shouldEnable)
        }
    }

    /// Handle input source changes - apply enable/disable logic
    private func handleInputSourceChange(source: InputSourceInfo, shouldEnable: Bool) {
        // Check if this is XKeyIM input source
        let isXKeyIM = InputSourceManager.isXKeyInputSource(source)

        if isXKeyIM {
            // Switched TO XKeyIM - suspend CGEvent tap to let IMKit handle events
            debugWindowController?.logEvent("🔑 Switched to XKeyIM - suspending CGEvent tap")
            eventTapManager?.suspend()

            // Force DISABLE XKey main app's Vietnamese engine
            // XKeyIM handles Vietnamese typing itself, so XKey main app shows "E" (engine off)
            self.statusBarManager?.viewModel.isVietnameseEnabled = false
            self.keyboardHandler?.setVietnamese(false)
        } else {
            // Check if event tap is already running
            // If not (e.g., started with XKeyIM active), start it now
            guard let manager = eventTapManager else { return }

            // Try to start event tap if it's not running
            do {
                try manager.start()
            } catch EventTapManager.EventTapError.alreadyRunning {
                // Already running - just resume it
                manager.resume()
            } catch {
                debugWindowController?.logEvent("Failed to start event tap: \(error)")
            }

            // Get current state
            let currentlyEnabled = self.statusBarManager?.viewModel.isVietnameseEnabled ?? false

            // Auto enable/disable Vietnamese mode based on configuration
            if shouldEnable {
                // Enable Vietnamese mode
                if !currentlyEnabled {
                    self.statusBarManager?.viewModel.isVietnameseEnabled = true
                    self.keyboardHandler?.setVietnamese(true)
                    self.debugWindowController?.logEvent("'\(source.displayName)' → Vietnamese ON")
                }
            } else {
                // Disable Vietnamese mode
                if currentlyEnabled {
                    self.statusBarManager?.viewModel.isVietnameseEnabled = false
                    self.keyboardHandler?.setVietnamese(false)
                    self.debugWindowController?.logEvent("'\(source.displayName)' → Vietnamese OFF")
                }
            }
        }
    }

    // MARK: - Sparkle Auto-Update

    private func checkForUpdates() {
        debugWindowController?.logEvent("Manually checking for updates...")
        // Activate app to bring update dialog to front
        NSApp.activate(ignoringOtherApps: true)
        updaterController?.updater.checkForUpdates()
    }
    
    /// Check for updates from SwiftUI views (activates app to bring dialog to front)
    func checkForUpdatesFromUI() {
        debugWindowController?.logEvent("[UI] Manually checking for updates...")
        
        // Must be called on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Activate app to bring update dialog to front
            NSApp.activate(ignoringOtherApps: true)
            
            // Use the same method as menu bar - updater.checkForUpdates()
            if let updater = self.updaterController?.updater {
                self.debugWindowController?.logEvent("[UI] Calling updater.checkForUpdates()")
                updater.checkForUpdates()
            } else {
                self.debugWindowController?.logEvent("[UI] updaterController or updater is nil!")
            }
        }
    }


    private func setupSparkleUpdater() {
        // Create the update delegate first
        sparkleUpdateDelegate = SparkleUpdateDelegate()
        
        // Connect debug logging to the delegate
        sparkleUpdateDelegate?.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // Initialize Sparkle updater controller with our delegate
        // This will automatically check for updates based on Info.plist settings:
        // - SUFeedURL: appcast feed URL
        // - SUPublicEDKey: public key for signature verification
        // - SUEnableAutomaticChecks: enable automatic update checks
        // - SUScheduledCheckInterval: check interval in seconds (86400 = 24 hours)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sparkleUpdateDelegate,
            userDriverDelegate: sparkleUpdateDelegate  // Also use as user driver delegate to bring update dialog to front
        )
        
        debugWindowController?.logEvent("Sparkle auto-update initialized")
        debugWindowController?.logEvent("   Feed URL: \(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "Not configured")")
        debugWindowController?.logEvent("   Auto-check: \(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false)")
        debugWindowController?.logEvent("   Update delegate: SparkleUpdateDelegate (settings will be saved before restart)")
        
        // Apply auto-check setting from preferences
        let autoCheckEnabled = SharedSettings.shared.autoCheckForUpdates
        updaterController?.updater.automaticallyChecksForUpdates = autoCheckEnabled
        debugWindowController?.logEvent("   Auto-check (user setting): \(autoCheckEnabled)")
        
        // Check for updates immediately on app launch (silently in background)
        // Only if auto-check is enabled
        if autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let updater = self?.updaterController?.updater else { return }
                
                // Use background check - won't show UI if no update available
                if updater.canCheckForUpdates {
                    self?.debugWindowController?.logEvent("Checking for updates in background (startup check)...")
                    updater.checkForUpdatesInBackground()
                } else {
                    self?.debugWindowController?.logEvent("Skipping startup update check (already checking or in progress)")
                }
            }
        } else {
            debugWindowController?.logEvent("Skipping startup update check (auto-check disabled by user)")
        }
    }

    // MARK: - XKeyIM Auto-Update

    private func checkXKeyIMUpdate() {
        // Connect XKeyIMUpdateManager debug logging
        XKeyIMUpdateManager.shared.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // Always install bundled XKeyIM after a short delay
        // This ensures XKeyIM is always in sync with XKey app
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            XKeyIMUpdateManager.shared.installBundledXKeyIM(showNotification: false)
        }
    }

    // MARK: - Secure Input Detection
    
    /// Track Secure Input state to avoid spamming debug log
    private var lastSecureInputLogTime: CFAbsoluteTime = 0
    private var lastSecureInputPID: pid_t = 0
    
    /// Check if Secure Input is active and warn the user.
    /// When Secure Input is ON, ALL CGEvent taps are blocked from receiving keyDown/keyUp events,
    /// making XKey and all third-party input methods completely non-functional.
    /// The overlay shows on EVERY check (e.g., every app switch) to remind the user.
    /// Debug log is throttled to avoid spam.
    @discardableResult
    private func checkAndWarnSecureInput() -> Bool {
        guard let manager = eventTapManager else { return false }
        
        let (isSecure, pid, appName) = manager.checkSecureInput()
        
        if isSecure {
            let name = appName ?? "Unknown"
            
            // Only show overlay when Vietnamese mode is ON.
            // If user is in English mode, Secure Input doesn't affect typing.
            let isVietnamese = statusBarManager?.viewModel.isVietnameseEnabled ?? false
            if isVietnamese {
                SecureInputOverlay.shared.show(appName: name)
            }
            
            // Throttle debug log: only log once per app, or every 30 seconds for the same app
            let now = CFAbsoluteTimeGetCurrent()
            let samePID = pid == lastSecureInputPID
            if !samePID || (now - lastSecureInputLogTime) > 30.0 {
                lastSecureInputLogTime = now
                lastSecureInputPID = pid ?? 0
                debugWindowController?.logEvent("⚠️ Secure Input đang BẬT bởi '\(name)' — XKey không thể nhận phím!")
                debugWindowController?.updateStatus("⚠️ Secure Input: \(name)")
            }
            return true
        } else {
            // Clear state when Secure Input is released
            if lastSecureInputPID != 0 {
                lastSecureInputPID = 0
                SecureInputOverlay.shared.hide()
                debugWindowController?.logEvent("✅ Secure Input đã TẮT — XKey hoạt động bình thường")
                debugWindowController?.updateStatus("Ready")
            }
            return false
        }
    }

    // MARK: - Spell Check Dictionary Setup

    private func setupSpellCheckDictionary() {
        let preferences = SharedSettings.shared.loadPreferences()

        guard preferences.spellCheckEnabled else {
            debugWindowController?.logEvent("  Spell checking disabled, skipping dictionary load")
            return
        }

        let style: VNDictionaryManager.DictionaryStyle = preferences.modernStyle ? .dauMoi : .dauCu

        // Check if dictionary is already available locally
        if VNDictionaryManager.shared.isDictionaryAvailable(style: style) {
            // Load from local storage
            do {
                try VNDictionaryManager.shared.loadDictionary(style: style)
                let stats = VNDictionaryManager.shared.getDictionaryStats()
                let count = stats[style.rawValue] ?? 0
                debugWindowController?.logEvent("Loaded \(style.rawValue) dictionary (\(count) words)")
            } catch {
                debugWindowController?.logEvent("Failed to load dictionary: \(error.localizedDescription)")
            }
        } else {
            debugWindowController?.logEvent("Dictionary not found. User can download from Settings > Spell Checking")
        }
    }

    // MARK: - Temp Off Toolbar

    private func setupTempOffToolbar() {
        // Always setup notification observer for settings changes
        setupTempOffToolbarSettingsObserver()
        
        // Setup AXObserver for focus change monitoring (injection detection)
        // AXObserver runs regardless of toolbar setting for injection method detection
        setupFocusChangeMonitoring()

        let preferences = SharedSettings.shared.loadPreferences()

        // Only setup toolbar-specific features if enabled
        guard preferences.tempOffToolbarEnabled else {
            debugWindowController?.logEvent("Temp off toolbar disabled (timer off, AXObserver active)")
            return
        }

        enableTempOffToolbar()
    }

    /// Setup observer for toolbar settings changes
    private func setupTempOffToolbarSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: .tempOffToolbarSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTempOffToolbarSettingsChange()
        }
        debugWindowController?.logEvent("Temp off toolbar settings observer registered")
    }

    /// Handle toolbar settings changes (enable/disable or hotkey change)
    private func handleTempOffToolbarSettingsChange() {
        let preferences = SharedSettings.shared.loadPreferences()

        if preferences.tempOffToolbarEnabled {
            debugWindowController?.logEvent("Temp off toolbar settings changed - enabling")
            enableTempOffToolbar()
        } else {
            debugWindowController?.logEvent("Temp off toolbar settings changed - disabling")
            disableTempOffToolbar()
        }
    }

    /// Enable temp off toolbar and setup all related features
    private func enableTempOffToolbar() {
        // Setup toolbar state change callback
        TempOffToolbarController.shared.onStateChange = { [weak self] spellingOff, engineOff in
            guard let self = self else { return }

            // Update engine temp off states
            self.keyboardHandler?.engine.vTempOffSpelling = spellingOff ? 1 : 0
            self.keyboardHandler?.engine.vTempOffEngine = engineOff ? 1 : 0

            self.debugWindowController?.logEvent("Toolbar state changed: spelling=\(spellingOff ? "OFF" : "ON"), engine=\(engineOff ? "OFF" : "ON")")
        }

        // Setup hotkey from preferences
        setupTempOffToolbarHotkey()

        debugWindowController?.logEvent("Temp off toolbar enabled")
        
        // Check if user is already focused on a text input and show toolbar immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.lastFocusedElement = nil  // Reset to force re-check
            self?.handleFocusCheck()
        }
    }

    /// Disable temp off toolbar and cleanup
    /// Note: AXObserver continues for injection detection
    private func disableTempOffToolbar() {
        // Clear hotkey from EventTapManager
        eventTapManager?.toolbarHotkey = nil
        eventTapManager?.onToolbarHotkey = nil

        // Hide toolbar if visible
        TempOffToolbarController.shared.hide()

        // Clear callback
        TempOffToolbarController.shared.onStateChange = nil
        
        // Clear last focused element so re-enable will re-check
        lastFocusedElement = nil

        debugWindowController?.logEvent("Temp off toolbar disabled (AXObserver still active)")
    }

    /// Setup monitoring for focus changes to auto-show toolbar when focusing text fields
    private func setupFocusChangeMonitoring() {
        // Use NSWorkspace notification to detect app activation
        // Then check if focused element is a text field
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFocusCheck()
        }

        // Mouse clicks are already handled by mouseClickMonitor
        // Focus changes within apps are handled by AXObserver (event-driven, no polling)
        
        // Setup AXObserver for the current frontmost app on launch
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            setupAXObserverForApp(frontApp)
        }

        debugWindowController?.logEvent("Focus change monitoring enabled (AXObserver + NSWorkspace notifications)")
    }
    
    /// Main focus check handler - gets focused element once and passes to both processors
    /// OPTIMIZED: Uses FocusedElementInfo to cache AX attributes in a single query
    private func handleFocusCheck() {
        // Get focused element ONCE (avoid duplicate AX API calls)
        guard let axElement = AXHelper.getFocusedElement() else {
            // No focused element - hide toolbar if visible
            if SharedSettings.shared.tempOffToolbarEnabled && TempOffToolbarController.shared.isVisible {
                TempOffToolbarController.shared.hide()
            }
            return
        }
        
        // OPTIMIZED: Get all AX attributes in a single pass via FocusedElementInfo
        // This reduces AX API calls from ~10 to ~5 per focus check
        let elementInfo = FocusedElementInfo.from(axElement)
        
        // 1. ALWAYS check for injection method changes (CMD+T, Tab, etc.)
        checkIntraAppFocusChange(with: elementInfo)
        
        // 2. Check toolbar display (only if enabled)
        if SharedSettings.shared.tempOffToolbarEnabled {
            checkAndShowToolbarForFocusedElement(with: elementInfo)
        }
    }

    // MARK: - Intra-App Focus Monitoring
    
    /// Check if focused element has changed within the same app (e.g., CMD+T in browser)
    /// If so, re-detect injection method (but DO NOT reset engine - that's handled by user actions)
    /// Also re-primes cache when confirmedInjectionMethod was cleared (e.g., after mouse click)
    /// - Parameter elementInfo: Cached AX element info (passed from handleFocusCheck)
    private func checkIntraAppFocusChange(with elementInfo: FocusedElementInfo) {
        // OPTIMIZED: Use pre-computed signature from FocusedElementInfo
        let currentSignature = elementInfo.signature
        let detector = AppBehaviorDetector.shared
        
        // Check if signature changed (different element type)
        if currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty {
            
            // Re-detect injection method (needed for address bar, terminal, etc.)
            let previousMethod = detector.confirmedInjectionMethod
            let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo)
            
            // Log focus change
            debugWindowController?.logEvent("Focus changed (keyboard): \(lastFocusedElementSignature) → \(currentSignature)")
            
            // ALWAYS set confirmed method to ensure cache is populated
            detector.setConfirmedInjectionMethod(injectionInfo)
            
            // Log injection method change
            if let prev = previousMethod, (prev.method != injectionInfo.method || prev.description != injectionInfo.description) {
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                let emptyCharStr = injectionInfo.needsEmptyCharPrefix ? ", emptyCharPrefix=true" : ""
                debugWindowController?.logEvent("   Injection: \(prev.description) → \(injectionInfo.description) [\(textMethodName)\(emptyCharStr)]")
            }
            
            // NOTE: Engine reset is NOT done here!
            // Engine reset is handled by explicit user actions:
            // - Mouse click (setupMouseClickMonitor)
            // - Tab key (KeyboardEventHandler.processKeyEvent)
            // - Arrow keys / Home / End / PageUp / PageDown (KeyboardEventHandler.processKeyEvent)
            // - App switch (handleAppSwitch)
            //
            // Focus change detection is ONLY for re-detecting injection method.
            // This avoids issues where apps "refine" focus after user starts typing
            // (e.g., VSCode: AXWindow → AXTextArea, Facebook: dropdown menus).
            
            // NEW: Notify engine about focus change during typing
            // This is important for suggestion popup scenarios where keystrokes may go to popup
            // causing buffer desync. Engine will use AX verify at next word break.
            keyboardHandler?.engine.notifyFocusChanged()
        } else if detector.confirmedInjectionMethod == nil {
            // Cache was cleared (e.g., by mouse click resetWithCursorMoved)
            // but signature is unchanged (same field).
            // Re-prime cache to avoid live AX detection on every keystroke.
            let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo)
            detector.setConfirmedInjectionMethod(injectionInfo)
        }
        
        // Update last signature
        lastFocusedElementSignature = currentSignature
    }
    
    // MARK: - AXObserver for Focus Changes
    
    /// Setup AXObserver for the given app to receive focus change notifications
    /// This is called when app switches to monitor focus changes within that app (e.g., Cmd+T in browser)
    private func setupAXObserverForApp(_ app: NSRunningApplication) {
        // Skip if it's XKey itself
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        
        let pid = app.processIdentifier
        
        // Skip if already observing this app
        guard pid != focusObserverPID else { return }
        
        // Remove existing observer if any
        removeAXObserver()
        
        // Create new observer for this app
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axNotificationCallback, &observer)
        
        guard result == .success, let newObserver = observer else {
            debugWindowController?.logEvent("AXObserver: Failed to create for PID \(pid) (error: \(result.rawValue))")
            return
        }
        
        // Get the app's AXUIElement
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        // Register for focused UI element changed notification
        let addResult = AXObserverAddNotification(
            newObserver,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )
        
        guard addResult == .success else {
            debugWindowController?.logEvent("AXObserver: Failed to add focus notification for PID \(pid) (error: \(addResult.rawValue))")
            return
        }
        
        // Register for window title changed notification (Layer 1)
        // Catches apps that update window title AFTER focus change (e.g., Slack channel switch)
        let titleResult = AXObserverAddNotification(
            newObserver,
            appElement,
            kAXTitleChangedNotification as CFString,
            refcon
        )
        
        if titleResult != .success {
            // Non-fatal: some apps may not support this notification
            // Layer 2 (delayed verification) will handle those cases
            debugWindowController?.logEvent("AXObserver: Title notification not supported for PID \(pid)")
        }
        
        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .defaultMode
        )
        
        // Save observer and PID
        focusObserver = newObserver
        focusObserverPID = pid
        
        debugWindowController?.logEvent("AXObserver: Monitoring '\(app.localizedName ?? "Unknown")' (PID: \(pid))")
    }
    
    /// Remove current AXObserver
    private func removeAXObserver() {
        // Cancel pending title verifications
        titleVerificationWorkItem?.cancel()
        titleVerificationWorkItem = nil
        titleChangeDebounceWorkItem?.cancel()
        titleChangeDebounceWorkItem = nil
        lastDetectedTitle = nil
        
        guard let observer = focusObserver else { return }
        
        // Remove from run loop
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        
        focusObserver = nil
        focusObserverPID = 0
    }
    
    /// Handle focus changed notification from AXObserver
    /// This is called by the C callback function
    /// OPTIMIZED: Uses FocusedElementInfo to cache AX attributes
    /// ALWAYS re-detects injection method (event-driven path, already throttled)
    /// to catch same-app context switches (tab/window) where signature stays the same
    /// but window title rules and injection method may change.
    func handleAXFocusChanged(_ element: AXUIElement) {
        // Throttle: Skip if called too rapidly (< 100ms since last call)
        // This prevents blocking the main thread when AXObserver fires rapidly
        // (e.g., during autocomplete, animations, or rapid UI updates)
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAXFocusChangeTime > axFocusChangeThrottleInterval else {
            return
        }
        lastAXFocusChangeTime = now
        
        // OPTIMIZED: Get all AX attributes in a single pass via FocusedElementInfo
        let elementInfo = FocusedElementInfo.from(element)
        let currentSignature = elementInfo.signature
        let signatureChanged = currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty
        
        // ALWAYS re-detect injection method in event-driven path.
        // AXObserver fires indicate genuine focus changes (throttle handles spam).
        // With pre-fetched focusedInfo, re-detection is pure logic (no extra AX calls).
        // This ensures same-app tab/window switches re-evaluate window title rules
        // even when AX role/subrole/description are identical.
        let detector = AppBehaviorDetector.shared
        // Read cache BEFORE re-detection to compare correctly
        let previousMethod = detector.confirmedInjectionMethod
        let injectionInfo = detector.detectInjectionMethod(focusedInfo: elementInfo)
        
        // Log focus change (only when signature actually changed)
        if signatureChanged {
            debugWindowController?.logEvent("Focus changed (AXObserver): \(lastFocusedElementSignature) → \(currentSignature)")
        }
        
        // ALWAYS set confirmed method to ensure cache is populated
        // (after mouse click clears cache, this re-populates it)
        detector.setConfirmedInjectionMethod(injectionInfo)
        
        // Log injection method change
        if let prev = previousMethod, (prev.method != injectionInfo.method || prev.description != injectionInfo.description) {
            let axWindowTitle = elementInfo.windowTitle ?? "(nil)"
            let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
            let emptyCharStr = injectionInfo.needsEmptyCharPrefix ? ", emptyCharPrefix=true" : ""
            debugWindowController?.logEvent("   Injection: \(prev.description) → \(injectionInfo.description) [\(textMethodName)\(emptyCharStr)]")
            debugWindowController?.logEvent("   Window: \(axWindowTitle)")
        }
        
        // Layer 2: Schedule delayed title verification
        // Apps like Slack update window title 200-500ms AFTER focus change notification.
        // The detection above may have used a STALE title → wrong rule applied.
        // This re-checks the title after a delay and re-detects if it changed.
        // Note: windowTitle was lazy-loaded by detectInjectionMethod → now cached in elementInfo
        lastDetectedTitle = elementInfo.windowTitle
        titleVerificationWorkItem?.cancel()
        let verifyWork = DispatchWorkItem { [weak self] in
            self?.performTitleChangeRedetection()
        }
        titleVerificationWorkItem = verifyWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: verifyWork)
        
        // NOTE: Engine reset is NOT done here!
        // See checkIntraAppFocusChange for explanation.
        
        // NEW: Notify engine about focus change during typing
        if signatureChanged {
            keyboardHandler?.engine.notifyFocusChanged()
        }
        
        // Update last signature (for timer-based checkIntraAppFocusChange)
        lastFocusedElementSignature = currentSignature
        
        // Check toolbar display (only if enabled)
        // This ensures toolbar shows/hides when focus changes via keyboard (CMD+T, Tab, etc.)
        let preferences = SharedSettings.shared.loadPreferences()
        let shouldShowTempOffToolbar = preferences.tempOffToolbarEnabled
        let shouldShowTranslationToolbar = preferences.translationEnabled && preferences.translationToolbarEnabled
        
        if shouldShowTempOffToolbar || shouldShowTranslationToolbar {
            // Reset lastFocusedElement to force toolbar re-evaluation
            lastFocusedElement = nil
            checkAndShowToolbarForFocusedElement(with: elementInfo)
        } else {
            // Just update for tracking
            lastFocusedElement = element
        }
    }
    
    // MARK: - Window Title Change Re-detection
    
    /// Handle window title changed notification from AXObserver (Layer 1)
    /// Apps like Slack fire this when switching channels/conversations
    /// Uses debounce to coalesce rapid-fire title updates
    func handleAXTitleChanged() {
        // Guard: Only re-detect if we have a confirmed method (active context)
        guard AppBehaviorDetector.shared.confirmedInjectionMethod != nil else { return }
        
        // Debounce: Coalesce rapid title changes (e.g., "Loading..." → "vn-abc - Slack")
        // We want the FINAL title, not intermediate states
        titleChangeDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performTitleChangeRedetection()
        }
        titleChangeDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    
    /// Re-detect injection method after window title changed
    /// Called by both Layer 1 (kAXTitleChangedNotification) and Layer 2 (delayed verification)
    /// Uses lastDetectedTitle guard to avoid duplicate work when both layers trigger
    private func performTitleChangeRedetection() {
        let detector = AppBehaviorDetector.shared
        
        // Query fresh window title (1-3 AX calls — lightweight)
        let freshTitle = detector.getCurrentWindowTitle() ?? ""
        
        // Skip if title hasn't actually changed from last detection
        guard freshTitle != (lastDetectedTitle ?? "") else { return }
        
        // Title DID change — re-detect with fresh state
        lastDetectedTitle = freshTitle
        
        let previousMethod = detector.confirmedInjectionMethod
        let injectionInfo = detector.detectInjectionMethod()
        
        // Only update and log if detection result actually changed
        if previousMethod == nil ||
           injectionInfo.method != previousMethod!.method ||
           injectionInfo.description != previousMethod!.description {
            detector.setConfirmedInjectionMethod(injectionInfo)
            debugWindowController?.logEvent("[TitleVerify] \"\(freshTitle.prefix(60))\"")
            debugWindowController?.logEvent("   Injection: \(previousMethod?.description ?? "nil") → \(injectionInfo.description)")
        }
    }
    
    /// Check if focused element is a text field and show toolbar
    /// - Parameter elementInfo: Cached AX element info (passed from handleFocusCheck)
    /// OPTIMIZED: Uses signature comparison instead of CFEqual, and cached isTextInput
    private func checkAndShowToolbarForFocusedElement(with elementInfo: FocusedElementInfo) {
        // OPTIMIZED: Use signature comparison instead of CFEqual
        // Signature is already computed by FocusedElementInfo, no additional AX calls needed
        let currentSignature = elementInfo.signature
        
        let preferences = SharedSettings.shared.loadPreferences()
        let showTempOff = preferences.tempOffToolbarEnabled
        let showTranslation = preferences.translationEnabled && preferences.translationToolbarEnabled
        
        // Check if it's the same element as before (using signature)
        if currentSignature == lastFocusedElementSignature && lastFocusedElement != nil {
            // Same element - update positions if visible, or re-show if hidden (only if has caret)
            let hasTextCursor = elementInfo.hasCaret
            
            if showTempOff {
                if TempOffToolbarController.shared.isVisible {
                    TempOffToolbarController.shared.updatePosition()
                } else if hasTextCursor {
                    // Toolbar was hidden (auto-hide), re-show it on click
                    TempOffToolbarController.shared.show()
                }
            }
            if showTranslation {
                if TranslationToolbarController.shared.isVisible {
                    TranslationToolbarController.shared.updatePosition()
                } else if hasTextCursor {
                    // Toolbar was hidden (auto-hide), re-show it on click (only if has caret)
                    TranslationToolbarController.shared.show()
                }
            }
            return
        }

        // New focused element
        lastFocusedElement = elementInfo.element

        // Both toolbars use hasCaret check - only show when element has actual text cursor
        let hasTextCursor = elementInfo.hasCaret
        
        if hasTextCursor {
            // Show TempOff toolbar if enabled
            if showTempOff {
                TempOffToolbarController.shared.show()
            }
            // Show Translation toolbar if enabled
            if showTranslation {
                TranslationToolbarController.shared.show()
            }
        } else {
            // No caret - hide both toolbars
            if showTempOff {
                TempOffToolbarController.shared.hide()
            }
            if showTranslation && !TranslationToolbarController.shared.isInteracting {
                TranslationToolbarController.shared.hide()
            }
        }
    }
    
    private func setupTempOffToolbarHotkey() {
        // Get hotkey from preferences
        let preferences = SharedSettings.shared.loadPreferences()
        let hotkey = preferences.tempOffToolbarHotkey

        // If no keycode, disable hotkey
        guard hotkey.keyCode != 0 else {
            eventTapManager?.toolbarHotkey = nil
            eventTapManager?.onToolbarHotkey = nil
            debugWindowController?.logEvent("  Temp off toolbar hotkey disabled (no key set)")
            return
        }

        // Configure EventTapManager to handle toolbar hotkey
        // This ensures the hotkey is consumed at the lowest level
        eventTapManager?.toolbarHotkey = hotkey
        eventTapManager?.onToolbarHotkey = { [weak self] in
            TempOffToolbarController.shared.toggle()
            self?.debugWindowController?.logEvent("Temp off toolbar toggled via hotkey (\(hotkey.displayString))")
        }

        debugWindowController?.logEvent("Temp off toolbar hotkey: \(hotkey.displayString) (via EventTap)")
    }

    /// Show temp off toolbar programmatically
    func showTempOffToolbar() {
        TempOffToolbarController.shared.show()
    }

    /// Hide temp off toolbar programmatically
    func hideTempOffToolbar() {
        TempOffToolbarController.shared.hide()
    }

    /// Toggle temp off toolbar programmatically
    func toggleTempOffToolbar() {
        TempOffToolbarController.shared.toggle()
    }

    // MARK: - Convert Tool Hotkey

    private func setupConvertToolHotkey() {
        // Setup notification observer for hotkey changes
        NotificationCenter.default.addObserver(
            forName: .convertToolHotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConvertToolHotkey()
        }

        // Initial setup
        updateConvertToolHotkey()
    }

    private func updateConvertToolHotkey() {
        let preferences = SharedSettings.shared.loadPreferences()
        let hotkey = preferences.convertToolHotkey

        // If no keycode, disable hotkey
        guard hotkey.keyCode != 0 else {
            eventTapManager?.convertToolHotkey = nil
            eventTapManager?.onConvertToolHotkey = nil
            debugWindowController?.logEvent("Convert tool hotkey disabled (no key set)")
            return
        }

        // Configure EventTapManager to handle convert tool hotkey
        eventTapManager?.convertToolHotkey = hotkey
        eventTapManager?.onConvertToolHotkey = { [weak self] in
            self?.openConvertTool()
            self?.debugWindowController?.logEvent("Convert tool opened via hotkey (\(hotkey.displayString))")
        }

        debugWindowController?.logEvent("Convert tool hotkey set: \(hotkey.displayString)")
    }

    // MARK: - Translation Hotkey

    private func setupTranslationHotkey() {
        // Connect TranslationService logging to Debug Window
        TranslationService.shared.logCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // Setup TranslationToolbar callback
        TranslationToolbarController.shared.onTranslateRequested = { [weak self] in
            self?.performTranslation()
        }
        
        // Setup notification observer for hotkey/settings changes
        NotificationCenter.default.addObserver(
            forName: .translationSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTranslationHotkey()
            self?.updateTranslateToSourceHotkey()
        }
        
        // Setup notification observer for translation toolbar settings changes
        NotificationCenter.default.addObserver(
            forName: .translationToolbarSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleTranslationToolbarSettingsChange()
        }

        // Initial setup
        updateTranslationHotkey()
        updateTranslateToSourceHotkey()
    }
    
    /// Handle translation toolbar settings changes (enable/disable)
    private func handleTranslationToolbarSettingsChange() {
        let preferences = SharedSettings.shared.loadPreferences()
        
        if preferences.translationEnabled && preferences.translationToolbarEnabled {
            debugWindowController?.logEvent("Translation toolbar enabled")
        } else {
            // Hide toolbar if disabled
            TranslationToolbarController.shared.hide()
            debugWindowController?.logEvent("Translation toolbar disabled")
        }
    }

    private func updateTranslationHotkey() {
        let preferences = SharedSettings.shared.loadPreferences()
        
        // Check if translation is enabled
        guard preferences.translationEnabled else {
            eventTapManager?.translationHotkey = nil
            eventTapManager?.onTranslationHotkey = nil
            debugWindowController?.logEvent("Translation hotkey disabled (feature off)")
            return
        }

        let hotkey = preferences.translationHotkey

        // If no keycode, disable hotkey
        guard hotkey.keyCode != 0 else {
            eventTapManager?.translationHotkey = nil
            eventTapManager?.onTranslationHotkey = nil
            debugWindowController?.logEvent("Translation hotkey disabled (no key set)")
            return
        }

        // Configure EventTapManager to handle translation hotkey
        eventTapManager?.translationHotkey = hotkey
        eventTapManager?.onTranslationHotkey = { [weak self] in
            self?.performTranslation()
        }

        debugWindowController?.logEvent("Translation hotkey set: \(hotkey.displayString)")
    }

    /// Perform translation on selected text or full input value
    private func performTranslation() {
        let preferences = SharedSettings.shared.loadPreferences()
        let service = TranslationService.shared
        
        debugWindowController?.logEvent("Translation triggered via hotkey")
        
        // Get selected text or full value via AX (with source info)
        guard let textResult = service.getSelectedTextWithSource(), !textResult.text.isEmpty else {
            debugWindowController?.logEvent("   No text to translate")
            showTranslationNotification(message: "Không có text để dịch. Hãy chọn text hoặc focus vào input.")
            return
        }
        
        let textToTranslate = textResult.text
        let needsSelectAll = textResult.needsSelectAllForReplace
        
        debugWindowController?.logEvent("   Text: \"\(textToTranslate.prefix(50))...\" (source: \(textResult.source), needsSelectAll: \(needsSelectAll))")
        
        // Show loading overlay near cursor
        TranslationLoadingOverlay.shared.show()
        
        // Perform translation asynchronously
        Task {
            do {
                let result = try await service.translate(
                    text: textToTranslate,
                    from: preferences.translationSourceLanguage,
                    to: preferences.translationTargetLanguage
                )
                
                await MainActor.run {
                    TranslationLoadingOverlay.shared.hide()
                    
                    // Preserve case pattern from original text
                    let finalText = service.preserveCase(original: textToTranslate, translated: result.translatedText)
                    debugWindowController?.logEvent("   Translated: \"\(result.translatedText.prefix(50))...\"")
                    debugWindowController?.logEvent("   Case preserved: \"\(finalText.prefix(50))...\"")
                    
                    // Use shared handler with per-direction settings
                    handleTranslationResult(
                        translatedText: finalText,
                        needsSelectAll: needsSelectAll,
                        shouldReplace: preferences.translationReplaceOriginal,
                        shouldCopy: preferences.translationCopyToClipboard,
                        shouldShowPopup: preferences.translationShowPopup,
                        autoHideSeconds: preferences.translationResultAutoHideSeconds,
                        logPrefix: "Translation"
                    )
                }
            } catch {
                await MainActor.run {
                    TranslationLoadingOverlay.shared.hide()
                    let message = self.translationErrorMessage(for: error)
                    self.debugWindowController?.logEvent("   Translation failed: \(error.localizedDescription)")
                    self.showTranslationNotification(message: message)
                }
            }
        }
    }
    
    /// Shared handler for translation results — used by both target and source direction
    private func handleTranslationResult(
        translatedText: String,
        needsSelectAll: Bool,
        shouldReplace: Bool,
        shouldCopy: Bool,
        shouldShowPopup: Bool,
        autoHideSeconds: Int,
        logPrefix: String
    ) {
        let service = TranslationService.shared
        
        // 1. Replace original text if enabled
        var replaceSucceeded = false
        if shouldReplace {
            if service.replaceSelectedText(with: translatedText, selectAllBeforePaste: needsSelectAll) {
                debugWindowController?.logEvent("   [\(logPrefix)] Replaced original text (selectAll: \(needsSelectAll))")
                replaceSucceeded = true
            } else {
                debugWindowController?.logEvent("   [\(logPrefix)] Could not replace text in this application")
                showTranslationNotification(message: "Không thể thay thế text trong ứng dụng này")
            }
        }
        
        // 2. Copy to clipboard if enabled (independent of replace)
        if shouldCopy {
            if replaceSucceeded {
                // replaceViaClipboardPaste restores old clipboard after 0.5s
                // We need to set clipboard AFTER that restore completes
                let textToCopy = translatedText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(textToCopy, forType: .string)
                }
                debugWindowController?.logEvent("   [\(logPrefix)] Will copy to clipboard after replace (delayed)")
            } else {
                // No replace or replace failed - copy immediately
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(translatedText, forType: .string)
                debugWindowController?.logEvent("   [\(logPrefix)] Copied to clipboard")
                TranslationLoadingOverlay.shared.showBrief(message: "Copied")
            }
        }
        
        // 3. Show popup overlay if enabled
        if shouldShowPopup {
            TranslationResultOverlay.shared.show(text: translatedText, autoHideSeconds: autoHideSeconds)
            debugWindowController?.logEvent("   [\(logPrefix)] Showing popup (autoHide: \(autoHideSeconds)s)")
        }
    }
    
    /// Show a brief notification to user about translation result
    private func showTranslationNotification(message: String) {
        DispatchQueue.main.async {
            // Show error/notification message using the translation result overlay
            TranslationResultOverlay.shared.show(text: message, autoHideSeconds: 5)
            print("[Translation] \(message)")
        }
    }
    
    /// Convert translation error to user-friendly Vietnamese message
    private func translationErrorMessage(for error: Error) -> String {
        guard let translationError = error as? TranslationError else {
            return "Lỗi dịch: \(error.localizedDescription)"
        }
        
        switch translationError {
        case .providerDisabled:
            return "Không có nhà cung cấp dịch nào khả dụng. Vui lòng bật ít nhất một nhà cung cấp trong Thiết lập → Dịch thuật."
        case .networkError:
            return "Lỗi kết nối mạng. Vui lòng kiểm tra kết nối Internet."
        case .rateLimited:
            return "Đã vượt quá giới hạn yêu cầu. Vui lòng thử lại sau."
        case .invalidResponse:
            return "Nhà cung cấp dịch trả về kết quả không hợp lệ. Vui lòng thử lại."
        case .emptyText:
            return "Không có text để dịch."
        case .unsupportedLanguage:
            return "Ngôn ngữ này chưa được hỗ trợ bởi nhà cung cấp dịch."
        case .unknown(let message):
            return "Lỗi dịch: \(message)"
        }
    }

    // MARK: - Translate to Source Hotkey

    private func updateTranslateToSourceHotkey() {
        let preferences = SharedSettings.shared.loadPreferences()
        
        // Check if translation is enabled
        guard preferences.translationEnabled else {
            eventTapManager?.translateToSourceHotkey = nil
            eventTapManager?.onTranslateToSourceHotkey = nil
            debugWindowController?.logEvent("Translate-to-source hotkey disabled (feature off)")
            return
        }

        let hotkey = preferences.translateToSourceHotkey

        // If no keycode, disable hotkey
        guard hotkey.keyCode != 0 else {
            eventTapManager?.translateToSourceHotkey = nil
            eventTapManager?.onTranslateToSourceHotkey = nil
            debugWindowController?.logEvent("Translate-to-source hotkey disabled (no key set)")
            return
        }

        // Configure EventTapManager to handle translate-to-source hotkey
        eventTapManager?.translateToSourceHotkey = hotkey
        eventTapManager?.onTranslateToSourceHotkey = { [weak self] in
            self?.performTranslateToSource()
        }

        debugWindowController?.logEvent("Translate-to-source hotkey set: \(hotkey.displayString)")
    }
    
    /// Perform translation of selected text back to source language
    /// Uses per-direction settings for replace, copy, and popup behavior
    private func performTranslateToSource() {
        let preferences = SharedSettings.shared.loadPreferences()
        let service = TranslationService.shared
        
        debugWindowController?.logEvent("Translate-to-source triggered via hotkey")
        
        // Get selected text or full value via AX (with source info)
        guard let textResult = service.getSelectedTextWithSource(), !textResult.text.isEmpty else {
            debugWindowController?.logEvent("   No text to translate")
            showTranslationNotification(message: "Không có text để dịch. Hãy chọn text hoặc focus vào input.")
            return
        }
        
        let textToTranslate = textResult.text
        let needsSelectAll = textResult.needsSelectAllForReplace
        
        debugWindowController?.logEvent("   Text: \"\(textToTranslate.prefix(50))...\" (source: \(textResult.source), needsSelectAll: \(needsSelectAll))")
        
        // Determine languages: translate FROM target TO source (reverse direction)
        let fromLang = preferences.translationTargetLanguage
        var toLang = preferences.translationSourceLanguage
        
        // Can't translate TO "auto" - use "vi" as default
        if toLang.code == "auto" {
            toLang = TranslationLanguage.find(byCode: "vi")
            debugWindowController?.logEvent("   Source language is 'auto', using 'vi' as target for reverse translation")
        }
        
        debugWindowController?.logEvent("   Reverse translation: \(fromLang.code) → \(toLang.code)")
        
        // Show loading overlay near cursor
        TranslationLoadingOverlay.shared.show()
        
        // Perform translation asynchronously
        Task {
            do {
                let result = try await service.translate(
                    text: textToTranslate,
                    from: fromLang,
                    to: toLang
                )
                
                await MainActor.run {
                    TranslationLoadingOverlay.shared.hide()
                    
                    let finalText = result.translatedText
                    debugWindowController?.logEvent("   Reverse translated: \"\(finalText.prefix(50))...\"")
                    
                    // Use shared handler with per-direction settings
                    handleTranslationResult(
                        translatedText: finalText,
                        needsSelectAll: needsSelectAll,
                        shouldReplace: preferences.translateToSourceReplaceOriginal,
                        shouldCopy: preferences.translateToSourceCopyToClipboard,
                        shouldShowPopup: preferences.translateToSourceShowPopup,
                        autoHideSeconds: preferences.translateToSourceAutoHideSeconds,
                        logPrefix: "Reverse"
                    )
                }
            } catch {
                await MainActor.run {
                    TranslationLoadingOverlay.shared.hide()
                    let message = self.translationErrorMessage(for: error)
                    self.debugWindowController?.logEvent("   Reverse translation failed: \(error.localizedDescription)")
                    self.showTranslationNotification(message: message)
                }
            }
        }
    }

    // MARK: - Debug Hotkey

    private func setupDebugHotkey() {
        // Setup notification observer for hotkey/settings changes
        NotificationCenter.default.addObserver(
            forName: .debugSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDebugHotkey()
        }

        // Initial setup
        updateDebugHotkey()
    }

    private func updateDebugHotkey() {
        let preferences = SharedSettings.shared.loadPreferences()
        let hotkey = preferences.debugHotkey

        // If no keycode, disable hotkey
        guard hotkey.keyCode != 0 else {
            eventTapManager?.debugHotkey = nil
            eventTapManager?.onDebugHotkey = nil
            debugWindowController?.logEvent("Debug hotkey disabled (no key set)")
            return
        }

        // Configure EventTapManager to handle debug hotkey
        eventTapManager?.debugHotkey = hotkey
        eventTapManager?.onDebugHotkey = { [weak self] in
            self?.toggleDebugWindowFromMenu()
            self?.debugWindowController?.logEvent("Debug mode toggled via hotkey (\(hotkey.displayString))")
        }

        debugWindowController?.logEvent("Debug hotkey set: \(hotkey.displayString)")
    }
    // MARK: - Toggle Exclusion Rules Hotkey

    private func setupToggleExclusionHotkey() {
        // Single load for both hotkey config and persisted state
        let preferences = SharedSettings.shared.loadPreferences()
        updateToggleExclusionHotkey(hotkey: preferences.toggleExclusionHotkey)
        keyboardHandler?.exclusionRulesEnabled = preferences.exclusionRulesEnabled
    }

    private func updateToggleExclusionHotkey(hotkey: Hotkey? = nil) {
        let resolvedHotkey = hotkey ?? SharedSettings.shared.loadPreferences().toggleExclusionHotkey

        // If no keycode, disable hotkey
        guard resolvedHotkey.keyCode != 0 else {
            eventTapManager?.toggleExclusionHotkey = nil
            eventTapManager?.onToggleExclusionHotkey = nil
            return
        }

        // Configure EventTapManager to handle toggle exclusion hotkey
        eventTapManager?.toggleExclusionHotkey = resolvedHotkey
        eventTapManager?.onToggleExclusionHotkey = { [weak self] in
            self?.toggleExclusionRules()
        }

        debugWindowController?.logEvent("Toggle exclusion hotkey set: \(resolvedHotkey.displayString)")
    }

    private func toggleExclusionRules() {
        let settings = SharedSettings.shared
        let newValue = !settings.exclusionRulesEnabled
        settings.exclusionRulesEnabled = newValue

        // Apply immediately to runtime
        keyboardHandler?.exclusionRulesEnabled = newValue

        // Re-detect injection method since exclusion state changed
        let newMethod = AppBehaviorDetector.shared.detectInjectionMethod()
        AppBehaviorDetector.shared.setConfirmedInjectionMethod(newMethod)

        // Beep feedback
        if SharedSettings.shared.beepOnToggle {
            NSSound.beep()
        }

        // Debug log
        let state = newValue ? "ON" : "OFF"
        debugWindowController?.logEvent("🔀 Exclusion rules toggled: \(state)")
        DebugLogger.shared.log("Exclusion rules toggled: \(state)")

        // Visual HUD feedback
        ToggleHUDWindow.shared.show(title: "Loại trừ ứng dụng", isEnabled: newValue)
    }

    // MARK: - Toggle Window Title Rules Hotkey

    private func setupToggleWindowRulesHotkey() {
        // Single load for both hotkey config and persisted state
        let preferences = SharedSettings.shared.loadPreferences()
        updateToggleWindowRulesHotkey(hotkey: preferences.toggleWindowRulesHotkey)
        AppBehaviorDetector.shared.windowTitleRulesEnabled = preferences.windowTitleRulesEnabled
    }

    private func updateToggleWindowRulesHotkey(hotkey: Hotkey? = nil) {
        let resolvedHotkey = hotkey ?? SharedSettings.shared.loadPreferences().toggleWindowRulesHotkey

        // If no keycode, disable hotkey
        guard resolvedHotkey.keyCode != 0 else {
            eventTapManager?.toggleWindowRulesHotkey = nil
            eventTapManager?.onToggleWindowRulesHotkey = nil
            return
        }

        // Configure EventTapManager to handle toggle window rules hotkey
        eventTapManager?.toggleWindowRulesHotkey = resolvedHotkey
        eventTapManager?.onToggleWindowRulesHotkey = { [weak self] in
            self?.toggleWindowTitleRules()
        }

        debugWindowController?.logEvent("Toggle window rules hotkey set: \(resolvedHotkey.displayString)")
    }

    private func toggleWindowTitleRules() {
        let settings = SharedSettings.shared
        let newValue = !settings.windowTitleRulesEnabled
        settings.windowTitleRulesEnabled = newValue

        // Apply immediately to runtime
        AppBehaviorDetector.shared.windowTitleRulesEnabled = newValue

        // Re-detect injection method since rules state changed
        let newMethod = AppBehaviorDetector.shared.detectInjectionMethod()
        AppBehaviorDetector.shared.setConfirmedInjectionMethod(newMethod)

        // Beep feedback
        if SharedSettings.shared.beepOnToggle {
            NSSound.beep()
        }

        // Debug log
        let state = newValue ? "ON" : "OFF"
        debugWindowController?.logEvent("🔀 Window Title Rules toggled: \(state)")
        DebugLogger.shared.log("Window Title Rules toggled: \(state)")

        // Visual HUD feedback
        ToggleHUDWindow.shared.show(title: "Hiệu chỉnh Engine", isEnabled: newValue)
    }
}

