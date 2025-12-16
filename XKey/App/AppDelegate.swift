//
//  AppDelegate.swift
//  XKey
//
//  Application delegate managing lifecycle and coordination
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

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

    // MARK: - Initialization

    override init() {
        super.init()
    }
    
    // MARK: - Public Accessors
    
    /// Get the macro manager for external access
    func getMacroManager() -> MacroManager? {
        return keyboardHandler?.getMacroManager()
    }

    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create debug window first
        setupDebugWindow()
        
        debugWindowController?.logEvent("🚀 XKey starting...")

        // Load and apply preferences
        let preferences = PreferencesManager.shared.loadPreferences()
        
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

        debugWindowController?.updateStatus("XKey started successfully")
        debugWindowController?.logEvent("✅ XKey started successfully")
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
    
    // MARK: - Setup

    private func setupDebugWindow() {
        // Check if debug mode is enabled in preferences
        let preferences = PreferencesManager.shared.loadPreferences()
        let shouldShowDebug = preferences.debugModeEnabled
        
        #if DEBUG
        // Always show in debug builds
        debugWindowController = DebugWindowController()
        debugWindowController?.showWindow(nil)
        debugWindowController?.logEvent("✅ Debug window created (DEBUG build)")
        
        // Setup read word callback
        debugWindowController?.setupReadWordCallback { [weak self] in
            self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
        }
        #else
        // Show in production only if enabled in settings
        if shouldShowDebug {
            debugWindowController = DebugWindowController()
            debugWindowController?.showWindow(nil)
            debugWindowController?.logEvent("✅ Debug window created (Production - enabled in settings)")
            
            // Setup read word callback
            debugWindowController?.setupReadWordCallback { [weak self] in
                self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
            }
        }
        #endif
    }

    private func setupKeyboardHandling() {
        debugWindowController?.logEvent("🔧 Setting up keyboard handling...")

        // Create keyboard handler
        keyboardHandler = KeyboardEventHandler()
        debugWindowController?.logEvent("  ✅ Keyboard handler created")
        
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
        debugWindowController?.logEvent("  ✅ Event tap manager created, delegate set")
        
        // Connect debug logging (only if logging is enabled)
        // EventTap logs are very verbose, skip most of them
        eventTapManager?.debugLogCallback = { [weak self] message in
            guard let self = self,
                  let debugWindow = self.debugWindowController,
                  debugWindow.isLoggingEnabled else { return }
            
            // Log important EventTap messages (setup, errors, status changes)
            let shouldLog = message.contains("No delegate") ||
                           message.contains("disabled") ||
                           message.contains("🚀") ||  // Start
                           message.contains("✅") ||  // Success
                           message.contains("❌") ||  // Error
                           message.contains("⏹️")    // Stop
            
            if shouldLog {
                debugWindow.logEvent(message)
            }
        }

        // Check permission BEFORE trying to start event tap
        // This prevents macOS system dialog from appearing
        guard let manager = eventTapManager else { return }
        
        if manager.checkAccessibilityPermission() {
            // Permission already granted, start event tap
            do {
                try manager.start()
                debugWindowController?.updateStatus("Event tap started - Ready to type!")
                debugWindowController?.logEvent("  ✅ Event tap started successfully!")
            } catch {
                debugWindowController?.updateStatus("ERROR: Failed to start event tap")
                debugWindowController?.logEvent("  ❌ Failed to start event tap: \(error)")
            }
        } else {
            // No permission yet - don't call start() to avoid system dialog
            debugWindowController?.updateStatus("Waiting for accessibility permission...")
            debugWindowController?.logEvent("  ⚠️ Accessibility permission not granted yet")
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
    
    private func applyPreferences(_ preferences: Preferences) {
        // Apply basic settings
        keyboardHandler?.inputMethod = preferences.inputMethod
        keyboardHandler?.codeTable = preferences.codeTable
        keyboardHandler?.modernStyle = preferences.modernStyle
        keyboardHandler?.spellCheckEnabled = preferences.spellCheckEnabled
        keyboardHandler?.fixAutocomplete = preferences.fixAutocomplete
        
        // Apply advanced features
        keyboardHandler?.quickTelexEnabled = preferences.quickTelexEnabled
        keyboardHandler?.quickStartConsonantEnabled = preferences.quickStartConsonantEnabled
        keyboardHandler?.quickEndConsonantEnabled = preferences.quickEndConsonantEnabled
        keyboardHandler?.upperCaseFirstChar = preferences.upperCaseFirstChar
        keyboardHandler?.restoreIfWrongSpelling = preferences.restoreIfWrongSpelling
        keyboardHandler?.allowConsonantZFWJ = preferences.allowConsonantZFWJ
        keyboardHandler?.freeMarkEnabled = preferences.freeMarkEnabled
        keyboardHandler?.tempOffSpellingEnabled = preferences.tempOffSpellingEnabled
        keyboardHandler?.tempOffEngineEnabled = preferences.tempOffEngineEnabled
        
        // Apply macro settings
        keyboardHandler?.macroEnabled = preferences.macroEnabled
        keyboardHandler?.macroInEnglishMode = preferences.macroInEnglishMode
        keyboardHandler?.autoCapsMacro = preferences.autoCapsMacro
        
        // Apply smart switch
        keyboardHandler?.smartSwitchEnabled = preferences.smartSwitchEnabled
        
        // Apply debug mode (toggle debug window)
        toggleDebugWindow(enabled: preferences.debugModeEnabled)
        
        // Update status bar manager
        statusBarManager?.viewModel.currentInputMethod = preferences.inputMethod
        statusBarManager?.viewModel.currentCodeTable = preferences.codeTable
        
        // Update hotkey display in menu
        statusBarManager?.updateHotkeyDisplay(preferences.toggleHotkey)
        
        // Update hotkey
        setupGlobalHotkey(with: preferences.toggleHotkey)
        
        debugWindowController?.logEvent("✅ Preferences applied (including advanced features)")
    }
    
    // MARK: - Debug Window Management
    
    private func toggleDebugWindow(enabled: Bool) {
        #if DEBUG
        // In debug builds, always keep debug window visible
        if debugWindowController == nil {
            setupDebugWindow()
        }
        debugWindowController?.logEvent("ℹ️ Debug mode setting changed to: \(enabled) (ignored in DEBUG build)")
        #else
        // In production builds, respect the setting
        if enabled {
            // Enable debug window
            if debugWindowController == nil {
                debugWindowController = DebugWindowController()
                debugWindowController?.setupReadWordCallback { [weak self] in
                    self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
                }
                debugWindowController?.logEvent("✅ Debug window enabled via settings")
            }
            debugWindowController?.showWindow(nil)
        } else {
            // Disable debug window
            if let window = debugWindowController?.window {
                window.close()
                debugWindowController = nil
            }
        }
        #endif
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
        
        debugWindowController?.logEvent("🔓 Opening System Settings for Accessibility permission")
    }
    
    private func startPermissionMonitoring() {
        // Check permission every 2 seconds
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let manager = self.eventTapManager else { return }
            
            if manager.checkAccessibilityPermission() {
                // Permission granted! Try to start event tap
                self.debugWindowController?.logEvent("✅ Accessibility permission granted!")
                
                do {
                    try manager.start()
                    self.debugWindowController?.updateStatus("Event tap started - Ready to type!")
                    self.debugWindowController?.logEvent("✅ Event tap started successfully after permission grant")
                    
                    // Stop monitoring
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    
                } catch {
                    self.debugWindowController?.logEvent("❌ Failed to start event tap: \(error)")
                }
            }
        }
        
        debugWindowController?.logEvent("👀 Started monitoring for permission changes")
    }

    private func setupGlobalHotkey() {
        let preferences = PreferencesManager.shared.loadPreferences()
        setupGlobalHotkey(with: preferences.toggleHotkey)
    }
    
    private func setupGlobalHotkey(with hotkey: Hotkey) {
        // Configure EventTapManager to handle toggle hotkey
        // This ensures the hotkey is consumed at the lowest level
        // and doesn't reach other applications
        eventTapManager?.toggleHotkey = hotkey
        eventTapManager?.onToggleHotkey = { [weak self] in
            self?.statusBarManager?.viewModel.toggleVietnamese()
            
            self?.debugWindowController?.logEvent("🔄 Toggled Vietnamese mode via hotkey (\(hotkey.displayString))")
        }

        debugWindowController?.logEvent("  ✅ Toggle hotkey configured in EventTap: \(hotkey.displayString)")
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
                    
                    self?.debugWindowController?.logEvent("⌨️ Read Word triggered via hotkey (Cmd+Shift+R)")
                }
            }
        }
        
        // Local monitor - catches hotkey when XKey app is focused
        readWordHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == keyCode && checkModifiers(event) {
                DispatchQueue.main.async {
                    self?.keyboardHandler?.engine.debugReadWordBeforeCursor()
                    
                    self?.debugWindowController?.logEvent("⌨️ Read Word triggered via hotkey (Cmd+Shift+R)")
                }
                // Return nil to consume the event
                return nil
            }
            return event
        }
        
        debugWindowController?.logEvent("  ✅ Read Word hotkey: Cmd+Shift+R")
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
            self.keyboardHandler?.reset()
            
            // Handle Smart Switch - auto switch language per app
            self.handleSmartSwitch(notification: notification)
            
            self.debugWindowController?.logEvent("🔄 App switched - engine reset")
        }

        debugWindowController?.logEvent("  ✅ App switch observer registered")
    }
    
    /// Handle Smart Switch when app changes
    private func handleSmartSwitch(notification: Notification) {
        guard let handler = keyboardHandler else { return }
        guard handler.smartSwitchEnabled else { return }
        
        // Get the new active app
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }
        
        // Check if should switch language
        let result = handler.engine.checkSmartSwitch()
        
        if result.shouldSwitch {
            // Switch language
            let newEnabled = result.newLanguage == 1
            statusBarManager?.viewModel.isVietnameseEnabled = newEnabled
            handler.setVietnamese(newEnabled)
            
            debugWindowController?.logEvent("🔄 Smart Switch: '\(bundleId)' → \(newEnabled ? "Vietnamese" : "English")")
        } else {
            // Save current language for this app
            let currentLanguage = statusBarManager?.viewModel.isVietnameseEnabled == true ? 1 : 0
            handler.engine.saveAppLanguage(bundleId: bundleId, language: currentLanguage)
        }
    }
    
    private func setupMouseClickMonitor() {
        // Monitor mouse clicks to detect focus changes
        // When user clicks, they might be switching between input fields
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Reset engine when mouse is clicked (likely focus change)
            self?.keyboardHandler?.reset()
            self?.debugWindowController?.logEvent("🖱️ Mouse click - engine reset")
        }
        
        debugWindowController?.logEvent("  ✅ Mouse click monitor registered")
    }
}

