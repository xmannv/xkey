//
//  DebugViewModel.swift
//  XKey
//
//  ViewModel for Debug Window - Optimized with file-based log reading
//  Logs are written directly to file, Debug Window reads from file periodically
//

import SwiftUI
import Combine

class DebugViewModel: ObservableObject {
    @Published var statusText = "Status: Initializing..."
    @Published var logLines: [String] = []  // Changed from logText to array for better performance
    @Published var isLoggingEnabled = true
    @Published var isVerboseLogging = false {
        didSet {
            verboseLoggingCallback?(isVerboseLogging)
        }
    }
    @Published var inputText = ""
    @Published var isAlwaysOnTop = true {
        didSet {
            alwaysOnTopCallback?(isAlwaysOnTop)
        }
    }
    
    // MARK: - Text Test Tab Properties (local text area)
    @Published var testInputText = ""
    @Published var testCaretPosition: Int = 0
    @Published var testWordBeforeCaret = ""
    @Published var testWordAfterCaret = ""
    
    // MARK: - External App Monitoring Properties
    @Published var focusedAppName = ""
    @Published var focusedAppBundleID = ""
    @Published var focusedWindowTitle = ""
    @Published var focusedInputRole = ""
    @Published var focusedInputSubrole = ""
    @Published var focusedInputRoleDescription = ""
    @Published var focusedInputDescription = ""
    @Published var focusedInputPlaceholder = ""
    @Published var externalCaretPosition: Int = 0
    @Published var externalWordBeforeCaret = ""
    @Published var externalWordAfterCaret = ""
    @Published var isMonitoringExternal = false
    private var externalMonitorTimer: Timer?
    
    // MARK: - App Detector Test Properties
    @Published var isAppDetectorTestRunning = false
    @Published var appDetectorTestCountdown = 0
    @Published var appDetectorTestLog: [String] = []
    @Published var detectedAppName = ""
    @Published var detectedAppBundleID = ""
    @Published var detectedFocusedText = ""
    private var appDetectorTestTimer: Timer?
    
    // MARK: - Pinned Configuration (not cleared)
    @Published var pinnedConfigInfo: [String] = []
    @Published var showPinnedConfig = true
    
    // MARK: - File-Based Logging Properties
    
    /// Log file URL
    let logFileURL: URL
    
    /// Log file reader for incremental reads
    private let logReader: LogFileReader
    
    /// Background queue for file writes (fire-and-forget)
    private let writeQueue = DispatchQueue(label: "com.xkey.debuglog.write", qos: .utility)
    
    /// Timer for reading new log entries from file
    private var readTimer: Timer?
    
    /// Read interval - how often to check for new logs (500ms is a good balance)
    private let readInterval: TimeInterval = 0.5
    
    /// Maximum lines to keep in memory
    private let maxDisplayLines = 1000
    
    /// Lock for file write operations
    private let writeLock = NSLock()
    
    /// Track if window is visible (skip reading when hidden)
    @Published var isWindowVisible = true
    
    /// Track if config was logged on first open
    private var hasLoggedInitialConfig = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // Callbacks
    var readWordCallback: (() -> Void)?
    var alwaysOnTopCallback: ((Bool) -> Void)?
    var verboseLoggingCallback: ((Bool) -> Void)?
    
    // MARK: - Computed Properties
    
    /// Combined log text for display (computed from lines)
    var logText: String {
        logLines.joined(separator: "\n")
    }
    
    // MARK: - Initialization
    
    init() {
        // Create log file in user's home directory
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = homeDirectory.appendingPathComponent("XKey_Debug.log")
        
        // Initialize log reader
        logReader = LogFileReader(fileURL: logFileURL, maxLines: maxDisplayLines)

        // Initialize log file with timestamp header
        initializeLogFile()
        
        // Load existing log content
        loadExistingLogs()
        
        // Start the periodic log reader
        startReadTimer()
        
        // Listen for debug logs from XKeyIM
        setupIMKitDebugListener()
    }
    
    deinit {
        readTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: - Log File Initialization
    
    private func initializeLogFile() {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let versionString = "XKey v\(AppVersion.current) (\(AppVersion.build))"
        let header = "=== XKey Debug Log ===\n\(versionString)\nStarted: \(timestamp)\nLog file: \(logFileURL.path)\n\n"

        // Create/overwrite file with header
        try? header.write(to: logFileURL, atomically: true, encoding: .utf8)
    }
    
    private func loadExistingLogs() {
        logReader.readAllLines { [weak self] lines in
            self?.logLines = lines
        }
    }
    
    // MARK: - Fire-and-Forget Logging (Write Only)
    
    /// Add a log event - writes directly to file, no UI blocking
    func logEvent(_ event: String) {
        guard isLoggingEnabled else { return }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logLine = "[\(timestamp)] \(event)"
        
        // Write to file asynchronously (fire-and-forget)
        writeToFileAsync(logLine)
    }
    
    /// Write to file asynchronously (non-blocking)
    private func writeToFileAsync(_ text: String) {
        writeQueue.async { [weak self] in
            self?.writeToFileSync(text + "\n")
        }
    }
    
    /// Write to file synchronously (called from background queue)
    private func writeToFileSync(_ text: String) {
        writeLock.lock()
        defer { writeLock.unlock() }
        
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            try handle.close()
        } catch {
            // Ignore write errors to avoid blocking
        }
    }
    
    // MARK: - Periodic Log Reading (Read from File)
    
    /// Start timer for periodic log file reading
    private func startReadTimer() {
        readTimer = Timer.scheduledTimer(withTimeInterval: readInterval, repeats: true) { [weak self] _ in
            self?.readNewLogs()
        }
    }
    
    /// Read new log entries from file
    private func readNewLogs() {
        // Skip reading if window is not visible or logging is disabled
        guard isWindowVisible && isLoggingEnabled else { return }
        
        logReader.readNewLines { [weak self] newLines in
            guard let self = self, !newLines.isEmpty else { return }
            
            // Append new lines
            self.logLines.append(contentsOf: newLines)
            
            // Trim to max lines
            if self.logLines.count > self.maxDisplayLines {
                let excess = self.logLines.count - self.maxDisplayLines
                self.logLines.removeFirst(excess)
            }
        }
    }
    
    // MARK: - IMKit Debug Listener
    
    private func setupIMKitDebugListener() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("XKey.debugLog"),
            object: nil,
            queue: nil // Use caller's queue, we handle threading ourselves
        ) { [weak self] notification in
            // Try to get message from object first (for InputSourceSwitcher)
            if let message = notification.object as? String {
                self?.logEvent(message)
                return
            }

            // Fallback to userInfo for XKeyIM messages with source
            guard let userInfo = notification.userInfo,
                  let message = userInfo["message"] as? String,
                  let source = userInfo["source"] as? String else {
                return
            }

            self?.logEvent("[\(source)] \(message)")
        }
    }
    
    // MARK: - Public Methods
    
    func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.statusText = "Status: \(status)"
        }
        logEvent("STATUS: \(status)")
    }
    
    func logKeyEvent(character: Character, keyCode: UInt16, result: String) {
        logEvent("KEY: '\(character)' (code: \(keyCode)) → \(result)")
    }
    
    func logEngineResult(input: String, output: String, backspaces: Int) {
        logEvent("ENGINE: '\(input)' → '\(output)' (bs: \(backspaces))")
    }
    
    func copyLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
        
        updateStatus("Logs copied to clipboard!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.updateStatus("Ready")
        }
    }
    
    func clearLogs() {
        // Clear in-memory logs
        logLines.removeAll()
        
        // Reset log reader
        logReader.reset()
        
        // Reinitialize log file
        initializeLogFile()
        
        // Auto-log current configuration after clearing
        logCurrentConfig()
        
        updateStatus("Logs cleared (config preserved)")
    }
    
    // MARK: - Configuration Summary
    
    /// Generate current configuration summary lines
    func generateConfigSummary() -> [String] {
        let settings = SharedSettings.shared
        var lines: [String] = []
        
        // Header
        lines.append("=== CURRENT CONFIGURATION ===")
        
        // Input Method
        let inputMethodName: String
        switch settings.inputMethod {
        case 0: inputMethodName = "Telex"
        case 1: inputMethodName = "VNI"
        case 2: inputMethodName = "Simple Telex"
        default: inputMethodName = "Unknown (\(settings.inputMethod))"
        }
        lines.append("Input Method: \(inputMethodName)")
        
        // Code Table
        let codeTableName: String
        switch settings.codeTable {
        case 0: codeTableName = "Unicode"
        case 1: codeTableName = "VNI Windows"
        case 2: codeTableName = "TCVN3"
        default: codeTableName = "Unknown (\(settings.codeTable))"
        }
        lines.append("Code Table: \(codeTableName)")
        lines.append("")
        
        // Key settings
        lines.append("[Input Settings]")
        lines.append("  Modern Style: \(settings.modernStyle ? "ON" : "OFF")")
        lines.append("  Spell Check: \(settings.spellCheckEnabled ? "ON" : "OFF")")
        lines.append("  Fix Autocomplete: \(settings.fixAutocomplete ? "ON" : "OFF")")
        lines.append("  Free Mark: \(settings.freeMarkEnabled ? "ON" : "OFF")")
        lines.append("")
        
        // Quick Telex
        lines.append("[Quick Telex]")
        lines.append("  Quick Telex (cc->ch): \(settings.quickTelexEnabled ? "ON" : "OFF")")
        lines.append("  Quick Start Consonant: \(settings.quickStartConsonantEnabled ? "ON" : "OFF")")
        lines.append("  Quick End Consonant: \(settings.quickEndConsonantEnabled ? "ON" : "OFF")")
        lines.append("")
        
        // Spell check options
        lines.append("[Spell Check Options]")
        lines.append("  Restore if Wrong: \(settings.restoreIfWrongSpelling ? "ON" : "OFF")")
        lines.append("  Instant Restore: \(settings.instantRestoreOnWrongSpelling ? "ON" : "OFF")")
        lines.append("")
        
        // Macro
        lines.append("[Macro]")
        lines.append("  Macro Enabled: \(settings.macroEnabled ? "ON" : "OFF")")
        lines.append("  Macro in English: \(settings.macroInEnglishMode ? "ON" : "OFF")")
        lines.append("  Auto Caps Macro: \(settings.autoCapsMacro ? "ON" : "OFF")")
        lines.append("  Add Space After: \(settings.addSpaceAfterMacro ? "ON" : "OFF")")
        lines.append("")
        
        // Smart Switch
        lines.append("[Smart Switch]")
        lines.append("  Smart Switch: \(settings.smartSwitchEnabled ? "ON" : "OFF")")
        lines.append("  Detect Overlay Apps: \(settings.detectOverlayApps ? "ON" : "OFF")")
        lines.append("")
        
        // IMKit
        lines.append("[IMKit]")
        lines.append("  IMKit Enabled: \(settings.imkitEnabled ? "ON" : "OFF")")
        lines.append("  Use Marked Text: \(settings.imkitUseMarkedText ? "ON" : "OFF")")
        lines.append("")
        
        // Toolbar
        lines.append("[Toolbar]")
        lines.append("  Temp Off Toolbar: \(settings.tempOffToolbarEnabled ? "ON" : "OFF")")
        
        lines.append("=== END CONFIGURATION ===")
        
        return lines
    }
    
    /// Refresh pinned configuration display
    func refreshPinnedConfig() {
        pinnedConfigInfo = generateConfigSummary()
    }
    
    /// Log current configuration to debug log (file only, timer will read and display)
    func logCurrentConfig() {
        let configLines = generateConfigSummary()
        for line in configLines {
            writeToFileAsync(line)
        }
    }
    
    func toggleLogging() {
        if isLoggingEnabled {
            updateStatus("Logging enabled")
            logEvent("=== Logging Enabled ===")
        } else {
            updateStatus("Logging disabled")
        }
    }
    
    func readWordBeforeCursor() {
        logEvent("=== Read Word Before Cursor ===")
        readWordCallback?()
    }
    
    func openLogFile() {
        // Reveal log file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
        logEvent("Opened log file in Finder")
    }
    
    // MARK: - Window Visibility
    
    func windowDidBecomeVisible() {
        isWindowVisible = true
        // Force read when window becomes visible
        readNewLogs()
        
        // Log configuration on first open (like Clear button does)
        if !hasLoggedInitialConfig {
            hasLoggedInitialConfig = true
            logCurrentConfig()
        }
    }
    
    func windowDidBecomeHidden() {
        isWindowVisible = false
    }
    
    // MARK: - Text Test Methods
    
    /// Update text test info based on current text and selection
    func updateTextTestInfo(text: String, selectedRange: NSRange) {
        testInputText = text
        testCaretPosition = selectedRange.location
        
        // Calculate word before caret
        if selectedRange.location > 0 && selectedRange.location <= text.count {
            let beforeIndex = text.index(text.startIndex, offsetBy: min(selectedRange.location, text.count))
            let textBefore = String(text[..<beforeIndex])
            
            // Find last word before caret (split by whitespace)
            let words = textBefore.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            testWordBeforeCaret = words.last.map(String.init) ?? ""
        } else {
            testWordBeforeCaret = ""
        }
        
        // Calculate word after caret
        if selectedRange.location < text.count {
            let afterIndex = text.index(text.startIndex, offsetBy: selectedRange.location)
            let textAfter = String(text[afterIndex...])
            
            // Find first word after caret
            let words = textAfter.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            testWordAfterCaret = words.first.map(String.init) ?? ""
        } else {
            testWordAfterCaret = ""
        }
    }
    
    // MARK: - App Detector Test Methods
    
    /// Start app detector test with countdown
    func startAppDetectorTest() {
        guard !isAppDetectorTestRunning else { return }

        isAppDetectorTestRunning = true
        appDetectorTestLog.removeAll()
        appDetectorTestCountdown = 5

        addAppDetectorLog("=== APP DETECTOR TEST ===")
        addAppDetectorLog("Starting test in 5 seconds...")
        addAppDetectorLog("Please open any app (Spotlight/Raycast/Alfred/etc.) when countdown reaches 0")

        // Countdown timer
        appDetectorTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.appDetectorTestCountdown -= 1

            if self.appDetectorTestCountdown > 0 {
                self.addAppDetectorLog("[\(self.appDetectorTestCountdown)] seconds remaining - GET READY!")
            } else if self.appDetectorTestCountdown == 0 {
                // Stop countdown timer immediately when reaching 0
                timer.invalidate()
                self.appDetectorTestTimer = nil

                self.addAppDetectorLog("[0] NOW! Open your target app (Cmd+Space for Spotlight, etc.)")
                self.addAppDetectorLog("")
                self.addAppDetectorLog("Starting to detect focused app in 2 seconds...")

                // Wait 2 seconds then start detecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.startDetectionPhase()
                }
            }
        }
    }
    
    /// Stop the app detector test
    func stopAppDetectorTest() {
        appDetectorTestTimer?.invalidate()
        appDetectorTestTimer = nil
        isAppDetectorTestRunning = false
        addAppDetectorLog("")
        addAppDetectorLog("=== TEST STOPPED ===")
    }
    
    /// Detection phase - detect every 500ms for 10 seconds
    private func startDetectionPhase() {
        addAppDetectorLog("")
        addAppDetectorLog("=== DETECTION PHASE ===")
        addAppDetectorLog("Detecting focused app every 0.5 seconds for 10 seconds...")
        addAppDetectorLog("Type some text in the app to test!")
        addAppDetectorLog("")
        
        var detectionCount = 0
        let maxDetections = 20 // 10 seconds at 500ms interval
        
        appDetectorTestTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            detectionCount += 1
            self.detectFocusedApp()
            
            if detectionCount >= maxDetections {
                timer.invalidate()
                self.appDetectorTestTimer = nil
                self.isAppDetectorTestRunning = false
                self.addAppDetectorLog("")
                self.addAppDetectorLog("=== DETECTION COMPLETE ===")
                self.addAppDetectorLog("Test finished. Review the results above.")
            }
        }
    }
    
    /// Detect currently focused app using Accessibility API
    private func detectFocusedApp() {
        // Priority 1: Check for overlay apps via OverlayAppDetector (uses AX attributes)
        // This is more accurate since overlay apps don't become frontmost application
        if let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() {
            // Map overlay name to bundle ID for display
            let bundleID: String
            switch overlayName {
            case "Spotlight":
                bundleID = "com.apple.Spotlight"
            case "Raycast":
                bundleID = "com.raycast.macos"
            case "Alfred":
                bundleID = "com.runningwithcrayons.Alfred"
            default:
                bundleID = "unknown.overlay"
            }
            
            detectedAppName = overlayName
            detectedAppBundleID = bundleID
            
            addAppDetectorLog("[Detection] App: \(overlayName) (\(bundleID))")
        } else {
            // Priority 2: Fallback to frontmost app (for non-overlay apps)
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
                addAppDetectorLog("[Detection] No frontmost app found")
                return
            }
            
            let appName = frontmostApp.localizedName ?? "Unknown"
            let bundleID = frontmostApp.bundleIdentifier ?? "Unknown"
            
            detectedAppName = appName
            detectedAppBundleID = bundleID
            
            // Check if it's a launcher app (via bundle ID - less reliable)
            let isLauncherApp = isKnownLauncherApp(bundleID)
            
            // Log app info
            var logLine = "[Detection] App: \(appName) (\(bundleID))"
            if isLauncherApp {
                logLine += " [LAUNCHER via BundleID]"
            }
            addAppDetectorLog(logLine)
        }
        
        // Get focused element info via AX API
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            addAppDetectorLog("  → Focused Element: (none)")
            return
        }
        
        let axElement = focusedElement as! AXUIElement
        
        // Get AX Role
        var roleRef: CFTypeRef?
        var role = "(unknown)"
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let roleStr = roleRef as? String {
            role = roleStr
        }
        
        // Get AX Subrole
        var subroleRef: CFTypeRef?
        var subrole = "(none)"
        if AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subroleStr = subroleRef as? String {
            subrole = subroleStr
        }
        
        // Get AX RoleDescription (human-readable)
        var roleDescRef: CFTypeRef?
        var roleDescription = "(none)"
        if AXUIElementCopyAttributeValue(axElement, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
           let roleDescStr = roleDescRef as? String {
            roleDescription = roleDescStr
        }
        
        // Get AX Description
        var descRef: CFTypeRef?
        var axDescription = "(none)"
        if AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let descStr = descRef as? String {
            axDescription = descStr
        }
        
        // Get AX Placeholder
        var placeholderRef: CFTypeRef?
        var placeholder = "(none)"
        if AXUIElementCopyAttributeValue(axElement, kAXPlaceholderValueAttribute as CFString, &placeholderRef) == .success,
           let placeholderStr = placeholderRef as? String {
            placeholder = placeholderStr
        }
        
        // Get AX Title
        var titleRef: CFTypeRef?
        var title = "(none)"
        if AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleStr = titleRef as? String {
            title = titleStr
        }
        
        // Get AX Value (text content)
        var valueRef: CFTypeRef?
        var textValue = "(not readable)"
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
           let valueStr = valueRef as? String {
            textValue = valueStr.isEmpty ? "(empty)" : "\"\(valueStr)\""
            detectedFocusedText = valueStr
        } else {
            detectedFocusedText = ""
        }
        
        // Get selected text range (caret position)
        var rangeRef: CFTypeRef?
        var caretInfo = "(unknown)"
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success {
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                caretInfo = "pos=\(range.location), len=\(range.length)"
            }
        }
        
        // Log all AX info
        addAppDetectorLog("  → AX Role: \(role)")
        addAppDetectorLog("  → AX Subrole: \(subrole)")
        addAppDetectorLog("  → AX RoleDescription: \(roleDescription)")
        addAppDetectorLog("  → AX Description: \(axDescription)")
        addAppDetectorLog("  → AX Placeholder: \(placeholder)")
        addAppDetectorLog("  → AX Title: \(title)")
        addAppDetectorLog("  → AX Value (Text): \(textValue)")
        addAppDetectorLog("  → Caret: \(caretInfo)")
    }
    
    /// Check if bundle ID is a known launcher app
    private func isKnownLauncherApp(_ bundleID: String) -> Bool {
        let launcherBundleIDs = [
            "com.apple.Spotlight",
            "com.raycast.macos",
            "com.runningwithcrayons.Alfred",
            "com.runningwithcrayons.Alfred-3",
            "at.obdev.LaunchBar",
            "com.apple.systemuiserver", // Sometimes Spotlight shows as this
        ]
        return launcherBundleIDs.contains(bundleID) || 
               bundleID.lowercased().contains("spotlight") ||
               bundleID.lowercased().contains("raycast") ||
               bundleID.lowercased().contains("alfred") ||
               bundleID.lowercased().contains("launchbar")
    }
    
    /// Add a log line to app detector test log AND main debug log
    private func addAppDetectorLog(_ message: String) {
        // Write to main debug log (file-based) so it shows in Log tab
        logEvent("[APP-DETECTOR-TEST] \(message)")
        
        // Also keep in memory array for dedicated UI if needed
        DispatchQueue.main.async {
            self.appDetectorTestLog.append(message)
        }
    }
    
    // MARK: - External App Monitoring Methods
    
    /// Start monitoring external apps for text input info
    func startExternalMonitoring() {
        guard !isMonitoringExternal else { return }
        isMonitoringExternal = true
        
        // Poll every 200ms for responsive updates
        externalMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollExternalAppInfo()
        }
        
        // Initial poll
        pollExternalAppInfo()
    }
    
    /// Stop monitoring external apps
    func stopExternalMonitoring() {
        externalMonitorTimer?.invalidate()
        externalMonitorTimer = nil
        isMonitoringExternal = false
    }
    
    /// Poll current focused app info using Accessibility API
    private func pollExternalAppInfo() {
        // Get frontmost app
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            clearExternalInfo()
            return
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        let bundleID = frontmostApp.bundleIdentifier ?? "Unknown"
        
        DispatchQueue.main.async {
            self.focusedAppName = appName
            self.focusedAppBundleID = bundleID
        }
        
        // Get focused UI element via AX API
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            DispatchQueue.main.async {
                self.focusedWindowTitle = "(no focus)"
                self.focusedInputRole = "(no element)"
                self.focusedInputSubrole = ""
                self.clearTextInfo()
            }
            return
        }
        
        let axElement = focusedElement as! AXUIElement
        
        // Get window title
        let windowTitle = getWindowTitle(from: axElement, pid: frontmostApp.processIdentifier)
        
        // Get role and subrole
        var roleRef: CFTypeRef?
        var role = ""
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let roleStr = roleRef as? String {
            role = roleStr
        }
        
        var subroleRef: CFTypeRef?
        var subrole = ""
        if AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subroleStr = subroleRef as? String {
            subrole = subroleStr
        }
        
        // Get AX RoleDescription
        var roleDescRef: CFTypeRef?
        var roleDescription = ""
        if AXUIElementCopyAttributeValue(axElement, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
           let roleDescStr = roleDescRef as? String {
            roleDescription = roleDescStr
        }

        // Get AX Description
        var descRef: CFTypeRef?
        var axDescription = ""
        if AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let descStr = descRef as? String {
            axDescription = descStr
        }

        // Get AX Placeholder
        var placeholderRef: CFTypeRef?
        var placeholder = ""
        if AXUIElementCopyAttributeValue(axElement, kAXPlaceholderValueAttribute as CFString, &placeholderRef) == .success,
           let placeholderStr = placeholderRef as? String {
            placeholder = placeholderStr
        }

        DispatchQueue.main.async {
            self.focusedWindowTitle = windowTitle
            self.focusedInputRole = role
            self.focusedInputSubrole = subrole
            self.focusedInputRoleDescription = roleDescription
            self.focusedInputDescription = axDescription
            self.focusedInputPlaceholder = placeholder
        }
        
        // Get text info if it's a text element
        if isTextElement(role: role, subrole: subrole) {
            getTextInfoFromElement(axElement)
        } else {
            DispatchQueue.main.async {
                self.clearTextInfo()
            }
        }
    }
    
    /// Get window title from element or app
    private func getWindowTitle(from element: AXUIElement, pid: pid_t) -> String {
        // Try to get from focused window of the app
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef {
            let windowElement = window as! AXUIElement
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                return title
            }
        }
        
        // Fallback: try main window
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement], let firstWindow = windows.first {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                return title
            }
        }
        
        return "(no title)"
    }
    
    /// Check if element is a text input element
    private func isTextElement(role: String, subrole: String) -> Bool {
        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXStaticText"]
        if textRoles.contains(role) {
            return true
        }
        
        // Some web content uses AXWebArea with text subroles
        if role == "AXWebArea" || role == "AXGroup" {
            return subrole == "AXSearchField" || subrole == "AXTextField" || subrole == "AXTextArea"
        }
        
        // For any other element, we'll try to read text anyway
        // This makes detection more permissive
        return true
    }
    
    /// Get text info (caret position, word before/after) from AX element
    private func getTextInfoFromElement(_ element: AXUIElement) {
        // Get full text value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else {
            DispatchQueue.main.async {
                self.clearTextInfo()
            }
            return
        }
        
        // Get selected text range (caret position)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success else {
            DispatchQueue.main.async {
                self.externalCaretPosition = 0
                self.externalWordBeforeCaret = ""
                self.externalWordAfterCaret = ""
            }
            return
        }
        
        var range = CFRange(location: 0, length: 0)
        if !AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
            DispatchQueue.main.async {
                self.clearTextInfo()
            }
            return
        }
        
        let caretPosition = range.location
        
        // Calculate words before/after caret
        var wordBefore = ""
        var wordAfter = ""
        
        if caretPosition > 0 && caretPosition <= text.count {
            let beforeIndex = text.index(text.startIndex, offsetBy: min(caretPosition, text.count))
            let textBefore = String(text[..<beforeIndex])
            let words = textBefore.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            wordBefore = words.last.map(String.init) ?? ""
        }
        
        if caretPosition < text.count {
            let afterIndex = text.index(text.startIndex, offsetBy: caretPosition)
            let textAfter = String(text[afterIndex...])
            let words = textAfter.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            wordAfter = words.first.map(String.init) ?? ""
        }
        
        DispatchQueue.main.async {
            self.externalCaretPosition = caretPosition
            self.externalWordBeforeCaret = wordBefore
            self.externalWordAfterCaret = wordAfter
        }
    }
    
    /// Clear external text info
    private func clearTextInfo() {
        externalCaretPosition = 0
        externalWordBeforeCaret = ""
        externalWordAfterCaret = ""
    }
    
    /// Clear all external info
    private func clearExternalInfo() {
        DispatchQueue.main.async {
            self.focusedAppName = ""
            self.focusedAppBundleID = ""
            self.focusedWindowTitle = ""
            self.focusedInputRole = ""
            self.focusedInputSubrole = ""
            self.clearTextInfo()
        }
    }
}
