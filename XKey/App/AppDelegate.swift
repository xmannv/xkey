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

/// C callback for AXObserver focus change notifications
/// Must be outside class since AXObserver requires a C function pointer
private func axFocusChangedCallback(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    // Get AppDelegate instance from refcon
    guard let refcon = refcon else { return }
    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    
    // Handle on main thread
    DispatchQueue.main.async {
        appDelegate.handleAXFocusChanged(element)
    }
}

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set shared instance for access from SwiftUI views
        AppDelegate.shared = self
        
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

        // Setup Sparkle auto-update
        setupSparkleUpdater()

        // Check and update XKeyIM if needed (on app startup)
        checkXKeyIMUpdate()

        // Load Vietnamese dictionary if spell checking is enabled
        setupSpellCheckDictionary()

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

        // Stop focus observer and timer
        focusCheckTimer?.invalidate()
        focusCheckTimer = nil
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
        let shouldShowDebug = preferences.debugModeEnabled

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
        
        settingsWindowController = SettingsWindowController(selectedSection: selectedSection) { [weak self] preferences in
            self?.applyPreferences(preferences)
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openLegacyPreferences(selectedTab: Int = 0) {
        // Close existing window if tab is different
        if let existingController = preferencesWindowController {
            existingController.close()
            preferencesWindowController = nil
        }
        
        preferencesWindowController = PreferencesWindowController(selectedTab: selectedTab) { [weak self] preferences in
            self?.applyPreferences(preferences)
        }
        
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openMacroManagement() {
        if #available(macOS 13.0, *) {
            openSettings(selectedSection: .macro)
        } else {
            openLegacyPreferences(selectedTab: 2) // Tab 2 = Nâng cao (has Macro section)
        }
    }
    
    func openConvertTool() {
        if #available(macOS 13.0, *) {
            openSettings(selectedSection: .convertTool)
        } else {
            openLegacyPreferences(selectedTab: 2) // Tab 2 = Nâng cao
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
        // Apply basic settings
        keyboardHandler?.inputMethod = preferences.inputMethod
        keyboardHandler?.codeTable = preferences.codeTable
        keyboardHandler?.modernStyle = preferences.modernStyle
        keyboardHandler?.spellCheckEnabled = preferences.spellCheckEnabled
        
        // Apply advanced features
        keyboardHandler?.quickTelexEnabled = preferences.quickTelexEnabled
        keyboardHandler?.quickStartConsonantEnabled = preferences.quickStartConsonantEnabled
        keyboardHandler?.quickEndConsonantEnabled = preferences.quickEndConsonantEnabled
        keyboardHandler?.upperCaseFirstChar = preferences.upperCaseFirstChar
        keyboardHandler?.restoreIfWrongSpelling = preferences.restoreIfWrongSpelling
        keyboardHandler?.allowConsonantZFWJ = preferences.allowConsonantZFWJ
        keyboardHandler?.freeMarkEnabled = preferences.freeMarkEnabled
        
        // Apply macro settings
        keyboardHandler?.macroEnabled = preferences.macroEnabled
        keyboardHandler?.macroInEnglishMode = preferences.macroInEnglishMode
        keyboardHandler?.autoCapsMacro = preferences.autoCapsMacro
        keyboardHandler?.addSpaceAfterMacro = preferences.addSpaceAfterMacro
        
        // Apply smart switch
        keyboardHandler?.smartSwitchEnabled = preferences.smartSwitchEnabled
        
        // Apply excluded apps
        keyboardHandler?.excludedApps = preferences.excludedApps
        
        // Apply debug mode (toggle debug window)
        toggleDebugWindow(enabled: preferences.debugModeEnabled)
        
        // Update status bar manager
        statusBarManager?.viewModel.currentInputMethod = preferences.inputMethod
        statusBarManager?.viewModel.currentCodeTable = preferences.codeTable
        
        // Update hotkey display in menu
        statusBarManager?.updateHotkeyDisplay(preferences.toggleHotkey)
        
        // Update menu bar icon style
        statusBarManager?.updateMenuBarIconStyle(preferences.menuBarIconStyle)
        
        // Update Dock icon visibility
        updateDockIconVisibility(show: preferences.showDockIcon)
        
        // Update hotkey
        setupGlobalHotkey(with: preferences.toggleHotkey)
        
        // Update switch XKey hotkey
        setupSwitchXKeyHotkey(with: preferences.switchToXKeyHotkey)
        
        // Update undo typing
        keyboardHandler?.undoTypingEnabled = preferences.undoTypingEnabled
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
                // Setup window close callback - disable debug mode when window is closed via Close button
                debugWindowController?.onWindowClose = { [weak self] in
                    self?.handleDebugWindowClosed()
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
            let defaultEscHotkey = Hotkey(keyCode: 0x35, modifiers: [], isModifierOnly: false)
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
            switchXKeyFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
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

            // Handle Smart Switch - auto switch language per app
            self.handleSmartSwitch(notification: notification)
            
            // Apply Force Accessibility (AXManualAccessibility) FIRST if matching rule exists
            // This MUST happen BEFORE detectInjectionMethod() because:
            // 1. Force AX enables enhanced accessibility for Electron/Chromium apps
            // 2. detectInjectionMethod() may need to read AX values
            // 3. AX values won't be available without Force AX enabled first
            ForceAccessibilityManager.shared.applyForCurrentApp()
            
            // Small delay to allow AX tree to update after setting AXManualAccessibility
            // Electron/Chromium apps need a moment to refresh their accessibility tree
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                
                // Detect and set confirmed injection method for the new app
                // This ensures keystrokes use correct method immediately after app switch
                let detector = AppBehaviorDetector.shared
                let injectionInfo = detector.detectInjectionMethod()
                detector.setConfirmedInjectionMethod(injectionInfo)

                self.debugWindowController?.logEvent("App switched - engine reset, mid-sentence mode")
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                self.debugWindowController?.logEvent("   Injection: \(injectionInfo.method) (\(injectionInfo.description)) [\(textMethodName)] ✓ confirmed")
                
                // Setup AXObserver for the new app to monitor focus changes (CMD+T, etc.)
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.setupAXObserverForApp(app)
                }
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

        // Check if overlay detection is enabled
        let prefs = SharedSettings.shared.loadPreferences()
        guard prefs.detectOverlayApps else { return }

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
        // Monitor mouse clicks to detect focus changes
        // When user clicks, they might be switching between input fields or moving cursor
        
        // Global monitor - catches clicks in OTHER apps
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Log that mouse click was detected (always visible, not verbose)
            self?.debugWindowController?.logEvent("Mouse click (global) → resetting engine buffer")

            // Reset engine when mouse is clicked (likely focus change or cursor move)
            // Mark as cursor moved to disable autocomplete fix (avoid deleting text on right)
            self?.keyboardHandler?.resetWithCursorMoved()

            // Special case: If clicking into overlay app (Spotlight/Raycast/Alfred) with empty input,
            // reset mid-sentence flag to allow Forward Delete (safe since no text to delete)
            // Use 0.15s delay to allow AX API to update window title (VSCode needs more time)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                if let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() {
                    let detector = AppBehaviorDetector.shared
                    if detector.getFocusedElementInfo().isEmpty {
                        self?.keyboardHandler?.resetMidSentenceFlag()
                        self?.debugWindowController?.logEvent("'\(overlayName)' with empty input → reset mid-sentence flag")
                    }
                }

                // Log detailed input detection info
                self?.logMouseClickInputDetection()
            }

            // Reset lastFocusedElement to allow toolbar to re-show after auto-hide
            // When user clicks, they might be moving cursor within same field
            self?.lastFocusedElement = nil

            // Trigger toolbar check with slight delay to allow focus to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.handleFocusCheck()
            }
        }
        
        // Local monitor - catches clicks within XKey app itself (Debug window, Settings, etc.)
        // This ensures engine resets even when interacting with XKey's own UI
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Reset engine when clicking within XKey app
            self?.keyboardHandler?.resetWithCursorMoved()
            return event  // Pass through the event
        }

        debugWindowController?.logEvent("Mouse click monitor registered (global + local)")
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
        
        // Get current detection results
        let behavior = detector.detect()
        let behaviorName = getBehaviorName(behavior)
        let injectionInfo = detector.detectInjectionMethod()
        
        // IMMEDIATELY set confirmed injection method so keystrokes use this method
        // This applies the best available method at each retry attempt
        detector.setConfirmedInjectionMethod(injectionInfo)
        
        // Check if this is an overlay behavior (may be stale data)
        let isOverlayBehavior = behavior == .spotlight || behavior == .overlayLauncher
        
        if attempt < maxAttempts && isOverlayBehavior {
            // Overlay detected - might be timing issue, retry after interval
            // Only log on first attempt to avoid spam
            if attempt == 1 {
                debugWindowController?.logEvent("Mouse click detected (checking for AX timing...)")
                debugWindowController?.logEvent("   Attempt \(attempt): \(behaviorName) → \(injectionInfo.method) (applying...)")
            } else {
                debugWindowController?.logEvent("   Attempt \(attempt): \(behaviorName) → \(injectionInfo.method) (applying...)")
            }
            
            // Schedule next attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.detectBehaviorWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts, interval: interval)
            }
            return
        }
        
        // Final attempt OR not overlay behavior - log the result
        logFinalMouseClickDetection(attempt: attempt, wasRetried: attempt > 1)
    }
    
    /// Log final mouse click detection result
    private func logFinalMouseClickDetection(attempt: Int, wasRetried: Bool) {
        // Get frontmost app info
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else {
            debugWindowController?.logEvent("Mouse click - engine reset, mid-sentence mode")
            return
        }

        let appName = app.localizedName ?? "Unknown"

        // Get focused element info from Accessibility API (single query for all attributes)
        let detector = AppBehaviorDetector.shared
        let elementInfo = detector.getFocusedElementInfo()
        let elementRole = elementInfo.role ?? "Unknown"
        let elementSubrole = elementInfo.subrole
        let axDescription = elementInfo.description
        let axIdentifier = elementInfo.identifier
        let domClasses = elementInfo.domClasses
        
        // Get window title
        let windowTitle = detector.getCachedWindowTitle()

        // Get app behavior type
        let behavior = detector.detect()
        let behaviorName = getBehaviorName(behavior)

        // Get injection method info
        let injectionInfo = detector.detectInjectionMethod()
        let injectionMethodName = getInjectionMethodName(injectionInfo.method)
        
        // Set as confirmed injection method (final result after all retries)
        detector.setConfirmedInjectionMethod(injectionInfo)

        // Get current input source
        let inputSource = InputSourceManager.getCurrentInputSource()
        let inputSourceName = inputSource?.displayName ?? "Unknown"
        
        // Get matched Window Title Rule (if any)
        let matchedRule = detector.findMatchingRule()
        
        // Get IMKit behavior
        let imkitBehavior = detector.detectIMKitBehavior()

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
        let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
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

            // Force enable Vietnamese mode for XKeyIM
            self.statusBarManager?.viewModel.isVietnameseEnabled = true
            self.keyboardHandler?.setVietnamese(true)
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
        
        do {
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
            
            // Check for updates immediately on app launch (silently in background)
            // This ensures updates are always checked at startup, not just on schedule
            // The dialog will only appear if a new update is found
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
            
        } catch {
            debugWindowController?.logEvent("Failed to initialize Sparkle: \(error)")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            XKeyIMUpdateManager.shared.installBundledXKeyIM(showNotification: false)
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
        
        // ALWAYS setup focus monitoring for injection detection (CMD+T, Tab, etc.)
        // This runs regardless of toolbar setting
        setupFocusChangeMonitoring()

        let preferences = SharedSettings.shared.loadPreferences()

        // Only setup toolbar-specific features if enabled
        guard preferences.tempOffToolbarEnabled else {
            debugWindowController?.logEvent("Temp off toolbar disabled (focus monitoring still active)")
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

        // Note: Focus monitoring is already setup in setupTempOffToolbar()
        // and runs for injection detection even when toolbar is disabled

        debugWindowController?.logEvent("Temp off toolbar enabled")
        
        // Check if user is already focused on a text input and show toolbar immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.lastFocusedElement = nil  // Reset to force re-check
            self?.handleFocusCheck()
        }
    }

    /// Disable temp off toolbar and cleanup
    /// Note: Focus check timer is NOT stopped - it continues for injection detection
    private func disableTempOffToolbar() {
        // Clear hotkey from EventTapManager
        eventTapManager?.toolbarHotkey = nil
        eventTapManager?.onToolbarHotkey = nil

        // Note: focusCheckTimer is NOT stopped here
        // It continues running for injection detection (CMD+T, etc.)

        // Hide toolbar if visible
        TempOffToolbarController.shared.hide()

        // Clear callback
        TempOffToolbarController.shared.onStateChange = nil
        
        // Clear last focused element so re-enable will re-check
        lastFocusedElement = nil

        debugWindowController?.logEvent("Temp off toolbar disabled (focus monitoring still active)")
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

        // Also monitor mouse clicks to detect focus changes within same app
        // This is already handled by mouseClickMonitor, we just need to hook into it
        // We'll use a timer to periodically check focus (more reliable backup)
        setupFocusCheckTimer()
        
        // Setup AXObserver for the current frontmost app on launch
        // This ensures focus changes are monitored immediately
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            setupAXObserverForApp(frontApp)
        }

        debugWindowController?.logEvent("Focus change monitoring enabled (AXObserver + timer backup)")
    }

    private var focusCheckTimer: Timer?

    private func setupFocusCheckTimer() {
        focusCheckTimer?.invalidate()
        // Use 1s interval as backup - AXObserver handles real-time detection
        // Timer is kept for edge cases where AXObserver might miss events
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.handleFocusCheck()
        }
    }
    
    /// Main focus check handler - gets focused element once and passes to both processors
    private func handleFocusCheck() {
        let systemWide = AXUIElementCreateSystemWide()
        
        // Get focused element ONCE (avoid duplicate AX API calls)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            // No focused element - hide toolbar if visible
            if SharedSettings.shared.tempOffToolbarEnabled && TempOffToolbarController.shared.isVisible {
                TempOffToolbarController.shared.hide()
            }
            return
        }
        
        let axElement = focusedElement as! AXUIElement
        
        // 1. ALWAYS check for injection method changes (CMD+T, Tab, etc.)
        checkIntraAppFocusChange(for: axElement)
        
        // 2. Check toolbar display (only if enabled)
        if SharedSettings.shared.tempOffToolbarEnabled {
            checkAndShowToolbarForFocusedElement(axElement)
        }
    }

    // MARK: - Intra-App Focus Monitoring
    
    /// Reset engine for focus change, handling overlay apps specially
    /// Overlay apps (Spotlight, Raycast, Alfred) always start with fresh empty input,
    /// so we don't set mid-sentence flag. Normal apps set mid-sentence flag to protect text.
    private func resetEngineForFocusChange() {
        if OverlayAppDetector.shared.getVisibleOverlayAppName() != nil {
            // Overlay app - reset engine but DON'T set mid-sentence flag
            keyboardHandler?.engine.startNewSession()
            keyboardHandler?.resetMidSentenceFlag()
        } else {
            // Normal app - set mid-sentence flag to protect text on the right of cursor
            keyboardHandler?.resetWithCursorMoved()
        }
    }
    
    /// Check if focused element has changed within the same app (e.g., CMD+T in browser)
    /// If so, re-detect injection method and reset engine
    /// - Parameter element: The currently focused AXUIElement (passed from handleFocusCheck)
    private func checkIntraAppFocusChange(for element: AXUIElement) {
        // Get current element's "signature" (role + description/identifier)
        let currentSignature = getElementSignature(element)
        
        // Check if signature changed (different element type)
        if currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty {
            // Focus changed within same app (different element type)
            // Re-detect injection method
            let detector = AppBehaviorDetector.shared
            let injectionInfo = detector.detectInjectionMethod()
            let previousMethod = detector.getConfirmedInjectionMethod()
            
            // Always log focus change for debugging (even if method doesn't change)
            debugWindowController?.logEvent("Focus changed (keyboard): \(lastFocusedElementSignature) → \(currentSignature)")
            
            // Only update injection method if it actually changed
            if previousMethod.method != injectionInfo.method {
                detector.setConfirmedInjectionMethod(injectionInfo)
                resetEngineForFocusChange()
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                debugWindowController?.logEvent("   Injection: \(previousMethod.method.rawValue) → \(injectionInfo.method.rawValue) [\(textMethodName)] ✓ confirmed")
            } else {
                // Method same but focus changed - still reset engine for safety
                resetEngineForFocusChange()
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                debugWindowController?.logEvent("   Injection: \(injectionInfo.method.rawValue) [\(textMethodName)] (unchanged, engine reset)")
            }
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
        let result = AXObserverCreate(pid, axFocusChangedCallback, &observer)
        
        guard result == .success, let newObserver = observer else {
            debugWindowController?.logEvent("AXObserver: Failed to create for PID \(pid) (error: \(result.rawValue))")
            return
        }
        
        // Get the app's AXUIElement
        let appElement = AXUIElementCreateApplication(pid)
        
        // Register for focused UI element changed notification
        let addResult = AXObserverAddNotification(
            newObserver,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard addResult == .success else {
            debugWindowController?.logEvent("AXObserver: Failed to add notification for PID \(pid) (error: \(addResult.rawValue))")
            return
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
    func handleAXFocusChanged(_ element: AXUIElement) {
        // Get current signature
        let currentSignature = getElementSignature(element)
        
        // Only process if signature actually changed
        if currentSignature != lastFocusedElementSignature && !lastFocusedElementSignature.isEmpty {
            // Re-detect injection method
            let detector = AppBehaviorDetector.shared
            let injectionInfo = detector.detectInjectionMethod()
            let previousMethod = detector.getConfirmedInjectionMethod()
            
            // Log focus change
            debugWindowController?.logEvent("Focus changed (AXObserver): \(lastFocusedElementSignature) → \(currentSignature)")
            
            if previousMethod.method != injectionInfo.method {
                // Injection method changed - update and reset engine
                detector.setConfirmedInjectionMethod(injectionInfo)
                resetEngineForFocusChange()
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                debugWindowController?.logEvent("   Injection: \(previousMethod.method.rawValue) → \(injectionInfo.method.rawValue) [\(textMethodName)] ✓ confirmed")
            } else {
                // Method same but focus changed - still reset engine for safety
                resetEngineForFocusChange()
                let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
                debugWindowController?.logEvent("   Injection: \(injectionInfo.method.rawValue) [\(textMethodName)] (unchanged, engine reset)")
            }
        }
        
        // Update last signature
        lastFocusedElementSignature = currentSignature
        
        // Also update lastFocusedElement for toolbar tracking
        lastFocusedElement = element
    }
    
    /// Get a signature string for an AX element (used to detect focus changes)
    /// Signature includes role, subrole, and description/identifier
    private func getElementSignature(_ element: AXUIElement) -> String {
        var parts: [String] = []
        
        // Get role
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            parts.append(role)
        }
        
        // Get subrole
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            parts.append(subrole)
        }
        
        // Get description (used for address bar detection in browsers)
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            // Truncate to first 50 chars to avoid overly long signatures
            let truncated = String(desc.prefix(50))
            parts.append("desc:\(truncated)")
        }
        
        // Get DOM identifier if available (for web content)
        var domIdRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXDOMIdentifier" as CFString, &domIdRef) == .success,
           let domId = domIdRef as? String, !domId.isEmpty {
            parts.append("dom:\(domId)")
        }
        
        return parts.joined(separator: "|")
    }

    /// Check if focused element is a text field and show toolbar
    /// - Parameter element: The currently focused AXUIElement (passed from handleFocusCheck)
    private func checkAndShowToolbarForFocusedElement(_ element: AXUIElement) {
        // Check if it's the same element as before
        if let lastElement = lastFocusedElement, CFEqual(lastElement, element) {
            // Same element
            if TempOffToolbarController.shared.isVisible {
                // Toolbar visible - just update position
                TempOffToolbarController.shared.updatePosition()
            }
            // If toolbar is hidden (after auto-hide), we'll re-show when mouse click triggers
            // The mouse click handler will reset lastFocusedElement
            return
        }

        // New focused element
        lastFocusedElement = element

        // Check if it's a text input element
        if isTextInputElement(element) {
            // Show toolbar near cursor
            TempOffToolbarController.shared.show()
        } else {
            // Not a text field - hide toolbar
            TempOffToolbarController.shared.hide()
        }
    }

    /// Check if an AX element is a text input field
    private func isTextInputElement(_ element: AXUIElement) -> Bool {
        // Get role
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        // Text input roles - only these are true text inputs
        let textRoles = [
            "AXTextField",
            "AXTextArea",
            "AXComboBox",
            "AXSearchField"
        ]

        if textRoles.contains(role) {
            return true
        }

        // Check subrole for web content text fields
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            // Only text-related subroles
            if subrole == "AXSearchField" || subrole == "AXSecureTextField" {
                return true
            }
        }

        // For contenteditable web elements (role=AXGroup or AXWebArea),
        // check if RoleDescription contains text input keywords
        if role == "AXGroup" || role == "AXWebArea" {
            var roleDescRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
               let roleDesc = roleDescRef as? String {
                let lowerDesc = roleDesc.lowercased()
                if lowerDesc.contains("field") || lowerDesc.contains("editor") || lowerDesc.contains("input") {
                    return true
                }
            }
        }

        // Do NOT use AXSelectedTextRange as fallback - links and other elements may have it
        return false
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
}

