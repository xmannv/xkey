import AppKit
import XCTest
@testable import XKey

final class IMKitTransportTests: XCTestCase {
    private var macroManager: MacroManager!
    private var previousMacroManager: MacroManager!

    override func setUp() {
        super.setUp()
        previousMacroManager = VNEngine().macroManager
        macroManager = MacroManager()
        VNEngine.setSharedMacroManager(macroManager)
    }

    override func tearDown() {
        VNEngine.setSharedMacroManager(previousMacroManager)
        macroManager = nil
        previousMacroManager = nil
        super.tearDown()
    }

    func testNormalizesKeyDownAndFlagsChanged() throws {
        let transport = IMKitTransport()
        let keyDown = try makeEvent(type: .keyDown,
                                    keyCode: VietnameseData.KEY_A,
                                    characters: "A",
                                    modifiers: [.shift, .capsLock])
        let flagsChanged = try makeEvent(type: .flagsChanged,
                                         keyCode: 0x37,
                                         characters: "",
                                         modifiers: [.command])

        XCTAssertEqual(transport.inputEvent(from: keyDown),
                       InputEvent(kind: .keyDown,
                                  keyCode: VietnameseData.KEY_A,
                                  characters: "A",
                                  modifiers: [.shift, .capsLock],
                                  isRepeat: false))
        XCTAssertEqual(transport.inputEvent(from: flagsChanged),
                       InputEvent(kind: .flagsChanged,
                                  keyCode: 0x37,
                                  characters: nil,
                                  modifiers: [.command],
                                  isRepeat: false))
    }

    func testPendingContextEventsReplayInOrderAndComposeFirstWord() {
        let queue = PendingIMKitEventQueue()
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        let a = inputEvent("a", VietnameseData.KEY_A)
        let s = inputEvent("s", VietnameseData.KEY_S)

        XCTAssertTrue(queue.append(event: a, client: client))
        XCTAssertTrue(queue.append(event: s, client: client))
        queue.drain(
            process: { event, client, _ in
                transport.apply(session.handle(event),
                                event: event,
                                session: session,
                                to: client,
                                mode: .markedText)
            },
            replay: { _, _ in XCTFail("composed events must not replay raw") }
        )

        XCTAssertEqual(transport.composingText, "á")
        XCTAssertEqual(client.calls.last, .setMarked(
            text: "á",
            selection: NSRange(location: 1, length: 0),
            replacement: NSRange(location: 0, length: 1)
        ))
    }

    func testPendingContextEventReplaysWhenAXProvidesNoFocusedElement() {
        let queue = PendingIMKitEventQueue()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        let event = inputEvent("a", VietnameseData.KEY_A)
        var replayed: [InputEvent] = []

        XCTAssertTrue(queue.append(event: event, client: client))
        queue.drain(
            process: { replayed.append($0); _ = $1; _ = $2; return true },
            replay: { _, _ in XCTFail("handled event must not replay raw") }
        )

        XCTAssertEqual(replayed, [event])
    }

    func testQueuedEventThatBecomesPassthroughReplaysRawCharactersExactly() {
        let queue = PendingIMKitEventQueue()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 3, length: 0))
        let event = inputEvent("Á", VietnameseData.KEY_A)

        XCTAssertTrue(queue.append(event: event, client: client))
        queue.drain(
            process: { _, _, _ in false },
            replay: { event, client in transport.replayRaw(event, to: client) }
        )

        XCTAssertEqual(client.calls, [
            .insert(text: "Á", replacement: NSRange(location: NSNotFound, length: 0)),
        ])
    }

    func testDeactivateBeforeContextResolutionReplaysPendingEventsExactlyOnceInFIFOOrder() {
        let queue = PendingIMKitEventQueue()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        XCTAssertTrue(queue.append(event: inputEvent("a", VietnameseData.KEY_A), client: client))
        XCTAssertTrue(queue.append(event: inputEvent("s", VietnameseData.KEY_S), client: client))

        queue.replayAll { event, client in transport.replayRaw(event, to: client) }
        queue.drain(
            process: { _, _, _ in XCTFail("late AX callback must not process replayed events"); return true },
            replay: { _, _ in XCTFail("late AX callback must not replay twice") }
        )

        XCTAssertEqual(client.calls, [
            .insert(text: "a", replacement: NSRange(location: NSNotFound, length: 0)),
            .insert(text: "s", replacement: NSRange(location: NSNotFound, length: 0)),
        ])
    }

    func testPendingQueueRetainsClientUntilDeactivateReplayCompletes() {
        let queue = PendingIMKitEventQueue()
        let transport = IMKitTransport()
        weak var weakClient: RecordingTextClient?
        var calls: [TextClientCall] = []

        autoreleasepool {
            var client: RecordingTextClient? = RecordingTextClient(
                selection: NSRange(location: 0, length: 0),
                onCall: { calls.append($0) }
            )
            weakClient = client
            XCTAssertTrue(queue.append(event: inputEvent("a", VietnameseData.KEY_A),
                                       client: client!))
            client = nil
        }

        XCTAssertNotNil(weakClient)
        queue.replayAll { event, client in transport.replayRaw(event, to: client) }
        XCTAssertNil(weakClient)
        XCTAssertEqual(calls, [
            .insert(text: "a", replacement: NSRange(location: NSNotFound, length: 0)),
        ])
    }

    func testNavigationAndCommandEventsAreNotBuffered() {
        let queue = PendingIMKitEventQueue()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))

        XCTAssertFalse(queue.append(
            event: InputEvent(kind: .keyDown,
                              keyCode: VietnameseData.KEY_LEFT,
                              characters: "",
                              modifiers: [],
                              isRepeat: false),
            client: client
        ))
        XCTAssertFalse(queue.append(
            event: InputEvent(kind: .keyDown,
                              keyCode: VietnameseData.KEY_A,
                              characters: "a",
                              modifiers: [.command],
                              isRepeat: false),
            client: client
        ))
        XCTAssertFalse(queue.append(
            event: InputEvent(kind: .keyDown,
                              keyCode: 0x47,
                              characters: "\u{F739}",
                              modifiers: [],
                              isRepeat: false),
            client: client
        ))
    }

    func testCrossTransportParityComparesCommittedDocumentAndFinalSessionState() throws {
        let scenarios: [(name: String, keys: [(String, UInt16)], expected: String)] = [
            ("tone replacement and space boundary",
             [("a", VietnameseData.KEY_A), ("s", VietnameseData.KEY_S),
              (" ", VietnameseData.KEY_SPACE)],
             "á "),
            ("multi-replacement and return boundary",
             [("t", VietnameseData.KEY_T), ("i", VietnameseData.KEY_I),
              ("e", VietnameseData.KEY_E), ("e", VietnameseData.KEY_E),
              ("s", VietnameseData.KEY_S), ("n", VietnameseData.KEY_N),
              ("g", VietnameseData.KEY_G), ("\r", VietnameseData.KEY_RETURN)],
             "tiếng\r"),
        ]

        for scenario in scenarios {
            let cgSession = makeSession()
            let imSession = makeSession()
            let sink = ParityInjectionSink()
            let cgTransport = CGEventTransport(sink: sink)
            let imTransport = IMKitTransport()
            let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))

            for (characters, keyCode) in scenario.keys {
                let input = inputEvent(characters, keyCode)
                let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
                let original = try XCTUnwrap(CGEvent(keyboardEventSource: source,
                                                     virtualKey: keyCode,
                                                     keyDown: true))
                let cgAction = cgSession.handle(input)
                if cgTransport.apply(cgAction,
                                     event: input,
                                     originalEvent: original,
                                     proxy: nil) != nil {
                    sink.text += characters
                }
                let imAction = imSession.handle(input)
                if !imTransport.apply(imAction,
                                      event: input,
                                      session: imSession,
                                      to: client,
                                      mode: .markedText) {
                    client.insertSystemText(characters)
                }
            }

            XCTAssertEqual(sink.text, scenario.expected, scenario.name)
            XCTAssertEqual(client.documentText, sink.text, scenario.name)
            XCTAssertEqual(imSession.engine.getCurrentWord(), cgSession.engine.getCurrentWord(), scenario.name)
            XCTAssertEqual(imSession.engine.index, cgSession.engine.index, scenario.name)
            XCTAssertEqual(imSession.engine.getCurrentWord(), "", scenario.name)
            XCTAssertFalse(imTransport.hasComposition, scenario.name)
        }
    }

    func testPassThroughReturnsFalseWithoutClientOperation() {
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 4, length: 0))

        XCTAssertFalse(transport.apply(.passThrough,
                                       event: inputEvent("a", VietnameseData.KEY_A),
                                       session: makeSession(vietnameseEnabled: false),
                                       to: client,
                                       mode: .direct))
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testOrdinaryLetterUpdatesMarkedTextAndConsumesEvent() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 4, length: 0))
        let event = inputEvent("a", VietnameseData.KEY_A)

        XCTAssertEqual(session.handle(event), .passThrough)
        XCTAssertTrue(transport.apply(.passThrough,
                                      event: event,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(client.calls, [
            .setMarked(text: "a",
                       selection: NSRange(location: 1, length: 0),
                       replacement: NSRange(location: NSNotFound, length: 0)),
        ])
    }

    func testMarkedReplacementUsesExistingCompositionRange() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 4, length: 0))
        let first = inputEvent("a", VietnameseData.KEY_A)
        _ = session.handle(first)
        _ = transport.apply(.passThrough, event: first, session: session, to: client, mode: .markedText)
        client.calls.removeAll()

        let tone = inputEvent("s", VietnameseData.KEY_S)
        let action = session.handle(tone)
        XCTAssertEqual(action, .replace(backspaces: 1, text: "á"))
        XCTAssertTrue(transport.apply(action, event: tone, session: session, to: client, mode: .markedText))
        XCTAssertEqual(client.calls, [
            .setMarked(text: "á",
                       selection: NSRange(location: 1, length: 0),
                       replacement: NSRange(location: 4, length: 1)),
        ])
    }

    func testDirectReplacementReplacesCorrectPrecedingRange() {
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 8, length: 0))

        XCTAssertTrue(transport.apply(.replace(backspaces: 3, text: "xin"),
                                      event: inputEvent("s", VietnameseData.KEY_S),
                                      session: makeSession(),
                                      to: client,
                                      mode: .direct))
        XCTAssertEqual(client.calls, [
            .insert(text: "xin", replacement: NSRange(location: 5, length: 3)),
        ])
    }

    func testDirectReplacementSwallowsOverlaySuggestionAndReplacesWholeWord() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        for (character, keyCode) in [("t", VietnameseData.KEY_T),
                                     ("h", VietnameseData.KEY_H),
                                     ("u", VietnameseData.KEY_U)] {
            let event = inputEvent(character, keyCode)
            XCTAssertFalse(transport.apply(session.handle(event),
                                           event: event,
                                           session: session,
                                           to: client,
                                           mode: .direct))
            client.selection.location += 1
        }
        client.selection = NSRange(location: 3, length: 4)
        client.calls.removeAll()
        let event = inputEvent("w", VietnameseData.KEY_W)

        XCTAssertTrue(transport.apply(session.handle(event),
                                      event: event,
                                      session: session,
                                      to: client,
                                      mode: .direct))
        XCTAssertEqual(client.calls, [
            .insert(text: "thư", replacement: NSRange(location: 0, length: 7)),
        ])
    }

    func testDirectBackspaceOverSelectionResetsStaleWordBeforeNextTyping() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))

        for (character, keyCode) in [("x", VietnameseData.KEY_X),
                                     ("i", VietnameseData.KEY_I),
                                     ("n", VietnameseData.KEY_N)] {
            let event = inputEvent(character, keyCode)
            XCTAssertFalse(transport.apply(session.handle(event),
                                           event: event,
                                           session: session,
                                           to: client,
                                           mode: .direct))
            client.selection.location += 1
        }

        client.selection = NSRange(location: 0, length: 3)
        let delete = inputEvent("\u{8}", VietnameseData.KEY_DELETE)
        XCTAssertTrue(transport.synchronizeCursor(in: session,
                                                  client: client,
                                                  mode: .direct,
                                                  detectsMovement: false,
                                                  event: delete))
        XCTAssertEqual(session.engine.index, 0)

        XCTAssertFalse(transport.apply(session.handle(delete),
                                       event: delete,
                                       session: session,
                                       to: client,
                                       mode: .direct))
        client.selection = NSRange(location: 0, length: 0)

        let letter = inputEvent("a", VietnameseData.KEY_A)
        XCTAssertFalse(transport.apply(session.handle(letter),
                                       event: letter,
                                       session: session,
                                       to: client,
                                       mode: .direct))
        client.selection.location = 1

        let tone = inputEvent("s", VietnameseData.KEY_S)
        XCTAssertEqual(session.handle(tone), .replace(backspaces: 1, text: "á"))
    }

    func testDirectSuggestionSelectionDoesNotResetBeforeToneKey() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 3, length: 4))
        for (character, keyCode) in [("t", VietnameseData.KEY_T),
                                     ("h", VietnameseData.KEY_H),
                                     ("u", VietnameseData.KEY_U)] {
            _ = session.handle(inputEvent(character, keyCode))
        }

        let tone = inputEvent("w", VietnameseData.KEY_W)
        XCTAssertFalse(transport.synchronizeCursor(in: session,
                                                   client: client,
                                                   mode: .direct,
                                                   detectsMovement: false,
                                                   event: tone))
        XCTAssertEqual(session.engine.getCurrentWord(), "thu")
        XCTAssertEqual(session.handle(tone), .replace(backspaces: 1, text: "ư"))
    }

    func testBackspaceAfterBoundaryDeletesSpaceThenMarksRestoredWord() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        for (character, keyCode) in [("t", VietnameseData.KEY_T),
                                     ("h", VietnameseData.KEY_H),
                                     ("u", VietnameseData.KEY_U)] {
            apply(character, keyCode, session: session, transport: transport, client: client)
        }
        let space = inputEvent(" ", VietnameseData.KEY_SPACE)
        XCTAssertFalse(transport.apply(session.handle(space),
                                       event: space,
                                       session: session,
                                       to: client,
                                       mode: .markedText))
        client.selection.location += 1
        client.calls.removeAll()

        let backspace = inputEvent("\u{8}", VietnameseData.KEY_DELETE)
        XCTAssertEqual(session.handle(backspace), .passThrough)
        XCTAssertTrue(transport.apply(.passThrough,
                                      event: backspace,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(client.calls, [
            .insert(text: "", replacement: NSRange(location: 3, length: 1)),
            .setMarked(text: "thu",
                       selection: NSRange(location: 3, length: 0),
                       replacement: NSRange(location: 0, length: 3)),
        ])
    }

    func testCommitInsertsFinalTextOverMarkedRange() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 2, length: 0))
        let event = inputEvent("a", VietnameseData.KEY_A)
        _ = session.handle(event)
        _ = transport.apply(.passThrough, event: event, session: session, to: client, mode: .markedText)
        client.calls.removeAll()

        transport.commitComposition(to: client)

        XCTAssertEqual(client.calls, [
            .insert(text: "a", replacement: NSRange(location: 2, length: 1)),
        ])
        XCTAssertFalse(transport.hasComposition)
    }

    func testResetClearsMarkedState() {
        let transport = IMKitTransport()
        let session = makeSession()
        let client = RecordingTextClient(selection: NSRange(location: 1, length: 0))
        let event = inputEvent("a", VietnameseData.KEY_A)
        _ = session.handle(event)
        _ = transport.apply(.passThrough, event: event, session: session, to: client, mode: .markedText)
        client.calls.removeAll()

        transport.resetComposition(in: client)

        XCTAssertEqual(client.calls, [
            .setMarked(text: "",
                       selection: NSRange(location: 0, length: 0),
                       replacement: NSRange(location: 1, length: 1)),
        ])
        XCTAssertFalse(transport.hasComposition)
    }

    func testMacroExpansionMarksThenCommitsExpandedText() {
        XCTAssertTrue(macroManager.addMacro(text: "bb", content: "bạn bè"))
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.macroEnabled = true
        let session = makeSession(preferences: preferences)
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        apply("b", VietnameseData.KEY_B, session: session, transport: transport, client: client)
        apply("b", VietnameseData.KEY_B, session: session, transport: transport, client: client)
        client.calls.removeAll()

        let space = inputEvent(" ", VietnameseData.KEY_SPACE)
        let action = session.handle(space)
        XCTAssertEqual(action, .replace(backspaces: 2, text: "bạn bè"))
        XCTAssertTrue(transport.apply(action, event: space, session: session, to: client, mode: .markedText))
        XCTAssertEqual(client.calls, [
            .setMarked(text: "bạn bè",
                       selection: NSRange(location: 6, length: 0),
                       replacement: NSRange(location: 0, length: 2)),
            .insert(text: "bạn bè", replacement: NSRange(location: 0, length: 6)),
        ])
    }

    func testUndoReplacesActiveMarkedTextAndConsumesOnlyWhenPerformed() {
        var preferences = Preferences()
        preferences.spellCheckEnabled = false
        preferences.undoTypingEnabled = true
        let session = makeSession(preferences: preferences)
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 3, length: 0))
        for character in "tieesng" {
            apply(String(character),
                  KeyCodeToCharacter.keyCode(forCharacter: character)!,
                  session: session,
                  transport: transport,
                  client: client)
        }
        client.calls.removeAll()
        let undo = InputEvent(kind: .undo, keyCode: nil, characters: nil, modifiers: [], isRepeat: false)

        XCTAssertTrue(transport.apply(session.handle(undo),
                                      event: undo,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(client.calls, [
            .insert(text: "tieesng", replacement: NSRange(location: 3, length: 5)),
        ])
        XCTAssertFalse(transport.apply(session.handle(undo),
                                       event: undo,
                                       session: session,
                                       to: client,
                                       mode: .markedText))
    }

    func testCommandFlagsChangedCommitsCompositionAndPassesThrough() {
        let session = makeSession()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        apply("a", VietnameseData.KEY_A, session: session, transport: transport, client: client)
        client.calls.removeAll()
        let flags = InputEvent(kind: .flagsChanged,
                               keyCode: 0x37,
                               characters: nil,
                               modifiers: [.command],
                               isRepeat: false)

        XCTAssertEqual(session.handle(flags), .commit(text: "a"))
        XCTAssertFalse(transport.apply(.commit(text: "a"),
                                       event: flags,
                                       session: session,
                                       to: client,
                                       mode: .markedText))
        XCTAssertEqual(client.calls, [
            .insert(text: "a", replacement: NSRange(location: 0, length: 1)),
        ])
    }

    func testRepeatedLetterContinuesMarkedCompositionAndAcceptsFollowingTone() throws {
        let session = makeSession()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        apply("a", VietnameseData.KEY_A, session: session, transport: transport, client: client)
        let repeatedEvent = try makeEvent(type: .keyDown,
                                          keyCode: VietnameseData.KEY_A,
                                          characters: "a",
                                          isRepeat: true)
        let repeated = try XCTUnwrap(transport.inputEvent(from: repeatedEvent))

        XCTAssertFalse(repeated.isRepeat)
        XCTAssertTrue(transport.apply(session.handle(repeated),
                                      event: repeated,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(session.engine.getCurrentWord(), "â")

        let tone = inputEvent("s", VietnameseData.KEY_S)
        XCTAssertTrue(transport.apply(session.handle(tone),
                                      event: tone,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(session.engine.getCurrentWord(), "ấ")
        XCTAssertEqual(client.calls, [
            .setMarked(text: "a",
                       selection: NSRange(location: 1, length: 0),
                       replacement: NSRange(location: NSNotFound, length: 0)),
            .setMarked(text: "â",
                       selection: NSRange(location: 1, length: 0),
                       replacement: NSRange(location: 0, length: 1)),
            .setMarked(text: "ấ",
                       selection: NSRange(location: 1, length: 0),
                       replacement: NSRange(location: 0, length: 1)),
        ])
        XCTAssertTrue(transport.hasComposition)
    }

    func testRepeatedBackspaceUpdatesMarkedComposition() throws {
        let session = makeSession()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0))
        apply("a", VietnameseData.KEY_A, session: session, transport: transport, client: client)
        apply("a", VietnameseData.KEY_A, session: session, transport: transport, client: client)
        client.calls.removeAll()
        let repeatedEvent = try makeEvent(type: .keyDown,
                                          keyCode: VietnameseData.KEY_DELETE,
                                          characters: "\u{8}",
                                          isRepeat: true)
        let repeated = try XCTUnwrap(transport.inputEvent(from: repeatedEvent))

        XCTAssertFalse(repeated.isRepeat)
        XCTAssertTrue(transport.apply(session.handle(repeated),
                                      event: repeated,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(session.engine.getCurrentWord(), "")
        XCTAssertEqual(client.calls, [
            .setMarked(text: "",
                       selection: NSRange(location: 0, length: 0),
                       replacement: NSRange(location: 0, length: 1)),
        ])
        XCTAssertFalse(transport.hasComposition)
    }

    func testPresentationModeIsExplicitAndDoesNotInspectOverlayBundle() {
        let session = makeSession()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 0, length: 0),
                                         bundleIdentifier: "com.apple.Spotlight")
        let event = inputEvent("a", VietnameseData.KEY_A)
        _ = session.handle(event)

        XCTAssertTrue(transport.apply(.passThrough,
                                      event: event,
                                      session: session,
                                      to: client,
                                      mode: .markedText))
        XCTAssertEqual(client.calls.count, 1)
    }

    func testCursorMoveCommitsMarkedTextAndResetsSessionBeforeNextKey() {
        let session = makeSession()
        let transport = IMKitTransport()
        let client = RecordingTextClient(selection: NSRange(location: 2, length: 0))
        let event = inputEvent("a", VietnameseData.KEY_A)
        _ = session.handle(event)
        _ = transport.apply(.passThrough,
                            event: event,
                            session: session,
                            to: client,
                            mode: .markedText)
        client.calls.removeAll()
        client.selection = NSRange(location: 20, length: 0)

        XCTAssertTrue(transport.synchronizeCursor(in: session,
                                                  client: client,
                                                  mode: .markedText,
                                                  detectsMovement: true))
        XCTAssertEqual(client.calls, [
            .insert(text: "a", replacement: NSRange(location: 2, length: 1)),
        ])
        XCTAssertEqual(session.engine.index, 0)
        XCTAssertFalse(transport.hasComposition)
    }

    private func apply(_ character: String,
                       _ keyCode: UInt16,
                       session: InputSession,
                       transport: IMKitTransport,
                       client: RecordingTextClient) {
        let event = inputEvent(character, keyCode)
        _ = transport.apply(session.handle(event),
                            event: event,
                            session: session,
                            to: client,
                            mode: .markedText)
    }

    private func makeSession(preferences: Preferences = Preferences(),
                             vietnameseEnabled: Bool = true) -> InputSession {
        InputSession(preferences: RuntimePreferences(
            preferences: preferences,
            vietnameseEnabled: vietnameseEnabled,
            windowTitleRulesEnabled: false,
            remoteDesktopInjectMode: false
        ), macroDataProvider: { nil })
    }

    private func inputEvent(_ characters: String, _ keyCode: UInt16) -> InputEvent {
        InputEvent(kind: .keyDown,
                   keyCode: keyCode,
                   characters: characters,
                   modifiers: [],
                   isRepeat: false)
    }

    private func makeEvent(type: NSEvent.EventType,
                           keyCode: UInt16,
                           characters: String,
                           modifiers: NSEvent.ModifierFlags = [],
                           isRepeat: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type,
                                      location: .zero,
                                      modifierFlags: modifiers,
                                      timestamp: 0,
                                      windowNumber: 0,
                                      context: nil,
                                      characters: characters,
                                      charactersIgnoringModifiers: characters.lowercased(),
                                      isARepeat: isRepeat,
                                      keyCode: keyCode))
    }
}

private enum TextClientCall: Equatable {
    case insert(text: String, replacement: NSRange)
    case setMarked(text: String, selection: NSRange, replacement: NSRange)
}

private final class RecordingTextClient: IMKitTextClient {
    var calls: [TextClientCall] = []
    var documentText = ""
    var selection: NSRange
    var currentMarkedRange = NSRange(location: NSNotFound, length: 0)
    let clientBundleIdentifier: String?
    private let onCall: ((TextClientCall) -> Void)?

    init(selection: NSRange,
         bundleIdentifier: String? = "com.example.Editor",
         onCall: ((TextClientCall) -> Void)? = nil) {
        self.selection = selection
        self.clientBundleIdentifier = bundleIdentifier
        self.onCall = onCall
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = Self.string(from: string)
        record(.insert(text: text, replacement: replacementRange))
        let start = replacementRange.location == NSNotFound ? selection.location : replacementRange.location
        replaceDocument(range: replacementRange.location == NSNotFound
            ? NSRange(location: selection.location, length: selection.length)
            : replacementRange,
            with: text)
        selection = NSRange(location: start + text.utf16.count, length: 0)
        currentMarkedRange = NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectionRange: NSRange, replacementRange: NSRange) {
        let text = Self.string(from: string)
        record(.setMarked(text: text,
                          selection: selectionRange,
                          replacement: replacementRange))
        let start = replacementRange.location == NSNotFound ? selection.location : replacementRange.location
        replaceDocument(range: replacementRange.location == NSNotFound
            ? NSRange(location: selection.location, length: selection.length)
            : replacementRange,
            with: text)
        selection = NSRange(location: start + selectionRange.location, length: selectionRange.length)
        currentMarkedRange = text.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: start, length: text.utf16.count)
    }

    func selectedRange() -> NSRange { selection }
    func markedRange() -> NSRange { currentMarkedRange }
    func bundleIdentifier() -> String? { clientBundleIdentifier }

    func insertSystemText(_ text: String) {
        replaceDocument(range: selection, with: text)
        selection = NSRange(location: selection.location + text.utf16.count, length: 0)
    }

    private func record(_ call: TextClientCall) {
        calls.append(call)
        onCall?(call)
    }

    private func replaceDocument(range: NSRange, with text: String) {
        let document = documentText as NSString
        guard range.location <= document.length,
              range.location + range.length <= document.length else { return }
        documentText = document.replacingCharacters(in: range, with: text)
    }

    private static func string(from value: Any) -> String {
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String ?? String(describing: value)
    }
}

private final class ParityInjectionSink: CGEventInjectionSink {
    var debugCallback: ((String) -> Void)?
    var text = ""

    func inject(backspaceCount: Int,
                characters: [VNCharacter],
                codeTable: CodeTable,
                proxy: CGEventTapProxy?) {
        text.removeLast(min(backspaceCount, text.count))
        text += characters.map { $0.unicode(codeTable: codeTable) }.joined()
    }

    func waitForInjectionComplete() {}
    func markNewSession(cursorMoved: Bool, preserveMidSentence: Bool) {}
    func resetMidSentenceFlag() {}
    func clearMethodCache() {}
}
