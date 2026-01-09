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
    @Published var focusedInputTitle = ""
    @Published var focusedInputIdentifier = ""
    @Published var focusedInputDOMId = ""
    @Published var focusedInputDOMClasses = ""
    @Published var focusedInputActions = ""
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
    private let maxDisplayLines = 5000
    
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

        let axError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard axError == .success, let focusedElement = focusedRef else {
            // Log detailed error info for debugging
            let (errorName, errorDesc): (String, String)
            switch axError {
            case .success:
                (errorName, errorDesc) = ("success", "Success")
            case .failure:
                (errorName, errorDesc) = ("failure", "General failure - app may not support AX")
            case .illegalArgument:
                (errorName, errorDesc) = ("illegalArgument", "Invalid argument")
            case .invalidUIElement:
                (errorName, errorDesc) = ("invalidUIElement", "Element no longer exists")
            case .invalidUIElementObserver:
                (errorName, errorDesc) = ("invalidUIElementObserver", "Invalid observer")
            case .cannotComplete:
                (errorName, errorDesc) = ("cannotComplete", "App is busy or not responding - try again later")
            case .attributeUnsupported:
                (errorName, errorDesc) = ("attributeUnsupported", "App does not support this attribute")
            case .actionUnsupported:
                (errorName, errorDesc) = ("actionUnsupported", "App does not support this action")
            case .notificationUnsupported:
                (errorName, errorDesc) = ("notificationUnsupported", "App does not support notifications")
            case .notImplemented:
                (errorName, errorDesc) = ("notImplemented", "Feature not implemented")
            case .notificationAlreadyRegistered:
                (errorName, errorDesc) = ("notificationAlreadyRegistered", "Notification already registered")
            case .notificationNotRegistered:
                (errorName, errorDesc) = ("notificationNotRegistered", "Notification not registered")
            case .apiDisabled:
                (errorName, errorDesc) = ("apiDisabled", "⚠️ Accessibility API disabled - grant permission in System Settings")
            case .noValue:
                (errorName, errorDesc) = ("noValue", "No element is focused (normal if not clicking on a text field)")
            case .parameterizedAttributeUnsupported:
                (errorName, errorDesc) = ("parameterizedAttributeUnsupported", "Parameterized attribute not supported")
            case .notEnoughPrecision:
                (errorName, errorDesc) = ("notEnoughPrecision", "Not enough precision")
            @unknown default:
                (errorName, errorDesc) = ("unknown(\(axError.rawValue))", "Unknown error")
            }

            // Also check AXIsProcessTrusted
            let isTrusted = AXIsProcessTrusted()
            let trustDesc = isTrusted
                ? "✅ Accessibility permission granted"
                : "❌ No permission - go to System Settings → Privacy & Security → Accessibility"

            addAppDetectorLog("  → Focused Element: (none)")
            addAppDetectorLog("  → AXError: \(errorName)")
            addAppDetectorLog("  → Description: \(errorDesc)")
            addAppDetectorLog("  → AXIsProcessTrusted: \(isTrusted) - \(trustDesc)")
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
        
        // Get AX Title
        var titleRef: CFTypeRef?
        var axTitle = ""
        if AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleStr = titleRef as? String {
            axTitle = titleStr
        }
        
        // Get AX Identifier
        var identifierRef: CFTypeRef?
        var axIdentifier = ""
        if AXUIElementCopyAttributeValue(axElement, kAXIdentifierAttribute as CFString, &identifierRef) == .success,
           let identifierStr = identifierRef as? String {
            axIdentifier = identifierStr
        }
        
        // Get DOM ID (for web content)
        var domIdRef: CFTypeRef?
        var domId = ""
        if AXUIElementCopyAttributeValue(axElement, "AXDOMIdentifier" as CFString, &domIdRef) == .success,
           let domIdStr = domIdRef as? String {
            domId = domIdStr
        }
        
        // Get DOM Class List (for web content)
        var domClassRef: CFTypeRef?
        var domClasses = ""
        if AXUIElementCopyAttributeValue(axElement, "AXDOMClassList" as CFString, &domClassRef) == .success,
           let classList = domClassRef as? [String] {
            domClasses = classList.joined(separator: ", ")
        }
        
        // Get available actions
        var actionsRef: CFArray?
        var actions = ""
        if AXUIElementCopyActionNames(axElement, &actionsRef) == .success,
           let actionList = actionsRef as? [String] {
            actions = actionList.joined(separator: ", ")
        }

        DispatchQueue.main.async {
            self.focusedWindowTitle = windowTitle
            self.focusedInputRole = role
            self.focusedInputSubrole = subrole
            self.focusedInputRoleDescription = roleDescription
            self.focusedInputDescription = axDescription
            self.focusedInputPlaceholder = placeholder
            self.focusedInputTitle = axTitle
            self.focusedInputIdentifier = axIdentifier
            self.focusedInputDOMId = domId
            self.focusedInputDOMClasses = domClasses
            self.focusedInputActions = actions
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
    
    // MARK: - Injection Test Properties
    
    /// Input keys for injection test (e.g., "a + s + n + h")
    @Published var injectionTestInput = ""
    
    /// Expected result for injection test (e.g., "ánh")
    @Published var injectionTestExpected = ""
    
    /// Current injection test state
    @Published var injectionTestState: InjectionTestState = .idle
    
    /// Countdown seconds remaining
    @Published var injectionTestCountdown = 0
    
    /// Current injection method being tested
    @Published var injectionTestCurrentMethod: InjectionMethod = .fast
    
    /// Text sending method (chunked or oneByOne)
    @Published var injectionTestTextSendingMethod: TextSendingMethod = .chunked
    
    /// Whether to show advanced options
    @Published var injectionTestShowAdvanced = false
    
    /// Custom delays (in microseconds) - Advanced options
    @Published var injectionTestDelayBackspace: UInt32 = 1000    // 1ms
    @Published var injectionTestDelayWait: UInt32 = 3000         // 3ms  
    @Published var injectionTestDelayText: UInt32 = 1500         // 1.5ms
    
    /// Whether to auto-clear text after test fail (default: true)
    @Published var injectionTestAutoClear = true
    
    /// Index of current method in the test sequence
    @Published var injectionTestMethodIndex = 0
    
    /// Result message after test
    @Published var injectionTestResult = ""
    
    /// Whether the test passed
    @Published var injectionTestPassed = false
    
    /// Log messages for injection test
    @Published var injectionTestLog: [String] = []
    
    /// Timer for countdown
    private var injectionTestTimer: Timer?
    
    /// Countdown duration before typing
    private let injectionTestPrepareCountdown = 5
    
    /// Countdown duration before verification
    private let injectionTestVerifyCountdown = 2
    
    /// Delay between simulated keystrokes (ms) - human-like speed
    private let injectionTestKeystrokeDelay: UInt32 = 80_000  // 80ms
    
    /// All injection methods available for testing
    let injectionMethodsToTest: [InjectionMethod] = [.fast, .slow, .selection, .autocomplete, .axDirect]
    
    /// Callback to get CharacterInjector for injection test
    var characterInjectorProvider: (() -> CharacterInjector)?
    
    /// Callback to get EventTapProxy for injection test
    var eventTapProxyProvider: (() -> CGEventTapProxy?)?
    
    // MARK: - Injection Test State Enum
    
    enum InjectionTestState: Equatable {
        case idle                    // Not running
        case preparingInput          // Countdown before typing
        case typing                  // Simulating keystrokes
        case preparingVerify         // Countdown before verification
        case verifying               // Checking result
        case passed                  // Test passed
        case failed                  // Test failed, waiting for user action
        case completed               // All methods tested
        case paused                  // Paused by user, waiting to resume
    }
    
    /// Saved countdown value when paused
    private var pausedCountdown: Int = 0
    
    /// Whether we were in preparingInput or preparingVerify when paused
    private var pausedFromState: InjectionTestState = .idle
    
    // MARK: - Injection Test Methods
    
    /// Start injection test
    func startInjectionTest() {
        guard injectionTestState == .idle || injectionTestState == .failed || injectionTestState == .completed else {
            addInjectionTestLog("Cannot start: test already running")
            return
        }
        
        // Validate input
        guard !injectionTestInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            addInjectionTestLog("[ERROR] Please enter input keys (e.g., 'asnh')")
            return
        }
        
        guard !injectionTestExpected.trimmingCharacters(in: .whitespaces).isEmpty else {
            addInjectionTestLog("[ERROR] Please enter expected result (e.g., 'ánh')")
            return
        }
        
        // Find the index of the user-selected method to start from
        if let startIndex = injectionMethodsToTest.firstIndex(of: injectionTestCurrentMethod) {
            injectionTestMethodIndex = startIndex
        } else {
            injectionTestMethodIndex = 0
            injectionTestCurrentMethod = injectionMethodsToTest[0]
        }
        
        // Clear log for new test
        injectionTestLog.removeAll()
        injectionTestPassed = false
        injectionTestResult = ""
        
        addInjectionTestLog("=== INJECTION TEST ===")
        addInjectionTestLog("Input: \(injectionTestInput)")
        addInjectionTestLog("Expected: \(injectionTestExpected)")
        addInjectionTestLog("Starting method: \(injectionTestCurrentMethod.displayName)")
        addInjectionTestLog("Will try \(injectionMethodsToTest.count - injectionTestMethodIndex) method(s)")
        addInjectionTestLog("")
        
        // Start countdown
        startPrepareCountdown()
    }
    
    /// Stop injection test
    func stopInjectionTest() {
        injectionTestTimer?.invalidate()
        injectionTestTimer = nil
        injectionTestState = .idle
        injectionTestCountdown = 0
        
        // Clear force override
        setForceOverride(enabled: false)
        
        addInjectionTestLog("")
        addInjectionTestLog("=== TEST STOPPED ===")
    }
    
    /// Pause injection test (during countdown)
    func pauseInjectionTest() {
        guard injectionTestState == .preparingInput || injectionTestState == .preparingVerify else {
            return
        }
        
        // Save current state
        pausedFromState = injectionTestState
        pausedCountdown = injectionTestCountdown
        
        // Stop timer
        injectionTestTimer?.invalidate()
        injectionTestTimer = nil
        
        // Update state
        injectionTestState = .paused
        addInjectionTestLog("")
        addInjectionTestLog("[PAUSED] Click Resume when ready")
    }
    
    /// Resume injection test from paused state
    func resumeInjectionTest() {
        guard injectionTestState == .paused else { return }
        
        addInjectionTestLog("[RESUMED] Continuing...")
        
        // Restore countdown and restart timer
        if pausedFromState == .preparingInput {
            injectionTestState = .preparingInput
            injectionTestCountdown = pausedCountdown
            addInjectionTestLog("Typing starts in \(injectionTestCountdown) seconds...")
            
            injectionTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.injectionTestCountdown -= 1
                
                if self.injectionTestCountdown > 0 {
                    self.addInjectionTestLog("[\(self.injectionTestCountdown)] Get ready...")
                } else {
                    timer.invalidate()
                    self.injectionTestTimer = nil
                    self.startTypingPhase()
                }
            }
        } else if pausedFromState == .preparingVerify {
            injectionTestState = .preparingVerify
            injectionTestCountdown = pausedCountdown
            addInjectionTestLog("Verifying result in \(injectionTestCountdown) seconds...")
            
            injectionTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.injectionTestCountdown -= 1
                
                if self.injectionTestCountdown <= 0 {
                    timer.invalidate()
                    self.injectionTestTimer = nil
                    self.verifyResult()
                }
            }
        }
    }
    
    /// Start countdown before typing
    private func startPrepareCountdown() {
        injectionTestState = .preparingInput
        injectionTestCountdown = injectionTestPrepareCountdown
        
        addInjectionTestLog("Prepare to focus on target app...")
        addInjectionTestLog("Typing starts in \(injectionTestCountdown) seconds...")
        
        injectionTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.injectionTestCountdown -= 1
            
            if self.injectionTestCountdown > 0 {
                self.addInjectionTestLog("[\(self.injectionTestCountdown)] Get ready...")
            } else {
                timer.invalidate()
                self.injectionTestTimer = nil
                self.startTypingPhase()
            }
        }
    }
    
    /// Start typing phase - simulate keystrokes
    private func startTypingPhase() {
        injectionTestState = .typing
        addInjectionTestLog("")
        addInjectionTestLog("[NOW] Typing...")
        
        // Set force override for CharacterInjector
        // This makes CharacterInjector use our selected method instead of auto-detecting
        setForceOverride(enabled: true)
        addInjectionTestLog("Override: \(injectionTestCurrentMethod.displayName) + \(injectionTestTextSendingMethod.rawValue)")
        
        // Parse input keys
        let keys = parseInputKeys(injectionTestInput)
        addInjectionTestLog("Keys to type: \(keys.map { String($0) }.joined(separator: ", "))")
        
        // Simulate typing in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for (index, key) in keys.enumerated() {
                // Simulate key press using CGEvent
                self.simulateKeyPress(key)
                
                DispatchQueue.main.async {
                    self.addInjectionTestLog("  Typed: '\(key)' (\(index + 1)/\(keys.count))")
                }
                
                // Human-like delay between keystrokes
                usleep(self.injectionTestKeystrokeDelay)
            }
            
            // Typing complete, start verify countdown
            DispatchQueue.main.async {
                self.addInjectionTestLog("")
                self.addInjectionTestLog("Typing complete!")
                self.startVerifyCountdown()
            }
        }
    }
    
    /// Start countdown before verification
    private func startVerifyCountdown() {
        injectionTestState = .preparingVerify
        injectionTestCountdown = injectionTestVerifyCountdown
        
        addInjectionTestLog("Verifying result in \(injectionTestCountdown) seconds...")
        
        injectionTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            self.injectionTestCountdown -= 1
            
            if self.injectionTestCountdown <= 0 {
                timer.invalidate()
                self.injectionTestTimer = nil
                self.verifyResult()
            }
        }
    }
    
    /// Verify the result matches expected
    private func verifyResult() {
        injectionTestState = .verifying
        addInjectionTestLog("")
        addInjectionTestLog("=== VERIFYING ===")
        
        // Get text from focused element using AX API
        let actualText = getFocusedElementText()
        
        addInjectionTestLog("Expected: '\(injectionTestExpected)'")
        addInjectionTestLog("Actual:   '\(actualText ?? "(could not read)")'")
        
        // Check if actual matches expected
        if let actual = actualText {
            // Normalize strings for comparison (Unicode canonical form)
            let normalizedExpected = injectionTestExpected.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
            let normalizedActual = actual.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
            
            // Strict comparison: actual must equal expected
            if normalizedActual == normalizedExpected {
                injectionTestPassed = true
                injectionTestState = .passed
                injectionTestResult = "PASSED with method: \(injectionTestCurrentMethod.displayName)"
                addInjectionTestLog("")
                addInjectionTestLog("[OK] TEST PASSED!")
                addInjectionTestLog("Injection method '\(injectionTestCurrentMethod.displayName)' + '\(injectionTestTextSendingMethod.rawValue)' works correctly.")
                addInjectionTestLog("")
                
                // Clear force override since test is complete
                setForceOverride(enabled: false)
                
                // Log detailed AX info for development purposes
                logDetailedAXInfo()
                
                addInjectionTestLog("")
                addInjectionTestLog("=== TEST COMPLETE ===")
            } else {
                // Show clear diff information
                addInjectionTestLog("")
                addInjectionTestLog("[FAIL] \(injectionTestCurrentMethod.displayName) + \(injectionTestTextSendingMethod.rawValue)")
                addInjectionTestLog("  Expected length: \(normalizedExpected.count)")
                addInjectionTestLog("  Actual length:   \(normalizedActual.count)")
                
                // Show character-by-character diff for debugging
                if normalizedActual.count != normalizedExpected.count {
                    addInjectionTestLog("  Length mismatch!")
                } else {
                    // Find first difference
                    for (i, (e, a)) in zip(normalizedExpected, normalizedActual).enumerated() {
                        if e != a {
                            addInjectionTestLog("  First diff at position \(i): expected '\(e)' got '\(a)'")
                            break
                        }
                    }
                }
                
                // Auto-clear text if enabled
                if injectionTestAutoClear {
                    clearTypedText(count: normalizedActual.count)
                }
                
                // Try next text sending method, then next injection method
                tryNextTextSendingMethod()
            }
        } else {
            addInjectionTestLog("")
            addInjectionTestLog("[FAIL] Could not read text from target app")
            addInjectionTestLog("Make sure the app supports Accessibility API.")
            
            // Still try next combination - maybe it works better
            tryNextTextSendingMethod()
        }
    }
    
    /// Clear typed text by sending backspaces
    private func clearTypedText(count: Int) {
        guard count > 0 else { return }
        
        addInjectionTestLog("  Clearing \(count) characters...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            
            // Send backspaces to clear text
            for _ in 0..<count {
                // Backspace keycode is 0x33
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else {
                    continue
                }
                
                keyDown.post(tap: .cghidEventTap)
                usleep(1000)  // 1ms delay
                keyUp.post(tap: .cghidEventTap)
                usleep(5000)  // 5ms between backspaces
            }
            
            DispatchQueue.main.async {
                self.addInjectionTestLog("  Text cleared")
            }
        }
    }
    
    /// Try the next injection method, or complete if all methods exhausted
    private func tryNextMethod() {
        injectionTestMethodIndex += 1
        
        if injectionTestMethodIndex >= injectionMethodsToTest.count {
            // All methods exhausted
            injectionTestPassed = false
            injectionTestState = .completed
            injectionTestResult = "All combinations failed. Expected '\(injectionTestExpected)'"
            addInjectionTestLog("")
            addInjectionTestLog("=== ALL COMBINATIONS TESTED ===")
            addInjectionTestLog("No injection method + text sending combination produced the expected result.")
            addInjectionTestLog("This may indicate an issue with the target app.")
            
            // Clear force override since test is complete
            setForceOverride(enabled: false)
            
            return
        }
        
        // Move to next method
        injectionTestCurrentMethod = injectionMethodsToTest[injectionTestMethodIndex]
        // Reset text sending to chunked for new method
        injectionTestTextSendingMethod = .chunked
        
        addInjectionTestLog("")
        addInjectionTestLog("--- TRYING NEXT METHOD ---")
        addInjectionTestLog("Method: \(injectionTestCurrentMethod.displayName) + \(injectionTestTextSendingMethod.rawValue)")
        addInjectionTestLog("(\(injectionTestMethodIndex + 1)/\(injectionMethodsToTest.count) methods)")
        addInjectionTestLog("")
        
        // Start countdown for next attempt
        startPrepareCountdown()
    }
    
    /// Try the next text sending method, or move to next injection method if both tried
    private func tryNextTextSendingMethod() {
        // If currently chunked, try oneByOne
        if injectionTestTextSendingMethod == .chunked {
            injectionTestTextSendingMethod = .oneByOne
            addInjectionTestLog("")
            addInjectionTestLog("--- TRYING DIFFERENT TEXT SENDING ---")
            addInjectionTestLog("Method: \(injectionTestCurrentMethod.displayName) + \(injectionTestTextSendingMethod.rawValue)")
            addInjectionTestLog("")
            
            // Start countdown for next attempt
            startPrepareCountdown()
        } else {
            // Both text sending methods tried, move to next injection method
            tryNextMethod()
        }
    }
    
    /// Parse input string into array of characters
    /// Now accepts natural input - just type characters directly
    /// Example: "xin chào" → ['x', 'i', 'n', ' ', 'c', 'h', 'à', 'o']
    private func parseInputKeys(_ input: String) -> [Character] {
        // Simply return all characters from the input
        return Array(input)
    }
    
    /// Simulate a key press using CGEvent
    /// IMPORTANT: Do NOT set Unicode string - just use keycode like a real keyboard
    /// This allows EventTap to intercept and VNEngine to process the keys
    private func simulateKeyPress(_ char: Character) {
        // Use .hidSystemState to mimic real keyboard input
        // This is more realistic than .privateState
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        // Get keycode for the character
        let keyCode = getKeyCode(for: char)
        
        // Only simulate keys we have keycodes for
        guard keyCode != 0xFF else {
            addInjectionTestLog("  [WARN] No keycode for '\(char)', skipping")
            return
        }
        
        // Create key down event - do NOT set Unicode string
        // This makes it behave like a real keyboard press
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        // Do NOT set Unicode string - let the system (and XKey EventTap) handle it
        // If we set Unicode string, EventTap might not process it correctly
        
        // Do NOT set the XKey marker - we want EventTap to process these as real keystrokes
        
        // Post events to HID level so EventTap sees them
        keyDown.post(tap: .cghidEventTap)
        usleep(1000)  // 1ms between down and up
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Get virtual key code for a character
    /// Returns 0xFF if no keycode found (character should be skipped)
    private func getKeyCode(for char: Character) -> CGKeyCode {
        let charLower = char.lowercased()
        
        // Common key codes for US keyboard layout
        let keyCodes: [Character: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
            "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
            "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12,
            "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
            "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B,
            "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32, " ": 0x31,
            "\n": 0x24
        ]
        
        if let code = keyCodes[Character(charLower)] {
            return code
        }
        
        // Return 0xFF for unknown characters - they will be skipped
        return 0xFF
    }
    
    /// Get text from currently focused element
    private func getFocusedElementText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let element = focusedRef else {
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // Get text value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else {
            return nil
        }
        
        return text
    }
    
    /// Log detailed AX info about the focused element for development purposes
    private func logDetailedAXInfo() {
        addInjectionTestLog("--- AX INFO (for development) ---")
        
        // Get frontmost app info
        if let app = NSWorkspace.shared.frontmostApplication {
            addInjectionTestLog("App: \(app.localizedName ?? "Unknown")")
            addInjectionTestLog("Bundle ID: \(app.bundleIdentifier ?? "Unknown")")
        }
        
        // Get focused element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let element = focusedRef else {
            addInjectionTestLog("(Could not get focused element)")
            return
        }
        
        let axElement = element as! AXUIElement
        
        // Get Role
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            addInjectionTestLog("Role: \(role)")
        }
        
        // Get Subrole
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            addInjectionTestLog("Subrole: \(subrole)")
        }
        
        // Get RoleDescription
        var roleDescRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
           let roleDesc = roleDescRef as? String {
            addInjectionTestLog("RoleDesc: \(roleDesc)")
        }
        
        // Get Description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            addInjectionTestLog("Description: \(desc)")
        }
        
        // Get Placeholder
        var placeholderRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXPlaceholderValueAttribute as CFString, &placeholderRef) == .success,
           let placeholder = placeholderRef as? String, !placeholder.isEmpty {
            addInjectionTestLog("Placeholder: \(placeholder)")
        }
        
        // Get Title
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            addInjectionTestLog("Title: \(title)")
        }
        
        // Get Identifier
        var identifierRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXIdentifierAttribute as CFString, &identifierRef) == .success,
           let identifier = identifierRef as? String, !identifier.isEmpty {
            addInjectionTestLog("Identifier: \(identifier)")
        }
        
        // Get DOM Identifier (for web content)
        var domIdRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, "AXDOMIdentifier" as CFString, &domIdRef) == .success,
           let domId = domIdRef as? String, !domId.isEmpty {
            addInjectionTestLog("DOM ID: \(domId)")
        }
        
        // Get DOM Class List (for web content)
        var domClassRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, "AXDOMClassList" as CFString, &domClassRef) == .success,
           let classList = domClassRef as? [String], !classList.isEmpty {
            addInjectionTestLog("DOM Classes: \(classList.joined(separator: ", "))")
        }
        
        // Get available actions
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(axElement, &actionsRef) == .success,
           let actions = actionsRef as? [String], !actions.isEmpty {
            addInjectionTestLog("Actions: \(actions.joined(separator: ", "))")
        }
        
        // Get Window Title
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                let windowElement = window as! AXUIElement
                var winTitleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &winTitleRef) == .success,
                   let winTitle = winTitleRef as? String {
                    addInjectionTestLog("Window: \(winTitle)")
                }
            }
        }
        
        // Log injection config
        addInjectionTestLog("")
        addInjectionTestLog("[Config]")
        addInjectionTestLog("Method: \(injectionTestCurrentMethod.rawValue)")
        addInjectionTestLog("TextSending: \(injectionTestTextSendingMethod.rawValue)")
        addInjectionTestLog("Delays: bs=\(injectionTestDelayBackspace)µs, wait=\(injectionTestDelayWait)µs, text=\(injectionTestDelayText)µs")
        addInjectionTestLog("--- END AX INFO ---")
    }
    
    /// Set or clear force override for injection method
    /// When enabled, CharacterInjector will use our selected method instead of auto-detecting
    private func setForceOverride(enabled: Bool) {
        if enabled {
            AppBehaviorDetector.shared.forceInjectionMethod = injectionTestCurrentMethod
            AppBehaviorDetector.shared.forceTextSendingMethod = injectionTestTextSendingMethod
            AppBehaviorDetector.shared.forceDelays = (injectionTestDelayBackspace, injectionTestDelayWait, injectionTestDelayText)
        } else {
            AppBehaviorDetector.shared.forceInjectionMethod = nil
            AppBehaviorDetector.shared.forceTextSendingMethod = nil
            AppBehaviorDetector.shared.forceDelays = nil
            // Also clear confirmed method to trigger fresh detection
            AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        }
    }
    
    /// Add log message to injection test log
    private func addInjectionTestLog(_ message: String) {
        DispatchQueue.main.async {
            self.injectionTestLog.append(message)
        }
        // Also log to main debug log
        logEvent("[INJECTION-TEST] \(message)")
    }
}
