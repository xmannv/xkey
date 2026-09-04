//
//  XKeyIMController.swift
//  XKeyIM
//

import Cocoa
import InputMethodKit

private struct IMKitHostCommandContext {
    let performUndo: () -> HostCommandResult
}

@objc(XKeyIMController)
class XKeyIMController: IMKInputController {
    private static var hasPreWarmed = false

    private var session: InputSession!
    private let transport = IMKitTransport()
    private let pendingContextEvents = PendingIMKitEventQueue()
    private var engine: VNEngine { session.engine }
    private lazy var appPolicyRuntime = AppPolicyRuntime(
        smartSwitchStore: session.engine.smartSwitchManager,
        windowTitleRules: { AppBehaviorDetector.shared.getCustomRules() }
    )
    private let settingsReloadDebouncer = SettingsReloadDebouncer(interval: 0.5)
    private var modifierOnlyCommandResolver = ModifierOnlyHostCommandResolver()
    private lazy var hostCommandRouter = HostCommandRouter<IMKitHostCommandContext>(
        capabilities: .xkeyIM,
        handler: { [weak self] command, context in
            self?.handleHostCommand(command, context: context) ?? .unavailable
        },
        log: { message in IMKitDebugger.shared.log(message, category: "COMMAND") }
    )

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        DebugLogger.shared.isLoggingEnabled = SharedSettings.shared.loadPreferences().debugModeEnabled
        if !Self.hasPreWarmed {
            Self.hasPreWarmed = true
            preWarmSingletons()
        }

        let preferences = runtimePreferences()
        session = InputSession(preferences: preferences)
        AppBehaviorDetector.shared.windowTitleRulesEnabled = preferences.windowTitleRulesEnabled
        AppBehaviorDetector.shared.loadCustomRules()
        refreshDictionary(for: preferences.engineSettings)
        updateEngineLogWiring()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: Notification.Name("XKey.settingsDidChange"),
            object: nil
        )
        NSLog("XKeyIMController: Initialized")
    }

    deinit {
        settingsReloadDebouncer.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func handleSettingsChanged(_ notification: Notification) {
        settingsReloadDebouncer.submit { [weak self] in self?.reloadSettings() }
    }

    private func runtimePreferences() -> RuntimePreferences {
        let preferences = SharedSettings.shared.loadPreferences()
        return RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
            windowTitleRulesEnabled: preferences.windowTitleRulesEnabled,
            remoteDesktopInjectMode: preferences.remoteDesktopInjectMode
        )
    }

    private func hostCommand(for event: NSEvent, preferences: Preferences) -> HostCommand? {
        let eventModifiers = ModifierFlags(from: event.modifierFlags)
        let relevantModifiers = eventModifiers.intersection([.control, .shift, .option, .command])
        let undoHotkey = preferences.undoTypingEnabled
            ? (preferences.undoTypingHotkey
                ?? Hotkey(keyCode: VietnameseData.KEY_ESC, modifiers: []))
            : nil
        let bindings: [(Hotkey?, HostCommand, Bool)] = [
            (preferences.toggleHotkey, .toggleVietnamese, true),
            (preferences.tempOffToolbarHotkey, .showToolbar, true),
            (preferences.convertToolHotkey, .showConvertTool, true),
            (preferences.translationEnabled ? preferences.translationHotkey : nil,
             .showTranslation, false),
            (preferences.translationEnabled ? preferences.translateToSourceHotkey : nil,
             .translateToSource, false),
            (preferences.debugHotkey, .showDebugWindow, false),
            (preferences.toggleExclusionHotkey, .toggleExclusionRules, false),
            (preferences.toggleWindowRulesHotkey, .toggleWindowTitleRules, false),
            (undoHotkey, .undoTyping, false),
        ]

        if event.type == .flagsChanged {
            let modifierOnlyBindings: [(hotkey: Hotkey, command: HostCommand)] = bindings.compactMap { hotkey, command, _ in
                guard let hotkey, hotkey.isModifierOnly else { return nil }
                return (hotkey: hotkey, command: command)
            }
            return modifierOnlyCommandResolver.update(
                modifiers: eventModifiers,
                bindings: modifierOnlyBindings
            )
        }

        guard event.type == .keyDown else { return nil }
        modifierOnlyCommandResolver.cancel()
        for (hotkey, command, requiresExactModifiers) in bindings {
            guard let hotkey, hotkey.keyCode != 0, !hotkey.isModifierOnly else { continue }
            let modifiers = requiresExactModifiers ? eventModifiers : relevantModifiers
            if event.keyCode == hotkey.keyCode, modifiers == hotkey.modifiers {
                return command
            }
        }
        return nil
    }

    private func applySettings() {
        let preferences = runtimePreferences()
        session.engine.smartSwitchManager.loadFromPlist()
        AppBehaviorDetector.shared.windowTitleRulesEnabled = preferences.windowTitleRulesEnabled
        AppBehaviorDetector.shared.loadCustomRules()
        refreshDictionary(for: preferences.engineSettings)
        session.apply(preferences)
        TapController.shared.applyVietnameseEnabled(preferences.vietnameseEnabled)
    }

    private func refreshDictionary(for settings: VNEngine.EngineSettings) {
        let style: VNDictionaryManager.DictionaryStyle = settings.modernStyle ? .dauMoi : .dauCu
        let result = DictionaryRuntime.shared.refresh(enabled: settings.spellCheckEnabled, style: style)
        guard result.didChange else { return }
        switch result.newState {
        case .unavailable(let style):
            IMKitDebugger.shared.log("Dictionary unavailable: \(style.rawValue)", category: "SETTINGS")
        case .failed(let style):
            let diagnostic = result.diagnostic.map { ": \($0)" } ?? ""
            IMKitDebugger.shared.log("Dictionary load failed: \(style.rawValue)\(diagnostic)",
                                     category: "SETTINGS")
        case .disabled, .loaded:
            break
        }
    }

    private func updateEngineLogWiring() {
        engine.logCallback = DebugLogger.shared.isLoggingEnabled
            ? { message in IMKitDebugger.shared.log(message, category: "VNEngine") }
            : nil
    }

    private func reloadSettings() {
        SharedSettings.shared.invalidateCache()
        applySettings()
        DebugLogger.shared.isLoggingEnabled = SharedSettings.shared.loadPreferences().debugModeEnabled
        updateEngineLogWiring()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    private static let overlayAppBundleIds: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.runningwithcrayons.Alfred-3",
    ]

    private func isOverlayApp(_ client: IMKTextInput) -> Bool {
        guard let bundleIdentifier = client.bundleIdentifier() else { return false }
        let isOverlay = Self.overlayAppBundleIds.contains(bundleIdentifier)
        if isOverlay {
            IMKitDebugger.shared.log("Detected overlay app: \(bundleIdentifier) - using direct mode",
                                     category: "OVERLAY")
        }
        return isOverlay
    }

    private func isPassthroughClient(_ bundleIdentifier: String) -> Bool {
        RemoteDesktopBundleIds.all.contains(bundleIdentifier.lowercased())
    }

    private func applyAppPolicy(context: AppContext) -> AppPolicyDecision {
        session.engine.smartSwitchManager.loadFromPlist()
        let preferences = runtimePreferences()
        let current = SharedSettings.shared.vietnameseEnabled
        let decision = appPolicyRuntime.evaluate(
            context: context,
            currentVietnameseEnabled: current,
            preferences: preferences
        )
        switch decision {
        case .keepCurrentLanguage:
            session.setEffectiveVietnameseEnabled(current)
        case .overrideVietnamese(let enabled):
            session.setEffectiveVietnameseEnabled(enabled)
        case .restoreVietnamese(let enabled):
            session.setEffectiveVietnameseEnabled(enabled)
            SharedSettings.shared.vietnameseEnabled = enabled
        case .disableTransformation:
            session.setEffectiveVietnameseEnabled(false)
            session.reset()
        }
        return decision
    }

    private func isSecureTextField(_ client: IMKTextInput) -> Bool {
        client.bundleIdentifier() == "com.apple.SecurityAgent"
    }

    private func shouldUseMarkedText(_ client: IMKTextInput) -> Bool {
        !isOverlayApp(client) && !isSecureTextField(client)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event,
              let client = sender as? IMKTextInput,
              let inputEvent = transport.inputEvent(from: event)
        else { return false }

        let textClient = IMKTextInputClient(client)
        if TapController.shared.consumeChannelChange() {
            transport.commitComposition(to: textClient)
            session.reset()
            transport.resetComposition(in: nil)
        }
        let secureInputEnabled = TapController.shared.evaluateSecureInput()
        if TapController.shared.isArmed { return false }
        if TapController.shared.blocksIMKitProcessingForHandoff { return false }
        if secureInputEnabled || isPassthroughClient(textClient.bundleIdentifier() ?? "") {
            transport.commitComposition(to: textClient)
            session.reset()
            transport.resetComposition(in: nil)
            return false
        }

        let matchedHostCommand = hostCommand(
            for: event,
            preferences: SharedSettings.shared.loadPreferences()
        )
        if let command = matchedHostCommand, command != .undoTyping {
            let result = hostCommandRouter.route(
                command,
                context: IMKitHostCommandContext(performUndo: { .unavailable })
            )
            return result.shouldConsumeEvent && inputEvent.kind == .keyDown
        }

        let bundleIdentifier = textClient.bundleIdentifier()
        guard let context = TapController.shared.resolvedAppContext(
            bundleIdentifier: bundleIdentifier,
            onResolved: { [weak self] context in
                guard let self else { return }
                self.pendingContextEvents.drain(
                    process: { [weak self] event, client, command in
                        self?.processInputEvent(event,
                                                client: client,
                                                context: context,
                                                matchedHostCommand: command) ?? false
                    },
                    replay: { [weak self] event, client in
                        self?.transport.replayRaw(event, to: client)
                    }
                )
            }
        ) else {
            return pendingContextEvents.append(event: inputEvent,
                                               client: textClient,
                                               command: matchedHostCommand)
        }
        return processInputEvent(inputEvent,
                                 client: textClient,
                                 context: context,
                                 matchedHostCommand: matchedHostCommand)
    }

    private func processInputEvent(_ inputEvent: InputEvent,
                                   client textClient: IMKitTextClient,
                                   context: AppContext,
                                   matchedHostCommand: HostCommand?) -> Bool {
        let appPolicyDecision = applyAppPolicy(context: context)
        let secureInputEnabled = TapController.shared.evaluateSecureInput()

        if secureInputEnabled
            || appPolicyDecision == .disableTransformation
            || isPassthroughClient(textClient.bundleIdentifier() ?? "") {
            transport.commitComposition(to: textClient)
            session.reset()
            transport.resetComposition(in: nil)
            return false
        }

        let isOverlay = Self.overlayAppBundleIds.contains(textClient.bundleIdentifier() ?? "")
        let mode: IMKitPresentationMode = isOverlay
            || textClient.bundleIdentifier() == "com.apple.SecurityAgent" ? .direct : .markedText
        IMKitDebugger.shared.log(
            "Client: \(textClient.bundleIdentifier() ?? "unknown"), isOverlay=\(isOverlay), marked=\(mode == .markedText)",
            category: "OVERLAY"
        )
        _ = transport.synchronizeCursor(in: session,
                                        client: textClient,
                                        mode: mode,
                                        detectsMovement: !isOverlay,
                                        event: inputEvent)

        if let command = matchedHostCommand {
            let result = hostCommandRouter.route(
                command,
                context: IMKitHostCommandContext(performUndo: { [weak self] in
                    guard let self else { return .unavailable }
                    let undoEvent = InputEvent(kind: .undo,
                                               keyCode: nil,
                                               characters: nil,
                                               modifiers: [],
                                               isRepeat: false)
                    let undoAction = self.session.handle(undoEvent)
                    guard undoAction != .passThrough else { return .unavailable }
                    return self.transport.apply(undoAction,
                                                event: undoEvent,
                                                session: self.session,
                                                to: textClient,
                                                mode: mode)
                        ? .handled : .unavailable
                })
            )
            if result.shouldConsumeEvent {
                return inputEvent.kind == .keyDown
            }
            if command != .undoTyping || inputEvent.keyCode != VietnameseData.KEY_ESC {
                return false
            }
        }

        if inputEvent.kind == .keyDown, inputEvent.keyCode == VietnameseData.KEY_ESC {
            let hasContent = transport.hasComposition || transport.currentWordLength > 0
            guard hasContent else {
                session.reset()
                return false
            }
            transport.cancelComposition(in: textClient, mode: mode)
            session.reset()
            return true
        }

        return transport.apply(session.handle(inputEvent),
                               event: inputEvent,
                               session: session,
                               to: textClient,
                               mode: mode)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        transport.commitComposition(to: IMKTextInputClient(client))
    }

    override func cancelComposition() {
        IMKitDebugger.shared.log("cancelComposition() called - handled by key event path",
                                 category: "CANCEL")
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        TapController.shared.imeDidActivate(isSelected: Self.isXKeyIMSelectedInputSource())
        reloadSettings()
        _ = session.handle(InputEvent(kind: .focusChanged,
                                      keyCode: nil,
                                      characters: nil,
                                      modifiers: [],
                                      isRepeat: false))
        transport.resetComposition(in: nil)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        IMKitDebugger.shared.log("XKeyIM v\(version) (build \(build)) activated",
                                 category: "ACTIVATE")
        NSLog("XKeyIMController: Activated")
    }

    private func preWarmSingletons() {
        let overallStart = CFAbsoluteTimeGetCurrent()
        IMKitDebugger.shared.log("Starting pre-warm sequence...", category: "PREWARM")

        var start = CFAbsoluteTimeGetCurrent()
        _ = SharedSettings.shared.spellCheckEnabled
        _ = SharedSettings.shared.modernStyle
        IMKitDebugger.shared.log(String(format: "SharedSettings: %.1f ms",
                                         (CFAbsoluteTimeGetCurrent() - start) * 1000),
                                 category: "PREWARM")

        start = CFAbsoluteTimeGetCurrent()
        let preferences = runtimePreferences()
        refreshDictionary(for: preferences.engineSettings)
        IMKitDebugger.shared.log(String(format: "VNDictionaryManager: %.1f ms",
                                         (CFAbsoluteTimeGetCurrent() - start) * 1000),
                                 category: "PREWARM")

        start = CFAbsoluteTimeGetCurrent()
        _ = NSSpellChecker.shared.checkSpelling(of: "xin",
                                                 startingAt: 0,
                                                 language: "vi",
                                                 wrap: false,
                                                 inSpellDocumentWithTag: 0,
                                                 wordCount: nil)
        IMKitDebugger.shared.log(String(format: "NSSpellChecker: %.1f ms",
                                         (CFAbsoluteTimeGetCurrent() - start) * 1000),
                                 category: "PREWARM")
        IMKitDebugger.shared.log(String(format: "Total pre-warm time: %.1f ms",
                                         (CFAbsoluteTimeGetCurrent() - overallStart) * 1000),
                                 category: "PREWARM")
    }

    override func deactivateServer(_ sender: Any!) {
        settingsReloadDebouncer.cancel()
        commitComposition(sender)
        pendingContextEvents.replayAll { [transport] event, client in
            transport.replayRaw(event, to: client)
        }
        session.reset()
        transport.resetComposition(in: nil)
        TapController.shared.imeDidDeactivate(stillSelected: Self.isXKeyIMSelectedInputSource())
        super.deactivateServer(sender)
        NSLog("XKeyIMController: Deactivated")
    }

    static func isXKeyIMSelectedInputSource() -> Bool {
        SystemSecureInputDetector.isXKeyIMSelectedInputSource
    }

    override func candidates(_ sender: Any!) -> [Any]! { nil }

    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        aSelector == #selector(deleteBackward(_:))
    }

    @objc func deleteBackward(_ sender: Any?) {}

    override func compositionAttributes(at range: NSRange) -> NSMutableDictionary {
        let attributes = NSMutableDictionary()
        attributes[NSAttributedString.Key.font] = NSFont.systemFont(ofSize: 0)
        attributes[NSAttributedString.Key.foregroundColor] = NSColor.textColor
        return attributes
    }

    override func mark(forStyle style: Int, at range: NSRange) -> [AnyHashable: Any]! {
        let baseAttributes = compositionAttributes(at: range)
        var attributes = baseAttributes as? [AnyHashable: Any] ?? [:]
        attributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[NSAttributedString.Key.underlineColor] =
            NSColor.textColor.withAlphaComponent(0.15)
        attributes[NSAttributedString.Key.markedClauseSegment] = NSNumber(value: style)
        return attributes
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let vietnameseItem = NSMenuItem(
            title: SharedSettings.shared.vietnameseEnabled ? "✓ Tiếng Việt" : "Tắt Tiếng Việt",
            action: #selector(toggleVietnamese),
            keyEquivalent: ""
        )
        vietnameseItem.target = self
        menu.addItem(vietnameseItem)
        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Phiên bản \(version) (\(build))",
                                     action: nil,
                                     keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let settingsItem = NSMenuItem(title: "Mở XKey Settings...",
                                      action: #selector(openXKeySettings),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let permission = TapController.eventPermissionStatus()
        let missingPermissions = [
            permission.canListen ? nil : "Input Monitoring",
            permission.canPost ? nil : "Accessibility"
        ].compactMap { $0 }
        let status = NSMenuItem(
            title: permission.isGranted
                ? (TapController.shared.isArmed ? "Chế độ gõ: phím thật" : "Chế độ gõ: gạch chân")
                : "Chế độ gõ: gạch chân (thiếu \(missingPermissions.joined(separator: ", ")))",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        if !permission.canListen {
            let grant = NSMenuItem(title: "Cấp quyền Input Monitoring…",
                                   action: #selector(openInputMonitoringSettings),
                                   keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        if !permission.canPost {
            let grant = NSMenuItem(title: "Cấp quyền Accessibility…",
                                   action: #selector(openAccessibilitySettings),
                                   keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        let reset = NSMenuItem(title: "Đặt lại & xin lại quyền Trợ năng",
                               action: #selector(resetAccessibilityGrant),
                               keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        return menu
    }

    @objc private func toggleVietnamese() {
        _ = hostCommandRouter.route(
            .toggleVietnamese,
            context: IMKitHostCommandContext(performUndo: { .unavailable })
        )
    }

    private func handleHostCommand(_ command: HostCommand,
                                   context: IMKitHostCommandContext) -> HostCommandResult {
        switch command {
        case .toggleVietnamese:
            performToggleVietnamese()
            return .handled
        case .undoTyping:
            return context.performUndo()
        case .toggleExclusionRules:
            SharedSettings.shared.exclusionRulesEnabled.toggle()
            reloadSettings()
            return .handled
        case .toggleWindowTitleRules:
            SharedSettings.shared.windowTitleRulesEnabled.toggle()
            reloadSettings()
            return .handled
        case .showTranslation, .translateToSource, .showConvertTool,
             .showSettings, .showDebugWindow, .showToolbar:
            return .unsupported
        }
    }

    private func performToggleVietnamese() {
        let enabled = !SharedSettings.shared.vietnameseEnabled
        let context = TapController.shared.appContext(
            bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        appPolicyRuntime.saveCurrentLanguage(
            enabled,
            context: context,
            preferences: runtimePreferences()
        )
        SharedSettings.shared.vietnameseEnabled = enabled
        TapController.shared.applyVietnameseEnabled(enabled)
        session.setEffectiveVietnameseEnabled(enabled)
        session.reset()
        transport.resetComposition(in: nil)
        if SharedSettings.shared.beepOnToggle { NSSound.beep() }
    }

    @objc private func openXKeySettings() {
        if let url = URL(string: "xkey://settings") {
            NSWorkspace.shared.open(url)
            NSLog("XKeyIMController: Opened xkey://settings")
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", "com.codetay.XKey"]
            do {
                try process.run()
                NSLog("XKeyIMController: Launched XKey app (fallback)")
            } catch {
                NSLog("XKeyIMController: Failed to launch XKey: \(error)")
            }
        }
    }

    @objc private func openInputMonitoringSettings() {
        _ = CGRequestListenEventAccess()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAccessibilitySettings() {
        _ = CGRequestPostEventAccess()
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func resetAccessibilityGrant() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleIdentifier]
        try? task.run()
        task.waitUntilExit()
        openAccessibilitySettings()
    }
}
