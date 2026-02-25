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
    @Published var isVerboseLogging = true {
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
    
    // MARK: - Force Accessibility Properties
    /// Whether AXManualAccessibility is currently enabled for the focused app
    @Published var isForceAccessibilityEnabled = false
    /// Status message for force accessibility
    @Published var forceAccessibilityStatus = ""
    /// PID of the app that has force accessibility enabled
    private var forceAccessibilityPid: pid_t = 0
    /// Last external app PID (not XKey) - used for Force Accessibility targeting
    private var lastExternalAppPid: pid_t = 0
    /// Last external app name - for display purposes
    private var lastExternalAppName: String = ""
    /// Last external app bundle ID
    private var lastExternalAppBundleID: String = ""
    /// Public access to target app name for UI
    var forceAccessibilityTargetApp: String {
        lastExternalAppName.isEmpty ? "(none)" : lastExternalAppName
    }
    
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
    
    /// Maximum lines to keep in memory (reduced from 5000 to save ~300KB RAM)
    private let maxDisplayLines = 2000
    
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
        
        // Get macOS version info
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        let header = "=== XKey Debug Log ===\n\(versionString)\n\(osVersionString)\nStarted: \(timestamp)\nLog file: \(logFileURL.path)\n\n"

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
        case 2: inputMethodName = "Simple Telex 1"
        case 3: inputMethodName = "Simple Telex 2"
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
        lines.append("  Allow Consonant ZFWJ: \(settings.allowConsonantZFWJ ? "ON" : "OFF")")
        lines.append("  Upper Case First Char: \(settings.upperCaseFirstChar ? "ON" : "OFF")")
        lines.append("  Undo Typing: \(settings.undoTypingEnabled ? "ON" : "OFF")")
        lines.append("  Beep on Toggle: \(settings.beepOnToggle ? "ON" : "OFF")")
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
        lines.append("")
        
        // Translation
        lines.append("[Translation]")
        lines.append("  Translation: \(settings.translationEnabled ? "ON" : "OFF")")
        lines.append("  Source Language: \(settings.translationSourceLanguage)")
        lines.append("  Target Language: \(settings.translationTargetLanguage)")
        lines.append("  Replace Original: \(settings.translationReplaceOriginal ? "ON" : "OFF")")
        lines.append("  Toolbar: \(settings.translationToolbarEnabled ? "ON" : "OFF")")
        lines.append("")
        
        // Excluded Apps
        if let data = settings.getExcludedApps(),
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            lines.append("[Excluded Apps] Count: \(apps.count)")
            for app in apps {
                lines.append("  - \(app.appName) (\(app.bundleIdentifier))")
            }
        } else {
            lines.append("[Excluded Apps] Count: 0")
        }
        
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
        
        // Restart read timer if it was stopped
        if readTimer == nil {
            startReadTimer()
        }
        
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
        // Stop read timer to save CPU when window is hidden
        readTimer?.invalidate()
        readTimer = nil
    }
    
    /// Stop all timers - called when window is closing to release resources
    func stopAllTimers() {
        readTimer?.invalidate()
        readTimer = nil
        externalMonitorTimer?.invalidate()
        externalMonitorTimer = nil
        appDetectorTestTimer?.invalidate()
        appDetectorTestTimer = nil
        
        // Clear log lines to free memory
        logLines.removeAll()
        appDetectorTestLog.removeAll()
        
        // Reset log reader
        logReader.reset()
        
        // Remove notification observer
        DistributedNotificationCenter.default().removeObserver(self)
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
        // Get frontmost app info
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName ?? "Unknown"
        let bundleID = frontmostApp?.bundleIdentifier ?? "Unknown"
        
        // Priority 1: Check for overlay apps via OverlayAppDetector (uses AX attributes)
        // This is more accurate since overlay apps don't become frontmost application
        if let overlayName = OverlayAppDetector.shared.getVisibleOverlayAppName() {
            // Map overlay name to bundle ID for display
            let overlayBundleID: String
            switch overlayName {
            case "Spotlight":
                overlayBundleID = "com.apple.Spotlight"
            case "Raycast":
                overlayBundleID = "com.raycast.macos"
            case "Alfred":
                overlayBundleID = "com.runningwithcrayons.Alfred"
            default:
                overlayBundleID = "unknown.overlay"
            }
            
            detectedAppName = overlayName
            detectedAppBundleID = overlayBundleID
            
            addAppDetectorLog("[Detection] App: \(overlayName) (\(overlayBundleID)) [OVERLAY]")
        } else {
            guard frontmostApp != nil else {
                addAppDetectorLog("[Detection] No frontmost app found")
                return
            }
            
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
        
        // Get AppBehaviorDetector info
        let detector = AppBehaviorDetector.shared
        let windowTitle = detector.getCachedWindowTitle()
        addAppDetectorLog("  → Window: \(windowTitle.isEmpty ? "(no title)" : windowTitle)")
        
        // Get focused element info via optimized single query
        let elementInfo = detector.getFocusedElementInfo()
        
        // Log AX element info
        let role = elementInfo.role ?? "(unknown)"
        let subrole = elementInfo.subrole ?? "(none)"
        addAppDetectorLog("  → AXRole: \(role)")
        if subrole != "(none)" {
            addAppDetectorLog("  → AXSubrole: \(subrole)")
        }
        
        if let desc = elementInfo.description, !desc.isEmpty {
            addAppDetectorLog("  → AXDescription: \(desc)")
        }
        
        if let identifier = elementInfo.identifier, !identifier.isEmpty {
            addAppDetectorLog("  → AXIdentifier: \(identifier)")
        }
        
        if let classes = elementInfo.domClasses, !classes.isEmpty {
            addAppDetectorLog("  → AXDOMClassList: \(classes.joined(separator: ", "))")
        }
        
        // Get text value and caret
        if let textValue = elementInfo.textValue {
            let displayText = textValue.isEmpty ? "(empty)" : "\"\(textValue.prefix(50))\(textValue.count > 50 ? "..." : "")\""
            addAppDetectorLog("  → AX Value (Text): \(displayText)")
            detectedFocusedText = textValue
        } else {
            addAppDetectorLog("  → AX Value (Text): (not readable)")
            detectedFocusedText = ""
        }
        
        // Get behavior type
        let behavior = detector.detect()
        let behaviorName: String
        switch behavior {
        case .standard: behaviorName = "Standard"
        case .terminal: behaviorName = "Terminal"
        case .browserAddressBar: behaviorName = "Browser Address Bar"
        case .jetbrainsIDE: behaviorName = "JetBrains IDE"
        case .microsoftOffice: behaviorName = "Microsoft Office"
        case .spotlight: behaviorName = "Spotlight"
        case .overlayLauncher: behaviorName = "Overlay Launcher"
        case .electronApp: behaviorName = "Electron App"
        case .codeEditor: behaviorName = "Code Editor"
        }
        addAppDetectorLog("  → Behavior: \(behaviorName)")
        
        // Get injection method info
        let injectionInfo = detector.detectInjectionMethod()
        let injectionMethodName: String

        switch injectionInfo.method {
            case .fast: injectionMethodName = "Fast"
            case .slow: injectionMethodName = "Slow"
            case .selection: injectionMethodName = "Selection"
            case .autocomplete: injectionMethodName = "Autocomplete"
            case .axDirect: injectionMethodName = "AX Direct"
            case .passthrough: injectionMethodName = "Passthrough"
        }

        let textMethodName = injectionInfo.textSendingMethod == .chunked ? "Chunked" : "OneByOne"
        let emptyCharPrefixNote = injectionInfo.needsEmptyCharPrefix ? " [EmptyCharPrefix]" : ""
        addAppDetectorLog("  → Injection: \(injectionMethodName) [bs:\(injectionInfo.delays.backspace)µs, wait:\(injectionInfo.delays.wait)µs, txt:\(injectionInfo.delays.text)µs] [\(textMethodName)]\(emptyCharPrefixNote)")
        addAppDetectorLog("  → Injection Reason: \(injectionInfo.description)")
        
        // Get IMKit behavior
        let imkitBehavior = detector.detectIMKitBehavior()
        addAppDetectorLog("  → IMKit: markedText=\(imkitBehavior.useMarkedText), issues=\(imkitBehavior.hasMarkedTextIssues), delay=\(imkitBehavior.commitDelay)µs")
        
        // Get matched Window Title Rule (if any)
        if let rule = detector.findMatchingRule() {
            addAppDetectorLog("  → Rule: \(rule.name) (pattern: \"\(rule.titlePattern)\")")
        }
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
        let pid = frontmostApp.processIdentifier
        
        // Track external app (any app that's not XKey)
        // This is used for Force Accessibility to target the correct app
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.xkey"
        if bundleID != myBundleID {
            lastExternalAppPid = pid
            lastExternalAppName = appName
            lastExternalAppBundleID = bundleID
        }
        
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
    
    // MARK: - Force Accessibility Methods
    
    /// Toggle force accessibility (AXManualAccessibility) for the currently focused app
    /// This is useful for Electron/Chromium apps that need explicit enablement
    func toggleForceAccessibility() {
        if isForceAccessibilityEnabled {
            disableForceAccessibility()
        } else {
            enableForceAccessibility()
        }
    }
    
    /// Enable AXManualAccessibility for the last focused external app (not XKey)
    func enableForceAccessibility() {
        // Use the last tracked external app (not XKey itself)
        guard lastExternalAppPid != 0 else {
            DispatchQueue.main.async {
                self.forceAccessibilityStatus = "❌ No external app tracked. Focus on an app first."
            }
            return
        }
        
        let pid = lastExternalAppPid
        let appName = lastExternalAppName
        let bundleID = lastExternalAppBundleID
        
        // Log what we're targeting
        logEvent("[FORCE-AX] Targeting: \(appName) (\(bundleID)) PID=\(pid)")
        
        // Create AX application element
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try to set AXManualAccessibility = true
        // This tells Chrome/Electron to keep accessibility enabled
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        
        DispatchQueue.main.async {
            if result == .success {
                self.isForceAccessibilityEnabled = true
                self.forceAccessibilityPid = pid
                self.forceAccessibilityStatus = "✅ Enabled for \(appName)"
                self.logEvent("[FORCE-AX] Enabled AXManualAccessibility for \(appName) (\(bundleID)) PID=\(pid)")
            } else {
                let errorDesc = result.humanReadableDescription
                self.forceAccessibilityStatus = "❌ \(appName): \(errorDesc)"
                self.logEvent("[FORCE-AX] Failed to set AXManualAccessibility for \(appName): \(errorDesc)")
            }
        }
    }
    
    /// Disable AXManualAccessibility for the previously enabled app
    func disableForceAccessibility() {
        guard forceAccessibilityPid != 0 else {
            DispatchQueue.main.async {
                self.isForceAccessibilityEnabled = false
                self.forceAccessibilityStatus = ""
            }
            return
        }
        
        let appElement = AXUIElementCreateApplication(forceAccessibilityPid)
        
        // Set AXManualAccessibility = false
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanFalse
        )
        
        DispatchQueue.main.async {
            self.isForceAccessibilityEnabled = false
            self.forceAccessibilityPid = 0
            
            if result == .success {
                self.forceAccessibilityStatus = "Disabled"
                self.logEvent("[FORCE-AX] Disabled AXManualAccessibility")
            } else {
                self.forceAccessibilityStatus = "Disabled (app may have closed)"
            }
        }
    }
    
    /// Enable AXEnhancedUserInterface for the last focused external app
    /// Note: This can cause side effects like animation issues in some apps
    func enableEnhancedUserInterface() {
        guard lastExternalAppPid != 0 else {
            DispatchQueue.main.async {
                self.forceAccessibilityStatus = "❌ No external app tracked"
            }
            return
        }
        
        let pid = lastExternalAppPid
        let appName = lastExternalAppName
        let bundleID = lastExternalAppBundleID
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try AXEnhancedUserInterface
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        
        DispatchQueue.main.async {
            if result == .success {
                self.forceAccessibilityStatus = "✅ Enhanced UI for \(appName)"
                self.logEvent("[FORCE-AX] Enabled AXEnhancedUserInterface for \(appName) (\(bundleID)) PID=\(pid)")
            } else {
                let errorDesc = result.humanReadableDescription
                self.forceAccessibilityStatus = "❌ \(appName): \(errorDesc)"
                self.logEvent("[FORCE-AX] Failed to set AXEnhancedUserInterface for \(appName): \(errorDesc)")
            }
        }
    }
    
    /// Check accessibility status of the target app
    /// This is more useful than trying to force-enable, as it shows what's available
    func checkAccessibilityStatus() {
        guard lastExternalAppPid != 0 else {
            DispatchQueue.main.async {
                self.forceAccessibilityStatus = "❌ No external app tracked"
            }
            return
        }
        
        let pid = lastExternalAppPid
        let appName = lastExternalAppName
        let bundleID = lastExternalAppBundleID
        
        let appElement = AXUIElementCreateApplication(pid)
        
        logEvent("[AX-CHECK] Checking accessibility for \(appName) (\(bundleID)) PID=\(pid)")
        
        // Check AXManualAccessibility current value
        var manualAxRef: CFTypeRef?
        let manualAxResult = AXUIElementCopyAttributeValue(appElement, "AXManualAccessibility" as CFString, &manualAxRef)
        let manualAxStatus: String
        if manualAxResult == .success {
            if let boolValue = manualAxRef as? Bool {
                manualAxStatus = boolValue ? "true" : "false"
            } else {
                manualAxStatus = "unknown type"
            }
        } else {
            manualAxStatus = manualAxResult.humanReadableDescription
        }
        
        // Check AXEnhancedUserInterface current value
        var enhancedRef: CFTypeRef?
        let enhancedResult = AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &enhancedRef)
        let enhancedStatus: String
        if enhancedResult == .success {
            if let boolValue = enhancedRef as? Bool {
                enhancedStatus = boolValue ? "true" : "false"
            } else {
                enhancedStatus = "unknown type"
            }
        } else {
            enhancedStatus = enhancedResult.humanReadableDescription
        }
        
        // Check if we can get focused window (basic accessibility test)
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        let windowStatus = windowResult == .success ? "✅ Available" : "❌ \(windowResult.humanReadableDescription)"
        
        // Check if we can get menu bar (another accessibility test)
        var menuRef: CFTypeRef?
        let menuResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuRef)
        let menuStatus = menuResult == .success ? "✅ Available" : "❌ \(menuResult.humanReadableDescription)"
        
        // Log results
        logEvent("[AX-CHECK] Results:")
        logEvent("[AX-CHECK]   AXManualAccessibility: \(manualAxStatus)")
        logEvent("[AX-CHECK]   AXEnhancedUserInterface: \(enhancedStatus)")
        logEvent("[AX-CHECK]   FocusedWindow: \(windowStatus)")
        logEvent("[AX-CHECK]   MenuBar: \(menuStatus)")
        
        // Determine overall status
        let hasBasicAccess = windowResult == .success || menuResult == .success
        
        DispatchQueue.main.async {
            if hasBasicAccess {
                self.forceAccessibilityStatus = "\(appName): Accessibility available"
            } else {
                self.forceAccessibilityStatus = "\(appName): Limited AX access"
            }
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
    
    /// Whether any test passed
    @Published var injectionTestPassed = false
    
    /// Track results for each method combination (method+textMode, passed)
    @Published var injectionTestResults: [(method: InjectionMethod, textMode: TextSendingMethod, passed: Bool)] = []
    
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
        
        // Clear log and results for new test
        injectionTestLog.removeAll()
        injectionTestResults.removeAll()
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
                // Record pass result
                injectionTestResults.append((method: injectionTestCurrentMethod, textMode: injectionTestTextSendingMethod, passed: true))
                injectionTestPassed = true
                
                addInjectionTestLog("")
                addInjectionTestLog("[OK] \(injectionTestCurrentMethod.displayName) + \(injectionTestTextSendingMethod.rawValue) PASSED!")
                
                // Auto-clear text before next test
                if injectionTestAutoClear {
                    clearTypedText(count: normalizedActual.count)
                }
                
                // Continue to next method (don't stop on pass)
                tryNextTextSendingMethod()
            } else {
                // Record fail result
                injectionTestResults.append((method: injectionTestCurrentMethod, textMode: injectionTestTextSendingMethod, passed: false))
                
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
            // Record fail result (could not read)
            injectionTestResults.append((method: injectionTestCurrentMethod, textMode: injectionTestTextSendingMethod, passed: false))
            
            addInjectionTestLog("")
            addInjectionTestLog("[FAIL] Could not read text from target app")
            addInjectionTestLog("Make sure the app supports Accessibility API.")
            
            // Still try next combination - maybe it works better
            tryNextTextSendingMethod()
        }
    }
    
    /// Clear typed text using Select All (Cmd+A) + Delete
    /// This is more reliable than backspaces because XKey engine won't process
    /// the remaining characters and add diacritics to them
    private func clearTypedText(count: Int) {
        guard count > 0 else { return }
        
        addInjectionTestLog("  Clearing text (Select All + Delete)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            
            // Step 1: Send Cmd+A (Select All)
            // 'A' keycode is 0x00
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(VietnameseData.KEY_A), keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(VietnameseData.KEY_A), keyDown: false) {
                // Set Command modifier
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                
                keyDown.post(tap: .cghidEventTap)
                usleep(1000)  // 1ms delay
                keyUp.post(tap: .cghidEventTap)
            }
            
            usleep(10000)  // 10ms delay before delete
            
            // Step 2: Send Delete/Backspace to remove selected text
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: VietnameseData.KEY_DELETE, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: VietnameseData.KEY_DELETE, keyDown: false) {
                keyDown.post(tap: .cghidEventTap)
                usleep(1000)  // 1ms delay
                keyUp.post(tap: .cghidEventTap)
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
            // All methods tested - show summary
            injectionTestState = .completed
            
            // Clear force override since test is complete
            setForceOverride(enabled: false)
            
            // Generate summary
            addInjectionTestLog("")
            addInjectionTestLog("═══════════════════════════════════════")
            addInjectionTestLog("         TEST SUMMARY")
            addInjectionTestLog("═══════════════════════════════════════")
            addInjectionTestLog("")
            
            let passedResults = injectionTestResults.filter { $0.passed }
            let failedResults = injectionTestResults.filter { !$0.passed }
            
            addInjectionTestLog("Total combinations tested: \(injectionTestResults.count)")
            addInjectionTestLog("Passed: \(passedResults.count) | Failed: \(failedResults.count)")
            addInjectionTestLog("")
            
            // List passed methods
            if passedResults.isEmpty {
                addInjectionTestLog("✗ No method passed the test")
                injectionTestResult = "All \(injectionTestResults.count) combinations failed"
            } else {
                addInjectionTestLog("✓ PASSED METHODS:")
                for result in passedResults {
                    addInjectionTestLog("  • \(result.method.displayName) + \(result.textMode.rawValue)")
                }
                
                // Recommend the first passing method
                let recommended = passedResults[0]
                injectionTestResult = "\(passedResults.count)/\(injectionTestResults.count) passed. Recommended: \(recommended.method.displayName) + \(recommended.textMode.rawValue)"
            }
            
            addInjectionTestLog("")
            
            // List failed methods
            if !failedResults.isEmpty {
                addInjectionTestLog("✗ FAILED METHODS:")
                for result in failedResults {
                    addInjectionTestLog("  • \(result.method.displayName) + \(result.textMode.rawValue)")
                }
            }
            
            addInjectionTestLog("")
            
            // Log detailed AX info for development purposes
            logDetailedAXInfo()
            
            addInjectionTestLog("")
            addInjectionTestLog("═══════════════════════════════════════")
            addInjectionTestLog("         TEST COMPLETE")
            addInjectionTestLog("═══════════════════════════════════════")
            
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
        // Create a fresh event source for each keystroke to avoid state leakage
        guard let source = CGEventSource(stateID: .privateState) else { return }
        
        // Get keycode for the character (and check if it needs Shift)
        let (keyCode, needsShift) = getKeyCodeAndShiftState(for: char)
        
        // Only simulate keys we have keycodes for
        guard keyCode != 0xFF else {
            addInjectionTestLog("  [WARN] No keycode for '\(char)', skipping")
            return
        }
        
        // Shift keycode is 0x38
        let shiftKeyCode: CGKeyCode = 0x38
        
        // For uppercase letters, simulate actual Shift key press/release
        // This is more reliable than just setting flags
        if needsShift {
            // Press Shift
            if let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: true) {
                shiftDown.post(tap: .cghidEventTap)
                usleep(500)
            }
        }
        
        // Create and post the main key event
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            
            // Set Shift flag on the key events too (for apps that check flags)
            if needsShift {
                keyDown.flags = .maskShift
                keyUp.flags = .maskShift
            }
            
            // Do NOT set Unicode string - let the system (and XKey EventTap) handle it
            // If we set Unicode string, EventTap might not process it correctly
            
            // Do NOT set the XKey marker - we want EventTap to process these as real keystrokes
            
            // Post the key events
            keyDown.post(tap: .cghidEventTap)
            usleep(500)  // Brief delay between down and up
            keyUp.post(tap: .cghidEventTap)
        }
        
        // For uppercase letters, release Shift after the key
        if needsShift {
            usleep(500)
            if let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: false) {
                shiftUp.post(tap: .cghidEventTap)
            }
        }
    }
    
    /// Get virtual key code for a character and whether Shift is needed
    /// Returns (0xFF, false) if no keycode found (character should be skipped)
    private func getKeyCodeAndShiftState(for char: Character) -> (CGKeyCode, Bool) {
        // Check if character is uppercase
        let isUppercase = char.isUppercase
        let charLower = Character(char.lowercased())
        
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
        
        if let code = keyCodes[charLower] {
            return (code, isUppercase)
        }
        
        // Return 0xFF for unknown characters - they will be skipped
        return (0xFF, false)
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
