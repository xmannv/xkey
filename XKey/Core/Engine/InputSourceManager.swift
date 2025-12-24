//
//  InputSourceManager.swift
//  XKey
//
//  Manages macOS Input Sources and auto-enables/disables XKey based on configuration
//

import Foundation
import Carbon

/// Represents a macOS Input Source
struct InputSourceInfo: Codable, Identifiable, Hashable {
    let id: String  // Input Source ID
    let name: String  // Localized name

    var displayName: String {
        return name.isEmpty ? id : name
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Configuration for auto-enabling XKey per input source
struct InputSourceConfig: Codable {
    var enabledInputSources: [String: Bool] = [:]  // Input Source ID -> enabled state

    /// Check if XKey should be enabled for a given input source
    func isXKeyEnabled(for inputSourceID: String) -> Bool {
        // Default to enabled if not configured
        return enabledInputSources[inputSourceID] ?? true
    }

    /// Set enabled state for an input source
    mutating func setEnabled(_ enabled: Bool, for inputSourceID: String) {
        enabledInputSources[inputSourceID] = enabled
    }
}

/// Manager for tracking and responding to Input Source changes
class InputSourceManager {

    // MARK: - Properties

    /// Callback when input source changes
    var onInputSourceChanged: ((InputSourceInfo, Bool) -> Void)?

    /// Current input source
    private(set) var currentInputSource: InputSourceInfo?

    /// All available input sources
    private(set) var availableInputSources: [InputSourceInfo] = []

    /// Configuration
    private(set) var config: InputSourceConfig

    /// Debug log callback
    var debugLogCallback: ((String) -> Void)?
    
    /// Flag to temporarily ignore input source changes (used when hotkey conflicts with macOS shortcuts)
    private var ignoreInputSourceChangesUntil: Date?

    // MARK: - Initialization

    init() {
        // Load configuration
        self.config = Self.loadConfig()

        // Get current input source
        self.currentInputSource = Self.getCurrentInputSource()

        // Get all available input sources
        self.availableInputSources = Self.getAllInputSources()

        // Setup observer
        setupObserver()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Observer Setup

    private func setupObserver() {
        // Listen for input source changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func inputSourceDidChange(_ notification: Notification) {
        // Check if we should ignore this change (hotkey was just pressed)
        if let ignoreUntil = ignoreInputSourceChangesUntil, Date() < ignoreUntil {
            debugLogCallback?("⏭️ Ignoring input source change (hotkey was just used)")
            // Still update current source for tracking
            if let newSource = Self.getCurrentInputSource() {
                currentInputSource = newSource
            }
            return
        }
        
        // Get new input source
        guard let newSource = Self.getCurrentInputSource() else { return }

        // Check if it actually changed
        if currentInputSource?.id == newSource.id {
            return
        }

        currentInputSource = newSource

        // For XKey/OpenKey itself - always enable Vietnamese
        let shouldEnable: Bool
        if Self.isXKeyInputSource(newSource) {
            shouldEnable = true
        } else {
            // Check if XKey should be enabled for this input source
            shouldEnable = config.isXKeyEnabled(for: newSource.id)
        }

        // Notify delegate
        onInputSourceChanged?(newSource, shouldEnable)

        // Refresh available sources (in case new ones were added)
        availableInputSources = Self.getAllInputSources()

        // Post notification for UI to update
        NotificationCenter.default.post(
            name: .inputSourceDidChange,
            object: nil,
            userInfo: ["source": newSource]
        )
    }
    
    // MARK: - Hotkey Coordination
    
    /// Temporarily ignore input source changes for the given duration
    /// This is used when a hotkey that conflicts with macOS input source shortcuts is pressed
    func temporarilyIgnoreInputSourceChanges(forSeconds seconds: TimeInterval = 0.5) {
        ignoreInputSourceChangesUntil = Date().addingTimeInterval(seconds)
        debugLogCallback?("⏸️ Temporarily ignoring input source changes for \(seconds)s")
    }

    // MARK: - Configuration Management

    /// Update enabled state for an input source
    func setEnabled(_ enabled: Bool, for inputSourceID: String) {
        config.setEnabled(enabled, for: inputSourceID)
        saveConfig()

        // If this is the current input source, trigger the change immediately
        if currentInputSource?.id == inputSourceID {
            if let source = currentInputSource {
                onInputSourceChanged?(source, enabled)

                // Also post notification for UI
                NotificationCenter.default.post(
                    name: .inputSourceDidChange,
                    object: nil,
                    userInfo: ["source": source]
                )
            }
        }
    }

    /// Get enabled state for an input source
    func isEnabled(for inputSourceID: String) -> Bool {
        return config.isXKeyEnabled(for: inputSourceID)
    }

    /// Save configuration to plist (via SharedSettings)
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            SharedSettings.shared.setInputSourceConfig(data)
        }
    }

    /// Load configuration from plist (via SharedSettings)
    private static func loadConfig() -> InputSourceConfig {
        guard let data = SharedSettings.shared.getInputSourceConfig(),
              let config = try? JSONDecoder().decode(InputSourceConfig.self, from: data) else {
            return InputSourceConfig()
        }
        return config
    }

    // MARK: - Input Source Queries

    /// Get the current keyboard input source
    static func getCurrentInputSource() -> InputSourceInfo? {
        let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return extractInputSourceInfo(from: currentSource)
    }

    /// Get all enabled keyboard input sources
    static func getAllInputSources() -> [InputSourceInfo] {
        // Get all enabled keyboard input sources
        let cfInputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let inputSources = cfInputSources as! [TISInputSource]

        var sources: [InputSourceInfo] = []

        for source in inputSources {
            // Only include keyboard input sources (exclude other types)
            if let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) {
                let categoryString = Unmanaged<CFString>.fromOpaque(category).takeUnretainedValue() as String

                // Only include keyboard input sources
                if categoryString == kTISCategoryKeyboardInputSource as String {
                    if let info = extractInputSourceInfo(from: source) {
                        sources.append(info)
                    }
                }
            }
        }

        // Remove duplicates and sort
        let uniqueSources = Array(Set(sources)).sorted { $0.displayName < $1.displayName }

        // Filter out XKey/OpenKey itself from the list
        return uniqueSources.filter { !isXKeyInputSource($0) }
    }

    /// Extract InputSourceInfo from TISInputSource
    private static func extractInputSourceInfo(from source: TISInputSource) -> InputSourceInfo? {
        // Get ID
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        // Get localized name
        var name = ""
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }

        return InputSourceInfo(id: id, name: name)
    }

    /// Check if an input source is XKey/OpenKey itself
    static func isXKeyInputSource(_ source: InputSourceInfo) -> Bool {
        let lowercaseID = source.id.lowercased()
        let lowercaseName = source.name.lowercased()

        let patterns = ["xkey"]

        return patterns.contains { pattern in
            lowercaseID.contains(pattern) || lowercaseName.contains(pattern)
        }
    }

    /// Check if an input source is a Vietnamese input method (heuristic)
    static func isVietnameseInputSource(_ source: InputSourceInfo) -> Bool {
        let lowercaseID = source.id.lowercased()
        let lowercaseName = source.name.lowercased()

        // Common Vietnamese input source patterns
        let patterns = [
            "vietnamese",
            "viet",
            "vi-vn",
            "telex",
            "vni",
            "viqr"
        ]

        return patterns.contains { pattern in
            lowercaseID.contains(pattern) || lowercaseName.contains(pattern)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when input source changes
    static let inputSourceDidChange = Notification.Name("XKey.inputSourceDidChange")
}
