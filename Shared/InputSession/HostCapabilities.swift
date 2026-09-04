import Foundation

enum HostCapability: Hashable {
    case secureInputFeedback
    case spellCheck
    case macroExpansion
    case smartSwitch
    case appRules
    case toggleVietnamese
    case undoTyping
    case translationUI
    case convertToolUI
    case settingsUI
    case debugWindowUI
    case toolbarUI
}

struct HostCapabilities: Equatable {
    let supported: Set<HostCapability>
    let unsupportedReasons: [HostCapability: String]

    init(supported: Set<HostCapability>) {
        self.supported = supported
        unsupportedReasons = [:]
    }

    init(supported: Set<HostCapability>,
         unsupportedReasons: [HostCapability: String]) {
        self.supported = supported
        self.unsupportedReasons = unsupportedReasons
    }

    func supports(_ capability: HostCapability) -> Bool {
        supported.contains(capability)
    }

    func unsupportedReason(for capability: HostCapability) -> String? {
        unsupportedReasons[capability]
    }

    static let xkeyApp = HostCapabilities(supported: Set([
        .secureInputFeedback, .spellCheck, .macroExpansion, .smartSwitch,
        .appRules, .toggleVietnamese, .undoTyping, .translationUI,
        .convertToolUI, .settingsUI, .debugWindowUI, .toolbarUI,
    ]))

    static let xkeyIM = HostCapabilities(
        supported: Set([
            .secureInputFeedback, .spellCheck, .macroExpansion, .smartSwitch,
            .appRules, .toggleVietnamese, .undoTyping,
        ]),
        unsupportedReasons: [
            .translationUI: "Translation UI is hosted by XKey.app",
            .convertToolUI: "Convert Tool UI is hosted by XKey.app",
            .settingsUI: "Settings UI is hosted by XKey.app",
            .debugWindowUI: "Debug window is hosted by XKey.app",
            .toolbarUI: "Toolbar UI is hosted by XKey.app",
        ]
    )
}
