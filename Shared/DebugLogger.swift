//
//  DebugLogger.swift
//  XKey / XKeyIM
//
//  Centralized logging utility that works in both XKey and XKeyIM
//  Optimized for high-frequency logging without blocking the caller
//

import Foundation

// Forward declaration for DebugWindowController (only available in XKey)
// This protocol allows us to reference the debug window without importing AppKit
protocol DebugWindowControllerProtocol: AnyObject {
    var isLoggingEnabled: Bool { get }
    var isVerboseLogging: Bool { get }
    func logEvent(_ message: String)
}

/// Centralized debug logger that works in both XKey and XKeyIM
/// Optimized for high-frequency logging without blocking
/// Uses fire-and-forget file writing for zero-blocking logging
class DebugLogger {

    /// Shared instance
    static let shared = DebugLogger()

    /// Log file URL (shared with DebugViewModel)
    private let logFileURL: URL
    
    /// Reference to debug window controller (set by AppDelegate in XKey)
    /// Using protocol to avoid dependency on AppKit/UI code
    weak var debugWindowController: DebugWindowControllerProtocol? {
        didSet {
            // When debug window is connected, use it for logging settings
            if let controller = debugWindowController {
                isLoggingEnabled = controller.isLoggingEnabled
                isVerboseLogging = controller.isVerboseLogging
            } else {
                // Debug window disconnected - disable file logging in XKey app
                isLoggingEnabled = false
                isVerboseLogging = false
            }
        }
    }
    
    /// Whether verbose logging is enabled
    var isVerboseLogging: Bool = true
    
    /// Whether logging is enabled (default: false, explicitly enabled by XKey/XKeyIM based on debugModeEnabled setting)
    var isLoggingEnabled: Bool = false
    
    /// Background queue for async file writing
    private let logQueue = DispatchQueue(label: "com.xkey.logger", qos: .utility)
    
    /// Lock for thread-safe file writes
    private let writeLock = NSLock()

    private init() {
        // Use same log file as DebugViewModel
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = homeDirectory.appendingPathComponent("XKey_Debug.log")
    }
    
    /// Write to file asynchronously (fire-and-forget)
    private func writeToFile(_ text: String) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.writeLock.lock()
            defer { self.writeLock.unlock() }
            
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "[\(timestamp)] \(text)\n"
            
            guard let data = line.data(using: .utf8) else { return }
            
            do {
                let handle = try FileHandle(forWritingTo: self.logFileURL)
                handle.seekToEndOfFile()
                handle.write(data)
                try handle.close()
            } catch {
                // Ignore write errors - fire and forget
            }
        }
    }

    /// Log a message (non-blocking, fire-and-forget)
    /// - Parameters:
    ///   - message: The message to log
    ///   - source: The source component (e.g., "VNEngine", "MacroManager")
    ///   - level: Log level (info, warning, error)
    func log(_ message: String, source: String = "", level: LogLevel = .info) {
        guard isLoggingEnabled else { return }
        
        let prefix = level.emoji
        let fullMessage: String
        if prefix.isEmpty {
            fullMessage = source.isEmpty ? message : "[\(source)] \(message)"
        } else {
            fullMessage = source.isEmpty ? "\(prefix) \(message)" : "\(prefix) [\(source)] \(message)"
        }

        // Check level before writing
        switch level {
        case .error, .warning:
            // Always log errors and warnings
            writeToFile(fullMessage)
        case .info, .success:
            // Only log info/success in DEBUG mode
            writeToFile(fullMessage)
        case .debug:
            // Only log debug if verbose mode is enabled
            let verbose = debugWindowController?.isVerboseLogging ?? isVerboseLogging
            if verbose {
                writeToFile(fullMessage)
            }
        }
    }

    /// Log an info message
    func info(_ message: String, source: String = "") {
        log(message, source: source, level: .info)
    }

    /// Log a warning message
    func warning(_ message: String, source: String = "") {
        log(message, source: source, level: .warning)
    }

    /// Log an error message
    func error(_ message: String, source: String = "") {
        log(message, source: source, level: .error)
    }

    /// Log a success message
    func success(_ message: String, source: String = "") {
        log(message, source: source, level: .success)
    }

    /// Log a debug message (only if verbose logging is enabled)
    func debug(_ message: String, source: String = "") {
        let verbose = debugWindowController?.isVerboseLogging ?? isVerboseLogging
        guard verbose else { return }
        log(message, source: source, level: .debug)
    }
}

// MARK: - Log Level

enum LogLevel {
    case info
    case warning
    case error
    case success
    case debug

    var emoji: String {
        switch self {
        case .info: return ""
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        case .success: return "[OK]"
        case .debug: return "[DEBUG]"
        }
    }
}

// MARK: - Convenience Global Functions

/// Log an info message to debug window
@inline(__always)
func logInfo(_ message: String, source: String = "") {
    DebugLogger.shared.info(message, source: source)
}

/// Log a warning message to debug window
@inline(__always)
func logWarning(_ message: String, source: String = "") {
    DebugLogger.shared.warning(message, source: source)
}

/// Log an error message to debug window
@inline(__always)
func logError(_ message: String, source: String = "") {
    DebugLogger.shared.error(message, source: source)
}

/// Log a success message to debug window
@inline(__always)
func logSuccess(_ message: String, source: String = "") {
    DebugLogger.shared.success(message, source: source)
}

/// Log a debug message to debug window (only if verbose logging is enabled)
@inline(__always)
func logDebug(_ message: String, source: String = "") {
    DebugLogger.shared.debug(message, source: source)
}

// MARK: - Aliases for SharedSettings compatibility

/// Alias for logInfo (used by SharedSettings)
@inline(__always)
func sharedLogInfo(_ message: String, source: String = "") {
    logInfo(message, source: source)
}

/// Alias for logWarning (used by SharedSettings)
@inline(__always)
func sharedLogWarning(_ message: String, source: String = "") {
    logWarning(message, source: source)
}

/// Alias for logError (used by SharedSettings)
@inline(__always)
func sharedLogError(_ message: String, source: String = "") {
    logError(message, source: source)
}

/// Alias for logSuccess (used by SharedSettings)
@inline(__always)
func sharedLogSuccess(_ message: String, source: String = "") {
    logSuccess(message, source: source)
}

/// Alias for logDebug (used by SharedSettings)
@inline(__always)
func sharedLogDebug(_ message: String, source: String = "") {
    logDebug(message, source: source)
}
