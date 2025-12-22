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
enum InjectionMethod {
    case fast           // Default: backspace + text with minimal delays
    case slow           // Terminals/IDEs: backspace + text with higher delays
    case selection      // Browser address bars: Shift+Left select + type replacement
    case autocomplete   // Spotlight: Forward Delete + backspace + text
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
        delays: (1000, 3000, 1500),
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

/// Rule for window title-based app behavior detection
/// Allows combining bundle ID and window title to identify specific contexts
/// (e.g., Google Docs opened in Safari vs regular Safari browsing)
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
    
    /// Description for debugging
    let description: String?
    
    // MARK: - Matching
    
    /// Check if this rule matches the given bundle ID and window title
    /// When titlePattern is empty, the rule matches any window of the app (skip window title check)
    func matches(bundleId: String, windowTitle: String) -> Bool {
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
        
        // If titlePattern is empty, match any window of the app (skip window title check)
        if titlePattern.isEmpty {
            return true
        }
        
        // Check window title pattern
        return matchMode.matches(title: windowTitle, pattern: titlePattern)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, name, bundleIdPattern, titlePattern, matchMode, isEnabled
        case useMarkedText, hasMarkedTextIssues, commitDelay
        case injectionMethod, injectionDelays, textSendingMethod, description
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        bundleIdPattern = try container.decode(String.self, forKey: .bundleIdPattern)
        titlePattern = try container.decode(String.self, forKey: .titlePattern)
        matchMode = try container.decode(WindowTitleMatchMode.self, forKey: .matchMode)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        useMarkedText = try container.decodeIfPresent(Bool.self, forKey: .useMarkedText)
        hasMarkedTextIssues = try container.decodeIfPresent(Bool.self, forKey: .hasMarkedTextIssues)
        commitDelay = try container.decodeIfPresent(UInt32.self, forKey: .commitDelay)
        injectionDelays = try container.decodeIfPresent([UInt32].self, forKey: .injectionDelays)
        textSendingMethod = try container.decodeIfPresent(TextSendingMethod.self, forKey: .textSendingMethod)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        // Decode injection method from string
        if let methodString = try container.decodeIfPresent(String.self, forKey: .injectionMethod) {
            switch methodString.lowercased() {
            case "fast": injectionMethod = .fast
            case "slow": injectionMethod = .slow
            case "selection": injectionMethod = .selection
            case "autocomplete": injectionMethod = .autocomplete
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
        try container.encodeIfPresent(useMarkedText, forKey: .useMarkedText)
        try container.encodeIfPresent(hasMarkedTextIssues, forKey: .hasMarkedTextIssues)
        try container.encodeIfPresent(commitDelay, forKey: .commitDelay)
        try container.encodeIfPresent(injectionDelays, forKey: .injectionDelays)
        try container.encodeIfPresent(textSendingMethod, forKey: .textSendingMethod)
        try container.encodeIfPresent(description, forKey: .description)
        
        // Encode injection method as string
        if let method = injectionMethod {
            let methodString: String
            switch method {
            case .fast: methodString = "fast"
            case .slow: methodString = "slow"
            case .selection: methodString = "selection"
            case .autocomplete: methodString = "autocomplete"
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
        useMarkedText: Bool? = nil,
        hasMarkedTextIssues: Bool? = nil,
        commitDelay: UInt32? = nil,
        injectionMethod: InjectionMethod? = nil,
        injectionDelays: [UInt32]? = nil,
        textSendingMethod: TextSendingMethod? = nil,
        description: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.bundleIdPattern = bundleIdPattern
        self.titlePattern = titlePattern
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        self.useMarkedText = useMarkedText
        self.hasMarkedTextIssues = hasMarkedTextIssues
        self.commitDelay = commitDelay
        self.injectionMethod = injectionMethod
        self.injectionDelays = injectionDelays
        self.textSendingMethod = textSendingMethod
        self.description = description
    }
}

// MARK: - App Behavior Detector

class AppBehaviorDetector {
    
    // MARK: - Singleton
    
    static let shared = AppBehaviorDetector()
    
    // MARK: - Cache
    
    private var cachedBundleId: String?
    private var cachedWindowTitle: String?
    private var cachedMatchedRule: WindowTitleRule?
    private var cachedBehavior: AppBehavior?
    private var cachedIMKitBehavior: IMKitBehavior?
    private var cachedInjectionMethod: InjectionMethodInfo?
    
    // MARK: - Window Title Rules
    
    /// User-defined custom rules (loaded from preferences)
    private var customRules: [WindowTitleRule] = []
    
    /// Built-in rules for known problematic web apps
    /// These have lower priority than custom rules
    static let builtInWindowTitleRules: [WindowTitleRule] = [
        // ============================================
        // Safari-specific rules (higher delays needed)
        // ============================================
        
        // Google Docs in Safari (needs higher delays)
        WindowTitleRule(
            name: "Google Docs (Safari)",
            bundleIdPattern: "com.apple.Safari",
            titlePattern: "Google Docs",
            matchMode: .contains,
            useMarkedText: false,
            hasMarkedTextIssues: true,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [5000, 10000, 8000],
            textSendingMethod: .oneByOne,
            description: "Google Docs in Safari - one-by-one text sending"
        ),
        
        // Google Sheets in Safari (needs higher delays)
        WindowTitleRule(
            name: "Google Sheets (Safari)",
            bundleIdPattern: "com.apple.Safari",
            titlePattern: "Google Sheets",
            matchMode: .contains,
            useMarkedText: false,
            hasMarkedTextIssues: true,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [5000, 10000, 8000],
            textSendingMethod: .oneByOne,
            description: "Google Sheets in Safari - one-by-one text sending"
        ),
        
        // ============================================
        // Firefox rules (autocomplete method)
        // ============================================
        
        // Firefox (all windows) - uses autocomplete injection like Spotlight
        WindowTitleRule(
            name: "Firefox",
            bundleIdPattern: "org.mozilla.firefox",
            titlePattern: "",  // Empty = match all windows
            matchMode: .contains,
            useMarkedText: true,
            hasMarkedTextIssues: false,
            commitDelay: 3000,
            injectionMethod: .autocomplete,
            injectionDelays: [1000, 3000, 1000],
            textSendingMethod: .chunked,
            description: "Firefox - dùng autocomplete injection (Forward Delete + backspace + text)"
        ),
        
        // Firefox Developer Edition
        WindowTitleRule(
            name: "Firefox Developer Edition",
            bundleIdPattern: "org.mozilla.firefoxdeveloperedition",
            titlePattern: "",  // Empty = match all windows
            matchMode: .contains,
            useMarkedText: true,
            hasMarkedTextIssues: false,
            commitDelay: 3000,
            injectionMethod: .autocomplete,
            injectionDelays: [1000, 3000, 1000],
            textSendingMethod: .chunked,
            description: "Firefox Developer Edition - dùng autocomplete injection"
        ),
        
        // Firefox Nightly
        WindowTitleRule(
            name: "Firefox Nightly",
            bundleIdPattern: "org.mozilla.nightly",
            titlePattern: "",  // Empty = match all windows
            matchMode: .contains,
            useMarkedText: true,
            hasMarkedTextIssues: false,
            commitDelay: 3000,
            injectionMethod: .autocomplete,
            injectionDelays: [1000, 3000, 1000],
            textSendingMethod: .chunked,
            description: "Firefox Nightly - dùng autocomplete injection"
        )
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
    
    /// Fast terminals (GPU-accelerated) - need less delay
    static let fastTerminals: Set<String> = [
        "io.alacritty", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "com.raphaelamorim.rio"
    ]
    
    /// Medium speed terminals
    static let mediumTerminals: Set<String> = [
        "com.googlecode.iterm2", "dev.warp.Warp-Stable", "co.zeit.hyper",
        "org.tabby", "com.termius-dmg.mac"
    ]
    
    /// Slow terminals (Apple Terminal)
    static let slowTerminals: Set<String> = [
        "com.apple.Terminal"
    ]
    
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
        // Firefox-based
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.waterfoxproject.waterfox",
        "io.gitlab.librewolf-community.librewolf",
        "one.ablaze.floorp",
        "org.torproject.torbrowser",
        "net.mullvad.mullvadbrowser",
        // Safari
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        // WebKit-based
        "com.kagi.kagimacOS",
        // Arc & Others
        "company.thebrowser.Browser",
        "company.thebrowser.Arc",
        "company.thebrowser.dia",
        "app.zen-browser.zen",
        "com.sigmaos.sigmaos.macos",
        "com.pushplaylabs.sidekick",
        "com.firstversionist.polypane",
        "ai.perplexity.comet",
        "com.duckduckgo.macos.browser"
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
    func detectIMKitBehavior() -> IMKitBehavior {
        guard let bundleId = getCurrentBundleId() else {
            return .standard
        }
        
        // Check cache (must also check window title for full cache validity)
        let windowTitle = getCachedWindowTitle()
        if bundleId == cachedBundleId, 
           windowTitle == cachedWindowTitle,
           let behavior = cachedIMKitBehavior {
            return behavior
        }
        
        cachedBundleId = bundleId
        cachedWindowTitle = windowTitle
        
        // Priority 1: Check Window Title Rules for context-specific behavior
        if let rule = findMatchingRule() {
            let behavior = IMKitBehavior(
                useMarkedText: rule.useMarkedText ?? true,
                hasMarkedTextIssues: rule.hasMarkedTextIssues ?? false,
                commitDelay: rule.commitDelay ?? 0,
                description: rule.name
            )
            cachedIMKitBehavior = behavior
            return behavior
        }
        
        // Priority 2: Fall back to bundle ID based detection
        let appBehavior = detectBehavior(for: bundleId)
        cachedBehavior = appBehavior
        cachedIMKitBehavior = getIMKitBehavior(for: bundleId, appBehavior: appBehavior)
        
        return cachedIMKitBehavior ?? .standard
    }
    
    /// Get current frontmost app's bundle identifier
    func getCurrentBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    
    /// Get current focused element's role using Accessibility API
    func getFocusedElementRole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            var roleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, kAXRoleAttribute as CFString, &roleVal)
            return roleVal as? String
        }
        
        return nil
    }
    
    /// Clear cache (call when app changes)
    func clearCache() {
        cachedBundleId = nil
        cachedWindowTitle = nil
        cachedMatchedRule = nil
        cachedBehavior = nil
        cachedIMKitBehavior = nil
        cachedInjectionMethod = nil
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
    func findMatchingRule() -> WindowTitleRule? {
        guard let bundleId = getCurrentBundleId() else {
            return nil
        }
        
        // Get window title (with caching)
        let windowTitle: String
        if let cached = cachedWindowTitle, bundleId == cachedBundleId {
            windowTitle = cached
        } else {
            windowTitle = getCurrentWindowTitle() ?? ""
            cachedWindowTitle = windowTitle
        }
        
        // Check cached result
        if bundleId == cachedBundleId, let rule = cachedMatchedRule {
            return rule
        }
        
        // Note: Empty window title is OK - rules with empty titlePattern will still match
        // This allows rules that apply to all windows of an app (e.g., Firefox rule)
        
        // Search in custom rules first (higher priority)
        for rule in customRules where rule.isEnabled {
            if rule.matches(bundleId: bundleId, windowTitle: windowTitle) {
                cachedMatchedRule = rule
                return rule
            }
        }
        
        // Then search in built-in rules
        for rule in Self.builtInWindowTitleRules where rule.isEnabled {
            if rule.matches(bundleId: bundleId, windowTitle: windowTitle) {
                cachedMatchedRule = rule
                return rule
            }
        }
        
        cachedMatchedRule = nil
        return nil
    }
    
    /// Check if current context has a matching Window Title Rule
    func hasMatchingWindowTitleRule() -> Bool {
        return findMatchingRule() != nil
    }
    
    /// Get current window title (cached)
    func getCachedWindowTitle() -> String {
        if let cached = cachedWindowTitle, cachedBundleId == getCurrentBundleId() {
            return cached
        }
        let title = getCurrentWindowTitle() ?? ""
        cachedWindowTitle = title
        cachedBundleId = getCurrentBundleId()
        return title
    }
    
    // MARK: - Custom Rules Management
    
    /// Load custom rules from preferences
    func loadCustomRules() {
        if let data = UserDefaults.standard.data(forKey: "WindowTitleRules"),
           let rules = try? JSONDecoder().decode([WindowTitleRule].self, from: data) {
            customRules = rules
        }
    }
    
    /// Save custom rules to preferences
    func saveCustomRules() {
        if let data = try? JSONEncoder().encode(customRules) {
            UserDefaults.standard.set(data, forKey: "WindowTitleRules")
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
    
    /// Get all built-in rules
    func getBuiltInRules() -> [WindowTitleRule] {
        return Self.builtInWindowTitleRules
    }
    
    private func detectBehavior(for bundleId: String) -> AppBehavior {
        // Spotlight
        if bundleId == "com.apple.Spotlight" {
            return .spotlight
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
        if Self.browserApps.contains(bundleId) {
            let role = getFocusedElementRole()
            if role == "AXTextField" || role == "AXComboBox" || role == "AXSearchField" {
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
    func detectInjectionMethod() -> InjectionMethodInfo {
        guard let bundleId = getCurrentBundleId() else {
            return .defaultFast
        }
        
        // Check cache (must also check window title for full cache validity)
        let windowTitle = getCachedWindowTitle()
        if bundleId == cachedBundleId,
           windowTitle == cachedWindowTitle,
           let method = cachedInjectionMethod {
            return method
        }
        
        cachedBundleId = bundleId
        cachedWindowTitle = windowTitle
        
        // Priority 1: Check Window Title Rules for context-specific injection method
        if let rule = findMatchingRule(),
           let injectionMethod = rule.injectionMethod {
            let delays: InjectionDelays
            if let d = rule.injectionDelays, d.count >= 3 {
                delays = (d[0], d[1], d[2])
            } else {
                // Default delays based on method
                switch injectionMethod {
                case .fast: delays = (1000, 3000, 1500)
                case .slow: delays = (3000, 6000, 3000)
                case .selection: delays = (1000, 3000, 2000)
                case .autocomplete: delays = (1000, 3000, 1000)
                }
            }
            
            // Get text sending method from rule, default to chunked
            let textMethod = rule.textSendingMethod ?? .chunked
            
            let info = InjectionMethodInfo(
                method: injectionMethod,
                delays: delays,
                textSendingMethod: textMethod,
                description: rule.name
            )
            cachedInjectionMethod = info
            return info
        }
        
        // Priority 2: Fall back to bundle ID based detection  
        cachedInjectionMethod = getInjectionMethod(for: bundleId)
        
        return cachedInjectionMethod ?? .defaultFast
    }
    
    private func getInjectionMethod(for bundleId: String) -> InjectionMethodInfo {
        let role = getFocusedElementRole()
        
        // Selection method for autocomplete UI elements (ComboBox, SearchField)
        if role == "AXComboBox" || role == "AXSearchField" {
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
                textSendingMethod: .chunked,
                description: "Selection (ComboBox/SearchField)"
            )
        }
        
        // Spotlight - use autocomplete method
        if bundleId == "com.apple.Spotlight" {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                textSendingMethod: .chunked,
                description: "Spotlight"
            )
        }
        
        // Browser address bars
        if Self.browserApps.contains(bundleId) && role == "AXTextField" {
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
                textSendingMethod: .chunked,
                description: "Browser Address Bar"
            )
        }
        
        // JetBrains IDEs
        if bundleId.hasPrefix("com.jetbrains") {
            if role == "AXTextField" {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: (1000, 3000, 2000),
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
            if role == "AXTextArea" {
                return InjectionMethodInfo(
                    method: .fast,
                    delays: (2000, 5000, 2000),
                    textSendingMethod: .chunked,
                    description: "Microsoft Office TextArea"
                )
            }
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
                textSendingMethod: .chunked,
                description: "Microsoft Office"
            )
        }
        
        // Fast terminals (GPU-accelerated)
        if Self.fastTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (2000, 4000, 2000),
                textSendingMethod: .chunked,
                description: "Fast Terminal (GPU)"
            )
        }
        
        // Medium terminals
        if Self.mediumTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (3000, 6000, 3000),
                textSendingMethod: .chunked,
                description: "Medium Terminal"
            )
        }
        
        // Slow terminals (Apple Terminal)
        if Self.slowTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (4000, 8000, 4000),
                textSendingMethod: .chunked,
                description: "Slow Terminal"
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
    
    // MARK: - Window Title Rule Convenience
    
    /// Check if current context has an active Window Title Rule
    var hasActiveWindowTitleRule: Bool {
        return findMatchingRule() != nil
    }
    
    /// Get the name of the active Window Title Rule, if any
    var activeWindowTitleRuleName: String? {
        return findMatchingRule()?.name
    }
    
    /// Get debug info for current detection state
    func getDetectionDebugInfo() -> String {
        let bundleId = getCurrentBundleId() ?? "unknown"
        let windowTitle = getCachedWindowTitle()
        let role = getFocusedElementRole() ?? "unknown"
        let matchedRule = findMatchingRule()
        let imkitBehavior = detectIMKitBehavior()
        let injectionInfo = detectInjectionMethod()
        
        var info = """
        === App Behavior Detection ===
        Bundle ID: \(bundleId)
        Window Title: \(windowTitle.isEmpty ? "(empty)" : windowTitle)
        Focused Element Role: \(role)
        
        """
        
        if let rule = matchedRule {
            info += """
            ✅ Matched Window Title Rule:
               Name: \(rule.name)
               Pattern: "\(rule.titlePattern)" (\(rule.matchMode.rawValue))
               Description: \(rule.description ?? "-")
            
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
