import CoreGraphics
import XCTest
@testable import XKey

final class CGEventTransportTests: XCTestCase {
    func testNormalizesKeyDownFieldsAndAllSupportedModifiers() throws {
        let event = try makeEvent(keyCode: 0x10, characters: "z")
        event.flags = [.maskControl, .maskAlternate, .maskShift, .maskCommand,
                       .maskSecondaryFn, .maskAlphaShift]
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)

        let normalized = try XCTUnwrap(CGEventTransport(sink: RecordingSink()).normalize(event, type: .keyDown))

        XCTAssertEqual(normalized.kind, .keyDown)
        XCTAssertEqual(normalized.keyCode, 0x10)
        XCTAssertEqual(normalized.characters, "z")
        XCTAssertEqual(normalized.modifiers,
                       [.control, .option, .shift, .command, .function, .capsLock])
        XCTAssertTrue(normalized.isRepeat)
    }

    func testNormalizesFlagsChangedWithoutTreatingItAsKeyDown() throws {
        let event = try makeEvent(keyCode: 0x38)
        event.flags = [.maskShift]

        let normalized = try XCTUnwrap(CGEventTransport(sink: RecordingSink()).normalize(event, type: .flagsChanged))

        XCTAssertEqual(normalized.kind, .flagsChanged)
        XCTAssertEqual(normalized.keyCode, 0x38)
        XCTAssertEqual(normalized.modifiers, [.shift])
        XCTAssertFalse(normalized.isRepeat)
    }

    func testIgnoresUnsupportedEventTypes() throws {
        let event = try makeEvent(keyCode: VietnameseData.KEY_A)

        XCTAssertNil(CGEventTransport(sink: RecordingSink()).normalize(event, type: .keyUp))
    }

    func testPassThroughCommitAndResetPreserveOriginalEventIdentity() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_A, characters: "a")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))

        XCTAssertTrue(transport.apply(.passThrough, event: normalized, originalEvent: event, proxy: nil) === event)
        XCTAssertTrue(transport.apply(.commit(text: "a"), event: normalized, originalEvent: event, proxy: nil) === event)
        XCTAssertTrue(transport.apply(.reset, event: normalized, originalEvent: event, proxy: nil) === event)
        XCTAssertEqual(sink.sessions.count, 1)
        XCTAssertEqual(sink.sessions.first?.cursorMoved, false)
        XCTAssertEqual(sink.sessions.first?.preserveMidSentence, true)
    }

    func testConsumeReturnsNilWithoutInjection() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_A, characters: "a")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))

        XCTAssertNil(transport.apply(.consume, event: normalized, originalEvent: event, proxy: nil))
        XCTAssertTrue(sink.injections.isEmpty)
    }

    func testNonReturnReplacementInjectsWithoutStartingNewSession() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_S, characters: "s")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))
        let characters = [VNCharacter(vowel: .a, tone: .acute)]
        let action = InputAction.replace(backspaces: 1, characters: characters, codeTable: .vniWindows)

        XCTAssertNil(transport.apply(action, event: normalized, originalEvent: event, proxy: nil))
        XCTAssertEqual(sink.injections, [Injection(backspaces: 1,
                                                   characters: characters,
                                                   codeTable: .vniWindows)])
        XCTAssertEqual(sink.calls, [.injection])
    }

    func testReturnReplacementInjectsBeforeStartingNewSession() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_RETURN, characters: "\r")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))
        let action = InputAction.replace(backspaces: 1,
                                         characters: [VNCharacter(character: "a")],
                                         codeTable: .unicode)

        XCTAssertNil(transport.apply(action, event: normalized, originalEvent: event, proxy: nil))
        XCTAssertEqual(sink.calls, [.injection, .session(cursorMoved: true,
                                                        preserveMidSentence: false)])
    }

    func testConsumedReturnStartsNewSession() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_RETURN, characters: "\n")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))

        XCTAssertNil(transport.apply(.consume, event: normalized, originalEvent: event, proxy: nil))
        XCTAssertEqual(sink.calls, [.session(cursorMoved: true,
                                             preserveMidSentence: false)])
    }

    func testCommandReturnResetDoesNotUseNewlineSessionMark() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: VietnameseData.KEY_RETURN, characters: "\r")
        event.flags = [.maskCommand]
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))

        XCTAssertTrue(transport.apply(.reset,
                                      event: normalized,
                                      originalEvent: event,
                                      proxy: nil) === event)
        XCTAssertEqual(sink.calls, [.session(cursorMoved: false,
                                             preserveMidSentence: true)])
    }

    func testUndoReplacementStartsFreshSessionWhileRegularReplacementDoesNot() throws {
        let sink = RecordingSink()
        let transport = CGEventTransport(sink: sink)
        let event = try makeEvent(keyCode: 0x35)
        let undo = InputEvent(kind: .undo, keyCode: nil, characters: nil, modifiers: [], isRepeat: false)

        _ = transport.apply(.replace(backspaces: 1,
                                     characters: [VNCharacter(character: "a")],
                                     codeTable: .unicode),
                            event: undo,
                            originalEvent: event,
                            proxy: nil)

        XCTAssertEqual(sink.sessions.count, 1)
        XCTAssertEqual(sink.sessions.first?.cursorMoved, false)
        XCTAssertEqual(sink.sessions.first?.preserveMidSentence, true)
    }

    func testOwnershipReleaseWaitsForPendingInjection() throws {
        let sink = BlockingInjectionSink()
        let transport = CGEventTransport(sink: sink)
        let handler = KeyboardEventHandler(transport: transport)
        let event = try makeEvent(keyCode: VietnameseData.KEY_S, characters: "s")
        let normalized = try XCTUnwrap(transport.normalize(event, type: .keyDown))
        _ = transport.apply(.replace(backspaces: 1, text: "á"),
                            event: normalized,
                            originalEvent: event,
                            proxy: nil)
        XCTAssertEqual(sink.injectionStarted.wait(timeout: .now() + 1), .success)

        let ownershipReleased = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            handler.releaseOwnership(afterPendingInjection: {
                ownershipReleased.signal()
            })
        }

        XCTAssertEqual(ownershipReleased.wait(timeout: .now() + 0.05), .timedOut)
        sink.allowInjectionToFinish.signal()
        XCTAssertEqual(ownershipReleased.wait(timeout: .now() + 1), .success)
    }

    private func makeEvent(keyCode: CGKeyCode, characters: String? = nil) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: source,
                                         virtualKey: keyCode,
                                         keyDown: true))
        if let characters {
            var utf16 = Array(characters.utf16)
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        }
        return event
    }
}

private struct Injection: Equatable {
    let backspaces: Int
    let characters: [VNCharacter]
    let codeTable: CodeTable
}

private enum SinkCall: Equatable {
    case injection
    case session(cursorMoved: Bool, preserveMidSentence: Bool)
}

private final class RecordingSink: CGEventInjectionSink {
    var debugCallback: ((String) -> Void)?
    var injections: [Injection] = []
    var sessions: [(cursorMoved: Bool, preserveMidSentence: Bool)] = []
    var calls: [SinkCall] = []

    func inject(backspaceCount: Int,
                characters: [VNCharacter],
                codeTable: CodeTable,
                proxy: CGEventTapProxy?) {
        injections.append(Injection(backspaces: backspaceCount,
                                    characters: characters,
                                    codeTable: codeTable))
        calls.append(.injection)
    }

    func waitForInjectionComplete() {}

    func markNewSession(cursorMoved: Bool, preserveMidSentence: Bool) {
        sessions.append((cursorMoved, preserveMidSentence))
        calls.append(.session(cursorMoved: cursorMoved,
                              preserveMidSentence: preserveMidSentence))
    }

    func resetMidSentenceFlag() {}
    func clearMethodCache() {}
}

private final class BlockingInjectionSink: CGEventInjectionSink {
    var debugCallback: ((String) -> Void)?
    let injectionStarted = DispatchSemaphore(value: 0)
    let allowInjectionToFinish = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)

    func inject(backspaceCount: Int,
                characters: [VNCharacter],
                codeTable: CodeTable,
                proxy: CGEventTapProxy?) {
        DispatchQueue.global().async {
            self.injectionStarted.signal()
            self.allowInjectionToFinish.wait()
            self.completed.signal()
        }
    }

    func waitForInjectionComplete() {
        completed.wait()
    }

    func markNewSession(cursorMoved: Bool, preserveMidSentence: Bool) {}
    func resetMidSentenceFlag() {}
    func clearMethodCache() {}
}
