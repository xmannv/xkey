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
    let description: String
    
    static let defaultFast = InjectionMethodInfo(
        method: .fast,
        delays: (1000, 3000, 1500),
        description: "Default (fast)"
    )
}

// MARK: - App Behavior Detector

class AppBehaviorDetector {
    
    // MARK: - Singleton
    
    static let shared = AppBehaviorDetector()
    
    // MARK: - Cache
    
    private var cachedBundleId: String?
    private var cachedBehavior: AppBehavior?
    private var cachedIMKitBehavior: IMKitBehavior?
    private var cachedInjectionMethod: InjectionMethodInfo?
    
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
    func detectIMKitBehavior() -> IMKitBehavior {
        guard let bundleId = getCurrentBundleId() else {
            return .standard
        }
        
        // Check cache
        if bundleId == cachedBundleId, let behavior = cachedIMKitBehavior {
            return behavior
        }
        
        cachedBundleId = bundleId
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
        cachedBehavior = nil
        cachedIMKitBehavior = nil
        cachedInjectionMethod = nil
    }
    
    // MARK: - Private Methods
    
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
    func detectInjectionMethod() -> InjectionMethodInfo {
        guard let bundleId = getCurrentBundleId() else {
            return .defaultFast
        }
        
        // Check cache
        if bundleId == cachedBundleId, let method = cachedInjectionMethod {
            return method
        }
        
        cachedBundleId = bundleId
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
                description: "Selection (ComboBox/SearchField)"
            )
        }
        
        // Spotlight - use autocomplete method
        if bundleId == "com.apple.Spotlight" {
            return InjectionMethodInfo(
                method: .autocomplete,
                delays: (1000, 3000, 1000),
                description: "Spotlight"
            )
        }
        
        // Browser address bars
        if Self.browserApps.contains(bundleId) && role == "AXTextField" {
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
                description: "Browser Address Bar"
            )
        }
        
        // JetBrains IDEs
        if bundleId.hasPrefix("com.jetbrains") {
            if role == "AXTextField" {
                return InjectionMethodInfo(
                    method: .selection,
                    delays: (1000, 3000, 2000),
                    description: "JetBrains TextField"
                )
            }
            return InjectionMethodInfo(
                method: .slow,
                delays: (12000, 30000, 12000),
                description: "JetBrains IDE"
            )
        }
        
        // Microsoft Office
        if Self.microsoftOfficeApps.contains(bundleId) {
            if role == "AXTextArea" {
                return InjectionMethodInfo(
                    method: .fast,
                    delays: (2000, 5000, 2000),
                    description: "Microsoft Office TextArea"
                )
            }
            return InjectionMethodInfo(
                method: .selection,
                delays: (1000, 3000, 2000),
                description: "Microsoft Office"
            )
        }
        
        // Fast terminals (GPU-accelerated)
        if Self.fastTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (2000, 4000, 2000),
                description: "Fast Terminal (GPU)"
            )
        }
        
        // Medium terminals
        if Self.mediumTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (3000, 6000, 3000),
                description: "Medium Terminal"
            )
        }
        
        // Slow terminals (Apple Terminal)
        if Self.slowTerminals.contains(bundleId) {
            return InjectionMethodInfo(
                method: .slow,
                delays: (4000, 8000, 4000),
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
}
