//
//  StatusBarViewModel.swift
//  XKey
//
//  ViewModel for Status Bar
//

import SwiftUI
import Combine
import Cocoa

class StatusBarViewModel: ObservableObject {
    @Published var isVietnameseEnabled = true
    @Published var currentInputMethod: InputMethod = .telex
    @Published var currentCodeTable: CodeTable = .unicode
    @Published var hotkeyDisplay = "⌘⇧V"
    @Published var hotkeyKeyEquivalent: KeyEquivalent = "v"
    @Published var hotkeyModifiers: EventModifiers = [.command, .shift]
    @Published var debugModeEnabled = false
    @Published var isRemoteDesktopRunning = false
    @Published var isRemoteDesktopTarget = false

    private weak var keyboardHandler: KeyboardEventHandler?
    private weak var eventTapManager: EventTapManager?
    private var remoteDesktopWorkspaceObservers: [NSObjectProtocol] = []
    private var settingsObserver: NSObjectProtocol?
    
    // Debug logging callback
    var debugLogCallback: ((String) -> Void)?
    
    var onOpenPreferences: (() -> Void)?
    var onOpenMacroManagement: (() -> Void)?
    var onOpenConvertTool: (() -> Void)?
    var onOpenDebugWindow: (() -> Void)?
    var onToggleDebugWindow: (() -> Void)?  // Toggle open/close debug window
    
    init(keyboardHandler: KeyboardEventHandler?, eventTapManager: EventTapManager?) {
        self.keyboardHandler = keyboardHandler
        self.eventTapManager = eventTapManager
        
        // Seed from the App Group before syncing: XKeyIM writes this flag too, and
        // setupKeyboardHandling() has already applied the shared value to the handler
        // via TapEnvironment. Starting from a hardcoded default would override it.
        isVietnameseEnabled = SharedSettings.shared.vietnameseEnabled

        // Sync initial state with keyboard handler
        if let handler = keyboardHandler {
            handler.setVietnamese(isVietnameseEnabled)
        }
        
        // Load hotkey from preferences
        updateHotkeyDisplay()

        // Remote desktop target state
        isRemoteDesktopTarget = SharedSettings.shared.isRemoteDesktopTarget
        checkRemoteDesktopRunning()
        setupRemoteDesktopMonitoring()
    }

    deinit {
        remoteDesktopWorkspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let obs = settingsObserver { NotificationCenter.default.removeObserver(obs) }
    }
    
    private func log(_ message: String) {
        debugLogCallback?(message)
    }

    private func checkRemoteDesktopRunning() {
        let runningIds = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() }
        isRemoteDesktopRunning = runningIds.contains { RemoteDesktopBundleIds.all.contains($0) }
    }

    private func setupRemoteDesktopMonitoring() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let onLaunch = workspaceCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkRemoteDesktopRunning()
        }
        let onTerminate = workspaceCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkRemoteDesktopRunning()
        }
        remoteDesktopWorkspaceObservers = [onLaunch, onTerminate]

        // Refresh isRemoteDesktopTarget when Settings panel saves (avoids stale toggle state)
        settingsObserver = NotificationCenter.default.addObserver(forName: .sharedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            let newValue = SharedSettings.shared.isRemoteDesktopTarget
            if self?.isRemoteDesktopTarget != newValue {
                self?.isRemoteDesktopTarget = newValue
            }
        }
    }

    func setRemoteDesktopTarget(_ enabled: Bool) {
        isRemoteDesktopTarget = enabled
        SharedSettings.shared.isRemoteDesktopTarget = enabled
        if eventTapManager?.isRunning == true {
            try? eventTapManager?.restart()
        }
        log("Remote desktop target mode: \(enabled ? "ON" : "OFF")")
    }
    
    func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        keyboardHandler?.setVietnamese(isVietnameseEnabled)

        // The user asking for a durable change: the status-bar click, the popover switch
        // and the global hotkey all land here, and init() seeds from this same flag. Only
        // XKeyIM used to write it, so one "off" from XKeyIM's menu stuck forever — XKey.app
        // could never write its way back out. Smart Switch and input-source restores
        // deliberately do NOT persist: those are transient per-app state, not a preference.
        SharedSettings.shared.vietnameseEnabled = isVietnameseEnabled

        log("Vietnamese toggled: \(isVietnameseEnabled ? "ON" : "OFF")")
        
        // Play beep sound if enabled
        // Using AudioManager to handle wake-from-sleep audio routing issues
        let prefs = SharedSettings.shared.loadPreferences()
        if prefs.beepOnToggle {
            AudioManager.shared.playBeep()
        }
        
        // Save language for current app (Smart Switch)
        saveLanguageForCurrentApp()
    }
    
    /// Save current language for the active app (for Smart Switch feature)
    private func saveLanguageForCurrentApp() {
        guard let handler = keyboardHandler else { return }
        guard handler.smartSwitchEnabled else { return }

        // Check if an overlay app (Spotlight/Raycast/Alfred) is currently visible
        if OverlayAppDetector.shared.isOverlayAppVisible() {
            if let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() {
                // Save language for the overlay app itself (not the underlying app)
                let overlayBundleId = overlayNameToBundleId(overlayName)
                if let bundleId = overlayBundleId {
                    let language = isVietnameseEnabled ? 1 : 0
                    handler.engine.saveAppLanguage(bundleId: bundleId, language: language)
                    log("📝 Smart Switch: Saved overlay '\(overlayName)' (\(bundleId)) → \(isVietnameseEnabled ? "Vietnamese" : "English")")
                } else {
                    log("Smart Switch: Overlay '\(overlayName)' has unknown bundleId, skipping save")
                }
            }
            return
        }

        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        // Excluded apps do not participate in Smart Switch: a toggle made while one is
        // frontmost must not be recorded as that app's language (see handleSmartSwitch).
        guard !handler.isAppExcluded(bundleIdentifier: bundleId) else {
            log("Smart Switch: Skipped save, app '\(bundleId)' excluded")
            return
        }

        let language = isVietnameseEnabled ? 1 : 0
        handler.engine.saveAppLanguage(bundleId: bundleId, language: language)
        log("📝 Smart Switch: Saved '\(bundleId)' → \(isVietnameseEnabled ? "Vietnamese" : "English")")
    }

    /// Map overlay app name to bundle ID for Smart Switch
    private func overlayNameToBundleId(_ name: String) -> String? {
        return OverlayAppDetector.bundleId(forOverlayName: name)
    }
    
    func selectInputMethod(_ method: InputMethod) {
        log("📋 selectInputMethod: BEFORE=\(currentInputMethod.displayName), setting to \(method.displayName)")
        
        currentInputMethod = method
        
        log("📋 selectInputMethod: AFTER=\(currentInputMethod.displayName)")
        
        if let handler = keyboardHandler {
            handler.inputMethod = method
            log("Set handler.inputMethod to \(method.displayName)")
        } else {
            log("keyboardHandler is nil!")
        }
        
        // Save to preferences
        var prefs = SharedSettings.shared.loadPreferences()
        prefs.inputMethod = method
        SharedSettings.shared.savePreferences(prefs)

        // Verify saved
        let savedPrefs = SharedSettings.shared.loadPreferences()
        log("📋 Saved to prefs, verified: \(savedPrefs.inputMethod.displayName)")
    }
    
    func selectCodeTable(_ table: CodeTable) {
        log("📋 selectCodeTable: setting to \(table.displayName)")
        
        currentCodeTable = table
        keyboardHandler?.codeTable = table
        
        // Save to preferences
        var prefs = SharedSettings.shared.loadPreferences()
        prefs.codeTable = table
        SharedSettings.shared.savePreferences(prefs)
        
        log("CodeTable set to \(table.displayName)")
    }
    
    func openPreferences() {
        onOpenPreferences?()
    }
    
    func openMacroManagement() {
        onOpenMacroManagement?()
    }
    
    func openConvertTool() {
        onOpenConvertTool?()
    }
    
    func openDebugWindow() {
        onOpenDebugWindow?()
    }
    
    func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateHotkeyDisplay(_ hotkey: Hotkey? = nil) {
        let hotkeyToUse = hotkey ?? SharedSettings.shared.loadPreferences().toggleHotkey
        
        // Update display string
        hotkeyDisplay = hotkeyToUse.displayString
        
        // For modifier-only hotkeys, don't set keyEquivalent (menu won't show shortcut)
        if hotkeyToUse.isModifierOnly {
            hotkeyKeyEquivalent = KeyEquivalent("\0")  // Null character - no key equivalent
        } else {
            hotkeyKeyEquivalent = keyCodeToKeyEquivalent(hotkeyToUse.keyCode)
        }
        hotkeyModifiers = modifierFlagsToEventModifiers(hotkeyToUse.modifiers)
    }
    
    private func keyCodeToKeyEquivalent(_ keyCode: UInt16) -> KeyEquivalent {
        // Use shared letter map, converting Character → KeyEquivalent
        if let letter = KeyCodeToCharacter.keyCodeToLetterMap[keyCode] {
            return KeyEquivalent(letter)
        }
        // Space key
        if keyCode == 0x31 { return " " }
        return "v"  // Default fallback
    }
    
    private func modifierFlagsToEventModifiers(_ flags: ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
