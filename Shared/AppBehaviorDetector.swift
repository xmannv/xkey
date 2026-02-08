//
//  AppBehaviorDetector.swift
//  XKey
//
//  Shared module for detecting app-specific behaviors
//  Used by both XKey (CGEvent) and XKeyIM (IMKit) to apply appropriate workarounds
//

import Cocoa
import Carbon

// MARK: - App Behavior Types

/// App behavior category for Vietnamese input
enum AppBehavior {
    case standard           // Normal apps - use default behavior
    case terminal           // Terminal apps - may need delays or different handling
    case browserAddressBar  // Browser address bars - have autocomplete issues
    case jetbrainsIDE       // JetBrains IDEs - need special handling
    case microsoftOffice    // Microsoft Office - may need selection method
    case spotlight          // Spotlight - has autocomplete
    case overlayLauncher    // Overlay launchers (Raycast, Alfred) - similar to Spotlight
    case electronApp        // Electron apps - may have quirks
    case codeEditor         // Code editors (VSCode, Sublime, etc.)
}

/// IMKit-specific behavior hints
struct IMKitBehavior {
    /// Whether to use marked text (underline) or direct insertion
    let useMarkedText: Bool
    
    /// Whether this app has issues with marked text
    let hasMarkedTextIssues: Bool
    
    /// Delay before committing text (microseconds)
    let commitDelay: UInt32
    
    /// Description for debugging
    let description: String
    
    /// Default behavior
    static let standard = IMKitBehavior(
        useMarkedText: true,
        hasMarkedTextIssues: false,
        commitDelay: 0,
        description: "Standard"
    )
}

// MARK: - CGEvent Injection Types (for CharacterInjector)

/// Injection method for CGEvent-based input
enum InjectionMethod: String, Codable, CaseIterable {
    case fast           // Default: backspace + text with minimal delays
    case slow           // Terminals/IDEs: backspace + text with higher delays
    case selection      // Browser address bars: Shift+Left select + type replacement
    case autocomplete   // Spotlight: Forward Delete + backspace + text
    case axDirect       // Firefox content area: Use Accessibility API to set text directly
    case passthrough    // Bypass Vietnamese processing - just pass keystrokes through

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .slow: return "Slow"
        case .selection: return "Selection"
        case .autocomplete: return "Autocomplete"
        case .axDirect: return "AX Direct"
        case .passthrough: return "Passthrough (tắt tiếng việt)"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Backspace + gõ text với delay thấp (mặc định)"
        case .slow: return "Backspace + gõ text với delay cao (Terminal, IDE)"
        case .selection: return "Shift+Left select + gõ thay thế (Browser address bar)"
        case .autocomplete: return "Forward Delete + backspace + text (Spotlight, Raycast)"
        case .axDirect: return "Dùng Accessibility API trực tiếp (Firefox content area)"
        case .passthrough: return "Bỏ qua xử lý Tiếng Việt - chỉ truyền phím thẳng qua"
        }
    }
    
    /// Default delays for this injection method (backspace, wait, text) in microseconds
    /// Centralized here to avoid duplication across codebase
    var defaultDelays: (backspace: UInt32, wait: UInt32, text: UInt32) {
        switch self {
        case .fast:         return (1000, 3000, 1500)   // Low delays for responsive apps
        case .slow:         return (3000, 6000, 3000)   // High delays for terminals/IDEs
        case .selection:    return (1000, 3000, 2000)   // Medium delays for selection-based injection
        case .autocomplete: return (1000, 3000, 1000)   // Fast text, for overlays like Spotlight
        case .axDirect:     return (1000, 3000, 2000)   // Medium delays for AX API injection
        case .passthrough:  return (0, 0, 0)            // No delays needed - passthrough doesn't inject
        }
    }
}

/// Injection delays in microseconds (backspace, wait, text)
/// - backspace: Delay between each backspace keystroke
/// - wait: Delay after all backspaces, before sending new text
/// - text: Delay between each character when injecting
typealias InjectionDelays = (backspace: UInt32, wait: UInt32, text: UInt32)

/// Complete injection method info
struct InjectionMethodInfo {
    let method: InjectionMethod
    let delays: InjectionDelays
    let textSendingMethod: TextSendingMethod
    let description: String
    
    static let defaultFast = InjectionMethodInfo(
        method: .fast,
        delays: InjectionMethod.fast.defaultDelays,
        textSendingMethod: .chunked,
        description: "Default (fast)"
    )
}

/// Text sending method for CGEvent-based input
/// Some apps (Safari/Google Docs) don't handle multiple Unicode chars in single CGEvent
enum TextSendingMethod: String, Codable, CaseIterable {
    case chunked = "chunked"      // Send multiple chars per CGEvent (faster, default)
    case oneByOne = "oneByOne"    // Send one char at a time (for Safari/Google Docs compatibility)
    
    var displayName: String {
        switch self {
        case .chunked: return "Chunked (Nhanh)"
        case .oneByOne: return "Từng ký tự (Chậm hơn nhưng an toàn hơn)"
        }
    }
    
    var description: String {
        switch self {
        case .chunked: return "Gửi nhiều ký tự cùng lúc, nhanh hơn"
        case .oneByOne: return "Gửi từng ký tự một, tương thích tốt hơn với Safari/Google Docs"
        }
    }
}

// MARK: - Window Title-Based Detection

/// Match mode for window title patterns
enum WindowTitleMatchMode: String, Codable, CaseIterable {
    case contains = "contains"      // Title contains pattern
    case prefix = "prefix"          // Title starts with pattern
    case suffix = "suffix"          // Title ends with pattern
    case regex = "regex"            // Regex pattern matching
    case exact = "exact"            // Exact match
    
    /// Check if title matches the pattern
    func matches(title: String, pattern: String) -> Bool {
        let lowercaseTitle = title.lowercased()
        let lowercasePattern = pattern.lowercased()
        
        switch self {
        case .contains:
            return lowercaseTitle.contains(lowercasePattern)
        case .prefix:
            return lowercaseTitle.hasPrefix(lowercasePattern)
        case .suffix:
            return lowercaseTitle.hasSuffix(lowercasePattern)
        case .exact:
            return lowercaseTitle == lowercasePattern
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(title.startIndex..., in: title)
            return regex.firstMatch(in: title, options: [], range: range) != nil
        }
    }
}

/// Result of merging all matching Window Title Rules
/// Uses cascade logic: later rules override earlier rules (last non-nil value wins)
/// This allows creating base rules with general settings and specific rules to override certain properties
struct MergedRuleResult {
    /// Names of all matched rules (for display/debugging)
    var matchedRuleNames: [String] = []
    
    /// Whether to use marked text (nil = use default)
    var useMarkedText: Bool?
    
    /// Whether this context has marked text issues (nil = use default)
    var hasMarkedTextIssues: Bool?
    
    /// Commit delay in microseconds (nil = use default)
    var commitDelay: UInt32?
    
    /// Injection method (nil = use default)
    var injectionMethod: InjectionMethod?
    
    /// Injection delays [backspace, wait, text] (nil = use default)
    var injectionDelays: [UInt32]?
    
    /// Text sending method (nil = use default/auto-detect)
    var textSendingMethod: TextSendingMethod?
    
    /// Enable AXManualAccessibility for Electron/Chromium apps
    var enableForceAccessibility: Bool?
    
    /// Target input source ID to switch to when rule matches (nil = use XKey/current)
    /// When set, XKey will automatically switch to this input source when the rule matches
    var targetInputSourceId: String?
    
    /// Combined description from all rules
    var description: String?
    
    /// Whether any rules matched
    var hasMatches: Bool {
        return !matchedRuleNames.isEmpty
    }
    
    /// Display name showing all matched rules
    var displayName: String {
        matchedRuleNames.joined(separator: " + ")
    }
    
    /// Merge a rule into this result (later rules override earlier)
    mutating func merge(from rule: WindowTitleRule) {
        matchedRuleNames.append(rule.name)
        
        // Override with non-nil values from the rule
        if let value = rule.useMarkedText { useMarkedText = value }
        if let value = rule.hasMarkedTextIssues { hasMarkedTextIssues = value }
        if let value = rule.commitDelay { commitDelay = value }
        if let value = rule.injectionMethod { injectionMethod = value }
        if let value = rule.injectionDelays { injectionDelays = value }
        if let value = rule.textSendingMethod { textSendingMethod = value }
        if let value = rule.enableForceAccessibility { enableForceAccessibility = value }
        if let value = rule.targetInputSourceId { targetInputSourceId = value }
        if let value = rule.description { description = value }
    }
}

/// Rule for window title-based app behavior detection
/// Allows combining bundle ID, window title, and AX attributes to identify specific contexts
/// (e.g., Google Docs opened in Safari vs regular Safari browsing, Notion code blocks, etc.)
struct WindowTitleRule: Codable, Identifiable {
    var id = UUID()
    
    /// Name for display/debugging
    let name: String
    
    /// Bundle ID pattern to match (empty string = any app, supports regex)
    let bundleIdPattern: String
    
    /// Window title pattern to match
    let titlePattern: String
    
    /// How to match the title pattern
    let matchMode: WindowTitleMatchMode
    
    /// Whether this rule is enabled
    var isEnabled: Bool = true
    
    // MARK: - AX-Based Matching (Phase 1)
    
    /// AX Role pattern to match (e.g., "AXTextArea", "AXTextField", "AXComboBox")
    /// Empty or nil = match any role
    let axRolePattern: String?
    
    /// AX Description pattern to match (e.g., "Address and search bar", "Terminal*")
    /// Supports same matchMode as titlePattern (contains, prefix, suffix, regex, exact)
    /// Empty or nil = match any description
    let axDescriptionPattern: String?
    
    /// AX Identifier pattern to match (e.g., "urlbar-input", "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD")
    /// Empty or nil = match any identifier
    let axIdentifierPattern: String?
    
    /// AX DOM Class List - match if focused element contains ANY of these classes
    /// Useful for web content detection (e.g., ["notranslate"] for Notion code blocks)
    /// Empty or nil = skip DOM class matching
    let axDOMClassList: [String]?
    
    // MARK: - Behavior Overrides
    
    /// Override: Whether to use marked text (nil = use default)
    let useMarkedText: Bool?
    
    /// Override: Whether this context has marked text issues (nil = use default)
    let hasMarkedTextIssues: Bool?
    
    /// Override: Commit delay in microseconds (nil = use default)
    let commitDelay: UInt32?
    
    /// Override: Injection method (nil = use default)
    let injectionMethod: InjectionMethod?
    
    /// Override: Injection delays [backspace, wait, text] (nil = use default)
    let injectionDelays: [UInt32]?
    
    /// Override: Text sending method (nil = use default/auto-detect)
    let textSendingMethod: TextSendingMethod?
    
    /// Override: Enable AXManualAccessibility for Electron/Chromium apps
    /// When enabled, XKey will set AXManualAccessibility = true when this app is focused
    /// This helps retrieve more detailed text info from Electron apps (VS Code, Slack, etc.)
    let enableForceAccessibility: Bool?
    
    /// Override: Target input source to switch to when rule matches
    /// When set, XKey will automatically switch to this input source when the rule matches
    /// Example: "com.apple.keylayout.ABC" for US English, "com.apple.keylayout.French" for French
    let targetInputSourceId: String?
    
    /// Description for debugging
    let description: String?
    
    // MARK: - Matching
    
    /// Check if this rule matches the given bundle ID, window title, and AX info
    /// - Parameters:
    ///   - bundleId: The app's bundle identifier
    ///   - windowTitle: The focused window's title
    ///   - axInfo: The focused element's AX attributes (required for rules with AX patterns)
    /// - Returns: true if all specified patterns match
    func matches(bundleId: String, windowTitle: String, axInfo: AppBehaviorDetector.FocusedElementInfo?) -> Bool {
        // Check bundle ID pattern
        if !bundleIdPattern.isEmpty {
            // If pattern contains pipe | it's OR matching
            if bundleIdPattern.contains("|") {
                let patterns = bundleIdPattern.split(separator: "|").map { String($0) }
                let bundleMatches = patterns.contains { pattern in
                    if pattern == ".*" || pattern == "*" {
                        return true
                    }
                    // Simple wildcard or exact match
                    if pattern.hasPrefix("*.") {
                        let suffix = String(pattern.dropFirst(2))
                        return bundleId.hasSuffix(suffix)
                    }
                    return bundleId == pattern || bundleId.contains(pattern)
                }
                if !bundleMatches {
                    return false
                }
            } else if bundleIdPattern != ".*" && bundleIdPattern != "*" {
                // Simple pattern matching
                if !bundleId.contains(bundleIdPattern) && bundleId != bundleIdPattern {
                    return false
                }
            }
        }
        
        // If titlePattern is NOT empty, check window title pattern
        if !titlePattern.isEmpty {
            if !matchMode.matches(title: windowTitle, pattern: titlePattern) {
                return false
            }
        }
        
        // MARK: AX-Based Matching
        // If any AX pattern is specified, we need axInfo to match
        let hasAXPatterns = (axRolePattern != nil && !axRolePattern!.isEmpty) ||
                            (axDescriptionPattern != nil && !axDescriptionPattern!.isEmpty) ||
                            (axIdentifierPattern != nil && !axIdentifierPattern!.isEmpty) ||
                            (axDOMClassList != nil && !axDOMClassList!.isEmpty)
        
        if hasAXPatterns {
            guard let info = axInfo else {
                // AX patterns specified but no axInfo provided - cannot match
                return false
            }
            
            // Check AX Role pattern
            if let rolePattern = axRolePattern, !rolePattern.isEmpty {
                guard let role = info.role else { return false }
                if !matchMode.matches(title: role, pattern: rolePattern) {
                    return false
                }
            }
            
            // Check AX Description pattern
            if let descPattern = axDescriptionPattern, !descPattern.isEmpty {
                guard let desc = info.description else { return false }
                if !matchMode.matches(title: desc, pattern: descPattern) {
                    return false
                }
            }
            
            // Check AX Identifier pattern (matches against EITHER AXIdentifier OR AXDOMIdentifier)
            // Firefox and web browsers use AXDOMIdentifier for DOM element IDs (e.g., "urlbar-input")
            if let idPattern = axIdentifierPattern, !idPattern.isEmpty {
                let identifierMatches = info.identifier.map { matchMode.matches(title: $0, pattern: idPattern) } ?? false
                let domIdentifierMatches = info.domIdentifier.map { matchMode.matches(title: $0, pattern: idPattern) } ?? false
                
                // Match if EITHER identifier matches
                if !identifierMatches && !domIdentifierMatches {
                    return false
                }
            }
            
            // Check AX DOM Class List - match if ANY specified class is present
            if let requiredClasses = axDOMClassList, !requiredClasses.isEmpty {
                guard let domClasses = info.domClasses else { return false }
                let hasMatch = requiredClasses.contains { requiredClass in
                    domClasses.contains { $0.lowercased().contains(requiredClass.lowercased()) }
                }
                if !hasMatch {
                    return false
                }
            }
        }
        
        return true
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, name, bundleIdPattern, titlePattern, matchMode, isEnabled
        // AX matching patterns
        case axRolePattern, axDescriptionPattern, axIdentifierPattern, axDOMClassList
        // Behavior overrides
        case useMarkedText, hasMarkedTextIssues, commitDelay
        case injectionMethod, injectionDelays, textSendingMethod
        case enableForceAccessibility, targetInputSourceId, description
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        bundleIdPattern = try container.decode(String.self, forKey: .bundleIdPattern)
        titlePattern = try container.decode(String.self, forKey: .titlePattern)
        matchMode = try container.decode(WindowTitleMatchMode.self, forKey: .matchMode)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        
        // Decode AX matching patterns
        axRolePattern = try container.decodeIfPresent(String.self, forKey: .axRolePattern)
        axDescriptionPattern = try container.decodeIfPresent(String.self, forKey: .axDescriptionPattern)
        axIdentifierPattern = try container.decodeIfPresent(String.self, forKey: .axIdentifierPattern)
        axDOMClassList = try container.decodeIfPresent([String].self, forKey: .axDOMClassList)
        
        // Decode behavior overrides
        useMarkedText = try container.decodeIfPresent(Bool.self, forKey: .useMarkedText)
        hasMarkedTextIssues = try container.decodeIfPresent(Bool.self, forKey: .hasMarkedTextIssues)
        commitDelay = try container.decodeIfPresent(UInt32.self, forKey: .commitDelay)
        injectionDelays = try container.decodeIfPresent([UInt32].self, forKey: .injectionDelays)
        textSendingMethod = try container.decodeIfPresent(TextSendingMethod.self, forKey: .textSendingMethod)
        enableForceAccessibility = try container.decodeIfPresent(Bool.self, forKey: .enableForceAccessibility)
        targetInputSourceId = try container.decodeIfPresent(String.self, forKey: .targetInputSourceId)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        // Decode injection method from string
        if let methodString = try container.decodeIfPresent(String.self, forKey: .injectionMethod) {
            switch methodString.lowercased() {
            case "fast": injectionMethod = .fast
            case "slow": injectionMethod = .slow
            case "selection": injectionMethod = .selection
            case "autocomplete": injectionMethod = .autocomplete
            case "axdirect": injectionMethod = .axDirect
            case "passthrough": injectionMethod = .passthrough
            default: injectionMethod = nil
            }
        } else {
            injectionMethod = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdPattern, forKey: .bundleIdPattern)
        try container.encode(titlePattern, forKey: .titlePattern)
        try container.encode(matchMode, forKey: .matchMode)
        try container.encode(isEnabled, forKey: .isEnabled)
        
        // Encode AX matching patterns
        try container.encodeIfPresent(axRolePattern, forKey: .axRolePattern)
        try container.encodeIfPresent(axDescriptionPattern, forKey: .axDescriptionPattern)
        try container.encodeIfPresent(axIdentifierPattern, forKey: .axIdentifierPattern)
        try container.encodeIfPresent(axDOMClassList, forKey: .axDOMClassList)
        
        // Encode behavior overrides
        try container.encodeIfPresent(useMarkedText, forKey: .useMarkedText)
        try container.encodeIfPresent(hasMarkedTextIssues, forKey: .hasMarkedTextIssues)
        try container.encodeIfPresent(commitDelay, forKey: .commitDelay)
        try container.encodeIfPresent(injectionDelays, forKey: .injectionDelays)
        try container.encodeIfPresent(textSendingMethod, forKey: .textSendingMethod)
        try container.encodeIfPresent(enableForceAccessibility, forKey: .enableForceAccessibility)
        try container.encodeIfPresent(targetInputSourceId, forKey: .targetInputSourceId)
        try container.encodeIfPresent(description, forKey: .description)
        
        // Encode injection method as string
        if let method = injectionMethod {
            let methodString: String
            switch method {
            case .fast: methodString = "fast"
            case .slow: methodString = "slow"
            case .selection: methodString = "selection"
            case .autocomplete: methodString = "autocomplete"
            case .axDirect: methodString = "axDirect"
            case .passthrough: methodString = "passthrough"
            }
            try container.encode(methodString, forKey: .injectionMethod)
        }
    }
    
    // MARK: - Convenience Initializer
    
    init(
        name: String,
        bundleIdPattern: String,
        titlePattern: String,
        matchMode: WindowTitleMatchMode,
        isEnabled: Bool = true,
        // AX matching patterns
        axRolePattern: String? = nil,
        axDescriptionPattern: String? = nil,
        axIdentifierPattern: String? = nil,
        axDOMClassList: [String]? = nil,
        // Behavior overrides
        useMarkedText: Bool? = nil,
        hasMarkedTextIssues: Bool? = nil,
        commitDelay: UInt32? = nil,
        injectionMethod: InjectionMethod? = nil,
        injectionDelays: [UInt32]? = nil,
        textSendingMethod: TextSendingMethod? = nil,
        enableForceAccessibility: Bool? = nil,
        targetInputSourceId: String? = nil,
        description: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.bundleIdPattern = bundleIdPattern
        self.titlePattern = titlePattern
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        // AX matching patterns
        self.axRolePattern = axRolePattern
        self.axDescriptionPattern = axDescriptionPattern
        self.axIdentifierPattern = axIdentifierPattern
        self.axDOMClassList = axDOMClassList
        // Behavior overrides
        self.useMarkedText = useMarkedText
        self.hasMarkedTextIssues = hasMarkedTextIssues
        self.commitDelay = commitDelay
        self.injectionMethod = injectionMethod
        self.injectionDelays = injectionDelays
        self.textSendingMethod = textSendingMethod
        self.enableForceAccessibility = enableForceAccessibility
        self.targetInputSourceId = targetInputSourceId
        self.description = description
    }
    
    /// Check if this rule has any AX-based matching patterns
    var hasAXPatterns: Bool {
        return (axRolePattern != nil && !axRolePattern!.isEmpty) ||
               (axDescriptionPattern != nil && !axDescriptionPattern!.isEmpty) ||
               (axIdentifierPattern != nil && !axIdentifierPattern!.isEmpty) ||
               (axDOMClassList != nil && !axDOMClassList!.isEmpty)
    }
    
    /// Get a summary of AX patterns for display
    var axPatternsSummary: String {
        var parts: [String] = []
        if let role = axRolePattern, !role.isEmpty {
            parts.append("Role: \(role)")
        }
        if let desc = axDescriptionPattern, !desc.isEmpty {
            parts.append("Desc: \(desc)")
        }
        if let id = axIdentifierPattern, !id.isEmpty {
            parts.append("ID: \(id)")
        }
        if let classes = axDOMClassList, !classes.isEmpty {
            parts.append("DOM: [\(classes.joined(separator: ", "))]")
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }
}

// MARK: - App Behavior Detector

class AppBehaviorDetector {
    
    // MARK: - Singleton
    
    static let shared = AppBehaviorDetector()
    
    // MARK: - Dependency Injection
    
    /// Callback to get visible overlay app name (injected by XKey app)
    /// Used to detect Spotlight/Raycast/Alfred without direct dependency on OverlayAppDetector
    /// Returns overlay app name ("Spotlight", "Raycast", "Alfred") or nil if no overlay visible
    var overlayAppNameProvider: (() -> String?)?
    
    // MARK: - Force Override (for Injection Test)
    
    /// Force override injection method (set by Injection Test)
    /// When set, detectInjectionMethod() returns this instead of auto-detecting
    var forceInjectionMethod: InjectionMethod? = nil
    
    /// Force override text sending method (set by Injection Test)
    var forceTextSendingMethod: TextSendingMethod? = nil
    
    /// Force override delays (set by Injection Test)
    var forceDelays: InjectionDelays? = nil
    
    // MARK: - Confirmed Injection Method
    
    /// Confirmed injection method (set when app is detected via mouse click or app switch)
    /// When set, getConfirmedInjectionMethod() returns this instead of detecting every keystroke
    /// This improves performance and avoids AX API timing issues
    private var confirmedInjectionMethod: InjectionMethodInfo?
    
    /// Set confirmed injection method (call from mouse click handler or app switch)
    /// - Parameter methodInfo: The injection method to use for subsequent keystrokes
    func setConfirmedInjectionMethod(_ methodInfo: InjectionMethodInfo) {
        confirmedInjectionMethod = methodInfo
    }
    
    /// Get confirmed injection method, or detect if not set
    /// - Returns: Confirmed method if available, otherwise detects fresh
    func getConfirmedInjectionMethod() -> InjectionMethodInfo {
        // Priority 0: Check force override (set by Injection Test)
        if let forcedMethod = forceInjectionMethod {
            let delays = forceDelays ?? getDefaultDelays(for: forcedMethod)
            let textMethod = forceTextSendingMethod ?? .chunked
            return InjectionMethodInfo(
                method: forcedMethod,
                delays: delays,
                textSendingMethod: textMethod,
                description: "Forced Override (\(forcedMethod.displayName))"
            )
        }
        
        // Priority 1: Use confirmed method if available
        if let confirmed = confirmedInjectionMethod {
            return confirmed
        }
        
        // Priority 2: Fallback to live detection
        return detectInjectionMethod()
    }
    
    /// Clear confirmed injection method (call when context changes significantly)
    func clearConfirmedInjectionMethod() {
        confirmedInjectionMethod = nil
    }
    
    // MARK: - Cache (only for detect() which is used for UI display)
    // Note: detectInjectionMethod(), findMatchingRule(), and detectIMKitBehavior() 
    // don't use cache to ensure fresh detection on every keystroke

    private var cachedBundleId: String?
    private var cachedBehavior: AppBehavior?
    
    // MARK: - Window Title Rules
    
    /// User-defined custom rules (loaded from preferences)
    private var customRules: [WindowTitleRule] = []
    
    /// Built-in rules for known problematic web apps
    /// These have lower priority than custom rules
    static let builtInWindowTitleRules: [WindowTitleRule] = [
        // ============================================
        // Google Workspace rules (all browsers)
        // ============================================
        
        // Google Docs (all browsers, English + Vietnamese UI)
        // Matches: "Google Docs", "Google Tài liệu"
        WindowTitleRule(
            name: "Google Docs",
            bundleIdPattern: "",  // Match all browsers
            titlePattern: "Google (Docs|Tài liệu)",
            matchMode: .regex,
            useMarkedText: false,
            hasMarkedTextIssues: true,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [5000, 10000, 8000],
            textSendingMethod: .oneByOne,
            description: "Google Docs (all browsers) - one-by-one text sending"
        ),
        
        // Google Sheets (all browsers, English + Vietnamese UI)
        // Matches: "Google Sheets", "Google Trang tính"
        // Note: Uses fast method with chunked text sending (same as Excel)
        // Forward Delete is handled in CharacterInjector with AX check (like Excel)
        WindowTitleRule(
            name: "Google Sheets",
            bundleIdPattern: "",  // Match all browsers
            titlePattern: "Google (Sheets|Trang tính)",
            matchMode: .regex,
            useMarkedText: false,
            hasMarkedTextIssues: true,
            commitDelay: 5000,
            injectionMethod: .fast,
            injectionDelays: [2000, 5000, 2000],  // Same as Excel
            textSendingMethod: .chunked,          // Same as Excel
            description: "Google Sheets (all browsers) - fast method like Excel"
        ),
    ]
    
    // MARK: - Static App Lists (Single Source of Truth)
    
    /// Terminal apps that need special handling
    static let terminalApps: Set<String> = [
        // Apple Terminal
        "com.apple.Terminal",
        // Fast terminals (GPU-accelerated)
        "io.alacritty",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.raphaelamorim.rio",
        // Medium speed terminals
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "org.tabby",
        "com.termius-dmg.mac"
    ]
    
    /// Unified terminal delays (backspace, wait, text) in microseconds
    /// All terminals use the same config
    static let terminalDelays: InjectionDelays = (8000, 25000, 8000)
    
    /// Browser apps
    static let browserApps: Set<String> = [
        // Chromium-based
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "ru.yandex.desktop.yandex-browser",
        // Opera
        "com.opera.Opera",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaAir",
        "com.opera.OperaNext",
        // Safari
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        // WebKit-based
        "com.kagi.kagimacOS",
        // Arc & Others
        "company.thebrowser.Browser",
        "company.thebrowser.Arc",
        "company.thebrowser.dia",
        "com.sigmaos.sigmaos.macos",
        "com.pushplaylabs.sidekick",
        "com.firstversionist.polypane",
        "ai.perplexity.comet",
        "com.duckduckgo.macos.browser"
    ]

    /// Firefox-based browsers - need special handling for content area
    /// Address bar (AXTextField): use selection method
    /// Content area (AXWindow): use axDirect method (AX API to set text directly)
    /// Note: Selection method in content area interferes with mouse word selection
    static let firefoxBasedBrowsers: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.waterfoxproject.waterfox",
        "io.gitlab.librewolf-community.librewolf",
        "one.ablaze.floorp",
        "org.torproject.torbrowser",
        "net.mullvad.mullvadbrowser"
    ]

    /// Browsers that need AX attribute-based detection for address bar
    /// These browsers have non-standard address bar detection (not AXTextField/AXComboBox)
    /// Address bar is detected via AX Description regex pattern: "Search with xx or enter address"
    static let axAttributeDetectForBrowsers: Set<String> = [
        "app.zen-browser.zen"  // Zen Browser
        // Add more similar browsers
    ]

    /// Code editors (Electron-based or native)
    static let codeEditors: Set<String> = [
        // VSCode and variants
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium.codium",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        // Sublime
        "com.sublimetext.3",
        "com.sublimetext.4",
        // Atom (discontinued but still used)
        "com.github.atom",
        // Nova
        "com.panic.Nova",
        // TextMate
        "com.macromates.TextMate",
        "com.macromates.TextMate.preview",
        // BBEdit
        "com.barebones.bbedit",
        // CotEditor
        "com.coteditor.CotEditor"
    ]
    
    /// Apps known to have issues with IMKit marked text
    static let markedTextProblematicApps: Set<String> = [
        // Some terminals don't handle marked text well
        "com.apple.Terminal",
        "io.alacritty",
        // Some code editors
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium.codium",
        "com.todesktop.230313mzl4w4u92"  // Cursor
    ]
    
    /// Microsoft Office apps
    static let microsoftOfficeApps: Set<String> = [
        "com.microsoft.Excel",
        "com.microsoft.Word",
        "com.microsoft.Powerpoint"
    ]
    
    /// Apps that need fast method with oneByOne text sending
    /// These apps have timing issues with chunked text input
    static let fastOneByOneApps: Set<String> = [
        "texstudio"  // TeXstudio - LaTeX editor
    ]
    
    // MARK: - Detection Methods
    
    /// Detect app behavior for current frontmost app
    func detect() -> AppBehavior {
        guard let bundleId = getCurrentBundleId() else {
            return .standard
        }
        
        // Check cache
        if bundleId == cachedBundleId, let behavior = cachedBehavior {
            return behavior
        }
        
        cachedBundleId = bundleId
        cachedBehavior = detectBehavior(for: bundleId)
        
        return cachedBehavior ?? .standard
    }
    
    /// Detect IMKit-specific behavior
    /// First checks Window Title Rules, then falls back to bundle ID based detection
    ///
    /// Note: No caching is used here because:
    /// 1. Focus can change within same window (e.g., Google Docs content → address bar)
    /// 2. Window title might change (e.g., switching tabs)
    /// 3. The detection logic is very fast
    /// 4. Simpler code without cache = fewer bugs
    func detectIMKitBehavior() -> IMKitBehavior {
        guard let bundleId = getCurrentBundleId() else {
            return .standard
        }
        
        // Priority 1: Check Window Title Rules for context-specific behavior (merged cascade)
        let mergedResult = getMergedRuleResult()
        if mergedResult.hasMatches {
            return IMKitBehavior(
                useMarkedText: mergedResult.useMarkedText ?? true,
                hasMarkedTextIssues: mergedResult.hasMarkedTextIssues ?? false,
                commitDelay: mergedResult.commitDelay ?? 0,
                description: mergedResult.displayName
            )
        }
        
        // Priority 2: Fall back to bundle ID based detection
        let appBehavior = detectBehavior(for: bundleId)
        return getIMKitBehavior(for: bundleId, appBehavior: appBehavior)
    }
    
    /// Get current frontmost app's bundle identifier
    func getCurrentBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    
    // MARK: - Focused Element Info (Optimized - Single AX Query)
    
    /// Struct containing all relevant AX attributes of the focused element
    /// Queried once to avoid multiple AXUIElementCreateSystemWide() calls
    struct FocusedElementInfo {
        let role: String?
        let subrole: String?
        let description: String?
        let identifier: String?       // AXIdentifier
        let domIdentifier: String?    // AXDOMIdentifier (used by Firefox, Chromium for DOM element ID)
        let domClasses: [String]?     // AXDOMClassList
        let textValue: String?
        
        /// Check if this element is empty (no text or empty string)
        var isEmpty: Bool {
            guard let text = textValue else { return true }
            return text.isEmpty
        }
        
        static let empty = FocusedElementInfo(
            role: nil, subrole: nil, description: nil,
            identifier: nil, domIdentifier: nil, domClasses: nil, textValue: nil
        )
    }
    
    /// Get all AX attributes of the focused element in a single query
    /// This is more efficient than calling individual getFocused...() functions
    /// - Returns: FocusedElementInfo containing all relevant attributes
    func getFocusedElementInfo() -> FocusedElementInfo {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else {
            return .empty
        }
        
        let axEl = el as! AXUIElement
        
        // Query all attributes at once
        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, kAXRoleAttribute as CFString, &roleVal)
        
        var subroleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, kAXSubroleAttribute as CFString, &subroleVal)
        
        var descVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, kAXDescriptionAttribute as CFString, &descVal)
        
        var identifierVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, kAXIdentifierAttribute as CFString, &identifierVal)
        
        // AXDOMIdentifier is used by Firefox, Chromium for DOM element ID (e.g., "urlbar-input")
        var domIdentifierVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, "AXDOMIdentifier" as CFString, &domIdentifierVal)
        
        var domClassRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, "AXDOMClassList" as CFString, &domClassRef)
        
        var textVal: CFTypeRef?
        AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &textVal)
        
        return FocusedElementInfo(
            role: roleVal as? String,
            subrole: subroleVal as? String,
            description: descVal as? String,
            identifier: identifierVal as? String,
            domIdentifier: domIdentifierVal as? String,
            domClasses: domClassRef as? [String],
            textValue: textVal as? String
        )
    }
    
    // MARK: - Address Bar Detection (Using Single AX Query)
    
    /// Check if focused element matches Zen-style address bar pattern
    /// Detection methods:
    /// 1. DOM ID/Identifier: "urlbar-input" (Firefox/Zen Browser standard) - stored in AXDOMIdentifier
    /// 2. AX Description Pattern: "Search with <search_engine> or enter address"
    /// - Returns: true if focused element is a Zen-style address bar
    func isFirefoxStyleAddressBar() -> Bool {
        let info = getFocusedElementInfo()
        
        // Check DOM ID first (most reliable for Firefox-based browsers)
        // Firefox stores DOM element ID in AXDOMIdentifier, not AXIdentifier
        if let domId = info.domIdentifier, domId == "urlbar-input" {
            return true
        }
        
        // Also check AXIdentifier as fallback (for compatibility)
        if let identifier = info.identifier, identifier == "urlbar-input" {
            return true
        }
        
        // Fallback: Check AX Description pattern
        guard let desc = info.description else { return false }
        // Regex: "Search with <anything> or enter address"
        let pattern = "^Search with .+ or enter address$"
        return desc.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Check if focused element is Safari's address bar
    /// Detection via AX Identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    /// - Returns: true if focused element is Safari's address bar
    func isSafariAddressBar() -> Bool {
        guard let identifier = getFocusedElementInfo().identifier else { return false }
        return identifier == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    }
    
    /// Check if focused element is Chromium-based browser's address bar (Chrome, Edge, Brave, etc.)
    /// Detection methods:
    /// 1. AX Description: "Address and search bar"
    /// 2. AX DOM Classes: contains "OmniboxViewViews"
    /// - Returns: true if focused element is Chromium's address bar (Omnibox)
    func isChromiumAddressBar() -> Bool {
        let info = getFocusedElementInfo()
        
        // Check AX Description
        if let desc = info.description, desc == "Address and search bar" {
            return true
        }
        
        // Check DOM Classes for OmniboxViewViews (Chrome, Edge, etc.)
        // or BraveOmniboxViewViews (Brave Browser)
        if let domClasses = info.domClasses {
            if domClasses.contains("OmniboxViewViews") || domClasses.contains("BraveOmniboxViewViews") {
                return true
            }
        }
        
        return false
    }
    
    /// Check if focused element is Dia Browser's address bar (Command Bar)
    /// Detection via AX Identifier: "commandBarTextField"
    /// - Returns: true if focused element is Dia's address bar
    func isDiaAddressBar() -> Bool {
        guard let identifier = getFocusedElementInfo().identifier else { return false }
        return identifier == "commandBarTextField"
    }
    
    /// Check if focused element is a Terminal panel in VSCode/Cursor/etc
    /// Detection via AX Description: starts with "Terminal"
    /// - Returns: true if focused element is an integrated terminal panel
    func isInTerminalPanel() -> Bool {
        guard let desc = getFocusedElementInfo().description else { return false }
        return desc.hasPrefix("Terminal")
    }
    
    /// Check if focused element is a Notion Code Block
    /// Detection via AX DOM Class List containing "notranslate"
    /// Code blocks in Notion have class: "content-editable-leaf-rtl, notranslate"
    /// - Returns: true if focused element is a Notion code block
    func isNotionCodeBlock() -> Bool {
        guard let domClasses = getFocusedElementInfo().domClasses else { return false }
        return domClasses.contains("notranslate")
    }

    /// Clear cache (call when app changes)
    func clearCache() {
        cachedBundleId = nil
        cachedBehavior = nil
    }
    
    // MARK: - Window Title Detection
    
    /// Get current window title using Accessibility API
    /// Note: Requires Accessibility permission (which XKey already has)
    func getCurrentWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Try to get focused window first
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
           let windowElement = focusedWindow as! AXUIElement? {
            // Get window title
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                return title
            }
        }
        
        // Fallback: try to get main window
        var mainWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow) == .success,
           let windowElement = mainWindow as! AXUIElement? {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                return title
            }
        }
        
        // Fallback: try to get first window from windows array
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement], let firstWindow = windows.first {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                return title
            }
        }
        
        return nil
    }
    
    /// Find matching Window Title Rule for current context
    /// Returns the first matching rule (custom rules have priority over built-in rules)
    ///
    // MARK: - Rule Matching Helpers (shared logic)
    
    /// Check if a built-in rule is active based on user settings.
    /// - Default-enabled rules are active unless user explicitly disabled them
    /// - Default-disabled rules are active only if user explicitly enabled them
    private func isBuiltInRuleActive(
        _ rule: WindowTitleRule,
        disabledRules: Set<String>,
        enabledRules: Set<String>
    ) -> Bool {
        if rule.isEnabled {
            return !disabledRules.contains(rule.name)
        } else {
            return enabledRules.contains(rule.name)
        }
    }
    
    /// Iterate through a set of rules and collect matches against the current context.
    /// Uses lazy-loaded AX info to avoid unnecessary Accessibility API calls.
    /// - Parameters:
    ///   - rules: The rules to iterate
    ///   - bundleId: Current app's bundle ID
    ///   - windowTitle: Current window title
    ///   - cachedAXInfo: Inout cache for lazy AX info loading
    ///   - matches: Inout array to append matches to
    ///   - returnFirst: If true, stops after first match (for findMatchingRule)
    /// - Returns: The first matching rule if returnFirst is true and a match was found
    @discardableResult
    private func matchRules(
        _ rules: [WindowTitleRule],
        bundleId: String,
        windowTitle: String,
        cachedAXInfo: inout FocusedElementInfo?,
        matches: inout [WindowTitleRule],
        returnFirst: Bool = false
    ) -> WindowTitleRule? {
        for rule in rules {
            let axInfo = rule.hasAXPatterns ? {
                if cachedAXInfo == nil {
                    cachedAXInfo = getFocusedElementInfo()
                }
                return cachedAXInfo!
            }() : nil
            
            if rule.matches(bundleId: bundleId, windowTitle: windowTitle, axInfo: axInfo) {
                if returnFirst { return rule }
                matches.append(rule)
            }
        }
        return nil
    }
    
    // MARK: - Rule Matching (public API)
    
    /// Find the first matching Window Title Rule for the current context
    /// Priority: custom rules first (user-defined), then built-in rules
    ///
    /// Note: No caching is used here because:
    /// 1. Focus can change within same window (e.g., Google Docs content → address bar)
    /// 2. Window title might change (e.g., switching tabs)
    /// 3. The detection logic (string comparisons) is very fast
    /// 4. Simpler code without cache = fewer bugs
    func findMatchingRule() -> WindowTitleRule? {
        guard let bundleId = getCurrentBundleId() else {
            return nil
        }
        
        let windowTitle = getCurrentWindowTitle() ?? ""
        var cachedAXInfo: FocusedElementInfo? = nil
        var matches: [WindowTitleRule] = []  // not used for returnFirst, but required by matchRules
        
        // Search in custom rules first (higher priority)
        let activeCustomRules = customRules.filter { $0.isEnabled }
        if let match = matchRules(activeCustomRules, bundleId: bundleId, windowTitle: windowTitle,
                                  cachedAXInfo: &cachedAXInfo, matches: &matches, returnFirst: true) {
            return match
        }
        
        // Then search in built-in rules
        let disabledBuiltInRules = SharedSettings.shared.getDisabledBuiltInRules()
        let enabledBuiltInRules = SharedSettings.shared.getEnabledBuiltInRules()
        let activeBuiltInRules = Self.builtInWindowTitleRules.filter {
            isBuiltInRuleActive($0, disabledRules: disabledBuiltInRules, enabledRules: enabledBuiltInRules)
        }
        
        return matchRules(activeBuiltInRules, bundleId: bundleId, windowTitle: windowTitle,
                          cachedAXInfo: &cachedAXInfo, matches: &matches, returnFirst: true)
    }
    
    /// Find ALL matching Window Title Rules for current context
    /// Returns rules in application order: built-in rules first, then custom rules
    /// Later rules can override earlier rules' properties (cascade behavior)
    ///
    /// Note: No caching is used here for same reasons as findMatchingRule()
    func findAllMatchingRules() -> [WindowTitleRule] {
        guard let bundleId = getCurrentBundleId() else {
            return []
        }
        
        let windowTitle = getCurrentWindowTitle() ?? ""
        var matchingRules: [WindowTitleRule] = []
        var cachedAXInfo: FocusedElementInfo? = nil
        
        // FIRST: Search in built-in rules (lower priority - applied first)
        // This allows custom rules to override built-in rules
        let disabledBuiltInRules = SharedSettings.shared.getDisabledBuiltInRules()
        let enabledBuiltInRules = SharedSettings.shared.getEnabledBuiltInRules()
        let activeBuiltInRules = Self.builtInWindowTitleRules.filter {
            isBuiltInRuleActive($0, disabledRules: disabledBuiltInRules, enabledRules: enabledBuiltInRules)
        }
        matchRules(activeBuiltInRules, bundleId: bundleId, windowTitle: windowTitle,
                   cachedAXInfo: &cachedAXInfo, matches: &matchingRules)
        
        // THEN: Search in custom rules (higher priority - can override)
        let activeCustomRules = customRules.filter { $0.isEnabled }
        matchRules(activeCustomRules, bundleId: bundleId, windowTitle: windowTitle,
                   cachedAXInfo: &cachedAXInfo, matches: &matchingRules)
        
        return matchingRules
    }
    
    /// Get merged result from all matching rules
    /// Uses cascade logic: later rules override earlier rules (last non-nil value wins)
    /// 
    /// Application order:
    /// 1. Built-in rules (base settings)
    /// 2. Custom rules in user-defined order (can override)
    ///
    /// This allows creating flexible configurations:
    /// - A base rule setting injectionMethod for all Firefox windows
    /// - A specific rule enabling Force Accessibility for specific websites
    func getMergedRuleResult() -> MergedRuleResult {
        let matchingRules = findAllMatchingRules()
        
        var result = MergedRuleResult()
        for rule in matchingRules {
            result.merge(from: rule)
        }
        
        return result
    }
    
    /// Check if current context has a matching Window Title Rule
    func hasMatchingWindowTitleRule() -> Bool {
        return findMatchingRule() != nil
    }
    
    /// Check if Force Accessibility (AXManualAccessibility) is enabled by matching rules (merged cascade)
    /// - Returns: A tuple (shouldEnable: Bool, ruleName: String?, bundleId: String?)
    ///   - shouldEnable: true if any rule wants to enable AXManualAccessibility
    ///   - ruleName: display name of all matched rules for logging
    ///   - bundleId: bundle ID of the app to enable Force Accessibility for
    func getForceAccessibilityOverride() -> (shouldEnable: Bool, ruleName: String?, bundleId: String?) {
        let mergedResult = getMergedRuleResult()
        guard mergedResult.enableForceAccessibility == true else {
            return (false, nil, nil)
        }
        
        let bundleId = getCurrentBundleId() ?? ""
        return (true, mergedResult.displayName, bundleId)
    }
    
    /// Get target input source ID from matching rules (merged cascade)
    /// - Returns: A tuple (hasTarget: Bool, inputSourceId: String?, ruleName: String?)
    ///   - hasTarget: true if any rule has a target input source configured
    ///   - inputSourceId: the input source ID to switch to (e.g., "com.apple.keylayout.ABC")
    ///   - ruleName: display name of all matched rules for logging
    func getTargetInputSourceOverride() -> (hasTarget: Bool, inputSourceId: String?, ruleName: String?) {
        let mergedResult = getMergedRuleResult()
        guard let targetId = mergedResult.targetInputSourceId, !targetId.isEmpty else {
            return (false, nil, nil)
        }
        return (true, targetId, mergedResult.displayName)
    }
    
    /// Get current window title
    /// Note: Name kept for backward compatibility, but no longer uses cache
    func getCachedWindowTitle() -> String {
        return getCurrentWindowTitle() ?? ""
    }
    
    // MARK: - Custom Rules Management
    
    /// Load custom rules from preferences
    func loadCustomRules() {
        if let data = SharedSettings.shared.getWindowTitleRulesData(),
           let rules = try? JSONDecoder().decode([WindowTitleRule].self, from: data) {
            customRules = rules
        }
    }
    
    /// Save custom rules to preferences
    func saveCustomRules() {
        if let data = try? JSONEncoder().encode(customRules) {
            SharedSettings.shared.setWindowTitleRulesData(data)
        }
    }
    
    /// Add a custom rule
    func addCustomRule(_ rule: WindowTitleRule) {
        customRules.append(rule)
        saveCustomRules()
        clearCache()
    }
    
    /// Remove a custom rule by ID
    func removeCustomRule(id: UUID) {
        customRules.removeAll { $0.id == id }
        saveCustomRules()
        clearCache()
    }
    
    /// Update a custom rule
    func updateCustomRule(_ rule: WindowTitleRule) {
        if let index = customRules.firstIndex(where: { $0.id == rule.id }) {
            customRules[index] = rule
            saveCustomRules()
            clearCache()
        }
    }
    
    /// Get all custom rules
    func getCustomRules() -> [WindowTitleRule] {
        return customRules
    }
    
    /// Reorder custom rules (after drag & drop)
    /// The new order determines the application priority (later rules override earlier)
    func reorderCustomRules(_ newOrder: [WindowTitleRule]) {
        customRules = newOrder
        saveCustomRules()
        clearCache()
    }
    
    /// Get all built-in rules with their enabled state from preferences
    /// Takes into account both default state and user overrides
    func getBuiltInRules() -> [WindowTitleRule] {
        let disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
        let enabledNames = SharedSettings.shared.getEnabledBuiltInRules()
        return Self.builtInWindowTitleRules.map { rule in
            var mutableRule = rule
            if rule.isEnabled {
                // Default enabled: check if user disabled it
                mutableRule.isEnabled = !disabledNames.contains(rule.name)
            } else {
                // Default disabled: check if user enabled it
                mutableRule.isEnabled = enabledNames.contains(rule.name)
            }
            return mutableRule
        }
    }
    
    /// Toggle a built-in rule's enabled state
    /// Handles both rules that are enabled/disabled by default
    func toggleBuiltInRule(_ ruleName: String, enabled: Bool) {
        // Find the rule to check its default state
        guard let rule = Self.builtInWindowTitleRules.first(where: { $0.name == ruleName }) else {
            return
        }
        
        if rule.isEnabled {
            // Default enabled: use disabledBuiltInRules to disable
            var disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
            if enabled {
                disabledNames.remove(ruleName)
            } else {
                disabledNames.insert(ruleName)
            }
            SharedSettings.shared.setDisabledBuiltInRules(disabledNames)
        } else {
            // Default disabled: use enabledBuiltInRules to enable
            var enabledNames = SharedSettings.shared.getEnabledBuiltInRules()
            if enabled {
                enabledNames.insert(ruleName)
            } else {
                enabledNames.remove(ruleName)
            }
            SharedSettings.shared.setEnabledBuiltInRules(enabledNames)
        }
        clearCache()
    }
    
    /// Check if a built-in rule is enabled (considering default state and user overrides)
    func isBuiltInRuleEnabled(_ ruleName: String) -> Bool {
        guard let rule = Self.builtInWindowTitleRules.first(where: { $0.name == ruleName }) else {
            return false
        }
        
        if rule.isEnabled {
            // Default enabled: check if user disabled it
            let disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
            return !disabledNames.contains(ruleName)
        } else {
            // Default disabled: check if user enabled it
            let enabledNames = SharedSettings.shared.getEnabledBuiltInRules()
            return enabledNames.contains(ruleName)
        }
    }
    
    private func detectBehavior(for bundleId: String) -> AppBehavior {
        // Priority 0: Check if in Terminal panel (VSCode/Cursor/etc) directly via AX Description
        // This is more reliable than overlay detection and doesn't interfere with overlay logic
        if isInTerminalPanel() {
            return .terminal
        }
        
        // Priority 1: Check overlay launcher via injected provider (from OverlayAppDetector in XKey)
        // This detects Spotlight/Raycast/Alfred more accurately when user is focused on search field
        if let overlayName = overlayAppNameProvider?() {
            if overlayName == "Spotlight" {
                return .spotlight
            } else if overlayName == "Raycast" || overlayName == "Alfred" {
                return .overlayLauncher
            }
            // Unknown overlay name: fall through to bundle ID check below
        }
        
        // Fallback: Bundle ID check for Spotlight
        if bundleId == "com.apple.Spotlight" {
            return .spotlight
        }
        
        // Raycast
        if bundleId == "com.raycast.macos" {
            return .overlayLauncher
        }
        
        // Alfred
        if bundleId.contains("com.runningwithcrayons.Alfred") {
            return .overlayLauncher
        }
        
        // JetBrains IDEs
        if bundleId.hasPrefix("com.jetbrains") {
            return .jetbrainsIDE
        }
        
        // Microsoft Office
        if Self.microsoftOfficeApps.contains(bundleId) {
            return .microsoftOffice
        }
        
        // Terminal apps
        if Self.terminalApps.contains(bundleId) {
            return .terminal
        }
        
        // Browser apps - check if in address bar
        let isBrowserApp = Self.browserApps.contains(bundleId)
            || Self.firefoxBasedBrowsers.contains(bundleId)
            || Self.axAttributeDetectForBrowsers.contains(bundleId)
        if isBrowserApp {
            // Safari: Use AX Identifier for accurate detection (avoids web content inputs)
            if bundleId == "com.apple.Safari" || bundleId == "com.apple.SafariTechnologyPreview" {
                if isSafariAddressBar() {
                    return .browserAddressBar
                }
                return .standard
            }
            
            // Firefox-style address bar (detected via DOM ID or AX Description)
            if Self.firefoxBasedBrowsers.contains(bundleId) || Self.axAttributeDetectForBrowsers.contains(bundleId) {
                if isFirefoxStyleAddressBar() {
                    return .browserAddressBar
                }
                return .standard
            }
            
            // Chromium-based browsers: Use AX Description for accurate detection
            // This matches "Address and search bar" which is Chrome's Omnibox identifier
            if isChromiumAddressBar() {
                return .browserAddressBar
            }
            
            // Dia Browser address bar (AX Identifier: commandBarTextField)
            if bundleId == "company.thebrowser.dia" && isDiaAddressBar() {
                return .browserAddressBar
            }
            
            // Browser content area - treat as standard
            return .standard
        }
        
        // Code editors
        if Self.codeEditors.contains(bundleId) {
            return .codeEditor
        }
        
        // Electron apps (generic detection)
        // Most Electron apps have certain patterns in their bundle IDs
        if bundleId.contains("electron") {
            return .electronApp
        }
        
        return .standard
    }
    
    private func getIMKitBehavior(for bundleId: String, appBehavior: AppBehavior) -> IMKitBehavior {
        // Check if this app has known marked text issues
        let hasIssues = Self.markedTextProblematicApps.contains(bundleId)
        
        switch appBehavior {
        case .terminal:
            return IMKitBehavior(
                useMarkedText: !hasIssues,  // Use user preference, but warn about issues
                hasMarkedTextIssues: hasIssues,
                commitDelay: 5000,  // 5ms delay for terminals
                description: "Terminal"
            )
            
        case .browserAddressBar:
            return IMKitBehavior(
                useMarkedText: true,  // Marked text usually works in address bars
                hasMarkedTextIssues: false,
                commitDelay: 3000,
                description: "Browser Address Bar"
            )
            
        case .jetbrainsIDE:
            return IMKitBehavior(
                useMarkedText: true,
                hasMarkedTextIssues: false,
                commitDelay: 10000,  // JetBrains needs more time
                description: "JetBrains IDE"
            )
            
        case .microsoftOffice:
            return IMKitBehavior(
                useMarkedText: true,
                hasMarkedTextIssues: false,
                commitDelay: 5000,
                description: "Microsoft Office"
            )
            
        case .spotlight:
            return IMKitBehavior(
                useMarkedText: true,
                hasMarkedTextIssues: false,
                commitDelay: 3000,
                description: "Spotlight"
            )
            
        case .overlayLauncher:
            return IMKitBehavior(
                useMarkedText: true,
                hasMarkedTextIssues: false,
                commitDelay: 3000,
                description: "Overlay Launcher (Raycast/Alfred)"
            )
            
        case .codeEditor:
            return IMKitBehavior(
                useMarkedText: !hasIssues,
                hasMarkedTextIssues: hasIssues,
                commitDelay: 5000,
                description: "Code Editor"
            )
            
        case .electronApp:
            return IMKitBehavior(
                useMarkedText: true,
                hasMarkedTextIssues: true,  // Electron apps often have quirks
                commitDelay: 5000,
                description: "Electron App"
            )
            
        case .standard:
            return .standard
        }
    }
    
    // MARK: - CGEvent Injection Method Detection

    /// Detect injection method for CGEvent-based character injection (used by CharacterInjector)
    /// First checks Window Title Rules, then falls back to bundle ID based detection
    ///
    /// Note: No caching is used here because:
    /// 1. We must always call AX APIs to get current role (focus can change via keyboard)
    /// 2. The detection logic (string comparisons, Set lookups) is very fast
    /// 3. Simpler code without cache = fewer bugs
    func detectInjectionMethod() -> InjectionMethodInfo {
        // Priority 0: Check force override (set by Injection Test)
        if let forcedMethod = forceInjectionMethod {
            let delays = forceDelays ?? getDefaultDelays(for: forcedMethod)
            let textMethod = forceTextSendingMethod ?? .chunked
            return InjectionMethodInfo(
                method: forcedMethod,
                delays: delays,
                textSendingMethod: textMethod,
                description: "Forced Override (\(forcedMethod.displayName))"
            )
        }
        
        guard let bundleId = getCurrentBundleId() else {
            return .defaultFast
        }

        let currentRole = getFocusedElementInfo().role

        // Priority 0.2: Terminal panels in VSCode/Cursor/etc
        // Check directly via AX Description - doesn't go through overlay detection if it's a terminal panel (VSCode/Cursor)
        if isInTerminalPanel() {
            return InjectionMethodInfo(
                method: .slow,
                delays: Self.terminalDelays,
                textSendingMethod: .chunked,
                description: "Terminal (VSCode/Cursor)"
            )
        }
        
        // Priority 0.25: Notion Code Blocks or Unknown Role elements
        // Code blocks need higher delays and oneByOne text mode to prevent race conditions
        // Also applies to AXRole: Unknown as fallback - these are often problematic input areas
        if bundleId == "notion.id" {
            let isCodeBlock = isNotionCodeBlock()
            let isUnknownRole = currentRole == "AXUnknown" || currentRole == nil
            
            if isCodeBlock || isUnknownRole {
                return InjectionMethodInfo(
                    method: .slow,
                    delays: (20000, 50000, 15000),  // bs: 20ms, wait: 50ms, text: 15ms
                    textSendingMethod: .oneByOne,
                    description: isCodeBlock ? "Notion Code Block" : "Notion (Unknown Role Fallback)"
                )
            }
        }

        // Priority 0.3: Overlay launchers (Spotlight/Raycast/Alfred)
        // MUST check this BEFORE browser address bar and Window Title Rules because:
        // - Spotlight opens as overlay while Chrome may still be "frontmost app"
        // - Window Title Rules (like Google Docs) would match first without this check
        // - Spotlight/Raycast/Alfred need .autocomplete method
        if let overlayName = overlayAppNameProvider?() {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: InjectionMethod.autocomplete.defaultDelays,
                textSendingMethod: .chunked,
                description: "\(overlayName) (Overlay Launcher)"
            )
        }

        // Priority 0.5: Check if focused element is browser address bar
        // This takes precedence over Window Title Rules because:
        // - User might be in Google Docs tab (Window Title = "Google Docs")
        // - But clicked on address bar (focused element = Omnibox/AXTextField)
        // - Address bar needs different injection method than Google Docs content
        let isBrowserApp = Self.browserApps.contains(bundleId)
            || Self.firefoxBasedBrowsers.contains(bundleId)
            || Self.axAttributeDetectForBrowsers.contains(bundleId)
        
        if isBrowserApp {
            // Safari address bar
            if (bundleId == "com.apple.Safari" || bundleId == "com.apple.SafariTechnologyPreview")
                && isSafariAddressBar() {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: InjectionMethod.selection.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "Safari Address Bar"
                )
            }
            
            // Chromium address bar (Chrome, Edge, Brave, etc.)
            if isChromiumAddressBar() {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: InjectionMethod.selection.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "Chromium Address Bar"
                )
            }
            
            // Dia Browser address bar (AX Identifier: commandBarTextField)
            if bundleId == "company.thebrowser.dia" && isDiaAddressBar() {
                return InjectionMethodInfo(
                    method: .axDirect,
                    delays: InjectionMethod.axDirect.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "Dia Address Bar"
                )
            }
            
            // Firefox-based browsers address bar (AXDOMIdentifier: "urlbar-input")
            if Self.firefoxBasedBrowsers.contains(bundleId) && isFirefoxStyleAddressBar() {
                return InjectionMethodInfo(
                    method: .axDirect,
                    delays: InjectionMethod.axDirect.defaultDelays,
                    textSendingMethod: .oneByOne,
                    description: "Firefox Address Bar"
                )
            }
        }

        // Priority 1: Check Window Title Rules for context-specific injection method (merged cascade)
        let mergedResult = getMergedRuleResult()
        if let injectionMethod = mergedResult.injectionMethod {
            let delays: InjectionDelays
            if let d = mergedResult.injectionDelays, d.count >= 3 {
                delays = (d[0], d[1], d[2])
            } else {
                // Use centralized default delays
                delays = injectionMethod.defaultDelays
            }

            // Get text sending method from merged result, default to chunked
            let textMethod = mergedResult.textSendingMethod ?? .chunked

            return InjectionMethodInfo(
                method: injectionMethod,
                delays: delays,
                textSendingMethod: textMethod,
                description: mergedResult.displayName
            )
        }

        // Priority 2: Fall back to bundle ID based detection
        return getInjectionMethod(for: bundleId, role: currentRole)
    }
    
    /// Get default delays for an injection method
    /// Uses the centralized defaultDelays property on InjectionMethod
    private func getDefaultDelays(for method: InjectionMethod) -> InjectionDelays {
        return method.defaultDelays
    }

    private func getInjectionMethod(for bundleId: String, role: String?) -> InjectionMethodInfo {        
        // Priority 1: Selection method for autocomplete UI elements (ComboBox, SearchField)
        if role == "AXComboBox" || role == "AXSearchField" {
            return InjectionMethodInfo(
                method: .selection,
                delays: InjectionMethod.selection.defaultDelays,
                textSendingMethod: .chunked,
                description: "Selection (ComboBox/SearchField)"
            )
        }

        // Browsers with AX attribute-based address bar detection (Zen-like)
        // Address bar detected via AX Description: "Search with xx or enter address"
        // Only use axDirect for address bar, content area uses default fast method
        if Self.axAttributeDetectForBrowsers.contains(bundleId) {
            if isFirefoxStyleAddressBar() {
                return InjectionMethodInfo(
                    method: .axDirect,
                    delays: InjectionMethod.axDirect.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "Zen-style Address Bar"
                )
            }
            // Content area - use default fast method
            return InjectionMethodInfo(
                method: .fast,
                delays: InjectionMethod.fast.defaultDelays,
                textSendingMethod: .chunked,
                description: "Zen Browser Content"
            )
        }

        // Firefox-based browsers - content area handling
        // Address bar is handled by hardcoded logic in detectInjectionMethod() via isFirefoxStyleAddressBar()
        // Content area (AXWindow): use axDirect method (AX API to set text directly)
        // Note: Selection method in content area interferes with mouse word selection
        if Self.firefoxBasedBrowsers.contains(bundleId) {
            if role == "AXWindow" {
                return InjectionMethodInfo(
                    method: .axDirect,
                    delays: InjectionMethod.axDirect.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "Firefox Content Area"
                )
            }
        }

        // JetBrains IDEs
        if bundleId.hasPrefix("com.jetbrains") {
            if role == "AXTextField" {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: InjectionMethod.selection.defaultDelays,
                    textSendingMethod: .chunked,
                    description: "JetBrains TextField"
                )
            }
            return InjectionMethodInfo(
                method: .slow,
                delays: (12000, 30000, 12000),
                textSendingMethod: .chunked,
                description: "JetBrains IDE"
            )
        }
        
        // Microsoft Office
        if Self.microsoftOfficeApps.contains(bundleId) {
            // Use Fast method for all text input areas:
            // - AXTextArea: Main document/cell editing area
            // - AXLayoutArea: Excel spreadsheet area
            // - AXTextField: Dialogs like Data Validation, Find & Replace, etc.
            // 
            // Selection method (Shift+Left) doesn't work correctly in some MS Office
            // dialogs, causing unwanted characters like "+" to appear.
            if role == "AXTextArea" || role == "AXLayoutArea" || role == "AXTextField" {
                return InjectionMethodInfo(
                    method: .fast,
                    delays: (2000, 5000, 2000),
                    textSendingMethod: .chunked,
                    description: "Microsoft Office TextArea"
                )
            }
            // Other roles (unknown) - fallback to selection for safety
            return InjectionMethodInfo(
                method: .selection,
                delays: InjectionMethod.selection.defaultDelays,
                textSendingMethod: .chunked,
                description: "Microsoft Office"
            )
        }
        
        // All terminals - unified delays
        if Self.terminalApps.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: Self.terminalDelays,
                textSendingMethod: .chunked,
                description: "Terminal"
            )
        }
        
        // Apps that need fast method with oneByOne text sending
        if Self.fastOneByOneApps.contains(bundleId) {
            return InjectionMethodInfo(
                method: .fast,
                delays: InjectionMethod.fast.defaultDelays,
                textSendingMethod: .oneByOne,
                description: "Fast + OneByOne"
            )
        }
        
        // Default: fast with safe delays
        return .defaultFast
    }
}

// MARK: - Convenience Extensions

extension AppBehaviorDetector {
    
    /// Check if current app is a terminal
    var isTerminal: Bool {
        return detect() == .terminal
    }
    
    /// Check if current app is a browser
    var isBrowser: Bool {
        guard let bundleId = getCurrentBundleId() else { return false }
        return Self.browserApps.contains(bundleId)
            || Self.firefoxBasedBrowsers.contains(bundleId)
            || Self.axAttributeDetectForBrowsers.contains(bundleId)
    }
    
    /// Check if current app has marked text issues
    var hasMarkedTextIssues: Bool {
        return detectIMKitBehavior().hasMarkedTextIssues
    }
    
    /// Check if should prefer direct insertion over marked text for current app
    var shouldPreferDirectInsertion: Bool {
        let behavior = detectIMKitBehavior()
        return behavior.hasMarkedTextIssues
    }
    
    /// Check if current app needs selection method (for CharacterInjector)
    var needsSelectionMethod: Bool {
        return detectInjectionMethod().method == .selection
    }
    
    /// Check if current app needs slow injection (for CharacterInjector)
    var needsSlowInjection: Bool {
        return detectInjectionMethod().method == .slow
    }
    
    /// Check if current context needs Forward Delete with AX check before backspaces
    /// This applies to apps with autocomplete suggestions that can interfere with backspace:
    /// - Microsoft Office (Excel, Word, PowerPoint)
    /// - Google Workspace in browsers (Sheets, Docs, Slides)
    /// The AX check ensures we only send Forward Delete when there's no real text after cursor
    var needsForwardDeleteWithAXCheck: Bool {
        // Check Microsoft Office apps
        if detect() == .microsoftOffice {
            return true
        }
        
        // Check Google Workspace apps via Window Title Rules
        // These rules are matched by window title pattern "Google (Sheets|Docs|Slides|...)"
        if let ruleName = activeWindowTitleRuleName {
            let googleWorkspaceRules = ["Google Sheets"]
            for googleRule in googleWorkspaceRules {
                if ruleName.contains(googleRule) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Window Title Rule Convenience
    
    /// Check if current context has an active Window Title Rule
    var hasActiveWindowTitleRule: Bool {
        return getMergedRuleResult().hasMatches
    }
    
    /// Get the name of the active Window Title Rule(s), if any
    /// Returns all matched rule names joined with " + "
    var activeWindowTitleRuleName: String? {
        let result = getMergedRuleResult()
        return result.hasMatches ? result.displayName : nil
    }
    
    /// Get debug info for current detection state
    func getDetectionDebugInfo() -> String {
        let bundleId = getCurrentBundleId() ?? "unknown"
        let windowTitle = getCachedWindowTitle()
        let role = getFocusedElementInfo().role ?? "unknown"
        let mergedResult = getMergedRuleResult()
        let allMatchingRules = findAllMatchingRules()
        let imkitBehavior = detectIMKitBehavior()
        let injectionInfo = detectInjectionMethod()
        
        var info = """
        === App Behavior Detection ===
        Bundle ID: \(bundleId)
        Window Title: \(windowTitle.isEmpty ? "(empty)" : windowTitle)
        Focused Element Role: \(role)
        
        """
        
        if mergedResult.hasMatches {
            info += """
            ✅ Matched Window Title Rules (\(allMatchingRules.count)):
            """
            for (index, rule) in allMatchingRules.enumerated() {
                info += """
                
               [\(index + 1)] \(rule.name)
                   Pattern: "\(rule.titlePattern)" (\(rule.matchMode.rawValue))
                   Description: \(rule.description ?? "-")
            """
            }
            info += """
            
            
            📋 Merged Result:
               useMarkedText: \(mergedResult.useMarkedText.map { String($0) } ?? "nil")
               hasMarkedTextIssues: \(mergedResult.hasMarkedTextIssues.map { String($0) } ?? "nil")
               commitDelay: \(mergedResult.commitDelay.map { String($0) } ?? "nil")
               injectionMethod: \(mergedResult.injectionMethod?.rawValue ?? "nil")
               textSendingMethod: \(mergedResult.textSendingMethod?.rawValue ?? "nil")
               enableForceAccessibility: \(mergedResult.enableForceAccessibility.map { String($0) } ?? "nil")
            
            """
        } else {
            info += "❌ No Window Title Rule matched\n\n"
        }
        
        info += """
        IMKit Behavior:
           Use Marked Text: \(imkitBehavior.useMarkedText)
           Has Issues: \(imkitBehavior.hasMarkedTextIssues)
           Commit Delay: \(imkitBehavior.commitDelay)µs
           Description: \(imkitBehavior.description)
        
        Injection Method:
           Method: \(injectionInfo.method)
           Delays: backspace=\(injectionInfo.delays.backspace)µs, wait=\(injectionInfo.delays.wait)µs, text=\(injectionInfo.delays.text)µs
           Description: \(injectionInfo.description)
        """
        
        return info
    }
}
