//
//  CharacterInjector.swift
//  XKey
//
//  Injects Vietnamese characters into the system
//

import Cocoa
import Carbon

// MARK: - Event Marker
// Used to identify events injected by XKey - prevents re-processing by event tap
// This is critical for avoiding race conditions in terminal apps
let kXKeyEventMarker: Int64 = 0x584B4559  // "XKEY" in hex
let kXKeyHIDSeenMarker: Int64 = 0x584B4849  // "XKHI" in hex - marks events seen by HID tap

// MARK: - Injection Method
// NOTE: InjectionMethod, InjectionDelays, and InjectionMethodInfo are defined in
// Shared/AppBehaviorDetector.swift (Single Source of Truth)

class CharacterInjector {
    
    // MARK: - Properties
    
    private var eventSource: CGEventSource?
    private var isTypingMidSentence: Bool = false  // Track if user moved cursor (typing in middle of text)
    /// Semaphore to ensure injection completes before next keystroke is processed
    /// This prevents race conditions where backspace arrives before previous injection is rendered
    private let injectionSemaphore = DispatchSemaphore(value: 1)
    /// Serial queue used only for slow injection paths that already post directly to
    /// `.cgSessionEventTap`; proxy-based paths remain synchronous on the tap callback.
    private let slowInjectionQueue = DispatchQueue(label: "com.codetay.XKey.slow-injection", qos: .userInteractive)
    
    // Debug callback
    var debugCallback: ((String) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Use .privateState to isolate injected events from system event state
        eventSource = CGEventSource(stateID: .privateState)
    }
    /// Mark as new input session (call when cursor moves or new field focused)
    /// - Parameters:
    ///   - cursorMoved: true if cursor was moved by user (mouse click or arrow keys)
    ///   - preserveMidSentence: if true, keep current isTypingMidSentence value (for Escape undo, Forward Delete, etc.)
    func markNewSession(cursorMoved: Bool = false, preserveMidSentence: Bool = false) {
        if !preserveMidSentence {
            isTypingMidSentence = cursorMoved  // If cursor moved, we're likely typing in middle of text
        }
        debugCallback?("New session: isTypingMidSentence=\(isTypingMidSentence), cursorMoved=\(cursorMoved), preserved=\(preserveMidSentence)")
    }
    
    /// Check if currently typing in middle of sentence (cursor was moved)
    func getIsTypingMidSentence() -> Bool {
        return isTypingMidSentence
    }
    
    /// Reset mid-sentence flag (call when starting fresh input, e.g., new text field)
    func resetMidSentenceFlag() {
        isTypingMidSentence = false
        debugCallback?("Reset mid-sentence flag: isTypingMidSentence=false")
    }
    /// Wait for previous injection to complete (call BEFORE processing next keystroke)
    /// Uses semaphore to ensure 100% synchronization (better than cooldown timer)
    func waitForInjectionComplete() {
        // Timing is only useful for verbose diagnostics. In normal operation this runs
        // at the event-tap boundary for every physical event, so avoid two clock reads.
        guard debugCallback != nil else {
            injectionSemaphore.wait()
            injectionSemaphore.signal()
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        injectionSemaphore.wait()
        injectionSemaphore.signal()
        let waitTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if waitTimeMs > 0.5 {
            debugCallback?("    → Waited \(String(format: "%.1f", waitTimeMs))ms for previous injection")
        }
    }
    
    /// Begin injection (call at start of injection)
    private func beginInjection() {
        injectionSemaphore.wait()
    }
    
    /// End injection (call at end of injection)
    private func endInjection() {
        injectionSemaphore.signal()
    }
    
    // MARK: - Synchronized Injection

    /// Route injection through the smallest safe non-blocking path.
    ///
    /// Only plain `.slow` one-by-one/chunked injections run on the serial queue. Those
    /// paths already post every event directly to `.cgSessionEventTap`, so moving them
    /// off the event-tap callback does not change their posting behavior. Any path that
    /// may use `CGEventTapProxy` remains synchronous and unchanged.
    func inject(backspaceCount: Int, characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        let methodInfo = AppBehaviorDetector.shared.getConfirmedInjectionMethod()
        let canRunSlowDirectAsync = methodInfo.method == .slow
            && !methodInfo.needsEmptyCharPrefix
            && methodInfo.textSendingMethod != .paste
            && !AppBehaviorDetector.shared.needsForwardDeleteWithAXCheck

        guard canRunSlowDirectAsync else {
            injectSync(backspaceCount: backspaceCount, characters: characters, codeTable: codeTable, proxy: proxy)
            return
        }

        // Acquire before dispatch so waitForInjectionComplete() cannot slip through the
        // enqueue→execute gap and let the next physical key overtake this injection.
        injectionSemaphore.wait()
        let semaphore = injectionSemaphore
        let delays = methodInfo.delays
        let textSendingMethod = methodInfo.textSendingMethod
        slowInjectionQueue.async { [weak self] in
            defer { semaphore.signal() }
            self?.performSlowDirectInjection(
                backspaceCount: backspaceCount,
                characters: characters,
                codeTable: codeTable,
                delays: delays,
                textSendingMethod: textSendingMethod
            )
        }
    }
    
    /// Inject text replacement synchronously - backspaces + new text in one atomic operation
    /// This prevents race conditions where next keystroke arrives between backspace and text injection
    func injectSync(backspaceCount: Int, characters: [VNCharacter], codeTable: CodeTable, proxy: CGEventTapProxy) {
        // Acquire semaphore for entire injection operation
        injectionSemaphore.wait()
        defer { injectionSemaphore.signal() }
        
        // Create NEW event source for each injection
        // This ensures each injection has independent state, avoiding potential race conditions
        eventSource = CGEventSource(stateID: .privateState)
        
        let methodInfo = detectInjectionMethod()
        let method = methodInfo.method
        let delays = methodInfo.delays
        let textSendingMethod = methodInfo.textSendingMethod
        
        // For slow method (terminals), use direct post and use post(tap: .cgSessionEventTap) without proxy for injectViaBackspace
        // With HID level event tap, new event source per injection, and proper markers,
        // direct post should work correctly now
        let useDirectPost = (method == .slow)

        // Build preview of characters to inject
        let charPreview = characters.map { $0.unicode(codeTable: codeTable) }.joined()
        debugCallback?("Inject: bs=\(backspaceCount), chars=\(characters.count), text=\"\(charPreview)\", method=\(method), textMode=\(textSendingMethod), emptyCharPrefix=\(methodInfo.needsEmptyCharPrefix)")

        // AX Direct replaces text in one AX edit (delete `bs` units + insert), so it
        // does NOT follow the Step 1 (backspace) → Step 2 (text) model below.
        //
        // bs==0 goes through AX only for overlay launchers: their fields auto-select
        // an inline suggestion that must be cleared atomically even on a plain insert.
        // Other .axDirect contexts (Firefox-style content areas / address bars) keep
        // the synthetic Step 2 path for bs==0 — there is no suggestion to clear, and
        // routing every plain keystroke through AX would cost 4-6 IPC round-trips and
        // risk a full-value rewrite of large fields.
        if method == .axDirect && (backspaceCount > 0 || methodInfo.isOverlay) {
            // AX Direct: Use Accessibility API to manipulate text atomically.
            // Primary path for overlay launchers (Spotlight/Raycast/Alfred) and
            // Firefox-style content areas — both race with synthetic events.
            debugCallback?("    → AX Direct method: bs=\(backspaceCount), text=\"\(charPreview)\"")
            // Forward debug callback to AdvancedInjectionMethods
            AdvancedInjectionMethods.shared.debugCallback = debugCallback
            // Choose the synthetic fallback per context (used only if AX fails 3×):
            // - Overlay launchers have inline autocomplete → Forward Delete + backspace
            //   clears the auto-selected suggestion before retyping.
            // - Firefox content areas have no such suggestion → plain backspace + text
            //   (Shift+Left selection is unreliable there, e.g. "dịch" → "diịch").
            let isOverlayContext = methodInfo.isOverlay
            AdvancedInjectionMethods.shared.injectViaAXWithFallback(bs: backspaceCount, text: charPreview) {
                if isOverlayContext {
                    let skipFwdDel = !self.shouldSendForwardDeleteForAutocomplete()
                    self.debugCallback?("    → AX failed, fallback to autocomplete (skipFwdDel=\(skipFwdDel))")
                    self.injectViaAutocompleteInternal(count: backspaceCount, delays: delays, proxy: proxy, skipForwardDelete: skipFwdDel)
                } else {
                    self.debugCallback?("    → AX failed, fallback to backspace + text")
                    for i in 0..<backspaceCount {
                        self.sendKeyPress(VietnameseData.KEY_DELETE, proxy: proxy)
                        usleep(1000)
                        self.debugCallback?("    → Backspace \(i + 1)/\(backspaceCount)")
                    }
                    if backspaceCount > 0 {
                        usleep(3000)  // Wait for backspaces to be processed
                    }
                }
                self.sendTextChunkedInternal(charPreview, delay: delays.text, proxy: proxy, useDirectPost: false)
            }
            // AX Direct handles both backspace and text insertion (or fallback does)
            debugCallback?("injectSync: complete (AX Direct)")
            return
        }

        // Step 1: Send backspaces
        if backspaceCount > 0 {
            switch method {
            case .selection:
                debugCallback?("    → Selection method: Shift+Left × \(backspaceCount)")
                injectViaSelectionInternal(count: backspaceCount, delays: delays, proxy: proxy)

            case .autocomplete:
                // For autocomplete method, Forward Delete is ALWAYS needed to clear browser autosuggestions
                // However, we must skip it when typing mid-sentence or when AX detects text after cursor
                // Note: We use shouldSendForwardDeleteForAutocomplete() which ignores fixAutocomplete setting
                let shouldForwardDelete = shouldSendForwardDeleteForAutocomplete()
                debugCallback?("    → Autocomplete method: Forward Delete + backspaces (skipFwdDel=\(!shouldForwardDelete))")
                injectViaAutocompleteInternal(count: backspaceCount, delays: delays, proxy: proxy, skipForwardDelete: !shouldForwardDelete)

            case .axDirect:
                // Unreachable: backspaceCount > 0 is always handled before Step 1.
                break

            case .slow, .fast:
                // Empty char prefix: send U+202F to break autocomplete before backspaces
                // Used when AX query degrades on Firefox (can't tell address bar from content area)
                if methodInfo.needsEmptyCharPrefix {
                    debugCallback?("    → EmptyCharPrefix: sending U+202F + bs=\(backspaceCount + 1), text=\"\(charPreview)\"")
                    injectViaEmptyCharPrefixInternal(backspaceCount: backspaceCount, text: charPreview, delays: delays, proxy: proxy, textSendingMethod: textSendingMethod)
                    debugCallback?("injectSync: complete (emptyCharPrefix)")
                    return
                }
                
                debugCallback?("    → Backspace method: delays=\(delays), directPost=\(useDirectPost)")
                // Forward Delete is only used for .autocomplete method
                // For slow/fast methods, just send backspaces
                
                // SPECIAL CASE: Apps with AutoComplete suggestions
                // (Microsoft Office, Google Sheets/Docs/Slides in browsers)
                // Send Forward Delete before backspaces to clear AutoComplete suggestions
                // Forward Delete clears any highlighted suggestion text after cursor
                // Note: We use Forward Delete instead of Escape because:
                // - Escape in Excel CANCELS the entire edit session (loses all typed content)
                // - Forward Delete only clears text after cursor (the suggestion)
                //
                // IMPORTANT: Only send Forward Delete when there's NO real text after cursor.
                // If user clicked into middle of existing text, Forward Delete would delete
                // real characters. AutoComplete suggestions are not counted as "real text" by AX API.
                //
                // NOTE: For web apps (Google Sheets in Chrome), AX API often fails to get focused element.
                // When AX fails, we default to TRUE (assume text exists) to AVOID Forward Delete.
                // This is safer: missing an autocomplete clear is better than deleting real text.
                let needsForwardDelete = AppBehaviorDetector.shared.needsForwardDeleteWithAXCheck
                if needsForwardDelete && backspaceCount > 0 {
                    // Check if there's real text after cursor using Accessibility API
                    // Default to true (skip Forward Delete) when AX fails - safer to not delete
                    let hasRealTextAfter = hasTextAfterCursor() ?? true
                    if !hasRealTextAfter {
                        debugCallback?("    → AutoComplete app: sending Forward Delete to clear suggestion")
                        sendForwardDelete(proxy: proxy)
                        usleep(2000)  // 2ms delay after Forward Delete
                    } else {
                        debugCallback?("    → AutoComplete app: skipping Forward Delete (real text after cursor or AX failed)")
                    }
                }

                // Send backspaces immediately, then waits AFTER all backspaces are sent
                for i in 0..<backspaceCount {
                    sendBackspaceKey(codeTable: codeTable, proxy: proxy, useDirectPost: useDirectPost)
                    usleep(delays.backspace)
                    debugCallback?("    → Backspace \(i + 1)/\(backspaceCount)")
                }
                // Wait after all backspaces
                if backspaceCount > 0 {
                    usleep(delays.wait)
                    debugCallback?("    → Post-backspace wait: \(delays.wait)µs")
                }
            
            case .passthrough:
                // Passthrough should never reach here - it's filtered at shouldProcessEvent level
                // But if it does, just return without doing anything
                debugCallback?("    → Passthrough mode - no injection needed")
                return
            }
        }
        
        // Step 2: Send new characters. Reuse the string already built above instead
        // of converting every VNCharacter to Unicode a second time.
        if !characters.isEmpty {
            if let debugCallback {
                for (index, character) in characters.enumerated() {
                    debugCallback("  [\(index)]: '\(character.unicode(codeTable: codeTable))'")
                }
            }

            // Use text sending method from rule/detection
            switch textSendingMethod {
            case .oneByOne:
                debugCallback?("    → Text mode: one-by-one, directPost=\(useDirectPost)")
                sendTextOneByOneInternal(charPreview, delay: delays.text, proxy: proxy, useDirectPost: useDirectPost)
            case .chunked:
                debugCallback?("    → Text mode: chunked, directPost=\(useDirectPost)")
                sendTextChunkedInternal(charPreview, delay: delays.text, proxy: proxy, useDirectPost: useDirectPost)
            case .paste:
                debugCallback?("    → Text mode: paste (clipboard + Cmd+V)")
                sendTextViaPaste(charPreview, proxy: proxy, config: methodInfo.pasteConfig)
            }
        }
        
        // Settle time (skip if paste config says so)
        let shouldSkipSettle = (textSendingMethod == .paste && methodInfo.pasteConfig.skipSettleTime)
        if !shouldSkipSettle {
            let settleTime: UInt32 = (method == .slow) ? 20000 : 5000
            usleep(settleTime)
        }
        
        debugCallback?("injectSync: complete")
    }

    /// Performs the subset of `.slow` injection that is guaranteed to use direct session
    /// posting. The caller owns `injectionSemaphore`; this method must not wait or signal it.
    private func performSlowDirectInjection(
        backspaceCount: Int,
        characters: [VNCharacter],
        codeTable: CodeTable,
        delays: InjectionDelays,
        textSendingMethod: TextSendingMethod
    ) {
        eventSource = CGEventSource(stateID: .privateState)

        let text = characters.map { $0.unicode(codeTable: codeTable) }.joined()
        debugCallback?("Inject async slow-direct: bs=\(backspaceCount), chars=\(characters.count), text=\"\(text)\", textMode=\(textSendingMethod)")

        for index in 0..<backspaceCount {
            sendBackspaceKey(codeTable: codeTable, proxy: nil, useDirectPost: true)
            usleep(delays.backspace)
            debugCallback?("    → Backspace \(index + 1)/\(backspaceCount)")
        }
        if backspaceCount > 0 {
            usleep(delays.wait)
        }

        if !text.isEmpty {
            switch textSendingMethod {
            case .oneByOne:
                sendTextOneByOneInternal(text, delay: delays.text, proxy: nil, useDirectPost: true)
            case .chunked:
                sendTextChunkedInternal(text, delay: delays.text, proxy: nil, useDirectPost: true)
            case .paste:
                // Excluded by inject(); keep this exhaustive and fail closed if routing changes.
                assertionFailure("Paste injection must remain on the synchronous proxy-aware path")
                return
            }
        }

        usleep(20000) // Preserve the existing `.slow` settle time.
        debugCallback?("Inject async slow-direct: complete")
    }
    
    /// Internal: Send backspace key (no semaphore)
    private func sendBackspaceKey(codeTable: CodeTable, proxy: CGEventTapProxy?, useDirectPost: Bool = false) {
        let deleteKeyCode: CGKeyCode = VietnameseData.KEY_DELETE
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1
        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy, useDirectPost: useDirectPost)
            usleep(1000)
        }
    }
    
    /// Internal: Selection injection (no semaphore)
    private func injectViaSelectionInternal(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy) {
        for i in 0..<count {
            sendShiftLeftArrow(proxy: proxy)
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Shift+Left \(i + 1)/\(count)")
        }
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 3000)
        }
    }
    
    /// Internal: Autocomplete injection (no semaphore)
    /// - Parameter skipForwardDelete: if true, skip sending Forward Delete (e.g., when typing mid-sentence)
    private func injectViaAutocompleteInternal(count: Int, delays: InjectionDelays, proxy: CGEventTapProxy, skipForwardDelete: Bool = false) {
        if !skipForwardDelete {
            sendForwardDelete(proxy: proxy)
            usleep(3000)
        } else {
            debugCallback?("    → Skipped Forward Delete (mid-sentence)")
        }
        for i in 0..<count {
            sendKeyPress(VietnameseData.KEY_DELETE, proxy: proxy)
            usleep(delays.backspace > 0 ? delays.backspace : 1000)
            debugCallback?("    → Backspace \(i + 1)/\(count)")
        }
        if count > 0 {
            usleep(delays.wait > 0 ? delays.wait : 5000)
        }
    }
    
    /// Internal: EmptyCharPrefix injection (no semaphore)
    /// Sends U+202F to break autocomplete, then (backspaceCount+1) backspaces, then text.
    /// The +1 backspace removes the U+202F character itself.
    /// Uses post(tap: .cgSessionEventTap) for reliable delivery in Firefox.
    private func injectViaEmptyCharPrefixInternal(backspaceCount: Int, text: String, delays: InjectionDelays, proxy: CGEventTapProxy, textSendingMethod: TextSendingMethod) {
        // Step 1: Send U+202F to break autocomplete suggestions
        sendEmptyCharacter(proxy: proxy, useDirectPost: true)
        usleep(1000)  // 1ms for empty char to be registered
        debugCallback?("    → Sent U+202F (narrow no-break space) to break autocomplete")
        
        // Step 2: Send (backspaceCount + 1) backspaces
        // +1 to delete the U+202F we just sent
        let totalBackspaces = backspaceCount + 1
        for i in 0..<totalBackspaces {
            sendKeyPress(VietnameseData.KEY_DELETE, proxy: proxy, useDirectPost: true)
            usleep(delays.backspace)
            debugCallback?("    → Backspace \(i + 1)/\(totalBackspaces)")
        }
        
        // Step 3: Wait after all backspaces
        if totalBackspaces > 0 {
            usleep(delays.wait)
            debugCallback?("    → Post-backspace wait: \(delays.wait)µs")
        }
        
        // Step 4: Send replacement text
        if !text.isEmpty {
            switch textSendingMethod {
            case .oneByOne:
                debugCallback?("    → Text mode: one-by-one (directPost=true)")
                sendTextOneByOneInternal(text, delay: delays.text, proxy: proxy, useDirectPost: true)
            case .chunked:
                debugCallback?("    → Text mode: chunked (directPost=true)")
                sendTextChunkedInternal(text, delay: delays.text, proxy: proxy, useDirectPost: true)
            case .paste:
                debugCallback?("    → Text mode: paste (directPost=true)")
                sendTextViaPaste(text, proxy: proxy, config: PasteConfig(useDirectPost: true))
            }
        }
        
        // Settle time
        usleep(5000)
    }
    
    /// Internal: Send text chunked (no semaphore)
    /// Special handling for newline/tab: splits text and sends as key events
    private func sendTextChunkedInternal(_ text: String, delay: UInt32, proxy: CGEventTapProxy?, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        debugCallback?("    → Sending text chunked: '\(text)' (handling special chars), direct=\(useDirectPost)")
        
        // Split text into segments by newline and tab
        // Each segment is either: normal text, newline, or tab
        var segments: [(type: SegmentType, content: String)] = []
        var currentSegment = ""
        
        for char in text {
            if char == "\n" || char == "\r" {
                if !currentSegment.isEmpty {
                    segments.append((.text, currentSegment))
                    currentSegment = ""
                }
                segments.append((.newline, ""))
            } else if char == "\t" {
                if !currentSegment.isEmpty {
                    segments.append((.text, currentSegment))
                    currentSegment = ""
                }
                segments.append((.tab, ""))
            } else {
                currentSegment.append(char)
            }
        }
        if !currentSegment.isEmpty {
            segments.append((.text, currentSegment))
        }
        
        // Send each segment
        for (segmentIndex, segment) in segments.enumerated() {
            switch segment.type {
            case .newline:
                debugCallback?("    → Sending newline (Return key)")
                sendReturnKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                
            case .tab:
                debugCallback?("    → Sending tab (Tab key)")
                sendTabKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                
            case .text:
                // Send text in chunks
                let utf16 = Array(segment.content.utf16)
                var offset = 0
                let chunkSize = 20
                
                while offset < utf16.count {
                    let end = min(offset + chunkSize, utf16.count)
                    var chunk = Array(utf16[offset..<end])
                    
                    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                        break
                    }
                    
                    keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    
                    // Mark as XKey-injected event to prevent re-processing by event tap
                    keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
                    
                    // For slow method (terminals), post directly to session event tap
                    if useDirectPost {
                        keyDown.post(tap: .cgSessionEventTap)
                        keyUp.post(tap: .cgSessionEventTap)
                    } else if let proxy {
                        keyDown.tapPostEvent(proxy)
                        keyUp.tapPostEvent(proxy)
                    } else {
                        assertionFailure("A tap proxy is required when direct posting is disabled")
                        return
                    }
                    
                    debugCallback?("    → Sent chunk [\(offset)..<\(end)]: \(chunk.count) chars")
                    
                    if delay > 0 && end < utf16.count {
                        usleep(delay)
                    }
                    
                    offset = end
                }
            }
            
            // Add delay between segments
            if delay > 0 && segmentIndex < segments.count - 1 {
                usleep(delay)
            }
        }
    }
    
    /// Segment type for chunked text sending
    private enum SegmentType {
        case text
        case newline
        case tab
    }
    
    /// Internal: Send text one character at a time (for Safari/Google Docs compatibility)
    /// Some apps don't handle multiple Unicode characters in a single CGEvent properly
    /// Special handling for newline: sends Return key (0x24) instead of Unicode \n
    private func sendTextOneByOneInternal(_ text: String, delay: UInt32, proxy: CGEventTapProxy?, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }
        
        debugCallback?("    → Sending text one-by-one: '\(text)' (\(text.count) chars), direct=\(useDirectPost)")
        
        for (index, char) in text.enumerated() {
            // Special handling for newline - send Return key instead
            if char == "\n" || char == "\r" {
                debugCallback?("    → Sent char [\(index)]: newline (Return key)")
                sendReturnKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                if delay > 0 && index < text.count - 1 {
                    usleep(delay)
                }
                continue
            }
            
            // Special handling for tab - send Tab key instead
            if char == "\t" {
                debugCallback?("    → Sent char [\(index)]: tab (Tab key)")
                sendTabKeyInternal(proxy: proxy, useDirectPost: useDirectPost)
                if delay > 0 && index < text.count - 1 {
                    usleep(delay)
                }
                continue
            }
            
            var utf16 = Array(String(char).utf16)
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                break
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            
            // Mark as XKey-injected event to prevent re-processing by event tap
            keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            
            // For slow method (terminals), post directly to session event tap
            if useDirectPost {
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
            } else if let proxy {
                keyDown.tapPostEvent(proxy)
                keyUp.tapPostEvent(proxy)
            } else {
                assertionFailure("A tap proxy is required when direct posting is disabled")
                return
            }
            
            debugCallback?("    → Sent char [\(index)]: '\(char)'")
            
            // Add delay between characters (except after last one)
            if delay > 0 && index < text.count - 1 {
                usleep(delay)
            }
        }
    }
    
    /// Internal: Send Return key (for newline in macros)
    private func sendReturnKeyInternal(proxy: CGEventTapProxy?, useDirectPost: Bool = false) {
        sendKeyPress(0x24, proxy: proxy, useDirectPost: useDirectPost)  // Return key
    }
    
    /// Internal: Send Tab key (for tab in macros)
    private func sendTabKeyInternal(proxy: CGEventTapProxy?, useDirectPost: Bool = false) {
        sendKeyPress(0x30, proxy: proxy, useDirectPost: useDirectPost)  // Tab key
    }
    
    // MARK: - AX Helpers (shared boilerplate for cursor queries)
    
    /// Get the currently focused AXUIElement from the system-wide element.
    /// Returns nil if Accessibility is not available or no focused element exists.
    private func getFocusedAXElement(caller: String = #function) -> AXUIElement? {
        guard let element = AXHelper.getFocusedElement() else {
            debugCallback?("  [AX] \(caller): Failed to get focused element")
            return nil
        }
        return element
    }
    
    /// Get cursor position and selection length from the focused element's selected text range.
    /// Returns nil if the selected range attribute is not available.
    private func getCursorInfo(element: AXUIElement, caller: String = #function) -> (position: Int, selectionLength: Int)? {
        guard let range = AXHelper.getRange(element, attribute: kAXSelectedTextRangeAttribute) else {
            debugCallback?("  [AX] \(caller): Failed to get selected range")
            return nil
        }
        return (range.location, range.length)
    }
    
    /// Get total character count of the text in the focused element.
    /// Returns nil if the attribute is not available.
    private func getTotalLength(element: AXUIElement, caller: String = #function) -> Int? {
        guard let totalLength = AXHelper.getInt(element, attribute: kAXNumberOfCharactersAttribute) else {
            debugCallback?("  [AX] \(caller): Failed to get total length")
            return nil
        }
        return totalLength
    }
    
    // MARK: - AX Cursor Query Methods

    /// Check if there is text after cursor using Accessibility API
    /// Returns: true if there's text after cursor, false if at end of text, nil if AX not supported
    private func hasTextAfterCursor() -> Bool? {
        guard let element = getFocusedAXElement(caller: "hasTextAfterCursor") else { return nil }
        guard let cursor = getCursorInfo(element: element, caller: "hasTextAfterCursor") else { return nil }
        guard let totalLength = getTotalLength(element: element, caller: "hasTextAfterCursor") else { return nil }

        // If there's a selection (highlighted text), it's likely AutoComplete suggestion
        // In this case, we consider it as "no real text after cursor" because
        // the selected text will be replaced when user continues typing
        let hasRealTextAfter = cursor.position + cursor.selectionLength < totalLength
        debugCallback?("  [AX] hasTextAfterCursor: cursor=\(cursor.position), selection=\(cursor.selectionLength), total=\(totalLength), hasRealTextAfter=\(hasRealTextAfter)")

        return hasRealTextAfter
    }
    
    /// Check if there is a non-whitespace character immediately after cursor
    /// Returns: the character if exists and is not whitespace (cursor is mid-word),
    ///          nil if at end of text, followed by whitespace, or AX not supported
    /// This is used for context-aware macro checking
    func getCharacterAfterCursor() -> Character? {
        guard let element = getFocusedAXElement(caller: "getCharacterAfterCursor") else { return nil }
        guard let cursor = getCursorInfo(element: element, caller: "getCharacterAfterCursor") else { return nil }
        guard let totalLength = getTotalLength(element: element, caller: "getCharacterAfterCursor") else { return nil }

        // Check if there's text after cursor (accounting for selection)
        let positionAfterCursor = cursor.position + cursor.selectionLength
        guard positionAfterCursor < totalLength else {
            debugCallback?("  [AX] getCharacterAfterCursor: At end of text")
            return nil
        }

        // Read 1 character after cursor
        let readRange = CFRange(location: positionAfterCursor, length: 1)
        var readRangeValue = readRange
        guard let axRange = AXValueCreate(.cfRange, &readRangeValue) else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to create AXValue")
            return nil
        }

        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &text
        ) == .success else {
            debugCallback?("  [AX] getCharacterAfterCursor: Failed to read text")
            return nil
        }

        guard let charString = text as? String, let char = charString.first else {
            debugCallback?("  [AX] getCharacterAfterCursor: Text is empty")
            return nil
        }

        debugCallback?("  [AX] getCharacterAfterCursor: char='\(char)' isWhitespace=\(char.isWhitespace)")

        // Return nil if it's whitespace (word boundary)
        if char.isWhitespace || char.isNewline {
            return nil
        }

        return char
    }

    /// Get text before cursor using Accessibility API
    /// Returns: String of text before cursor (up to specified length), nil if AX not supported
    /// This is used for verifying buffer matches screen content before restore operations
    func getTextBeforeCursor(length: Int = 50) -> String? {
        guard let element = getFocusedAXElement(caller: "getTextBeforeCursor") else { return nil }
        guard let cursor = getCursorInfo(element: element, caller: "getTextBeforeCursor") else { return nil }

        let cursorPosition = cursor.position

        // Ensure cursor position is valid
        guard cursorPosition > 0 else {
            debugCallback?("  [AX] getTextBeforeCursor: Cursor at position 0")
            return ""  // Return empty string, not nil (AX works, just no text before cursor)
        }

        // Calculate how many characters to read (up to 'length' chars before cursor)
        let readLength = min(length, cursorPosition)
        let startPosition = cursorPosition - readLength
        let readRange = CFRange(location: startPosition, length: readLength)
        
        var readRangeValue = readRange
        guard let axRange = AXValueCreate(.cfRange, &readRangeValue) else {
            debugCallback?("  [AX] getTextBeforeCursor: Failed to create AXValue")
            return nil
        }

        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &text
        ) == .success else {
            debugCallback?("  [AX] getTextBeforeCursor: Failed to read text")
            return nil
        }

        guard let resultText = text as? String else {
            debugCallback?("  [AX] getTextBeforeCursor: Text is not a string")
            return nil
        }

        debugCallback?("  [AX] getTextBeforeCursor: Read '\(resultText)' (\(resultText.count) chars)")
        return resultText
    }


    /// Determine if Forward Delete should be sent for autocomplete method (Firefox/Safari address bar)
    /// Unlike shouldSendForwardDelete(), this doesn't check fixAutocomplete setting
    /// because autocomplete method ALWAYS needs Forward Delete to clear browser autosuggestions
    /// Only skips Forward Delete if:
    /// 1. Typing mid-sentence (cursor was moved)
    /// 2. AX API confirms text after cursor
    private func shouldSendForwardDeleteForAutocomplete() -> Bool {
        // Don't send if we know cursor was moved (typing mid-sentence)
        if isTypingMidSentence {
            debugCallback?("  [FwdDel-AC] Skipped: isTypingMidSentence=true")
            return false
        }

        // Check via Accessibility API if there's text after cursor
        if let hasTextAfter = hasTextAfterCursor() {
            if hasTextAfter {
                debugCallback?("  [FwdDel-AC] Skipped: AX detected text after cursor")
                return false
            } else {
                debugCallback?("  [FwdDel-AC] Allowed: AX confirmed no text after cursor")
                return true
            }
        }

        // AX not supported - ALLOW Forward Delete
        // Same reasoning as shouldSendForwardDelete(): isTypingMidSentence was already checked.
        // If user hasn't pressed Enter, clicked, or moved cursor, Forward Delete is safe.
        debugCallback?("  [FwdDel-AC] Allowed: AX not supported, but isTypingMidSentence=false")
        return true
    }

    /// Send text via clipboard paste (Cmd+V).
    /// Used for TUI apps (like Kiro CLI) and remote desktop clients that need
    /// clipboard-based input instead of raw Unicode CGEvents.
    ///
    /// USES .combinedSessionState EVENT SOURCE: remote desktop clients (RustDesk
    /// in particular) check the system-wide modifier state in addition to event
    /// flags. Synthetic events from .privateState don't update session/global
    /// modifier state, so RustDesk strips the Cmd modifier and forwards just V
    /// to the remote (e.g. "thuw" → "thv"). Posting from a .combinedSessionState
    /// source plus explicit Cmd key down → V → Cmd up sequence depresses the
    /// modifier at session level so RustDesk forwards Cmd+V correctly.
    /// Only the paste sequence uses this source — all other injection paths
    /// keep .privateState (avoids cross-app side effects).
    ///
    /// NOTE: Clipboard is NOT restored after paste to avoid race conditions when typing fast.
    private func sendTextViaPaste(_ text: String, proxy: CGEventTapProxy, config: PasteConfig = PasteConfig()) {
        let pasteboard = NSPasteboard.general

        // Set clipboard to replacement text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        debugCallback?("    → Paste: set clipboard = '\(text)'")

        // Wait for pasteboard server to commit data (and remote desktop clipboard sync)
        usleep(config.prePasteDelay)

        // Determine modifier key code from config (default Cmd, alt Ctrl)
        // 0x37 = Left Cmd, 0x3B = Left Ctrl
        let modifierKeyCode: CGKeyCode = config.pasteModifiers.contains(.maskControl) ? 0x3B : 0x37

        // Use combinedSessionState ONLY for paste — affects session modifier state
        // so remote desktop clients see the modifier as actually held.
        guard let pasteSource = CGEventSource(stateID: .combinedSessionState) else {
            debugCallback?("    → Paste: FAILED to create combinedSessionState event source")
            usleep(config.postPasteDelay)
            return
        }

        let postPaste: (CGEvent) -> Void = { event in
            event.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
            if config.useDirectPost {
                event.post(tap: .cgSessionEventTap)
            } else {
                event.tapPostEvent(proxy)
            }
        }

        // 1. Modifier key DOWN (e.g. Cmd) — depresses modifier at session level
        if let modDown = CGEvent(keyboardEventSource: pasteSource, virtualKey: modifierKeyCode, keyDown: true) {
            modDown.flags = config.pasteModifiers
            postPaste(modDown)
        }
        usleep(2000)  // 2ms — let session modifier state settle

        // 2. Paste key (V) DOWN+UP with modifier flag
        if let vDown = CGEvent(keyboardEventSource: pasteSource, virtualKey: CGKeyCode(config.pasteKeyCode), keyDown: true) {
            vDown.flags = config.pasteModifiers
            postPaste(vDown)
        }
        if let vUp = CGEvent(keyboardEventSource: pasteSource, virtualKey: CGKeyCode(config.pasteKeyCode), keyDown: false) {
            vUp.flags = config.pasteModifiers
            postPaste(vUp)
        }
        usleep(2000)

        // 3. Modifier key UP — release modifier
        if let modUp = CGEvent(keyboardEventSource: pasteSource, virtualKey: modifierKeyCode, keyDown: false) {
            modUp.flags = []
            postPaste(modUp)
        }

        debugCallback?("    → Paste: sent Cmd+V via combinedSessionState (directPost=\(config.useDirectPost))")

        // Wait for app to read clipboard and process paste
        usleep(config.postPasteDelay)

        debugCallback?("    → Paste: done")
    }
    
    // MARK: - Private Methods

    private func sendBackspace(codeTable: CodeTable, proxy: CGEventTapProxy) {
        let deleteKeyCode: CGKeyCode = VietnameseData.KEY_DELETE // Delete/Backspace key

        // For VNI and Unicode Compound, some characters require double backspace
        let backspaceCount = codeTable.requiresDoubleBackspace ? 2 : 1

        for _ in 0..<backspaceCount {
            sendKeyPress(deleteKeyCode, proxy: proxy)
            // Add small delay for apps like Spotlight that need time to process backspace
            usleep(1000) // 1ms delay between backspaces
        }
    }

    /// Unified method for sending a single key press (key down + key up) with optional modifiers.
    /// All other send key methods delegate to this to avoid duplicated CGEvent creation/posting logic.
    private func sendKeyPress(_ keyCode: CGKeyCode, proxy: CGEventTapProxy?, useDirectPost: Bool = false, modifiers: CGEventFlags? = nil) {
        guard let source = eventSource else { return }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        // Apply modifier keys if specified (e.g., Shift for Shift+Left Arrow)
        if let mods = modifiers {
            keyDown.flags.insert(mods)
            keyUp.flags.insert(mods)
        }

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

        // For slow method (terminals), post directly to session event tap
        // This avoids race conditions where tapPostEvent can cause timing issues
        if useDirectPost {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        } else if let proxy {
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
        } else {
            assertionFailure("A tap proxy is required when direct posting is disabled")
        }
    }
    
    private func sendUnicodeCharacter(_ char: UnicodeScalar, proxy: CGEventTapProxy) {
        guard let source = eventSource else { return }

        // Create keyboard events with Unicode character
        // Use CGEventCreateKeyboardEvent with virtualKey 0 for Unicode input
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        // Convert UnicodeScalar to UTF-16 (UniChar array)
        let unicodeString = String(char)
        var utf16Chars = Array(unicodeString.utf16)

        // Use the official keyboardSetUnicodeString instance method (Swift 3+ API)
        // This is the same method used by OpenKey
        keyDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
        keyUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

        // Post events using tapPostEvent
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
    }

    // MARK: - Autocomplete Fix Methods
    
    /// Send Right Arrow key to move cursor to end (deselect autocomplete in Spotlight)
    private func sendRightArrow(proxy: CGEventTapProxy) {
        sendKeyPress(CGKeyCode(VietnameseData.KEY_RIGHT), proxy: proxy)  // Right Arrow key
        debugCallback?("    → Sent Right Arrow to deselect autocomplete")
    }
    
    /// Send Forward Delete (Fn+Delete) to delete text after cursor (clear autocomplete suggestion)
    private func sendForwardDelete(proxy: CGEventTapProxy) {
        sendKeyPress(CGKeyCode(VietnameseData.KEY_FORWARD_DELETE), proxy: proxy)  // Forward Delete key
        debugCallback?("    → Sent Forward Delete to clear autocomplete suggestion")
    }
    
    /// Send Escape key to dismiss autocomplete suggestions (for Spotlight)
    private func sendEscapeKey(proxy: CGEventTapProxy) {
        sendKeyPress(CGKeyCode(VietnameseData.KEY_ESC), proxy: proxy)  // Escape key
        debugCallback?("    → Sent Escape key to dismiss autocomplete")
    }

    /// Send empty character to fix autocomplete (U+202F - Narrow No-Break Space)
    /// - Parameter useDirectPost: If true, posts via cgSessionEventTap (for emptyCharPrefix method).
    ///   If false, uses tapPostEvent(proxy) (for other methods).
    private func sendEmptyCharacter(proxy: CGEventTapProxy, useDirectPost: Bool = false) {
        guard let source = eventSource else { return }

        let emptyChar: UInt16 = 0x202F  // Narrow No-Break Space

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        var chars = [emptyChar]
        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)

        // Mark as XKey-injected event to prevent re-processing by event tap
        keyDown.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kXKeyEventMarker)

        if useDirectPost {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        } else {
            keyDown.tapPostEvent(proxy)
            keyUp.tapPostEvent(proxy)
        }
    }

    /// Send Shift+Left Arrow to select text (for Chromium browsers)
    private func sendShiftLeftArrow(proxy: CGEventTapProxy) {
        sendKeyPress(CGKeyCode(VietnameseData.KEY_LEFT), proxy: proxy, modifiers: .maskShift)  // Shift + Left Arrow key
    }

    /// Check if current frontmost app is a Chromium-based browser
    private func isChromiumBrowser() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let chromiumBrowsers = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Dev",
            "com.microsoft.edgemac.Beta"
        ]

        return chromiumBrowsers.contains(frontApp.bundleIdentifier ?? "")
    }
    

    // MARK: - Injection Method Detection
    
    /// Get injection method for current context
    /// Uses confirmed method from AppBehaviorDetector (set on mouse click/app switch)
    /// This avoids repeated AX API calls and timing issues
    func detectInjectionMethod() -> InjectionMethodInfo {
        // Use AppBehaviorDetector's confirmed method (Single Source of Truth)
        let methodInfo = AppBehaviorDetector.shared.getConfirmedInjectionMethod()
        
        debugCallback?("🌟 detectMethod: \(methodInfo.description) → \(methodInfo.method), textMode=\(methodInfo.textSendingMethod)")
        
        return methodInfo
    }
    
    /// Clear method cache (call when app changes)
    /// Delegates to AppBehaviorDetector which manages the confirmed method
    func clearMethodCache() {
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        AppBehaviorDetector.shared.clearCache()
    }
}

