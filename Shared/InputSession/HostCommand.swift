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
    private var armedCommands: Set<HostCommand> = []

    mutating func update(
        modifiers: ModifierFlags,
        bindings: [(hotkey: Hotkey, command: HostCommand)]
    ) -> HostCommand? {
        let relevantModifiers = modifiers.intersection([
            .control, .shift, .option, .command, .function,
        ])
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
            return bindings.first { armedCommands.contains($0.command) }?.command
        }

        if !matchingCommands.isEmpty {
            armedCommands = Set(matchingCommands)
        }
        return nil
    }

    mutating func cancel() {
        armedCommands.removeAll()
    }
}
