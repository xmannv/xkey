import CoreGraphics

protocol CGEventInjectionSink: AnyObject {
    var debugCallback: ((String) -> Void)? { get set }
    func inject(backspaceCount: Int,
                characters: [VNCharacter],
                codeTable: CodeTable,
                proxy: CGEventTapProxy?)
    func waitForInjectionComplete()
    func markNewSession(cursorMoved: Bool, preserveMidSentence: Bool)
    func resetMidSentenceFlag()
    func clearMethodCache()
}

extension CharacterInjector: CGEventInjectionSink {
    func inject(backspaceCount: Int,
                characters: [VNCharacter],
                codeTable: CodeTable,
                proxy: CGEventTapProxy?) {
        guard let proxy else {
            assertionFailure("A tap proxy is required for CharacterInjector")
            return
        }
        inject(backspaceCount: backspaceCount,
               characters: characters,
               codeTable: codeTable,
               proxy: proxy)
    }
}

final class CGEventTransport {
    private let sink: CGEventInjectionSink

    init(sink: CGEventInjectionSink = CharacterInjector()) {
        self.sink = sink
    }

    var debugCallback: ((String) -> Void)? {
        get { sink.debugCallback }
        set { sink.debugCallback = newValue }
    }

    func normalize(_ event: CGEvent, type: CGEventType) -> InputEvent? {
        let kind: InputEvent.Kind
        switch type {
        case .keyDown:
            kind = .keyDown
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }

        var modifiers: InputModifiers = []
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        if event.flags.contains(.maskAlphaShift) { modifiers.insert(.capsLock) }

        return InputEvent(kind: kind,
                          keyCode: event.keyCode,
                          characters: kind == .keyDown ? event.characters : nil,
                          modifiers: modifiers,
                          isRepeat: event.isKeyRepeat)
    }

    func apply(_ action: InputAction,
               event: InputEvent,
               originalEvent: CGEvent,
               proxy: CGEventTapProxy?) -> CGEvent? {
        let isPlainReturn = event.kind == .keyDown
            && event.keyCode == VietnameseData.KEY_RETURN
            && event.modifiers.intersection([.command, .control, .option]).isEmpty
        let result: CGEvent?

        switch action {
        case .passThrough, .commit:
            result = originalEvent
        case .consume:
            result = nil
        case .replacement(let replacement):
            sink.inject(backspaceCount: replacement.backspaces,
                        characters: replacement.characters,
                        codeTable: replacement.codeTable,
                        proxy: proxy)
            if event.kind == .undo {
                sink.markNewSession(cursorMoved: false, preserveMidSentence: true)
            }
            result = nil
        case .reset:
            let cursorMoved = event.kind == .focusChanged
                || (event.keyCode.map(VietnameseData.cursorMovementKeys.contains) ?? false)
            sink.markNewSession(cursorMoved: cursorMoved,
                                preserveMidSentence: !cursorMoved)
            result = originalEvent
        }

        if isPlainReturn, action != .reset {
            // Schedule the word-boundary session reset after any replacement injection,
            // matching the legacy handler's ordering.
            sink.markNewSession(cursorMoved: true, preserveMidSentence: false)
        }
        return result
    }

    func waitForPendingInjection() {
        sink.waitForInjectionComplete()
    }

    func reset(cursorMoved: Bool, preserveMidSentence: Bool) {
        sink.markNewSession(cursorMoved: cursorMoved,
                            preserveMidSentence: preserveMidSentence)
        sink.clearMethodCache()
    }

    func resetMidSentenceFlag() {
        sink.resetMidSentenceFlag()
    }
}
