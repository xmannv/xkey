//
//  XKeyIMController.swift
//  XKeyIM
//
//  IMKit Input Controller for Vietnamese typing
//  Provides native text composition without flickering
//

import Cocoa
import InputMethodKit
import Carbon

/// IMKit-based Vietnamese input controller
/// This is the main class that handles keyboard input for the Input Method
@objc(XKeyIMController)
class XKeyIMController: IMKInputController {

    // MARK: - Static Properties

    /// Flag to ensure pre-warming only runs once per process lifetime
    private static var hasPreWarmed = false

    // MARK: - Properties

    /// Vietnamese processing engine
    private var engine: VNEngine!
    
    /// Current composing text
    private var composingText: String = ""

    /// Current word length in document (for direct insertion mode)
    private var currentWordLength: Int = 0

    /// Start location of marked text (for marked text mode)
    private var markedTextStartLocation: Int = NSNotFound

    /// Settings from shared App Group
    private var settings: XKeyIMSettings!

    /// Last settings reload time (for debouncing)
    private var lastReloadTime: Date = .distantPast
    
    /// Effective useMarkedText value for current client
    /// This is false for overlay apps (Spotlight, Raycast, Alfred) to avoid "Enter twice" issue
    private var effectiveUseMarkedText: Bool = true
    
    /// Last known cursor selection location for detecting cursor movement
    /// When cursor moves (mouse click, arrow keys from other sources), we reset with cursorMoved flag
    private var lastKnownSelectionLocation: Int = NSNotFound
    
    /// Whether the current client has broken cursor tracking (always returns 0)
    /// Auto-detected: if after setMarkedText, selectedRange().location is still 0 when
    /// we expect it to be markedTextStartLocation + text.length, the client is broken.
    /// Examples: Warp terminal, some terminal emulators
    private var cursorTrackingBroken: Bool = false

    /// Whether the auto-detect check has already run for the current client.
    /// Without this latch, a "good" client (cursorTrackingBroken stays false forever)
    /// would pay a selectedRange() IPC round trip on every single keystroke.
    private var cursorTrackingVerified: Bool = false

    // Mirror VNEngine upperCaseStatus for IMKit paths where marked-text/cursor
    // bookkeeping can reset engine state before the next printable letter.
    // 0 = none, 1 = punctuation seen, 2 = newline, 3 = punctuation + space seen
    private var imUpperCaseStatus: UInt8 = 0
    
    /// Last known client bundle ID, used to reset cursorTrackingBroken on app switch
    private var lastClientBundleId: String = ""

    // MARK: - Initialization

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)

        // Load settings FIRST (before anything else)
        // This reads debugModeEnabled from plist to control logging
        settings = XKeyIMSettings()
        
        // Sync debug logging state BEFORE any log calls
        // This ensures prewarm timing logs are captured when debug mode is enabled
        DebugLogger.shared.isLoggingEnabled = settings.debugModeEnabled

        // Pre-warm singletons on first controller creation to eliminate cold start lag
        // This runs BEFORE any user input, so by the time user types, everything is ready
        if !Self.hasPreWarmed {
            Self.hasPreWarmed = true
            preWarmSingletons()
        }

        // Initialize engine
        engine = VNEngine()

        // Set up engine logging callback (nil while logging is off — see
        // updateEngineLogWiring)
        updateEngineLogWiring()

        // Apply engine settings from loaded settings
        applySettings()

        // Listen for settings changes from XKey app
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: Notification.Name("XKey.settingsDidChange"),
            object: nil
        )

        NSLog("XKeyIMController: Initialized")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Handle settings changed notification from XKey app
    @objc private func handleSettingsChanged(_ notification: Notification) {
        // Debounce: ignore if we just reloaded within last 0.5 seconds
        // This prevents spam when multiple notifications are sent in quick succession
        let now = Date()
        guard now.timeIntervalSince(lastReloadTime) > 0.5 else {
            // Silently skip - no need to log spam
            return
        }

        lastReloadTime = now
        // Log once per instance - settings reload will log specific changes
        reloadSettings()
    }
    
    // MARK: - Settings
    
    private func applySettings() {
        var engineSettings = VNEngine.EngineSettings()
        engineSettings.inputMethod = settings.inputMethod
        engineSettings.codeTable = settings.codeTable
        engineSettings.modernStyle = settings.modernStyle
        engineSettings.spellCheckEnabled = settings.spellCheckEnabled

        engineSettings.quickTelexEnabled = settings.quickTelexEnabled
        engineSettings.quickStartConsonantEnabled = settings.quickStartConsonantEnabled
        engineSettings.quickEndConsonantEnabled = settings.quickEndConsonantEnabled
        engineSettings.upperCaseFirstChar = settings.upperCaseFirstChar
        engineSettings.capitalizeOnlyAfterSpace = settings.capitalizeOnlyAfterSpace

        engineSettings.restoreIfWrongSpelling = settings.restoreIfWrongSpelling
        
        // Parse custom consonants string into Set<UInt16> for engine.
        // Match the main app: only enable custom consonants when the option is on.
        let customConsonantsStr = settings.customConsonantEnabled ? settings.customConsonants : ""
        engineSettings.customConsonants = VietnameseData.parseCustomConsonants(customConsonantsStr)
        
        engine.updateSettings(engineSettings)
        
        if !settings.upperCaseFirstChar {
            imUpperCaseStatus = 0
        }
    }
    
    /// Wire or unwire the engine log closure.
    /// While logging is off the callback is nil, so the engine skips building
    /// log strings entirely (they run on every keystroke; optional chaining
    /// short-circuits argument evaluation). Mirrors KeyboardEventHandler's
    /// updateEngineLogWiring in the main app.
    private func updateEngineLogWiring() {
        if DebugLogger.shared.isLoggingEnabled {
            engine.logCallback = { message in
                IMKitDebugger.shared.log(message, category: "VNEngine")
            }
        } else {
            engine.logCallback = nil
        }
    }

    /// Reload settings (called when settings change)
    private func reloadSettings() {
        // Drop SharedSettings' in-process cache first — don't rely on its own
        // distributed-notification observer having fired before this one.
        SharedSettings.shared.invalidateCache()
        settings.reload()
        applySettings()

        // Sync debug logging state - respect user's debug mode toggle
        DebugLogger.shared.isLoggingEnabled = settings.debugModeEnabled
        updateEngineLogWiring()
    }
    
    // MARK: - IMKInputController Overrides

    override func recognizedEvents(_ sender: Any!) -> Int {
        // keyDown + flagsChanged: commit the pending word the moment a modifier
        // goes DOWN, so the first ⌘/⌃ chord acts on committed text rather than a stale composition.
        return Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    /// Bundle IDs of overlay apps that should use direct mode instead of marked text
    /// This avoids the "Enter twice" issue in Spotlight and similar apps
    private static let overlayAppBundleIds: Set<String> = [
        "com.apple.Spotlight",           // Spotlight
        "com.raycast.macos",             // Raycast
        "com.runningwithcrayons.Alfred", // Alfred
        "com.runningwithcrayons.Alfred-3", // Alfred 3
    ]
    
    /// Check if current client is an overlay app that needs direct mode
    private func isOverlayApp(_ client: IMKTextInput) -> Bool {
        // bundleIdentifier() is a method on IMKTextInput that returns the client's bundle ID
        let bundleId = client.bundleIdentifier()
        if let bundleId = bundleId {
            let isOverlay = Self.overlayAppBundleIds.contains(bundleId)
            if isOverlay {
                IMKitDebugger.shared.log("Detected overlay app: \(bundleId) - using direct mode", category: "OVERLAY")
            }
            return isOverlay
        }
        return false
    }

    /// Passthrough classes: the IME behaves as OFF for these clients.
    /// - Remote desktop / VM viewers forward raw scancodes to a guest OS —
    ///   composed Vietnamese is meaningless there (guest runs its own IME).
    ///   IMKit mode has no clipboard-inject fallback, so this is unconditional
    ///   (unlike CGEvent mode's remoteDesktopInjectMode opt-in).
    /// - Apps the user excluded in XKey Settings (parity with injection mode,
    ///   KeyboardEventHandler.isCurrentAppExcluded()).
    private func isPassthroughClient(_ bundleId: String) -> Bool {
        if RemoteDesktopBundleIds.all.contains(bundleId.lowercased()) { return true }
        if settings.exclusionRulesEnabled, settings.excludedBundleIds.contains(bundleId) { return true }
        return false
    }

    /// Check if current focused element is a secure text field (password field)
    /// Secure text fields don't support IMKit marked text properly -
    /// selectedRange() always returns NSNotFound, causing duplicate characters on commit
    private func isSecureTextField(_ client: IMKTextInput) -> Bool {
        let bundleId = client.bundleIdentifier() ?? ""
        // SecurityAgent is Apple's password prompt (System Preferences, Software Update, etc.)
        if bundleId == "com.apple.SecurityAgent" {
            return true
        }
        return false
    }
    
    /// Without the tap, marked text is the only channel that composes correctly
    /// everywhere. Overlay launchers and secure fields are the two exceptions where
    /// a composition session misbehaves, so they still get plain insertion.
    private func shouldUseMarkedText(_ client: IMKTextInput) -> Bool {
        if isOverlayApp(client) { return false }
        if isSecureTextField(client) { return false }
        return true
    }
    
    private func updateIMUpperCaseStatus(character: Character) {
        guard settings.upperCaseFirstChar else { return }
        if character == "." || character == "?" || character == "!" {
            imUpperCaseStatus = 1
        } else if character == "\n" || character == "\r" {
            imUpperCaseStatus = 2
        } else if character == " " {
            if imUpperCaseStatus == 1 {
                imUpperCaseStatus = 3
            }
        } else {
            imUpperCaseStatus = 0
        }
    }
    
    private func shouldAutoCapitalizeNextLetter(_ character: Character) -> Bool {
        guard settings.upperCaseFirstChar, character.isLetter else { return false }
        let shouldCapitalize = settings.capitalizeOnlyAfterSpace
            ? (imUpperCaseStatus == 2 || imUpperCaseStatus == 3)
            : (imUpperCaseStatus >= 1)
        imUpperCaseStatus = 0
        return shouldCapitalize
    }
    
    private func resetIMUpperCaseStatus() {
        imUpperCaseStatus = 0
    }
    
    /// Handle keyboard events
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        if event.type == .flagsChanged {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                // A ⌘/⌃ chord is about to fire. In overlay panels (Spotlight/
                // Raycast) macOS does NOT route the chord's keyDown to the IME at
                // all, so the .command/.control branches below never run there —
                // this modifier-down moment is the ONLY place to finalize the
                // word. Direct mode keeps composingText empty while the ENGINE
                // still holds the word being typed: without the engine reset,
                // Cmd+A-then-type appends to the stale buffer ("nghiệm"+"thu" →
                // "nghiệmthuw" → w/r never transform → raw "thuwr" on screen).
                if let client = sender as? IMKTextInput, !composingText.isEmpty {
                    commitComposition(client)
                }
                engine.reset()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            }
            return false
        }
        guard event.type == .keyDown else { return false }

        guard let client = sender as? IMKTextInput else {
            return false
        }

        // The channel just switched (tap armed or disarmed). Finish the word in
        // progress on an explicit boundary instead of letting a desync heuristic
        // fire a keystroke later — the two channels track a word differently, so a
        // carried-over buffer describes text the new channel never wrote.
        if TapController.shared.consumeChannelChange() {
            if !composingText.isEmpty { commitComposition(client) }
            engine.reset()
            composingText = ""
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
        }

        // The tap owns the keyboard: it sees every physical key before the app does
        // and does all the typing. IMKit must not also process them — and our own
        // injected synthetic events arrive here too, so composing on them would
        // double-type. Pure pipe.
        if TapController.shared.isArmed {
            return false
        }

        // --- Early passthrough guards (passthrough decisions must come BEFORE any
        // composition work; a wrong in-place guess loses diacritics) ---

        // Secure input (password fields): never compose, never log content.
        // IsSecureEventInputEnabled() is the system-wide truth — bundle-id checks
        // (com.apple.SecurityAgent below) miss in-app password fields.
        if IsSecureEventInputEnabled() {
            if !composingText.isEmpty { commitComposition(client) }
            engine.reset()
            composingText = ""
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            return false
        }

        let earlyBundleId = client.bundleIdentifier() ?? ""
        if isPassthroughClient(earlyBundleId) {
            if !composingText.isEmpty { commitComposition(client) }
            engine.reset()
            composingText = ""
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            return false
        }

        // Update effective useMarkedText based on current client
        // For overlay apps (Spotlight, Raycast, Alfred), use direct mode to avoid "Enter twice"
        let bundleId = client.bundleIdentifier() ?? "unknown"
        let isOverlay = isOverlayApp(client)
        effectiveUseMarkedText = shouldUseMarkedText(client)
        
        // Log the first time we see a new bundle ID to debug overlay detection
        IMKitDebugger.shared.log("Client: \(bundleId), isOverlay=\(isOverlay), settings.useMarkedText=\(settings.useMarkedText), effective=\(effectiveUseMarkedText)", category: "OVERLAY")
        
        // CURSOR MOVEMENT DETECTION:
        // Detect if cursor has moved since last keystroke (mouse click, programmatic cursor move, etc.)
        // This is important because:
        // 1. User may click in middle of text and start typing - we shouldn't assume previous context
        // 2. Autocomplete/restore should not run when we don't have full context
        let currentSelection = client.selectedRange()
        let expectedLocation = lastKnownSelectionLocation
        let actualLocation = currentSelection.location

        // DEBUG: Log cursor tracking state
        IMKitDebugger.shared.log("Cursor check: actual=\(actualLocation), expected=\(expectedLocation), composing='\(composingText)', markedStart=\(markedTextStartLocation)", category: "CURSOR")

        // Check if cursor moved unexpectedly
        // Case 1: No composing text - straightforward comparison
        // Case 2: Has composing text - compare with markedTextStartLocation + composingText length
        var cursorMoved = false
        
        // Reset cursorTrackingBroken flag when switching to a different app
        if bundleId != lastClientBundleId {
            cursorTrackingBroken = false
            cursorTrackingVerified = false
            lastClientBundleId = bundleId
            IMKitDebugger.shared.log("App switched to \(bundleId), reset cursorTrackingBroken", category: "CURSOR")
        }
        
        // CRITICAL FIX: Skip cursor movement detection for:
        // 1. Overlay apps (Spotlight, Raycast, Alfred) - autocomplete changes cursor unpredictably
        // 2. Apps with broken cursor tracking (Warp, some terminals) - always report location=0
        // Without this fix, engine resets after every character, breaking Vietnamese composition
        if !isOverlay && !cursorTrackingBroken && lastKnownSelectionLocation != NSNotFound {
            if composingText.isEmpty {
                // Not composing - check if cursor jumped more than 1 position
                if actualLocation != expectedLocation && actualLocation != expectedLocation + 1 {
                    cursorMoved = true
                }
            } else {
                // Currently composing - check if cursor is outside expected marked text range
                // Expected: cursor should be at markedTextStartLocation + composingText.length
                if markedTextStartLocation != NSNotFound {
                    let expectedEnd = markedTextStartLocation + composingText.utf16.count
                    // If cursor is not at expected end, user clicked somewhere else
                    if actualLocation != expectedEnd && actualLocation != expectedEnd + 1 {
                        cursorMoved = true
                    }
                }
            }
        }
        
        if cursorMoved {
            // DEBUG: Log why cursor was detected as moved
            if composingText.isEmpty {
                IMKitDebugger.shared.log("CURSOR MOVED (no composing): actual=\(actualLocation) != expected=\(expectedLocation) or +1", category: "CURSOR")
            } else {
                let expectedEnd = markedTextStartLocation + composingText.utf16.count
                IMKitDebugger.shared.log("CURSOR MOVED (composing): actual=\(actualLocation) != expectedEnd=\(expectedEnd) or +1, markedStart=\(markedTextStartLocation)", category: "CURSOR")
            }

            // If we had composing text, we need to commit it first at its original location
            // BEFORE resetting, otherwise the marked text will be lost
            if !composingText.isEmpty && effectiveUseMarkedText {
                // Commit the current marked text at its original location
                let markedRange = client.markedRange()
                if markedRange.location != NSNotFound && markedRange.length > 0 {
                    client.insertText(composingText, replacementRange: markedRange)
                } else if markedTextStartLocation != NSNotFound {
                    let replaceRange = NSRange(location: markedTextStartLocation, length: composingText.utf16.count)
                    client.insertText(composingText, replacementRange: replaceRange)
                }
            }
            
            // Do NOT reset imUpperCaseStatus here.
            // IMKit can report false-positive cursor/desync between punctuation,
            // space, and the next letter. The local auto-cap state exists exactly
            // to survive those resets.
            engine.resetWithCursorMoved()
            composingText = ""
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
        }

        // Update last known location for next comparison
        lastKnownSelectionLocation = currentSelection.location
        
        // CRITICAL SYNC CHECK:
        // When user clicks elsewhere while having marked text, IMKit/system may auto-cancel the marked text
        // without notifying us. This causes a desync:
        // - composingText = "" (cleared by system)
        // - markedTextStartLocation = NSNotFound (cleared by system)
        // - BUT engine buffer still has old content!
        // We detect this by checking if engine has buffer content but our composingText is empty
        // NOTE: Only apply this check in marked text mode. In direct mode (overlay apps),
        // composingText is always empty but engine has valid buffer - this is expected.
        let engineWord = engine.getCurrentWord()
        if effectiveUseMarkedText && composingText.isEmpty && !engineWord.isEmpty {
            // DEBUG: Log desync detection
            IMKitDebugger.shared.log("DESYNC detected! composingText empty but engine has '\(engineWord)'. Resetting.", category: "CURSOR")
            // Do NOT reset imUpperCaseStatus here; see cursorMoved block above.
            engine.resetWithCursorMoved()
            currentWordLength = 0
        }

        // Get character info
        guard let characters = event.characters,
              let character = characters.first else {
            return false
        }

        let keyCode = UInt16(event.keyCode)

        // Detect uppercase correctly: check modifier flags
        // We need to check the actual modifiers, not rely on character case
        // because macOS might or might not apply CapsLock to the character
        let hasCapsLock = event.modifierFlags.contains(.capsLock)
        let hasShift = event.modifierFlags.contains(.shift)

        // Get the base character (without modifiers) to check if it's a letter
        let baseChar = event.charactersIgnoringModifiers?.first ?? character
        let isLetter = baseChar.isLetter

        // Determine uppercase state:
        // - If CapsLock is ON and Shift is OFF → uppercase
        // - If CapsLock is OFF and Shift is ON → uppercase
        // - If both ON or both OFF → lowercase
        // But only for letters - non-letters follow the character as-is
        // SPECIAL CASE: For number keys with Shift (Shift+2 for "@", etc.),
        // we set isUppercase=true so VNEngine treats it as a word break
        // This enables proper save/restore behavior for backspace
        let isNumberKey = (keyCode >= 0x12 && keyCode <= 0x1D && keyCode != 0x1B) // 0x1B is minus key
        let isUppercase: Bool
        if isLetter {
            // For letters: CapsLock XOR Shift = uppercase
            isUppercase = hasCapsLock != hasShift
        } else if isNumberKey && hasShift {
            // For number keys with Shift: signal to VNEngine that this is a shifted symbol
            // This makes VNEngine call handleWordBreak() instead of handleMarkKey()
            isUppercase = true
        } else {
            // For non-letters: use character's actual case
            isUppercase = character.isUppercase
        }

        // Handle modifier keys
        if event.modifierFlags.contains(.command) {
            // Cmd+key: commit composition, reset buffer, and pass through
            // This is important for Cmd+A (select all), Cmd+C, Cmd+V, etc.
            // After Cmd+A, user expects to start fresh typing, not continue previous word
            commitComposition(client)
            engine.reset()
            resetIMUpperCaseStatus()
            currentWordLength = 0
            return false
        }
        
        if event.modifierFlags.contains(.control) {
            // Ctrl+key: commit composition and reset buffer (important for Ctrl+C in terminal)
            IMKitDebugger.shared.log("CTRL+key detected - committing and re-posting event", category: "CTRL")
            
            // Only need special handling if there was composing text
            let hadComposingText = !composingText.isEmpty
            
            commitComposition(client)
            engine.reset()
            resetIMUpperCaseStatus()
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            
            // If there was composing text, IMKit may not pass through the Ctrl+key properly
            // So we manually create and post a new event to ensure terminal receives it
            if hadComposingText {
                if let src = CGEventSource(stateID: .hidSystemState),
                   let cgEvent = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(event.keyCode), keyDown: true) {
                    cgEvent.flags = .maskControl
                    cgEvent.post(tap: .cgSessionEventTap)

                    // Also post key up event
                    if let keyUpEvent = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(event.keyCode), keyDown: false) {
                        keyUpEvent.flags = .maskControl
                        keyUpEvent.post(tap: .cgSessionEventTap)
                    }
                }
                return true  // We handled it by re-posting
            }
            
            return false  // No composing text, let it pass through normally
        }
        
        // Handle special keys
        switch event.keyCode {
        case 0x33: // Backspace
            IMKitDebugger.shared.log("BACKSPACE - calling handleBackspace()", category: "BACKSPACE")
            let result = handleBackspace(client: client)
            if !result, lastKnownSelectionLocation != NSNotFound, lastKnownSelectionLocation > 0 {
                // Pass-through backspace: the client deletes one character, so the caret
                // moves BACK by one. handle() above recorded the pre-delete caret, and the
                // cursor-move check only tolerates a forward step (+1) — without this
                // prediction the next keystroke reads the caret as an unexpected jump and
                // fires resetWithCursorMoved(), wiping the buffer and the restore history.
                lastKnownSelectionLocation -= 1
            }
            IMKitDebugger.shared.log("BACKSPACE - handleBackspace returned \(result)", category: "BACKSPACE")
            return result

        case 0x24, 0x4C: // Return, Enter
            let hadComposition = !composingText.isEmpty
            IMKitDebugger.shared.log("ENTER - composingText='\(composingText)', hadComposition=\(hadComposition)", category: "ENTER")
            
            // Commit any marked text first
            commitComposition(client)
            // Reset FIRST (clears cursor-moved state + any stale pending capitalize),
            // then set the newline status so the NEXT character on the next line
            // is capitalized. Order matters: resetWithCursorMoved() clears
            // upperCaseStatus, so it must come before updateUpperCaseStatus("\n").
            engine.resetWithCursorMoved()  // Enter moves cursor to new line
            engine.updateUpperCaseStatus(character: "\n")
            updateIMUpperCaseStatus(character: "\n")
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            
            // Pass through Enter to application
            // Note: For overlay apps (Spotlight, Raycast, Alfred), effectiveUseMarkedText is false
            // so there's no marked text commit issue - Enter works in one press
            IMKitDebugger.shared.log("ENTER - committed and passing through", category: "ENTER")
            return false

        case 0x30: // Tab
            commitComposition(client)
            engine.resetWithCursorMoved()  // Tab moves cursor
            resetIMUpperCaseStatus()
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            return false

        case 0x7C, // Arrow Right
             0x7B, // Arrow Left
             0x7E, // Arrow Up
             0x7D, // Arrow Down
             0x73, // Home
             0x77, // End
             0x74, // Page Up
             0x79: // Page Down
            // Navigation keys: Commit composition to prevent losing typed word, then pass through
            if !composingText.isEmpty {
                commitComposition(client)
                engine.resetWithCursorMoved()
                resetIMUpperCaseStatus()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            } else {
                // No composition, but still mark cursor as moved
                engine.resetWithCursorMoved()
                resetIMUpperCaseStatus()
            }
            return false // Let navigation key pass through

        case 0x35: // Escape
            // Check for content: in marked text mode use composingText, in direct mode use currentWordLength
            let hasContent = effectiveUseMarkedText ? !composingText.isEmpty : currentWordLength > 0
            IMKitDebugger.shared.log("ESC - canUndo=\(engine.canUndoTyping()) hasContent=\(hasContent) composing='\(composingText)' wordLen=\(currentWordLength)", category: "ESC")
            
            // Check if we can undo Vietnamese typing
            if engine.canUndoTyping() && hasContent {
                let result = engine.undoTyping()

                // Get undone text (raw keystrokes) from result.newCharacters
                // DO NOT use getCurrentWord() because engine was already reset in undoTyping()
                let undoneText = result.newCharacters.map {
                    $0.unicode(codeTable: settings.codeTable)
                }.joined()
                IMKitDebugger.shared.log("ESC - undone text: '\(undoneText)' (from \(result.newCharacters.count) chars)", category: "ESC")

                if effectiveUseMarkedText && !undoneText.isEmpty {
                    // Marked text mode: Clear current marked text and insert raw keystrokes
                    // This shows "tieesng" instead of "tiếng"
                    client.setMarkedText(
                        "",
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: client.markedRange()
                    )
                    client.insertText(
                        undoneText,
                        replacementRange: NSRange(location: NSNotFound, length: 0)
                    )
                } else if !effectiveUseMarkedText && !undoneText.isEmpty {
                    // Direct mode (Spotlight, Raycast, Alfred): Replace current word with raw keystrokes
                    // Use the same approach as insertTextDirect() for reliability
                    let selectedRange = client.selectedRange()
                    IMKitDebugger.shared.log("ESC - direct mode undo: replacing \(currentWordLength) chars at pos \(selectedRange.location) with '\(undoneText)'", category: "ESC")
                    
                    if currentWordLength > 0 && selectedRange.location >= currentWordLength {
                        // Calculate replacement range based on tracked word length
                        let replaceRange = NSRange(
                            location: selectedRange.location - currentWordLength,
                            length: currentWordLength
                        )
                        // Atomic replacement - delete old word and insert undone text
                        client.insertText(undoneText, replacementRange: replaceRange)
                    } else {
                        // Fallback: just insert
                        client.insertText(
                            undoneText,
                            replacementRange: NSRange(location: NSNotFound, length: 0)
                        )
                    }
                }

                // Reset state after undo
                // Set currentWordLength = 0 so next ESC passes through to Spotlight
                // The undone text ("thur") is now plain text - Spotlight will handle clearing it
                composingText = ""
                currentWordLength = 0  // Don't track undone text - let Spotlight handle it
                markedTextStartLocation = NSNotFound

                IMKitDebugger.shared.log("ESC - undo completed, returning true", category: "ESC")
                return true
            } else if hasContent {
                // Has content but cannot undo (no Vietnamese diacritics) - just cancel/clear
                // Consume ESC to match native Spotlight behavior:
                // - ESC 1: Clear text (handled here)
                // - ESC 2: Close Spotlight (pass through in the 'else' branch below)
                IMKitDebugger.shared.log("ESC - no diacritics, canceling composition only", category: "ESC")
                
                if effectiveUseMarkedText {
                    cancelComposition(client)
                } else {
                    // Direct mode: clear the word using insertText with empty string
                    let selectedRange = client.selectedRange()
                    if currentWordLength > 0 && selectedRange.location >= currentWordLength {
                        let replaceRange = NSRange(
                            location: selectedRange.location - currentWordLength,
                            length: currentWordLength
                        )
                        client.insertText("", replacementRange: replaceRange)
                    }
                }
                
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
                engine.reset()
                resetIMUpperCaseStatus()
                return true  // Consume ESC - don't pass through yet
            } else {
                // No content - let ESC pass through to application
                // This allows Spotlight and other apps to close with ESC
                IMKitDebugger.shared.log("ESC - no content, passing through", category: "ESC")
                engine.reset()  // Reset engine state just in case
                resetIMUpperCaseStatus()
                return false
            }

        case 0x31: // Space
            // IMPORTANT: Check if we have composing text or tracked word length before processing word break
            // If both are empty/zero, it means:
            // 1. User just started typing, OR
            // 2. Editor autocompleted characters (e.g., ":d" → emoji)
            // In both cases, we should NOT process word break with spell check
            // because it would restore/delete the autocompleted text
            if !composingText.isEmpty || currentWordLength > 0 {
                let result = engine.processWordBreak(character: " ")

                // Check if this is a restore case (spell check failed, restore to original keystrokes)
                // In this case, result.newCharacters contains the restored text (e.g., "tieesg")
                // and result.backspaceCount > 0 indicates how many chars to delete
                let isRestoreCase = result.shouldConsume && result.backspaceCount > 0

                if isRestoreCase && effectiveUseMarkedText {
                    // Restore case in marked text mode
                    // Replace current marked text with restored text from result.newCharacters
                    let restoredText = result.newCharacters.map { $0.unicode(codeTable: .unicode) }.joined()
                    IMKitDebugger.shared.log("Space: Restore detected, replacing with '\(restoredText)' (marked text mode)", category: "SPACE")

                    // Set the restored text as marked text, then commit
                    setMarkedText(restoredText, client: client)
                    commitComposition(client)

                    // NOTE: Do NOT call engine.reset() here!
                    // processWordBreak() already calls saveWord() and startNewSession()
                    // Calling reset() would clear history, breaking backspace restore feature
                    currentWordLength = 0
                    markedTextStartLocation = NSNotFound
                    return true  // Consume Space - don't insert extra space after restore
                } else if result.shouldConsume {
                    handleResult(result, client: client)
                    commitComposition(client)
                } else {
                    commitComposition(client)
                }

                // NOTE: Do NOT call engine.reset() here!
                // processWordBreak() already handles state management:
                // - Saves word to history (for backspace restore)
                // - Sets spaceCount = 1
                // - Calls startNewSession() to clear buffer
                // Calling reset() would clear history and spaceCount, breaking backspace restore
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
                // Predict cursor after the system inserts the space. Without this,
                // the next key can look like an unexpected cursor move and clear
                // pending auto-capitalize state from the engine.
                let currentSelection = client.selectedRange()
                if currentSelection.location != NSNotFound {
                    lastKnownSelectionLocation = currentSelection.location + 1
                }
            } else {
                // No composing text or tracked word - just let space pass through.
                // Match main app behavior: even with an empty buffer, Space after
                // sentence-ending punctuation must upgrade upperCaseStatus from
                // "punctuation seen" to "punctuation + space seen".
                engine.updateUpperCaseStatus(character: " ")
                updateIMUpperCaseStatus(character: " ")
                currentWordLength = 0
                let currentSelection = client.selectedRange()
                if currentSelection.location != NSNotFound {
                    lastKnownSelectionLocation = currentSelection.location + 1
                }
            }
            return false // Let space pass through
            
        default:
            break
        }

        // NOTE: Shift+number keys (like Shift+2 for "@") are now handled by VNEngine
        // because we set isUppercase=true for these keys earlier, triggering handleWordBreak()

        // Check if this is a printable character
        // Use baseChar to check letter status (important for CapsLock)
        // IMPORTANT: Include isSymbol and isMathSymbol for characters like <, >, +, -, =
        // These are NOT considered isPunctuation in Swift but should trigger word break + commit
        let isPrintable = baseChar.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character.isMathSymbol

        if !isPrintable {
            // Non-printable - let it pass through
            return false
        }

        // Check if Vietnamese is enabled
        guard SharedSettings.shared.vietnameseEnabled else {
            return false
        }

        // Determine if this character should be processed by Vietnamese engine
        // Use centralized logic from VNEngine to ensure consistency with XKey main app
        let shouldProcessVietnamese = VNEngine.isVietnameseSpecialKey(
            character: baseChar,
            inputMethod: settings.inputMethod
        )

        // If not processing Vietnamese, commit composition and insert the character ourselves
        // IMPORTANT: Don't rely on "return false" to let system insert the character
        // because some apps may "swallow" the character after marked text is committed
        if !shouldProcessVietnamese {
            
            if !composingText.isEmpty {
                // Commit the marked text first
                commitComposition(client)
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            }
            
            // Use processWordBreak to properly handle word break
            // This saves current word to history and tracks the special character
            // so backspace can restore the word correctly
            _ = engine.processWordBreak(character: character)
            updateIMUpperCaseStatus(character: character)
            
            // CRITICAL FIX: Insert the special character ourselves
            // Don't rely on "return false" which may cause the character to be lost
            // in some apps after marked text is committed
            client.insertText(
                String(character),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            
            // No "+ 1" here, unlike the Space / pass-through branches: insertText()
            // above ALREADY put the character in, so this caret read is the post-insert
            // one. Adding 1 made the next keystroke see actual == expected - 1, which
            // the cursor-move check reads as an unexpected jump and answers with
            // resetWithCursorMoved() — wiping the history this branch's
            // processWordBreak() just saved, so a following Backspace could not
            // restore the word ("thuwr" + "4" + Backspace + "s" → "thửs").
            let currentSelection = client.selectedRange()
            if currentSelection.location != NSNotFound {
                lastKnownSelectionLocation = currentSelection.location
            }

            return true  // We handled it - don't let system insert again
        }

        // Process through Vietnamese engine
        // Pass the original character so engine can detect tone marks correctly
        // The isUppercase flag tells engine when to apply capitalization
        let effectiveIsUppercase = isUppercase || shouldAutoCapitalizeNextLetter(baseChar)
        IMKitDebugger.shared.log("BEFORE engine.processKey: char='\(character)' keyCode=0x\(String(keyCode, radix: 16)) isUpper=\(effectiveIsUppercase)", category: "ENGINE")
        let result = engine.processKey(
            character: character,
            keyCode: keyCode,
            isUppercase: effectiveIsUppercase
        )
        IMKitDebugger.shared.log("AFTER engine.processKey: shouldConsume=\(result.shouldConsume) bs=\(result.backspaceCount) newChars=\(result.newCharacters.count)", category: "ENGINE")

        // IMKit marked text mode requires ALWAYS consuming Vietnamese-eligible characters
        // This is different from Accessibility mode where we only consume when processing
        if effectiveUseMarkedText {
            if result.shouldConsume {
                // Engine processed the key
                IMKitDebugger.shared.log("Calling handleResult...", category: "TIMING")
                handleResult(result, client: client)
                IMKitDebugger.shared.log("handleResult completed", category: "TIMING")
                return true
            } else if character.isLetter {
                // Engine didn't consume, but in marked text mode we need to mark ALL letters
                // so future modifications (like "u" + "w" → "ư") work correctly

                // Get current word from engine to include this character
                let currentWord = engine.getCurrentWord()
                if !currentWord.isEmpty {
                    // Engine has buffered text - show it as marked
                    setMarkedText(currentWord, client: client)
                    return true
                } else {
                    // Engine has no buffer - just mark the single character
                    setMarkedText(String(character), client: client)
                    return true
                }
            } else if !composingText.isEmpty {
                // Non-letter character (like @, #, $) with marked text outstanding
                // Engine treated this as word break - commit marked text before passing through
                // This ensures "o" is committed when typing "o@"
                IMKitDebugger.shared.log("Word break: committing '\(composingText)' before inserting '\(character)'", category: "WORDBREAK")
                commitComposition(client)
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
                // Let the system insert the character
                return false
            }
        } else {
            // Direct insertion mode - only consume when engine says so
            if result.shouldConsume {
                handleResult(result, client: client)
                return true
            } else if character.isLetter {
                // Engine didn't consume, but we need to track word length
                // so that future replacements work correctly
                let currentWord = engine.getCurrentWord()
                if !currentWord.isEmpty {
                    // Engine has buffered the character - track its length
                    currentWordLength = currentWord.utf16.count
                    IMKitDebugger.shared.log("Direct mode: pass-through, tracking length = \(currentWordLength)", category: "DIRECT")
                }
                // CRITICAL FIX for Spotlight: Update cursor tracking BEFORE returning false
                // When we return false, the system will insert the character and cursor moves +1
                // If we don't update lastKnownSelectionLocation, next keystroke will think
                // cursor moved unexpectedly and reset the engine (clearing our buffer!)
                let currentSelection = client.selectedRange()
                lastKnownSelectionLocation = currentSelection.location + 1  // Predict cursor after insert
                
                // Let the character pass through to be inserted by the system
                return false
            }
        }

        return false
    }
    
    /// Handle engine result
    private func handleResult(_ result: VNEngine.ProcessResult, client: IMKTextInput) {
        let fullWord = engine.getCurrentWord()
        if effectiveUseMarkedText {
            setMarkedText(fullWord, client: client)
        } else {
            insertTextDirect(newText: fullWord, client: client)
        }
    }

    /// Direct insertion for clients where a composition session misbehaves
    /// (overlay launchers "Enter twice", secure fields reporting NSNotFound).
    /// Deliberately minimal: no probing, no per-app learning, no caret-liar
    /// detection — when Accessibility is granted the tap owns typing, and this
    /// path only has to be correct, not clever.
    private func insertTextDirect(newText: String, client: IMKTextInput) {
        if !composingText.isEmpty {
            client.setMarkedText("",
                                 selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            composingText = ""
        }

        let selectedRange = client.selectedRange()
        if currentWordLength > 0 && selectedRange.location >= currentWordLength {
            // Inline autocomplete (Spotlight, omnibox class) keeps its suggestion as a
            // SELECTION starting at the caret. Replacing only the typed word makes the
            // client commit that suggestion as real text first. Swallow it into the
            // range instead. cursorTrackingBroken clients report garbage here, so they
            // never widen it.
            let suggestionLength = (!cursorTrackingBroken && selectedRange.length > 0)
                ? selectedRange.length : 0
            let replaceRange = NSRange(location: selectedRange.location - currentWordLength,
                                       length: currentWordLength + suggestionLength)
            client.insertText(newText, replacementRange: replaceRange)
        } else {
            client.insertText(newText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }

        currentWordLength = newText.utf16.count
        lastKnownSelectionLocation = client.selectedRange().location
    }

    /// Set marked text (with underline) - Option 1
    /// This is the standard IMKit way - marked text replaces itself automatically
    private func setMarkedText(_ text: String, client: IMKTextInput) {
        let previousComposingLength = composingText.utf16.count

        // Track start location of marked text
        if markedTextStartLocation == NSNotFound {
            // First character - save start location
            let selectedRange = client.selectedRange()
            markedTextStartLocation = selectedRange.location
        }

        // Build replacement range based on tracked start location and previous length
        let replacementRange: NSRange
        if previousComposingLength > 0 {
            // Replace existing marked text: use tracked start location and previous length
            replacementRange = NSRange(
                location: markedTextStartLocation,
                length: previousComposingLength
            )
        } else {
            // First character - insert at current position
            replacementRange = NSRange(location: NSNotFound, length: 0)
        }

        // Create attributed string with underline-only style (no background)
        // This avoids the "highlighted" appearance and shows only underline like JOkey
        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            // Near-invisible underline: marked text's reliability without the visual
            // noise Vietnamese typists reject (some IMEs ship no underline at all).
            .underlineColor: NSColor.textColor.withAlphaComponent(0.15)
            // IMPORTANT: No backgroundColor - this prevents highlighting/bôi đen
            // IMPORTANT: No .markedClauseSegment - let the system use mark(forStyle:at:)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        // Set marked text - this will mark the ENTIRE new text with underline only
        client.setMarkedText(
            attributedText,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: replacementRange
        )

        composingText = text
        
        // Update cursor tracking: cursor is now at end of marked text
        // markedTextStartLocation + text length = expected cursor position
        if markedTextStartLocation != NSNotFound {
            let expectedCursorPos = markedTextStartLocation + text.utf16.count
            lastKnownSelectionLocation = expectedCursorPos
            
            // AUTO-DETECT broken cursor tracking:
            // After setMarkedText, the cursor should be at expectedCursorPos.
            // If selectedRange().location doesn't match, the client doesn't properly
            // track cursor position through IMKit API.
            // Common in terminal emulators: Warp (always 0), iTerm2 (off-by-1), etc.
            if !cursorTrackingVerified && expectedCursorPos > 0 {
                cursorTrackingVerified = true
                let actualAfterMark = client.selectedRange().location
                if actualAfterMark != expectedCursorPos {
                    cursorTrackingBroken = true
                    IMKitDebugger.shared.log("AUTO-DETECTED broken cursor tracking: after setMarkedText('\(text)'), selectedRange().location=\(actualAfterMark) but expected=\(expectedCursorPos). Disabling cursor movement detection for this client.", category: "CURSOR")
                }
            }
        }
    }
    
    /// Handle backspace
    private func handleBackspace(client: IMKTextInput) -> Bool {
        IMKitDebugger.shared.log("handleBackspace() - useMarkedText=\(effectiveUseMarkedText) composing='\(composingText)'", category: "BACKSPACE")

        // For marked text mode, we need to handle backspace specially
        // to delete character-by-character instead of deleting entire marked text
        if effectiveUseMarkedText && !composingText.isEmpty {
            // Process backspace in engine
            _ = engine.processBackspace()

            // Get the updated word from engine
            let currentWord = engine.getCurrentWord()
            IMKitDebugger.shared.log("handleBackspace() - currentWord after delete: '\(currentWord)'", category: "BACKSPACE")

            if currentWord.isEmpty {
                // All text deleted - clear marked text and reset
                IMKitDebugger.shared.log("handleBackspace() - clearing all marked text", category: "BACKSPACE")
                client.setMarkedText(
                    "",
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: client.markedRange()
                )
                composingText = ""
                markedTextStartLocation = NSNotFound
                engine.reset()
            } else {
                // Still have text - update marked text with new word
                IMKitDebugger.shared.log("handleBackspace() - updating marked text to '\(currentWord)'", category: "BACKSPACE")
                setMarkedText(currentWord, client: client)
            }

            IMKitDebugger.shared.log("handleBackspace() - returning true (consumed)", category: "BACKSPACE")
            return true
        }

        // Direct mode or no marked text (including after Space)
        // The client deletes the character itself; we only keep the engine in sync,
        // otherwise its buffer drifts from the screen and composition breaks after backspace.
        if !effectiveUseMarkedText {
            // Always feed the engine, exactly like the main app's handleBackspace().
            // At a word boundary (currentWordLength == 0, i.e. backspacing over the
            // space that ended the previous word) this is the call that consumes
            // spaceCount and restores the previous word from history, which is what
            // makes "type word → Space → Backspace → fix its tone" work. Calling
            // reset() here instead cleared spaceCount AND the history, so the restore
            // could never happen and the next key started a brand new word.
            _ = engine.processBackspace()
            // Resync the tracked on-screen word length with whatever the engine now
            // holds: after a restore that is the whole previous word, not one char less.
            // insertTextDirect() builds its replacement range from this value.
            currentWordLength = engine.getCurrentWord().utf16.count
            IMKitDebugger.shared.log("Direct mode backspace: wordLen now \(currentWordLength)", category: "BACKSPACE")
            return false  // Let Spotlight handle backspace natively
        }
        
        let result = engine.processBackspace()

        if result.shouldConsume {
            handleResult(result, client: client)
            return true
        }
        
        // IMPORTANT: Check if engine restored a word from history (backspace after space)
        // In this case, engine has restored the previous word but result.shouldConsume is false
        // We need to show the restored word as marked text so user can continue editing it
        let restoredWord = engine.getCurrentWord()
        if effectiveUseMarkedText && !restoredWord.isEmpty && composingText.isEmpty {

            
            // At this point:
            // - Screen still has: "previous_text word " (with trailing space)
            // - Cursor is after the space (position = end of text)
            // - Engine has restored "word" in buffer
            // - We need to: delete the space, then mark "word" as editable
            
            let currentSelection = client.selectedRange()
            let wordLength = restoredWord.utf16.count
            
            // Calculate where the word starts:
            // currentSelection.location = position after trailing space
            // We need to subtract 1 (for the space) + wordLength (for the word)
            // Example: "thử dấu " where cursor is at 8
            //   - Space is at position 7
            //   - Word "dấu" is at positions 4-6
            //   - markedTextStartLocation = 8 - 1 - 3 = 4 ✓
            let spacePosition = currentSelection.location - 1
            markedTextStartLocation = spacePosition - wordLength
            
            if markedTextStartLocation >= 0 && currentSelection.location > wordLength {

                
                // Step 1: Delete the trailing space
                // Replace the space with empty string
                let spaceRange = NSRange(location: spacePosition, length: 1)
                client.insertText("", replacementRange: spaceRange)
                
                // Step 2: Now select the word and set as marked text
                // After deleting space, the word is at the same position
                let wordRange = NSRange(location: markedTextStartLocation, length: wordLength)
                
                // Set as marked text with underline
                let attributes: [NSAttributedString.Key: Any] = [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.textColor.withAlphaComponent(0.15)
                ]
                let attributedText = NSAttributedString(string: restoredWord, attributes: attributes)
                
                client.setMarkedText(
                    attributedText,
                    selectionRange: NSRange(location: wordLength, length: 0),
                    replacementRange: wordRange
                )
                
                composingText = restoredWord
                currentWordLength = wordLength
                // Cursor is now at end of marked text (markedStart + wordLength)
                lastKnownSelectionLocation = markedTextStartLocation + wordLength
                

                return true  // Consume backspace - we handled the restore
            }
        }

        // If engine doesn't handle, reset tracking and let it pass through
        if effectiveUseMarkedText && !composingText.isEmpty {
            // Clear any remaining marked text
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            composingText = ""
        }

        currentWordLength = 0
        markedTextStartLocation = NSNotFound
        // Don't reset engine here - we want to preserve history for multiple backspaces
        return false
    }
    
    /// Commit current composition
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }

        if !composingText.isEmpty {
            // If using marked text, commit it
            if effectiveUseMarkedText {
                // IMPORTANT: Use markedRange() to get the actual range of marked text
                // Using NSNotFound may not work correctly in some apps, causing text to disappear
                // when typing special characters like <, >, + immediately after marked text
                let markedRange = client.markedRange()
                let replacementRange: NSRange
                if markedRange.location != NSNotFound && markedRange.length > 0 {
                    // Use the actual marked range for precise replacement
                    replacementRange = markedRange
                } else if markedTextStartLocation != NSNotFound {
                    // Fallback: use tracked start location and composing text length
                    replacementRange = NSRange(
                        location: markedTextStartLocation,
                        length: composingText.utf16.count
                    )
                } else {
                    // Last resort: use NSNotFound (may cause issues in some apps)
                    replacementRange = NSRange(location: NSNotFound, length: 0)
                }
                
                client.insertText(
                    composingText,
                    replacementRange: replacementRange
                )
            }
            composingText = ""
        }

        markedTextStartLocation = NSNotFound
        
        // Update cursor tracking after commit
        let newSelection = client.selectedRange()
        lastKnownSelectionLocation = newSelection.location
    }
    
    /// Cancel composition (private helper)
    private func cancelComposition(_ client: IMKTextInput) {
        if effectiveUseMarkedText && !composingText.isEmpty {
            // Clear marked text
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
        engine.reset()
    }

    /// Cancel composition (IMKit override - no client parameter)
    /// This might be called by IMKit when Esc is pressed
    override func cancelComposition() {
        IMKitDebugger.shared.log("cancelComposition() called - composing='\(composingText)' - DOING NOTHING", category: "CANCEL")
        // Do nothing - we handle Esc in handle(_:client:) instead
    }
    
    /// Called when input method is activated
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // `isSelected` decides whether this is a genuine activate or a late,
        // out-of-order one arriving after TIS already moved away (see IMEActivation).
        TapController.shared.imeDidActivate(isSelected: Self.isXKeyIMSelectedInputSource())
        reloadSettings()
        engine.resetWithCursorMoved()  // App switch - we don't know cursor context
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
        lastKnownSelectionLocation = NSNotFound  // Reset cursor tracking for new session
        cursorTrackingVerified = false  // Re-verify once per input session: a good verdict from a
                                        // previous field must not carry over to a new field whose
                                        // cursor tracking may be broken (same app, different surface)

        // Log version to debug window when XKeyIM is activated
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        IMKitDebugger.shared.log("XKeyIM v\(version) (build \(build)) activated", category: "ACTIVATE")
        
        NSLog("XKeyIMController: Activated")
    }

    /// Pre-warm lazy-loaded singletons to eliminate first-keystroke lag
    /// NSSpellChecker MUST be initialized on main thread, so we do it synchronously
    private func preWarmSingletons() {
        let overallStart = CFAbsoluteTimeGetCurrent()
        IMKitDebugger.shared.log("Starting pre-warm sequence...", category: "PREWARM")

        // 1. Pre-warm SharedSettings first (reads plist)
        var t0 = CFAbsoluteTimeGetCurrent()
        _ = SharedSettings.shared.spellCheckEnabled
        _ = SharedSettings.shared.modernStyle
        IMKitDebugger.shared.log(String(format: "SharedSettings: %.1f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000), category: "PREWARM")

        // 2. Pre-warm VNDictionaryManager - load dictionary into memory if available
        t0 = CFAbsoluteTimeGetCurrent()
        let dictionaryStyle: VNDictionaryManager.DictionaryStyle = SharedSettings.shared.modernStyle ? .dauMoi : .dauCu
        VNDictionaryManager.shared.loadIfAvailable(style: dictionaryStyle)
        IMKitDebugger.shared.log(String(format: "VNDictionaryManager: %.1f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000), category: "PREWARM")

        // NOTE: AppBehaviorDetector is no longer pre-warmed because we don't use it in handleResult()
        // User's settings.useMarkedText is used directly instead of auto-detecting app behavior
        // This eliminates the 3-5s Accessibility API lag when switching apps

        // 3. Pre-warm NSSpellChecker (biggest lag source - loads language data)
        // This MUST be done on main thread
        t0 = CFAbsoluteTimeGetCurrent()
        let spellChecker = NSSpellChecker.shared
        _ = spellChecker.checkSpelling(of: "xin", startingAt: 0, language: "vi", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        IMKitDebugger.shared.log(String(format: "NSSpellChecker: %.1f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000), category: "PREWARM")

        let totalElapsed = (CFAbsoluteTimeGetCurrent() - overallStart) * 1000
        IMKitDebugger.shared.log(String(format: "Total pre-warm time: %.1f ms", totalElapsed), category: "PREWARM")
    }
    
    /// Called when input method is deactivated
    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        // `stillSelected` decides whether this is a genuine deactivate or a late,
        // out-of-order one from a client we already left (see IMEActivation).
        TapController.shared.imeDidDeactivate(stillSelected: Self.isXKeyIMSelectedInputSource())
        super.deactivateServer(sender)
        NSLog("XKeyIMController: Deactivated")
    }

    /// Is XKeyIM the OS-selected keyboard input source right now? This is the
    /// authority IMEActivation defers to — lifecycle callbacks are only hints.
    static func isXKeyIMSelectedInputSource() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.hasPrefix("com.codetay.inputmethod.XKey")
    }
    
    /// Return candidates (not used)
    override func candidates(_ sender: Any!) -> [Any]! {
        return nil
    }

    /// Handle commands (like delete, move cursor, etc.)
    /// This is called by IMKit for certain keyboard shortcuts and commands
    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        IMKitDebugger.shared.log("didCommand(\(String(describing: aSelector))) - composing='\(composingText)'", category: "COMMAND")

        // Prevent IMKit from handling deleteBackward: (which deletes entire marked text)
        // We handle backspace in handle(_:client:) instead
        if aSelector == #selector(deleteBackward(_:)) {
            IMKitDebugger.shared.log("didCommand(deleteBackward:) - returning true to CONSUME", category: "COMMAND")
            return true  // Consume - we already handled in handle()
        }

        // Let other commands pass through
        IMKitDebugger.shared.log("didCommand(\(String(describing: aSelector))) - returning false (pass through)", category: "COMMAND")
        return false
    }

    @objc func deleteBackward(_ sender: Any?) {
        // This should not be called because we return true in didCommand
        IMKitDebugger.shared.log("deleteBackward(_:) called - THIS SHOULD NOT HAPPEN!", category: "ERROR")
    }

    /// Override to provide composition attributes (font, color, etc.)
    /// This is called by the system to get base attributes for marked text
    override func compositionAttributes(at range: NSRange) -> NSMutableDictionary {
        let attributes = NSMutableDictionary()

        // Set font to match system default
        if let font = NSFont.systemFont(ofSize: 0) as NSFont? {
            attributes[NSAttributedString.Key.font] = font
        }

        // Set text color
        attributes[NSAttributedString.Key.foregroundColor] = NSColor.textColor

        return attributes
    }

    /// Override to control marking style for different composition states
    /// This ensures underline-only appearance (no background highlight)
    override func mark(forStyle style: Int, at range: NSRange) -> [AnyHashable: Any]! {
        // Get base composition attributes (as NSMutableDictionary from superclass)
        let baseAttributes = compositionAttributes(at: range)
        var attributes: [AnyHashable: Any] = baseAttributes as? [AnyHashable: Any] ?? [:]

        // Add underline style - always use single underline (thin line)
        // kTSMHiliteConvertedText = 0: normal converted text (what we use)
        // kTSMHiliteSelectedRawText = 1: selected raw text
        // kTSMHiliteSelectedConvertedText = 2: selected converted text
        attributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[NSAttributedString.Key.underlineColor] = NSColor.textColor.withAlphaComponent(0.15)

        // Add the clause segment marker
        attributes[NSAttributedString.Key.markedClauseSegment] = NSNumber(value: style)

        // IMPORTANT: No backgroundColor - this prevents the "highlighted/bôi đen" appearance
        // This is the key difference between JOkey's underline-only and the default behavior

        return attributes
    }

    // MARK: - Menu
    
    /// Input method menu
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        
        // Vietnamese toggle
        let vnItem = NSMenuItem(
            title: SharedSettings.shared.vietnameseEnabled ? "✓ Tiếng Việt" : "Tắt Tiếng Việt",
            action: #selector(toggleVietnamese),
            keyEquivalent: ""
        )
        vnItem.target = self
        menu.addItem(vnItem)
        
        menu.addItem(NSMenuItem.separator())

        // Version info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(
            title: "Phiên bản \(version) (\(build))",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        // Open XKey settings
        let settingsItem = NSMenuItem(
            title: "Mở XKey Settings...",
            action: #selector(openXKeySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let permitted = TapController.hasEventPermission()
        let status = NSMenuItem(
            title: permitted
                ? (TapController.shared.isArmed ? "Chế độ gõ: phím thật" : "Chế độ gõ: gạch chân")
                : "Chế độ gõ: gạch chân (chưa có quyền Trợ năng)",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !permitted {
            let grant = NSMenuItem(title: "Cấp quyền Trợ năng…",
                                   action: #selector(openAccessibilitySettings), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        let reset = NSMenuItem(title: "Đặt lại & xin lại quyền Trợ năng",
                               action: #selector(resetAccessibilityGrant), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        return menu
    }
    
    @objc private func toggleVietnamese() {
        let enabled = !SharedSettings.shared.vietnameseEnabled
        SharedSettings.shared.vietnameseEnabled = enabled
        TapController.shared.applyVietnameseEnabled(enabled)
        engine.reset()
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
    }
    
    @objc private func openXKeySettings() {
        // Use URL scheme to open XKey settings directly
        // This will open the settings window, not just the app
        if let url = URL(string: "xkey://settings") {
            NSWorkspace.shared.open(url)
            NSLog("XKeyIMController: Opened xkey://settings")
        } else {
            // Fallback: Just launch the app
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

    @objc private func openAccessibilitySettings() {
        // Fires the system prompt from THIS process — it is the code identity being
        // asked about, so the prompt must not come from XKey.app.
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Recovery for a grant that exists but no longer matches this build's signature:
    /// the Settings checkbox is drawn from the bundle id while the actual check uses
    /// the requirement recorded when the grant was made, so a stale row looks enabled
    /// and still fails. Resetting our own row (no root needed — it can only REMOVE
    /// permission) lets the next prompt write a fresh one.
    /// Only ever on an explicit user click; never automatic.
    @objc private func resetAccessibilityGrant() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleId]
        try? task.run()
        task.waitUntilExit()
        openAccessibilitySettings()
    }
}

// MARK: - Settings Helper

/// Settings wrapper for XKeyIM
/// ARCHITECTURE: Uses plist file directly for reliable sync with XKey app
class XKeyIMSettings {
    
    /// App Group identifier
    /// Note: macOS Sequoia+ requires TeamID prefix for native apps outside App Store
    private let appGroup = "7E6Z9B4F2H.com.codetay.inputmethod.XKey"
    
    /// Cache of plist URL
    private lazy var plistURL: URL? = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            IMKitDebugger.shared.log("Cannot get App Group container URL", category: "SETTINGS")
            return nil
        }
        return containerURL.appendingPathComponent("Library/Preferences/\(appGroup).plist")
    }()
    
    // MARK: - Settings Properties
    
    private static let defaultCustomConsonants = "Z,F,W,J"
    
    var inputMethod: InputMethod = .telex
    var codeTable: CodeTable = .unicode
    var modernStyle: Bool = true
    var spellCheckEnabled: Bool = true

    var quickTelexEnabled: Bool = true
    var quickStartConsonantEnabled: Bool = false
    var quickEndConsonantEnabled: Bool = false
    var restoreIfWrongSpelling: Bool = true
    var upperCaseFirstChar: Bool = false
    var capitalizeOnlyAfterSpace: Bool = true
    var customConsonantEnabled: Bool = false
    var customConsonants: String = XKeyIMSettings.defaultCustomConsonants
    var useMarkedText: Bool = true  // Default to true - standard IMKit behavior
    var debugModeEnabled: Bool = false  // Controls whether XKeyIM writes to ~/XKey_Debug.log
    var exclusionRulesEnabled: Bool = false
    var excludedBundleIds: Set<String> = []
    
    init() {
        reload()
    }
    
    func reload() {
        // Read all settings from plist file
        
        // Input Method
        let oldInputMethod = inputMethod
        if let method = InputMethod(rawValue: readInt(forKey: "XKey.inputMethod")) {
            inputMethod = method
            if oldInputMethod != method {
                IMKitDebugger.shared.log("reload() - inputMethod CHANGED: \(oldInputMethod.displayName) → \(method.displayName)", category: "SETTINGS")
            }
        }
        
        // Code Table
        if let table = CodeTable(rawValue: readInt(forKey: "XKey.codeTable")) {
            codeTable = table
        }
        
        // Boolean settings
        modernStyle = readBool(forKey: "XKey.modernStyle")
        spellCheckEnabled = readBool(forKey: "XKey.spellCheckEnabled")

        quickTelexEnabled = readBool(forKey: "XKey.quickTelexEnabled", defaultValue: true)
        quickStartConsonantEnabled = readBool(forKey: "XKey.quickStartConsonantEnabled")
        quickEndConsonantEnabled = readBool(forKey: "XKey.quickEndConsonantEnabled")
        restoreIfWrongSpelling = readBool(forKey: "XKey.restoreIfWrongSpelling", defaultValue: true)
        upperCaseFirstChar = readBool(forKey: "XKey.upperCaseFirstChar")
        capitalizeOnlyAfterSpace = readBool(forKey: "XKey.capitalizeOnlyAfterSpace", defaultValue: true)
        customConsonantEnabled = readBool(forKey: "XKey.customConsonantEnabled")
        customConsonants = readString(forKey: "XKey.customConsonants") ?? XKeyIMSettings.defaultCustomConsonants
        
        // Use Marked Text
        let oldUseMarkedText = useMarkedText
        useMarkedText = readBool(forKey: "XKey.imkitUseMarkedText", defaultValue: true)
        if oldUseMarkedText != useMarkedText {
            IMKitDebugger.shared.log("reload() - useMarkedText CHANGED: \(oldUseMarkedText) → \(useMarkedText)", category: "SETTINGS")
        }
        
        // Debug Mode - controls whether XKeyIM writes to ~/XKey_Debug.log
        debugModeEnabled = readBool(forKey: "XKey.debugModeEnabled")

        // Excluded apps (parity with injection mode's exclusion rules)
        exclusionRulesEnabled = readBool(forKey: "XKey.exclusionRulesEnabled")
        if let dict = readPlistDict(), let data = dict["XKey.excludedApps"] as? Data,
           let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedBundleIds = Set(apps.map(\.bundleIdentifier))
        } else {
            excludedBundleIds = []
        }
    }
    
    // MARK: - Plist Read Helpers
    
    /// Read the entire plist dictionary
    private func readPlistDict() -> [String: Any]? {
        guard let url = plistURL,
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    /// Read an Int value from plist
    private func readInt(forKey key: String) -> Int {
        if let dict = readPlistDict(), let value = dict[key] as? Int {
            return value
        }
        return 0
    }
    
    /// Read a Bool value from plist
    private func readBool(forKey key: String, defaultValue: Bool = false) -> Bool {
        if let dict = readPlistDict() {
            if let value = dict[key] as? Bool {
                return value
            }
            if let value = dict[key] as? Int {
                return value != 0
            }
        }
        return defaultValue
    }
    
    /// Read a String value from plist
    private func readString(forKey key: String) -> String? {
        if let dict = readPlistDict(), let value = dict[key] as? String {
            return value
        }
        return nil
    }
}
