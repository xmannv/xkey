import AppKit
import InputMethodKit

protocol IMKitTextClient: AnyObject {
    func insertText(_ string: Any, replacementRange: NSRange)
    func setMarkedText(_ string: Any, selectionRange: NSRange, replacementRange: NSRange)
    func selectedRange() -> NSRange
    func markedRange() -> NSRange
    func bundleIdentifier() -> String?
}

final class IMKTextInputClient: IMKitTextClient {
    private let client: IMKTextInput

    init(_ client: IMKTextInput) {
        self.client = client
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        client.insertText(string, replacementRange: replacementRange)
    }

    func setMarkedText(_ string: Any, selectionRange: NSRange, replacementRange: NSRange) {
        client.setMarkedText(string,
                             selectionRange: selectionRange,
                             replacementRange: replacementRange)
    }

    func selectedRange() -> NSRange { client.selectedRange() }
    func markedRange() -> NSRange { client.markedRange() }
    func bundleIdentifier() -> String? { client.bundleIdentifier() }
}

enum IMKitPresentationMode {
    case markedText
    case direct
}

final class PendingIMKitEventQueue {
    private struct Entry {
        let event: InputEvent
        let client: IMKitTextClient
        let command: HostCommand?
    }

    private var entries: [Entry] = []

    @discardableResult
    func append(event: InputEvent,
                client: IMKitTextClient,
                command: HostCommand? = nil) -> Bool {
        guard command == nil,
              event.kind == .keyDown,
              let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .privateUse, .surrogate:
                      return false
                  default:
                      return true
                  }
              }),
              event.modifiers.intersection([.command, .control, .option, .function]).isEmpty,
              event.keyCode != VietnameseData.KEY_DELETE,
              event.keyCode != VietnameseData.KEY_FORWARD_DELETE,
              event.keyCode != VietnameseData.KEY_ESC,
              event.keyCode != VietnameseData.KEY_TAB,
              event.keyCode != VietnameseData.KEY_RETURN,
              event.keyCode != VietnameseData.KEY_ENTER,
              (event.keyCode.map { !VietnameseData.cursorMovementKeys.contains($0) } ?? true)
        else { return false }
        entries.append(Entry(event: event, client: client, command: command))
        return true
    }

    func drain(
        process: (InputEvent, IMKitTextClient, HostCommand?) -> Bool,
        replay: (InputEvent, IMKitTextClient) -> Void
    ) {
        let pending = entries
        entries.removeAll()
        pending.forEach {
            if !process($0.event, $0.client, $0.command) {
                replay($0.event, $0.client)
            }
        }
    }

    func replayAll(_ replay: (InputEvent, IMKitTextClient) -> Void) {
        let pending = entries
        entries.removeAll()
        pending.forEach { replay($0.event, $0.client) }
    }

}

final class IMKitTransport {
    private(set) var composingText = ""
    private(set) var markedTextStartLocation = NSNotFound
    private(set) var currentWordLength = 0
    private var lastKnownSelectionLocation = NSNotFound
    private var lastBundleIdentifier = ""
    private var cursorTrackingBroken = false
    private var cursorTrackingVerified = false

    var hasComposition: Bool { !composingText.isEmpty }

    @discardableResult
    func synchronizeCursor(in session: InputSession,
                           client: IMKitTextClient,
                           mode: IMKitPresentationMode,
                           detectsMovement: Bool,
                           event: InputEvent? = nil) -> Bool {
        let bundleIdentifier = client.bundleIdentifier() ?? ""
        if bundleIdentifier != lastBundleIdentifier {
            lastBundleIdentifier = bundleIdentifier
            cursorTrackingBroken = false
            cursorTrackingVerified = false
            lastKnownSelectionLocation = NSNotFound
        }

        let selection = client.selectedRange()
        var moved = false
        if let event,
           event.kind == .keyDown,
           event.keyCode == VietnameseData.KEY_DELETE,
           selection.location != NSNotFound,
           selection.length > 0 {
            moved = true
        }
        if !moved,
           detectsMovement,
           !cursorTrackingBroken,
           lastKnownSelectionLocation != NSNotFound,
           selection.location != NSNotFound {
            if hasComposition, markedTextStartLocation != NSNotFound {
                let expectedEnd = markedTextStartLocation + composingText.utf16.count
                moved = selection.location != expectedEnd && selection.location != expectedEnd + 1
            } else {
                moved = selection.location != lastKnownSelectionLocation
                    && selection.location != lastKnownSelectionLocation + 1
            }
        }

        if moved {
            commitComposition(to: client)
            _ = session.handle(InputEvent(kind: .focusChanged,
                                          keyCode: nil,
                                          characters: nil,
                                          modifiers: [],
                                          isRepeat: false))
            currentWordLength = 0
        } else if mode == .markedText,
                  !hasComposition,
                  !session.engine.getCurrentWord().isEmpty {
            _ = session.handle(InputEvent(kind: .focusChanged,
                                          keyCode: nil,
                                          characters: nil,
                                          modifiers: [],
                                          isRepeat: false))
            currentWordLength = 0
        }
        lastKnownSelectionLocation = selection.location
        return moved
    }

    func inputEvent(from event: NSEvent) -> InputEvent? {
        let kind: InputEvent.Kind
        switch event.type {
        case .keyDown:
            kind = .keyDown
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }

        var modifiers: InputModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }
        if event.modifierFlags.contains(.capsLock) { modifiers.insert(.capsLock) }

        return InputEvent(kind: kind,
                          keyCode: UInt16(event.keyCode),
                          characters: kind == .keyDown ? event.characters : nil,
                          modifiers: modifiers,
                          // IMKit historically receives repeats as discrete typing input.
                          // The event-tap adapter owns repeat filtering for its transport.
                          isRepeat: false)
    }

    func replayRaw(_ event: InputEvent, to client: IMKitTextClient) {
        guard event.kind == .keyDown, let characters = event.characters else { return }
        client.insertText(characters,
                          replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func apply(_ action: InputAction,
               event: InputEvent,
               session: InputSession,
               to client: IMKitTextClient,
               mode: IMKitPresentationMode) -> Bool {
        switch action {
        case .passThrough:
            return applyPassThrough(event: event, session: session, to: client, mode: mode)
        case .consume:
            return true
        case .replacement(let replacement):
            return applyReplacement(replacement,
                                    event: event,
                                    session: session,
                                    to: client,
                                    mode: mode)
        case .commit:
            commitComposition(to: client)
            currentWordLength = 0
            return false
        case .reset:
            commitComposition(to: client)
            currentWordLength = 0
            return false
        }
    }

    func commitComposition(to client: IMKitTextClient) {
        guard !composingText.isEmpty else {
            clearCompositionState()
            return
        }

        client.insertText(composingText, replacementRange: activeMarkedRange(in: client))
        clearCompositionState()
        lastKnownSelectionLocation = client.selectedRange().location
    }

    func resetComposition(in client: IMKitTextClient?) {
        if let client, hasComposition {
            client.setMarkedText("",
                                 selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: activeMarkedRange(in: client))
        }
        clearCompositionState()
        currentWordLength = 0
        lastKnownSelectionLocation = client?.selectedRange().location ?? NSNotFound
        cursorTrackingVerified = false
    }

    func cancelComposition(in client: IMKitTextClient, mode: IMKitPresentationMode) {
        if mode == .markedText {
            resetComposition(in: client)
        } else if currentWordLength > 0 {
            let range = precedingRange(length: currentWordLength,
                                       selection: client.selectedRange())
            client.insertText("", replacementRange: range)
            clearCompositionState()
            currentWordLength = 0
        }
    }

    private func applyPassThrough(event: InputEvent,
                                  session: InputSession,
                                  to client: IMKitTextClient,
                                  mode: IMKitPresentationMode) -> Bool {
        guard event.kind == .keyDown else { return false }

        if event.keyCode == VietnameseData.KEY_DELETE {
            guard mode == .markedText else {
                currentWordLength = session.engine.getCurrentWord().utf16.count
                if lastKnownSelectionLocation > 0 { lastKnownSelectionLocation -= 1 }
                return false
            }

            let word = session.engine.getCurrentWord()
            if !hasComposition, !word.isEmpty {
                let selection = client.selectedRange()
                let wordLength = word.utf16.count
                guard selection.location != NSNotFound,
                      selection.location > wordLength
                else { return false }
                let spaceRange = NSRange(location: selection.location - 1, length: 1)
                let wordRange = NSRange(location: selection.location - 1 - wordLength,
                                        length: wordLength)
                client.insertText("", replacementRange: spaceRange)
                setMarkedText(word, replacing: wordRange, to: client)
                return true
            }
            guard hasComposition else { return false }
            if word.isEmpty {
                resetComposition(in: client)
            } else {
                setMarkedText(word, to: client)
            }
            return true
        }

        guard let character = event.characters?.first else { return false }
        if VNEngine.isWordBreak(character: character,
                                inputMethod: session.preferences.engineSettings.inputMethod) {
            let hadComposition = hasComposition
            commitComposition(to: client)
            currentWordLength = 0
            if hadComposition,
               character != " ", character != "\n", character != "\r", character != "\t" {
                client.insertText(String(character),
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
                return true
            }
            if client.selectedRange().location != NSNotFound {
                lastKnownSelectionLocation = client.selectedRange().location + 1
            }
            return false
        }

        let currentWord = session.engine.getCurrentWord()
        guard !currentWord.isEmpty else { return false }

        if mode == .markedText {
            setMarkedText(currentWord, to: client)
            return true
        }

        currentWordLength = currentWord.utf16.count
        let selection = client.selectedRange()
        if selection.location != NSNotFound {
            lastKnownSelectionLocation = selection.location + 1
        }
        return false
    }

    private func applyReplacement(_ replacement: InputReplacement,
                                  event: InputEvent,
                                  session: InputSession,
                                  to client: IMKitTextClient,
                                  mode: IMKitPresentationMode) -> Bool {
        if event.kind == .undo {
            replaceForUndo(replacement, in: client, mode: mode)
            return true
        }

        if mode == .direct {
            let selection = client.selectedRange()
            let currentWord = session.engine.getCurrentWord()
            if currentWordLength > 0,
               selection.location != NSNotFound,
               selection.location >= currentWordLength,
               !currentWord.isEmpty {
                let range = NSRange(location: selection.location - currentWordLength,
                                    length: currentWordLength + selection.length)
                client.insertText(currentWord, replacementRange: range)
            } else {
                let range = precedingRange(length: replacement.backspaces,
                                           selection: selection)
                client.insertText(replacement.text, replacementRange: range)
            }
            currentWordLength = session.engine.getCurrentWord().utf16.count
            lastKnownSelectionLocation = client.selectedRange().location
            return true
        }

        let currentWord = session.engine.getCurrentWord()
        let text = currentWord.isEmpty ? replacement.text : currentWord
        if !hasComposition, replacement.backspaces > 0 {
            let range = precedingRange(length: replacement.backspaces,
                                       selection: client.selectedRange())
            client.insertText("", replacementRange: range)
        }
        setMarkedText(text, to: client)

        if isWordBreak(event, session: session) {
            commitComposition(to: client)
        }
        return true
    }

    private func replaceForUndo(_ replacement: InputReplacement,
                                in client: IMKitTextClient,
                                mode: IMKitPresentationMode) {
        let range: NSRange
        if mode == .markedText, hasComposition {
            range = activeMarkedRange(in: client)
        } else {
            range = precedingRange(length: replacement.backspaces,
                                   selection: client.selectedRange())
        }
        client.insertText(replacement.text, replacementRange: range)
        clearCompositionState()
        currentWordLength = 0
    }

    private func setMarkedText(_ text: String, to client: IMKitTextClient) {
        if markedTextStartLocation == NSNotFound {
            markedTextStartLocation = client.selectedRange().location
        }
        let replacementRange = composingText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: markedTextStartLocation,
                      length: composingText.utf16.count)
        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.textColor.withAlphaComponent(0.15),
        ]
        client.setMarkedText(NSAttributedString(string: text, attributes: attributes),
                             selectionRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: replacementRange)
        composingText = text
        currentWordLength = text.utf16.count
        updateCursorTracking(afterMarking: text, client: client)
    }

    private func setMarkedText(_ text: String,
                               replacing range: NSRange,
                               to client: IMKitTextClient) {
        markedTextStartLocation = range.location
        let attributes: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.textColor.withAlphaComponent(0.15),
        ]
        client.setMarkedText(NSAttributedString(string: text, attributes: attributes),
                             selectionRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: range)
        composingText = text
        currentWordLength = text.utf16.count
        updateCursorTracking(afterMarking: text, client: client)
    }

    private func updateCursorTracking(afterMarking text: String, client: IMKitTextClient) {
        guard markedTextStartLocation != NSNotFound else { return }
        lastBundleIdentifier = client.bundleIdentifier() ?? ""
        let expected = markedTextStartLocation + text.utf16.count
        lastKnownSelectionLocation = expected
        if !cursorTrackingVerified, expected > 0 {
            cursorTrackingVerified = true
            cursorTrackingBroken = client.selectedRange().location != expected
        }
    }

    private func activeMarkedRange(in client: IMKitTextClient) -> NSRange {
        let range = client.markedRange()
        if range.location != NSNotFound, range.length > 0 {
            return range
        }
        if markedTextStartLocation != NSNotFound {
            return NSRange(location: markedTextStartLocation,
                           length: composingText.utf16.count)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    private func precedingRange(length: Int, selection: NSRange) -> NSRange {
        guard length > 0, selection.location != NSNotFound, selection.location >= length else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: selection.location - length, length: length)
    }

    private func isWordBreak(_ event: InputEvent, session: InputSession) -> Bool {
        guard let character = event.characters?.first else { return false }
        return VNEngine.isWordBreak(character: character,
                                    inputMethod: session.preferences.engineSettings.inputMethod)
    }

    private func clearCompositionState() {
        composingText = ""
        markedTextStartLocation = NSNotFound
    }
}
