//
//  DebugViewModel.swift
//  XKey
//
//  ViewModel for Debug Window
//

import SwiftUI
import Combine

class DebugViewModel: ObservableObject {
    @Published var statusText = "Status: Initializing..."
    @Published var logText = ""
    @Published var isLoggingEnabled = true
    @Published var isVerboseLogging = false
    @Published var inputText = ""
    @Published var isAlwaysOnTop = true {
        didSet {
            alwaysOnTopCallback?(isAlwaysOnTop)
        }
    }
    
    private let logFileURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Create log file in user's home directory
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = homeDirectory.appendingPathComponent("XKey_Debug.log")
        
        // Initialize log file with timestamp
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let header = "=== XKey Debug Log ===\nStarted: \(timestamp)\nLog file: \(logFileURL.path)\n\n"
        try? header.write(to: logFileURL, atomically: true, encoding: .utf8)
        
        logMessage("Debug window initialized")
        logMessage("Log file location: \(logFileURL.path)")
    }
    
    func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.statusText = "Status: \(status)"
            self.logMessage("STATUS: \(status)")
        }
    }
    
    func logEvent(_ event: String) {
        guard isLoggingEnabled else { return }
        
        // Batch updates to reduce UI re-renders
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let logLine = "[\(timestamp)] \(event)\n"
            
            // Limit log size to prevent memory issues
            if self.logText.count > 50000 {
                // Keep only last 30000 characters
                let index = self.logText.index(self.logText.endIndex, offsetBy: -30000)
                self.logText = String(self.logText[index...])
            }
            
            self.logText += logLine
            self.logMessage(event)
        }
    }
    
    func logKeyEvent(character: Character, keyCode: UInt16, result: String) {
        let event = "KEY: '\(character)' (code: \(keyCode)) → \(result)"
        logEvent(event)
    }
    
    func logEngineResult(input: String, output: String, backspaces: Int) {
        let event = "ENGINE: '\(input)' → '\(output)' (bs: \(backspaces))"
        logEvent(event)
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
        logText = ""
        logMessage("=== Logs Cleared ===")
    }
    
    func toggleLogging() {
        if isLoggingEnabled {
            updateStatus("Logging enabled")
            logMessage("=== Logging Enabled ===")
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
        logMessage("Opened log file in Finder")
    }
    
    // Callback for reading word before cursor
    var readWordCallback: (() -> Void)?
    
    // Callback for toggling always on top
    var alwaysOnTopCallback: ((Bool) -> Void)?
    
    private func logMessage(_ message: String) {
        guard isLoggingEnabled else { return }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logLine = "[\(timestamp)] \(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }
}
