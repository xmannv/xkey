import Foundation

enum HostCommand: String, CaseIterable, Hashable {
    case toggleVietnamese
    case undoTyping
    case toggleExclusionRules
    case toggleWindowTitleRules
    case showTranslation
    case translateToSource
    case showConvertTool
    case showSettings
    case showDebugWindow
    case showToolbar

    var requiredCapability: HostCapability {
        switch self {
        case .toggleVietnamese:
            return .toggleVietnamese
        case .undoTyping:
            return .undoTyping
        case .toggleExclusionRules, .toggleWindowTitleRules:
            return .appRules
        case .showTranslation, .translateToSource:
            return .translationUI
        case .showConvertTool:
            return .convertToolUI
        case .showSettings:
            return .settingsUI
        case .showDebugWindow:
            return .debugWindowUI
        case .showToolbar:
            return .toolbarUI
        }
    }
}

enum HostCommandResult: Equatable {
    case handled
    case unsupported
    case unavailable

    var shouldConsumeEvent: Bool {
        self == .handled
    }
}

struct ModifierOnlyHostCommandResolver {
    /// A modifier-only hotkey fires only on a quick tap; holding longer is not a toggle.
    static let maxTapDuration: TimeInterval = 0.5

    private var armedCommands: Set<HostCommand> = []
    private var armedAt: TimeInterval = 0
    private var heldModifiers: ModifierFlags = []
    /// Set once the gesture is spoiled (extra modifier, key, click); blocks re-arming
    /// until every modifier is released.
    private var spoiledUntilRelease = false

    mutating func update(
        modifiers: ModifierFlags,
        bindings: [(hotkey: Hotkey, command: HostCommand)],
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> HostCommand? {
        let relevantModifiers = modifiers.intersection([
            .control, .shift, .option, .command, .function,
        ])
        heldModifiers = relevantModifiers
        if spoiledUntilRelease {
            if relevantModifiers.isEmpty { spoiledUntilRelease = false }
            return nil
        }

        let matchingCommands = bindings.compactMap { binding in
            binding.hotkey.modifiers == relevantModifiers ? binding.command : nil
        }

        if !armedCommands.isEmpty {
            let stillArmed = matchingCommands.filter(armedCommands.contains)
            if !stillArmed.isEmpty {
                armedCommands = Set(stillArmed)
                return nil
            }

            defer { armedCommands.removeAll() }
            // Only releasing modifiers completes a tap; adding one (Fn+Shift) spoils it.
            guard let fired = bindings.first(where: {
                armedCommands.contains($0.command) && relevantModifiers.isSubset(of: $0.hotkey.modifiers)
            }) else {
                spoiledUntilRelease = !relevantModifiers.isEmpty
                return nil
            }
            guard now - armedAt <= Self.maxTapDuration else { return nil }
            return fired.command
        }

        if !matchingCommands.isEmpty {
            armedCommands = Set(matchingCommands)
            armedAt = now
        }
        return nil
    }

    /// A non-modifier input arrived: the held modifiers are not a bare tap anymore.
    mutating func cancel() {
        armedCommands.removeAll()
        spoiledUntilRelease = !heldModifiers.isEmpty
    }
}
