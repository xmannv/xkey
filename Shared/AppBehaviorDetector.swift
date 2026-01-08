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

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .slow: return "Slow"
        case .selection: return "Selection"
        case .autocomplete: return "Autocomplete"
        case .axDirect: return "AX Direct"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Backspace + gõ text với delay thấp (mặc định)"
        case .slow: return "Backspace + gõ text với delay cao (Terminal, IDE)"
        case .selection: return "Shift+Left select + gõ thay thế (Browser address bar)"
        case .autocomplete: return "Forward Delete + backspace + text (Spotlight, Raycast)"
        case .axDirect: return "Dùng Accessibility API trực tiếp (Firefox content area)"
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
    
    /// Override: Disable Vietnamese input for this context (nil = use default, true = disable, false = enable)
    /// When enabled, XKey will automatically disable Vietnamese typing when this rule matches
    let disableVietnameseInput: Bool?
    
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
        case injectionMethod, injectionDelays, textSendingMethod
        case disableVietnameseInput, description
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
        disableVietnameseInput = try container.decodeIfPresent(Bool.self, forKey: .disableVietnameseInput)
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
        try container.encodeIfPresent(disableVietnameseInput, forKey: .disableVietnameseInput)
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
        disableVietnameseInput: Bool? = nil,
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
        self.disableVietnameseInput = disableVietnameseInput
        self.description = description
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
        WindowTitleRule(
            name: "Google Sheets",
            bundleIdPattern: "",  // Match all browsers
            titlePattern: "Google (Sheets|Trang tính)",
            matchMode: .regex,
            useMarkedText: false,
            hasMarkedTextIssues: true,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [5000, 10000, 8000],
            textSendingMethod: .oneByOne,
            description: "Google Sheets (all browsers) - one-by-one text sending"
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
        ),
        
        // ============================================
        // Terminal rules
        // ============================================
        
        // Warp Terminal - optimized delays for modern terminal
        WindowTitleRule(
            name: "Warp Terminal",
            bundleIdPattern: "dev.warp.Warp-Stable",
            titlePattern: "",  // Empty = match all windows
            matchMode: .contains,
            useMarkedText: true,
            hasMarkedTextIssues: false,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [8000, 15000, 8000],
            textSendingMethod: .chunked,
            description: "Warp Terminal"
        ),
        
        // ============================================
        // Electron apps
        // ============================================
    
        // Notion - needs higher delays for Monaco editor
        WindowTitleRule(
            name: "Notion",
            bundleIdPattern: "notion.id",
            titlePattern: "",
            matchMode: .contains,
            useMarkedText: true,
            hasMarkedTextIssues: false,
            commitDelay: 5000,
            injectionMethod: .slow,
            injectionDelays: [12000, 25000, 12000],
            textSendingMethod: .chunked,
            description: "Notion - Monaco editor needs higher delays"
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
        
        // Priority 1: Check Window Title Rules for context-specific behavior
        if let rule = findMatchingRule() {
            return IMKitBehavior(
                useMarkedText: rule.useMarkedText ?? true,
                hasMarkedTextIssues: rule.hasMarkedTextIssues ?? false,
                commitDelay: rule.commitDelay ?? 0,
                description: rule.name
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

    /// Get current focused element's AX Description using Accessibility API
    /// - Returns: The AX Description of the focused element, or nil if not available
    func getFocusedElementDescription() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            var descVal: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, kAXDescriptionAttribute as CFString, &descVal)
            return descVal as? String
        }
        
        return nil
    }
    
    /// Get current focused element's AX Identifier (DOM ID) using Accessibility API
    /// - Returns: The AX Identifier of the focused element, or nil if not available
    func getFocusedElementIdentifier() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            var identifierVal: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, kAXIdentifierAttribute as CFString, &identifierVal)
            return identifierVal as? String
        }
        
        return nil
    }
    
    /// Check if focused element matches Zen-style address bar pattern
    /// Detection methods:
    /// 1. DOM ID/Identifier: "urlbar-input" (Firefox/Zen Browser standard)
    /// 2. AX Description Pattern: "Search with <search_engine> or enter address"
    /// - Returns: true if focused element is a Zen-style address bar
    func isFirefoxStyleAddressBar() -> Bool {
        // Check DOM ID first (most reliable for Firefox-based browsers)
        if let identifier = getFocusedElementIdentifier(), identifier == "urlbar-input" {
            return true
        }
        
        // Fallback: Check AX Description pattern
        guard let desc = getFocusedElementDescription() else { return false }
        // Regex: "Search with <anything> or enter address"
        let pattern = "^Search with .+ or enter address$"
        return desc.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Check if focused element is Safari's address bar
    /// Detection via AX Identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    /// - Returns: true if focused element is Safari's address bar
    func isSafariAddressBar() -> Bool {
        guard let identifier = getFocusedElementIdentifier() else { return false }
        return identifier == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    }
    
    /// Check if focused element is Chromium-based browser's address bar (Chrome, Edge, Brave, etc.)
    /// Detection methods:
    /// 1. AX Description: "Address and search bar"
    /// 2. AX DOM Classes: contains "OmniboxViewViews"
    /// - Returns: true if focused element is Chromium's address bar (Omnibox)
    func isChromiumAddressBar() -> Bool {
        // Check AX Description
        if let desc = getFocusedElementDescription(), desc == "Address and search bar" {
            return true
        }
        
        // Check DOM Classes for OmniboxViewViews
        if let domClasses = getFocusedElementDOMClasses(), domClasses.contains("OmniboxViewViews") {
            return true
        }
        
        return false
    }
    
    /// Check if focused element is a Terminal panel in VSCode/Cursor/etc
    /// Detection via AX Description: starts with "Terminal"
    /// - Returns: true if focused element is an integrated terminal panel
    func isInTerminalPanel() -> Bool {
        guard let desc = getFocusedElementDescription() else { return false }
        return desc.hasPrefix("Terminal")
    }
    
    /// Get current focused element's DOM Classes using Accessibility API
    /// - Returns: Array of DOM class names, or nil if not available
    func getFocusedElementDOMClasses() -> [String]? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            var domClassRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axEl, "AXDOMClassList" as CFString, &domClassRef) == .success,
               let classes = domClassRef as? [String] {
                return classes
            }
        }
        
        return nil
    }

    /// Get current focused element's text value using Accessibility API
    /// - Returns: The text value of the focused element, or nil if not available
    func getFocusedElementTextValue() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?

        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let el = focused {
            let axEl = el as! AXUIElement
            var textVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &textVal) == .success,
               let text = textVal as? String {
                return text
            }
        }

        return nil
    }

    /// Check if focused element is empty (no text or empty string)
    /// - Returns: true if focused element has no text or empty text
    func isFocusedElementEmpty() -> Bool {
        guard let text = getFocusedElementTextValue() else {
            return true  // No text value = empty
        }
        return text.isEmpty
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
    /// Note: No caching is used here because:
    /// 1. Focus can change within same window (e.g., Google Docs content → address bar)
    /// 2. Window title might change (e.g., switching tabs)
    /// 3. The detection logic (string comparisons) is very fast
    /// 4. Simpler code without cache = fewer bugs
    func findMatchingRule() -> WindowTitleRule? {
        guard let bundleId = getCurrentBundleId() else {
            return nil
        }
        
        // Always get fresh window title (no caching)
        let windowTitle = getCurrentWindowTitle() ?? ""
        
        // Note: Empty window title is OK - rules with empty titlePattern will still match
        // This allows rules that apply to all windows of an app (e.g., Firefox rule)
        
        // Search in custom rules first (higher priority)
        for rule in customRules where rule.isEnabled {
            if rule.matches(bundleId: bundleId, windowTitle: windowTitle) {
                return rule
            }
        }
        
        // Then search in built-in rules (check disabled list from preferences)
        let disabledBuiltInRules = SharedSettings.shared.getDisabledBuiltInRules()
        for rule in Self.builtInWindowTitleRules {
            // Skip if rule is disabled in preferences
            if disabledBuiltInRules.contains(rule.name) {
                continue
            }
            if rule.matches(bundleId: bundleId, windowTitle: windowTitle) {
                return rule
            }
        }
        
        return nil
    }
    
    /// Check if current context has a matching Window Title Rule
    func hasMatchingWindowTitleRule() -> Bool {
        return findMatchingRule() != nil
    }
    
    /// Check if Vietnamese input is overridden by a matching rule
    /// - Returns: A tuple (shouldOverride: Bool, disableVietnamese: Bool, ruleName: String?)
    ///   - shouldOverride: true if a rule wants to override Vietnamese input state
    ///   - disableVietnamese: true = disable Vietnamese, false = enable Vietnamese
    ///   - ruleName: name of the matching rule for logging
    func getVietnameseInputOverride() -> (shouldOverride: Bool, disableVietnamese: Bool, ruleName: String?) {
        guard let rule = findMatchingRule(),
              let disableVN = rule.disableVietnameseInput else {
            return (false, false, nil)
        }
        return (true, disableVN, rule.name)
    }
    
    /// Check if Vietnamese input is overridden for a specific bundle ID
    /// Used for overlay apps (Spotlight, Raycast, Alfred) where we need to check
    /// the overlay's rule instead of the background app's rule
    /// - Parameter bundleId: The bundle ID to check rules for
    /// - Returns: A tuple (shouldOverride: Bool, disableVietnamese: Bool, ruleName: String?)
    func getVietnameseInputOverrideForApp(bundleId: String) -> (shouldOverride: Bool, disableVietnamese: Bool, ruleName: String?) {
        // Search in custom rules first (higher priority)
        for rule in customRules where rule.isEnabled {
            if rule.matches(bundleId: bundleId, windowTitle: "") {
                if let disableVN = rule.disableVietnameseInput {
                    return (true, disableVN, rule.name)
                }
            }
        }
        
        // Then search in built-in rules
        let disabledBuiltInRules = SharedSettings.shared.getDisabledBuiltInRules()
        for rule in Self.builtInWindowTitleRules {
            if disabledBuiltInRules.contains(rule.name) {
                continue
            }
            if rule.matches(bundleId: bundleId, windowTitle: "") {
                if let disableVN = rule.disableVietnameseInput {
                    return (true, disableVN, rule.name)
                }
            }
        }
        
        return (false, false, nil)
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
    
    /// Get all built-in rules with their enabled state from preferences
    func getBuiltInRules() -> [WindowTitleRule] {
        let disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
        return Self.builtInWindowTitleRules.map { rule in
            var mutableRule = rule
            mutableRule.isEnabled = !disabledNames.contains(rule.name)
            return mutableRule
        }
    }
    
    /// Toggle a built-in rule's enabled state
    func toggleBuiltInRule(_ ruleName: String, enabled: Bool) {
        var disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
        if enabled {
            disabledNames.remove(ruleName)
        } else {
            disabledNames.insert(ruleName)
        }
        SharedSettings.shared.setDisabledBuiltInRules(disabledNames)
        clearCache()
    }
    
    /// Check if a built-in rule is enabled
    func isBuiltInRuleEnabled(_ ruleName: String) -> Bool {
        let disabledNames = SharedSettings.shared.getDisabledBuiltInRules()
        return !disabledNames.contains(ruleName)
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
            switch overlayName {
            case "Spotlight":
                return .spotlight
            case "Raycast", "Alfred":
                return .overlayLauncher
            default:
                // Unknown overlay, treat as spotlight-like
                return .spotlight
            }
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

        let currentRole = getFocusedElementRole()

        // Priority 0.2: Terminal panels in VSCode/Cursor/etc
        // Check directly via AX Description - doesn't go through overlay detection
        if isInTerminalPanel() {
            return InjectionMethodInfo(
                method: .slow,
                delays: (3000, 6000, 3000),
                textSendingMethod: .chunked,
                description: "Terminal (VSCode/Cursor)"
            )
        }

        // Priority 0.3: Overlay launchers (Spotlight/Raycast/Alfred)
        // MUST check this BEFORE browser address bar and Window Title Rules because:
        // - Spotlight opens as overlay while Chrome may still be "frontmost app"
        // - Window Title Rules (like Google Docs) would match first without this check
        // - Spotlight/Raycast/Alfred need .autocomplete method
        if let overlayName = overlayAppNameProvider?() {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
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
                    delays: (1000, 3000, 2000),
                    textSendingMethod: .chunked,
                    description: "Safari Address Bar"
                )
            }
            
            // Chromium address bar (Chrome, Edge, Brave, etc.)
            if isChromiumAddressBar() {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: (1000, 3000, 2000),
                    textSendingMethod: .chunked,
                    description: "Chromium Address Bar"
                )
            }
            
            // Firefox-style address bar
            if Self.firefoxBasedBrowsers.contains(bundleId) || Self.axAttributeDetectForBrowsers.contains(bundleId) {
                if isFirefoxStyleAddressBar() {
                    let method: InjectionMethod = Self.axAttributeDetectForBrowsers.contains(bundleId) ? .axDirect : .selection
                    return InjectionMethodInfo(
                        method: method,
                        delays: (1000, 3000, 2000),
                        textSendingMethod: .chunked,
                        description: "Firefox-style Address Bar"
                    )
                }
            }
        }

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
                case .axDirect: delays = (1000, 3000, 2000)
                }
            }

            // Get text sending method from rule, default to chunked
            let textMethod = rule.textSendingMethod ?? .chunked

            return InjectionMethodInfo(
                method: injectionMethod,
                delays: delays,
                textSendingMethod: textMethod,
                description: rule.name
            )
        }

        // Priority 2: Fall back to bundle ID based detection
        return getInjectionMethod(for: bundleId, role: currentRole)
    }
    
    /// Get default delays for an injection method
    private func getDefaultDelays(for method: InjectionMethod) -> InjectionDelays {
        switch method {
        case .fast: return (1000, 3000, 1500)
        case .slow: return (3000, 6000, 3000)
        case .selection: return (1000, 3000, 2000)
        case .autocomplete: return (1000, 3000, 1000)
        case .axDirect: return (1000, 3000, 2000)
        }
    }

    private func getInjectionMethod(for bundleId: String, role: String?) -> InjectionMethodInfo {
        
        // Priority 0: Terminal panels in VSCode/Cursor/etc
        // Check directly via AX Description - doesn't go through overlay detection
        if isInTerminalPanel() {
            return InjectionMethodInfo(
                method: .slow,
                delays: (3000, 6000, 3000),
                textSendingMethod: .chunked,
                description: "Terminal (VSCode/Cursor)"
            )
        }
        
        // Priority 1: Overlay launchers (Spotlight/Raycast/Alfred) - use autocomplete method
        // MUST check this BEFORE AXComboBox/AXSearchField because Spotlight uses AXSearchField role
        if let overlayName = overlayAppNameProvider?() {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                textSendingMethod: .chunked,
                description: "\(overlayName) (Overlay Launcher)"
            )
        }
        
        // Priority 2: Fallback bundle ID check for Spotlight/Raycast/Alfred
        // (in case overlay provider is not available)
        if bundleId == "com.apple.Spotlight" {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                textSendingMethod: .chunked,
                description: "Spotlight"
            )
        }
        
        if bundleId == "com.raycast.macos" {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                textSendingMethod: .chunked,
                description: "Raycast"
            )
        }
        
        if bundleId.contains("com.runningwithcrayons.Alfred") {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                textSendingMethod: .chunked,
                description: "Alfred"
            )
        }
        
        // Priority 3: Selection method for autocomplete UI elements (ComboBox, SearchField)
        // Note: This comes AFTER Spotlight/Raycast/Alfred check to avoid conflict
        if role == "AXComboBox" || role == "AXSearchField" {
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
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
                    delays: (1000, 3000, 2000),
                    textSendingMethod: .chunked,
                    description: "Zen-style Address Bar"
                )
            }
            // Content area - use default fast method
            return InjectionMethodInfo(
                method: .fast,
                delays: (1000, 3000, 1500),
                textSendingMethod: .chunked,
                description: "Zen Browser Content"
            )
        }

        // Firefox-based browsers - special handling for content area vs address bar
        // Address bar (AXTextField): use selection method
        // Content area (AXWindow): use axDirect method (AX API to set text directly)
        // Note: Selection method in content area interferes with mouse word selection
        if Self.firefoxBasedBrowsers.contains(bundleId) {
            if role == "AXTextField" {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: (1000, 3000, 2000),
                    textSendingMethod: .chunked,
                    description: "Firefox Address Bar"
                )
            } else if role == "AXWindow" {
                return InjectionMethodInfo(
                    method: .axDirect,
                    delays: (1000, 3000, 2000),
                    textSendingMethod: .chunked,
                    description: "Firefox Content Area"
                )
            }
        }

        // Browser address bars (non-Firefox)
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
            if role == "AXTextArea" || role == "AXLayoutArea" {
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
                delays: (12000, 30000, 6000),
                textSendingMethod: .oneByOne,
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
