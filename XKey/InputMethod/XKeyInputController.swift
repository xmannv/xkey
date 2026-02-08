//
//  XKeyInputController.swift
//  XKey
//
//  IMKit-based input controller for Vietnamese typing
//  This provides native text composition without flickering
//
//  NOTE: This is a PROTOTYPE. To use IMKit, XKey needs to be restructured
//  as an Input Method bundle (.app) installed in ~/Library/Input Methods/
//

import Cocoa
import InputMethodKit

/// IMKit-based Vietnamese input controller
/// Provides native text composition without the backspace+inject approach
///
/// Benefits over CGEvent injection:
/// - No flickering/jumping text
/// - Native support in all apps that implement NSTextInputClient
/// - Atomic text replacement
/// - Works perfectly in terminals and IDEs
///
/// Usage:
/// 1. Build as separate XKeyIM.app bundle
/// 2. Install to ~/Library/Input Methods/
/// 3. Enable in System Settings → Keyboard → Input Sources
/// 4. Select "XKey Vietnamese" as input source
@available(macOS 10.15, *)
class XKeyInputController: IMKInputController {
    
    // MARK: - Properties
    
    /// Vietnamese processing engine (shared with main XKey)
    private var engine: VNEngine!
    
    /// Current composing buffer (text being typed)
    private var composingBuffer: String = ""
    
    /// Whether to use marked text (underline) or direct insert
    /// Set to false for "instant" typing without underline
    private var useMarkedText: Bool = false
    
    /// Code table for output encoding
    private var codeTable: CodeTable = .unicode
    
    /// Input method (Telex, VNI, etc.)
    private var inputMethod: InputMethod = .telex
    
    // MARK: - Initialization
    
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        
        // Initialize Vietnamese engine
        engine = VNEngine()
        
        // Load settings (could sync with main XKey app)
        loadSettings()
    }
    
    // MARK: - Settings
    
    private func loadSettings() {
        // Load from shared plist file
        // This allows settings to be shared between XKey and XKeyIM
        // Note: macOS Sequoia+ requires TeamID prefix for native apps outside App Store
        let appGroup = "7E6Z9B4F2H.com.codetay.inputmethod.XKey"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return
        }
        
        let plistURL = containerURL.appendingPathComponent("Library/Preferences/\(appGroup).plist")
        
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return
        }

        if let methodRaw = dict["XKey.inputMethod"] as? Int,
           let method = InputMethod(rawValue: methodRaw) {
            inputMethod = method
        }

        if let tableRaw = dict["XKey.codeTable"] as? Int,
           let table = CodeTable(rawValue: tableRaw) {
            codeTable = table
        }

        if let markedText = dict["XKey.imkitUseMarkedText"] as? Bool {
            useMarkedText = markedText
        } else if let markedText = dict["XKey.imkitUseMarkedText"] as? Int {
            useMarkedText = markedText != 0
        }

        // Update engine settings
        var settings = VNEngine.EngineSettings()
        settings.inputMethod = inputMethod
        settings.codeTable = codeTable
        engine.updateSettings(settings)
    }
    
    // MARK: - IMKInputController Overrides
    
    /// Handle keyboard events
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        
        // Only handle key down events
        guard event.type == .keyDown else { return false }
        
        // Get the text input client
        guard let client = sender as? IMKTextInput else { return false }
        
        // Get character info
        guard let characters = event.characters,
              let character = characters.first else {
            return false
        }
        
        let keyCode = UInt16(event.keyCode)
        let isUppercase = character.isUppercase
        
        // Handle special keys
        if event.keyCode == VietnameseData.KEY_DELETE { // Backspace
            return handleBackspace(client: client)
        }
        
        // Handle word break keys (space, enter, etc.)
        if isWordBreakKey(character) {
            commitComposition(client)
            return false // Let the key pass through
        }
        
        // Process through Vietnamese engine
        let result = engine.processKey(
            character: character,
            keyCode: keyCode,
            isUppercase: isUppercase
        )
        
        if result.shouldConsume {
            // Build new text from result
            let newText = buildText(from: result.newCharacters)
            
            if useMarkedText {
                // Option 1: Use marked text (shows underline)
                setMarkedText(newText, client: client)
            } else {
                // Option 2: Direct replacement (no underline) - PREFERRED
                replaceText(
                    newText: newText,
                    deleteCount: result.backspaceCount,
                    client: client
                )
            }
            
            return true // Event consumed
        }
        
        return false // Let event pass through
    }
    
    /// Commit the current composition
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        
        if !composingBuffer.isEmpty {
            // Insert final text
            client.insertText(
                composingBuffer,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            composingBuffer = ""
        }
        
        // Reset engine for next word
        engine.reset()
    }
    
    /// Called when input method is activated
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        engine.reset()
        composingBuffer = ""
    }
    
    /// Called when input method is deactivated
    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        super.deactivateServer(sender)
    }
    
    /// Return candidates (not used for Vietnamese)
    override func candidates(_ sender: Any!) -> [Any]! {
        return nil
    }
    
    // MARK: - Text Manipulation
    
    /// Replace text using IMKit's native replacement
    /// This is the key advantage over CGEvent - atomic replacement without flickering
    private func replaceText(newText: String, deleteCount: Int, client: IMKTextInput) {
        // Get current cursor position
        let selectedRange = client.selectedRange()
        
        if deleteCount > 0 && selectedRange.location >= deleteCount {
            // Calculate replacement range (text to delete)
            let replaceRange = NSRange(
                location: selectedRange.location - deleteCount,
                length: deleteCount
            )
            
            // Atomic replacement - delete old + insert new in one operation
            client.insertText(newText, replacementRange: replaceRange)
        } else {
            // Just insert at cursor
            client.insertText(
                newText,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        
        // Update composing buffer
        composingBuffer = newText
    }
    
    /// Set marked text (with underline)
    private func setMarkedText(_ text: String, client: IMKTextInput) {
        composingBuffer = text
        
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }
    
    /// Handle backspace key
    private func handleBackspace(client: IMKTextInput) -> Bool {
        let result = engine.processBackspace()
        
        if result.shouldConsume {
            let newText = buildText(from: result.newCharacters)
            
            if useMarkedText {
                if newText.isEmpty {
                    // Clear marked text
                    client.setMarkedText(
                        "",
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: 0)
                    )
                } else {
                    setMarkedText(newText, client: client)
                }
            } else {
                replaceText(
                    newText: newText,
                    deleteCount: result.backspaceCount,
                    client: client
                )
            }
            
            return true
        }
        
        return false // Let backspace pass through
    }
    
    // MARK: - Helpers
    
    /// Build output string from VNCharacter array
    private func buildText(from characters: [VNCharacter]) -> String {
        return characters.map { $0.unicode(codeTable: codeTable) }.joined()
    }
    
    /// Check if character is a word break
    private func isWordBreakKey(_ character: Character) -> Bool {
        // Use centralized logic from VNEngine to ensure consistency
        return VNEngine.isWordBreak(character: character, inputMethod: inputMethod)
    }
}

// MARK: - IMKServer Setup (for standalone app)

/// Main entry point for XKeyIM.app bundle
/// This would be used when building XKey as a standalone Input Method
@available(macOS 10.15, *)
class XKeyIMAppDelegate: NSObject, NSApplicationDelegate {
    
    var server: IMKServer!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create IMK server with connection name matching Info.plist
        server = IMKServer(
            name: "XKeyIM_Connection",
            bundleIdentifier: Bundle.main.bundleIdentifier!
        )
        
        NSLog("XKeyIM: Input Method server started")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("XKeyIM: Input Method server stopping")
    }
}
