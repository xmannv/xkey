//
//  XKeyIMController.swift
//  XKeyIM
//
//  IMKit Input Controller for Vietnamese typing
//  Provides native text composition without flickering
//

import Cocoa
import InputMethodKit

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

    /// Whether currently in Vietnamese mode
    private var isVietnameseEnabled: Bool = true

    /// Last settings reload time (for debouncing)
    private var lastReloadTime: Date = .distantPast
    
    /// Effective useMarkedText value for current client
    /// This is false for overlay apps (Spotlight, Raycast, Alfred) to avoid "Enter twice" issue
    private var effectiveUseMarkedText: Bool = true

    // MARK: - Initialization

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)

        // Pre-warm singletons on first controller creation to eliminate cold start lag
        // This runs BEFORE any user input, so by the time user types, everything is ready
        if !Self.hasPreWarmed {
            Self.hasPreWarmed = true
            preWarmSingletons()
        }

        // Initialize engine
        engine = VNEngine()

        // Set up engine logging callback
        engine.logCallback = { message in
            IMKitDebugger.shared.log(message, category: "VNEngine")
        }

        // Load settings
        settings = XKeyIMSettings()
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
        engineSettings.freeMarking = settings.freeMarkEnabled
        engineSettings.restoreIfWrongSpelling = settings.restoreIfWrongSpelling
        engine.updateSettings(engineSettings)
    }
    
    /// Reload settings (called when settings change)
    private func reloadSettings() {
        settings.reload()
        applySettings()
    }
    
    // MARK: - IMKInputController Overrides
    
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
    
    /// Determine if we should use marked text for this client
    /// Returns false for overlay apps to avoid "Enter twice" issue
    private func shouldUseMarkedText(_ client: IMKTextInput) -> Bool {
        if isOverlayApp(client) {
            return false  // Use direct mode for overlay apps
        }
        return settings.useMarkedText
    }
    
    /// Handle keyboard events
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else {
            return false
        }

        guard let client = sender as? IMKTextInput else {
            return false
        }
        
        // Update effective useMarkedText based on current client
        // For overlay apps (Spotlight, Raycast, Alfred), use direct mode to avoid "Enter twice"
        let bundleId = client.bundleIdentifier() ?? "unknown"
        let isOverlay = isOverlayApp(client)
        effectiveUseMarkedText = shouldUseMarkedText(client)
        
        // Log the first time we see a new bundle ID to debug overlay detection
        IMKitDebugger.shared.log("Client: \(bundleId), isOverlay=\(isOverlay), settings.useMarkedText=\(settings.useMarkedText), effective=\(effectiveUseMarkedText)", category: "OVERLAY")

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
        let isUppercase: Bool
        if isLetter {
            // For letters: CapsLock XOR Shift = uppercase
            isUppercase = hasCapsLock != hasShift
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
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            
            // If there was composing text, IMKit may not pass through the Ctrl+key properly
            // So we manually create and post a new event to ensure terminal receives it
            if hadComposingText {
                if let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: true) {
                    cgEvent.flags = .maskControl
                    cgEvent.post(tap: .cgSessionEventTap)
                    
                    // Also post key up event
                    if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(event.keyCode), keyDown: false) {
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
            IMKitDebugger.shared.log("BACKSPACE - handleBackspace returned \(result)", category: "BACKSPACE")
            return result

        case 0x24, 0x4C: // Return, Enter
            let hadComposition = !composingText.isEmpty
            IMKitDebugger.shared.log("ENTER - composingText='\(composingText)', hadComposition=\(hadComposition)", category: "ENTER")
            
            // Commit any marked text first
            commitComposition(client)
            engine.reset()
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            
            // Pass through Enter to application
            // Note: For overlay apps (Spotlight, Raycast, Alfred), effectiveUseMarkedText is false
            // so there's no marked text commit issue - Enter works in one press
            IMKitDebugger.shared.log("ENTER - committed and passing through", category: "ENTER")
            return false

        case 0x30: // Tab
            commitComposition(client)
            engine.reset()
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
            return false

        case 0x7C: // Arrow Right
            // Commit composition like spacebar - accept the current word
            if !composingText.isEmpty {
                commitComposition(client)
                engine.reset()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            }
            return false // Let arrow key pass through for cursor movement

        case 0x7B: // Arrow Left
            // Also commit composition to prevent losing the typed word
            if !composingText.isEmpty {
                commitComposition(client)
                engine.reset()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            }
            return false // Let arrow key pass through for cursor movement

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
                    // Use the same approach as replaceTextDirect() for reliability
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
                return true  // Consume ESC - don't pass through yet
            } else {
                // No content - let ESC pass through to application
                // This allows Spotlight and other apps to close with ESC
                IMKitDebugger.shared.log("ESC - no content, passing through", category: "ESC")
                engine.reset()  // Reset engine state just in case
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

                    engine.reset()
                    currentWordLength = 0
                    markedTextStartLocation = NSNotFound
                    return true  // Consume Space - don't insert extra space after restore
                } else if result.shouldConsume {
                    handleResult(result, client: client)
                    commitComposition(client)
                } else {
                    commitComposition(client)
                }

                engine.reset()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            } else {
                // No composing text or tracked word - just reset engine and let space pass through
                // This prevents restoring autocompleted text (like emojis)
                engine.reset()
                currentWordLength = 0
            }
            return false // Let space pass through
            
        default:
            break
        }

        // Check if this is a printable character
        // Use baseChar to check letter status (important for CapsLock)
        let isPrintable = baseChar.isLetter || character.isNumber || character.isPunctuation

        if !isPrintable {
            // Non-printable - let it pass through
            return false
        }

        // Check if Vietnamese is enabled
        guard isVietnameseEnabled else {
            return false
        }

        // Determine if this character should be processed by Vietnamese engine
        // Use centralized logic from VNEngine to ensure consistency with XKey main app
        let shouldProcessVietnamese = VNEngine.isVietnameseSpecialKey(
            character: baseChar,
            inputMethod: settings.inputMethod
        )

        // If not processing Vietnamese, commit composition and let it pass through
        if !shouldProcessVietnamese {
            if !composingText.isEmpty {
                commitComposition(client)
                engine.reset()
                currentWordLength = 0
                markedTextStartLocation = NSNotFound
            } else {
                // Even if no composing text, reset engine to clear buffer
                // This prevents spell check from restoring when user types special chars
                // Example: ":d" autocompletes to emoji, then Space should not restore
                engine.reset()
                currentWordLength = 0
            }
            return false
        }

        // Process through Vietnamese engine
        // Pass the original character so engine can detect tone marks correctly
        // The isUppercase flag tells engine when to apply capitalization
        IMKitDebugger.shared.log("BEFORE engine.processKey: char='\(character)' keyCode=0x\(String(keyCode, radix: 16)) isUpper=\(isUppercase)", category: "ENGINE")
        let result = engine.processKey(
            character: character,
            keyCode: keyCode,
            isUppercase: isUppercase
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
                // Let the character pass through to be inserted by the system
                return false
            }
        }

        return false
    }
    
    /// Handle engine result
    private func handleResult(_ result: VNEngine.ProcessResult, client: IMKTextInput) {
        // OPTIMIZATION: Use user's settings directly instead of detecting app behavior
        // This eliminates Accessibility API calls that cause 3-5s lag when switching apps
        // User can control marked text mode via XKey settings
        let useMarkedText = effectiveUseMarkedText

        if useMarkedText {
            // Option 1: Marked text mode - RECOMMENDED
            // IMPORTANT: Use getCurrentWord() to get FULL word, not just delta
            // result.newCharacters only contains changed characters (e.g., "ư")
            // but we need the entire word (e.g., "thư")
            let fullWord = engine.getCurrentWord()
            setMarkedText(fullWord, client: client)
        } else {
            // Option 2: Direct replacement mode
            // IMPORTANT: Also use getCurrentWord() to get FULL word!
            // result.newCharacters only contains delta (changed chars), not full word
            // Using delta would replace "thu" with just "ư" → lose "th"!
            let fullWord = engine.getCurrentWord()
            replaceTextDirect(newText: fullWord, client: client)
        }
    }
    
    /// Replace text directly without marked text (Option 2)
    /// This method tracks the current word length and replaces it atomically
    private func replaceTextDirect(newText: String, client: IMKTextInput) {
        // IMPORTANT: Clear any existing marked text first to prevent underline
        // When useMarkedText is false, we should not have any marked text showing
        if !composingText.isEmpty {
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            composingText = ""
        }

        let selectedRange = client.selectedRange()

        // Replace the current word we've been building
        if currentWordLength > 0 && selectedRange.location >= currentWordLength {
            // Calculate replacement range based on tracked word length
            let replaceRange = NSRange(
                location: selectedRange.location - currentWordLength,
                length: currentWordLength
            )

            // Atomic replacement - delete old word and insert new word
            client.insertText(newText, replacementRange: replaceRange)
        } else {
            // First character - just insert
            client.insertText(
                newText,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }

        // Update tracked length for next character
        // Use UTF-16 count because NSRange uses UTF-16 code units
        currentWordLength = newText.utf16.count
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
            .underlineColor: NSColor.secondaryLabelColor
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

        // Direct mode or no marked text
        let result = engine.processBackspace()

        if result.shouldConsume {
            handleResult(result, client: client)
            return true
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
        engine.reset()
        return false
    }
    
    /// Commit current composition
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }

        if !composingText.isEmpty {
            // If using marked text, commit it
            if effectiveUseMarkedText {
                // Insert the final text - this replaces marked text with plain text
                // Using NSNotFound for location tells the system to replace marked text
                client.insertText(
                    composingText,
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            }
            composingText = ""
        }

        markedTextStartLocation = NSNotFound
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
        reloadSettings()
        engine.reset()
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
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
        super.deactivateServer(sender)
        NSLog("XKeyIMController: Deactivated")
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
        attributes[NSAttributedString.Key.underlineColor] = NSColor.textColor

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
        // let vnItem = NSMenuItem(
        //     title: isVietnameseEnabled ? "✓ Tiếng Việt" : "Tiếng Việt",
        //     action: #selector(toggleVietnamese),
        //     keyEquivalent: ""
        // )
        // vnItem.target = self
        // menu.addItem(vnItem)
        
        // menu.addItem(NSMenuItem.separator())

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

        return menu
    }
    
    @objc private func toggleVietnamese() {
        isVietnameseEnabled.toggle()
        engine.reset()
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
        NSLog("XKeyIMController: Vietnamese = \(isVietnameseEnabled)")
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
    
    var inputMethod: InputMethod = .telex
    var codeTable: CodeTable = .unicode
    var modernStyle: Bool = true
    var spellCheckEnabled: Bool = true

    var quickTelexEnabled: Bool = true
    var freeMarkEnabled: Bool = false
    var restoreIfWrongSpelling: Bool = true
    var useMarkedText: Bool = true  // Default to true - standard IMKit behavior
    
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
        freeMarkEnabled = readBool(forKey: "XKey.freeMarkEnabled")
        restoreIfWrongSpelling = readBool(forKey: "XKey.restoreIfWrongSpelling", defaultValue: true)
        
        // Use Marked Text
        let oldUseMarkedText = useMarkedText
        useMarkedText = readBool(forKey: "XKey.imkitUseMarkedText", defaultValue: true)
        if oldUseMarkedText != useMarkedText {
            IMKitDebugger.shared.log("reload() - useMarkedText CHANGED: \(oldUseMarkedText) → \(useMarkedText)", category: "SETTINGS")
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
}
