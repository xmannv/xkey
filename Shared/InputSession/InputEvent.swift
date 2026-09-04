import Foundation

/// Transport event state, distinct from the persisted hotkey `ModifierFlags` model.
struct InputModifiers: OptionSet, Equatable {
    let rawValue: UInt

    static let control = InputModifiers(rawValue: 1 << 0)
    static let option = InputModifiers(rawValue: 1 << 1)
    static let shift = InputModifiers(rawValue: 1 << 2)
    static let command = InputModifiers(rawValue: 1 << 3)
    static let function = InputModifiers(rawValue: 1 << 4)
    static let capsLock = InputModifiers(rawValue: 1 << 5)
}

struct InputEvent: Equatable {
    enum Kind: Equatable {
        case keyDown
        case flagsChanged
        case focusChanged
        case reset
        case undo
    }

    let kind: Kind
    let keyCode: UInt16?
    let characters: String?
    let modifiers: InputModifiers
    let isRepeat: Bool
}
