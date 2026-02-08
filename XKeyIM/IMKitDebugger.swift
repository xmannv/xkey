//
//  IMKitDebugger.swift
//  XKeyIM
//
//  Thin wrapper around DebugLogger for XKeyIM-specific logging.
//  Delegates all file I/O to DebugLogger.shared (available in both targets).
//

import Foundation

/// Singleton debugger for IMKit logging - delegates to shared DebugLogger
class IMKitDebugger {
    static let shared = IMKitDebugger()

    private init() {}

    /// Log a message with [XKeyIM] prefix
    func log(_ message: String) {
        DebugLogger.shared.info("[XKeyIM] \(message)")
    }

    /// Log with category
    func log(_ message: String, category: String) {
        DebugLogger.shared.info("[XKeyIM] [\(category)] \(message)")
    }
}
