import XCTest
@testable import XKey

final class HostCommandRouterTests: XCTestCase {
    func testXKeyIMHandlesRuntimeCommands() {
        var handled: [HostCommand] = []
        let router = HostCommandRouter(capabilities: .xkeyIM) { command in
            handled.append(command)
            return .handled
        }

        let commands: [HostCommand] = [
            .toggleVietnamese,
            .undoTyping,
            .toggleExclusionRules,
            .toggleWindowTitleRules,
        ]

        XCTAssertEqual(commands.map(router.route), Array(repeating: .handled, count: commands.count))
        XCTAssertEqual(handled, commands)
    }

    func testXKeyIMRejectsUIOnlyCommandsWithoutInvokingHandler() {
        var handled: [HostCommand] = []
        var logs: [String] = []
        let router = HostCommandRouter(
            capabilities: .xkeyIM,
            handler: { command in
                handled.append(command)
                return .handled
            },
            log: { logs.append($0) }
        )
        let commands: [HostCommand] = [
            .showTranslation,
            .translateToSource,
            .showConvertTool,
            .showSettings,
            .showDebugWindow,
            .showToolbar,
        ]

        XCTAssertEqual(commands.map(router.route), Array(repeating: .unsupported, count: commands.count))
        XCTAssertTrue(handled.isEmpty)
        XCTAssertEqual(logs.count, commands.count)
    }

    func testXKeyAppRoutesEveryCommand() {
        var handled: [HostCommand] = []
        let router = HostCommandRouter(capabilities: .xkeyApp) { command in
            handled.append(command)
            return .handled
        }
        let commands = HostCommand.allCases

        XCTAssertEqual(commands.map(router.route), Array(repeating: .handled, count: commands.count))
        XCTAssertEqual(handled, commands)
    }

    func testOnlyHandledResultConsumesHotkeyEvent() {
        XCTAssertTrue(HostCommandResult.handled.shouldConsumeEvent)
        XCTAssertFalse(HostCommandResult.unsupported.shouldConsumeEvent)
        XCTAssertFalse(HostCommandResult.unavailable.shouldConsumeEvent)
    }

    func testSupportedCommandPreservesUnavailableResult() {
        let router = HostCommandRouter(capabilities: .xkeyIM) { _ in .unavailable }

        XCTAssertEqual(router.route(.undoTyping), .unavailable)
    }

    func testModifierOnlyResolverUsesBindingPriorityAndClearsDuplicateState() {
        let hotkey = Hotkey(keyCode: 0, modifiers: [.control, .shift])
        let bindings = [
            (hotkey: hotkey, command: HostCommand.toggleVietnamese),
            (hotkey: hotkey, command: HostCommand.undoTyping),
        ]
        var resolver = ModifierOnlyHostCommandResolver()

        XCTAssertNil(resolver.update(modifiers: [.control, .shift], bindings: bindings))
        XCTAssertEqual(resolver.update(modifiers: [.control], bindings: bindings), .toggleVietnamese)
        XCTAssertNil(resolver.update(modifiers: [], bindings: bindings))
    }

    func testModifierOnlyResolverIgnoresLongHold() {
        let hotkey = Hotkey(keyCode: 0, modifiers: [.function])
        let bindings = [(hotkey: hotkey, command: HostCommand.toggleVietnamese)]
        var resolver = ModifierOnlyHostCommandResolver()

        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 0))
        XCTAssertNil(resolver.update(modifiers: [], bindings: bindings, now: 1.0))

        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 2.0))
        XCTAssertEqual(resolver.update(modifiers: [], bindings: bindings, now: 2.2), .toggleVietnamese)
    }

    func testModifierOnlyResolverIgnoresExtraModifierAndCancel() {
        let hotkey = Hotkey(keyCode: 0, modifiers: [.function])
        let bindings = [(hotkey: hotkey, command: HostCommand.toggleVietnamese)]
        var resolver = ModifierOnlyHostCommandResolver()

        // Fn, then Shift joins: spoiled, no toggle, and Fn alone must not re-arm.
        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 0))
        XCTAssertNil(resolver.update(modifiers: [.function, .shift], bindings: bindings, now: 0.1))
        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 0.2))
        XCTAssertNil(resolver.update(modifiers: [], bindings: bindings, now: 0.3))

        // Fully released: a clean tap works again.
        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 1))
        XCTAssertEqual(resolver.update(modifiers: [], bindings: bindings, now: 1.1), .toggleVietnamese)

        // cancel() (key/click while held) spoils the tap.
        XCTAssertNil(resolver.update(modifiers: [.function], bindings: bindings, now: 2))
        resolver.cancel()
        XCTAssertNil(resolver.update(modifiers: [], bindings: bindings, now: 2.1))
    }
}
