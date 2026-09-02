//
//  EngineManagerSharingTests.swift
//  XKeyTests
//
//  VNEngine.macroManager / smartSwitchManager are backed by process-wide
//  statics (see VNEngineMacro.swift / VNEngineSmartSwitch.swift).
//  KeyboardEventHandler.init() rebinds both via setSharedMacroManager /
//  setSharedSmartSwitchManager — a write that lands even for a VNEngine
//  instance that existed first (e.g. XKeyIMController's marked-text engine,
//  which is constructed long before XKeyIM's tap ever arms and builds its
//  own KeyboardEventHandler).
//
//  These tests pin that this rebind is a deliberate convergence, not
//  cross-channel corruption: afterward every VNEngine instance in the
//  process — no matter when it was created — reads the SAME manager
//  instance the tap's own engine uses. See the comment at
//  KeyboardEventHandler.swift for why that single-source-of-truth is safe.
//

import XCTest
@testable import XKey

final class EngineManagerSharingTests: XCTestCase {

    func testKeyboardEventHandlerConvergesMacroManagerAcrossEngines() {
        // Simulate an engine created BEFORE any KeyboardEventHandler exists
        // in this process — XKeyIMController's situation.
        let earlyEngine = VNEngine()

        // Seed the shared static with a known, controlled instance so the
        // assertions below don't depend on real on-disk macro data.
        let sentinel = MacroManager()
        _ = sentinel.addMacro(text: "zzsentinel", content: "SENTINEL")
        VNEngine.setSharedMacroManager(sentinel)
        XCTAssertTrue(earlyEngine.macroManager === sentinel,
                      "an engine created before the handler must still read the shared static")

        // Constructing KeyboardEventHandler is the "second write" the audit
        // flagged: its init() rebinds VNEngine's shared macro manager.
        let handler = KeyboardEventHandler()

        // The rebind converges every reader onto one instance rather than
        // leaving earlyEngine stuck on the sentinel or on a copy of its own.
        XCTAssertTrue(earlyEngine.macroManager === handler.engine.macroManager,
                      "all VNEngine instances in the process must share one macro manager")
        XCTAssertFalse(earlyEngine.macroManager === sentinel,
                        "the handler's plist-loaded manager must replace the sentinel")
    }

    func testKeyboardEventHandlerConvergesSmartSwitchManagerAcrossEngines() {
        let earlyEngine = VNEngine()

        let sentinel = SmartSwitchManager()
        sentinel.setAppLanguage(bundleId: "zz.sentinel", language: 1)
        VNEngine.setSharedSmartSwitchManager(sentinel)
        XCTAssertTrue(earlyEngine.smartSwitchManager === sentinel,
                      "an engine created before the handler must still read the shared static")

        let handler = KeyboardEventHandler()

        XCTAssertTrue(earlyEngine.smartSwitchManager === handler.engine.smartSwitchManager,
                      "all VNEngine instances in the process must share one smart switch manager")
    }
}
