import XCTest
@testable import XKey

/// TapEnvironment exists so a host that forgets a dependency fails to COMPILE
/// rather than shipping a silently-wrong default. These tests pin the
/// property that carries that guarantee: every field is populated from the
/// caller, never defaulted.
final class TapEnvironmentTests: XCTestCase {

    override func setUpWithError() throws {
        try skipIfXKeyIMIsRunning()
    }

    private var originalOverlayAppNameProvider: (() -> String?)?
    private var originalRemoteDesktopInjectModeProvider: (() -> Bool)?
    private var originalWindowTitleRulesEnabled = true

    override func setUp() {
        super.setUp()
        // apply(to:) writes these three on a shared singleton; testApplyIsRepeatable
        // below calls it, so record them here and put them back in tearDown.
        let detector = AppBehaviorDetector.shared
        originalOverlayAppNameProvider = detector.overlayAppNameProvider
        originalRemoteDesktopInjectModeProvider = detector.remoteDesktopInjectModeProvider
        originalWindowTitleRulesEnabled = detector.windowTitleRulesEnabled
    }

    override func tearDown() {
        let detector = AppBehaviorDetector.shared
        detector.overlayAppNameProvider = originalOverlayAppNameProvider
        detector.remoteDesktopInjectModeProvider = originalRemoteDesktopInjectModeProvider
        detector.windowTitleRulesEnabled = originalWindowTitleRulesEnabled
        super.tearDown()
    }

    private func makeEnvironment(preferences: Preferences = Preferences(),
                                 windowTitleRulesEnabled: Bool = true,
                                 vietnameseEnabled: Bool = true) -> TapEnvironment {
        TapEnvironment(
            preferences: preferences,
            overlayAppName: { "Raycast" },
            remoteDesktopInjectMode: { true },
            windowTitleRulesEnabled: windowTitleRulesEnabled,
            vietnameseEnabled: vietnameseEnabled,
            axMessagingTimeout: 0.25
        )
    }

    func testProvidersAreCalledNotDefaulted() {
        let env = makeEnvironment()
        XCTAssertEqual(env.overlayAppName(), "Raycast")
        XCTAssertTrue(env.remoteDesktopInjectMode())
    }

    func testCarriesVietnameseStateVerbatim() {
        XCTAssertFalse(makeEnvironment(vietnameseEnabled: false).vietnameseEnabled)
        XCTAssertTrue(makeEnvironment(vietnameseEnabled: true).vietnameseEnabled)
    }

    /// An armed tap has exactly one way to pick up a settings change: rebuild the
    /// environment and apply it to the handler it is already driving. That only helps if
    /// a second apply(to:) really replaces the first one's values on a live handler
    /// instead of behaving like construction-time-only wiring.
    func testApplyIsRepeatableOnALiveHandler() {
        let handler = KeyboardEventHandler()

        var before = Preferences()
        before.inputMethod = .telex
        before.macroEnabled = false
        makeEnvironment(preferences: before,
                        windowTitleRulesEnabled: true,
                        vietnameseEnabled: true).apply(to: handler)
        XCTAssertEqual(handler.inputMethod, .telex)

        var after = Preferences()
        after.inputMethod = .vni
        after.macroEnabled = true
        makeEnvironment(preferences: after,
                        windowTitleRulesEnabled: false,
                        vietnameseEnabled: false).apply(to: handler)

        XCTAssertEqual(handler.inputMethod, .vni, "a settings change must reach the live handler")
        XCTAssertTrue(handler.macroEnabled, "a newly enabled macro must reach the live handler")
        XCTAssertEqual(handler.engine.vLanguage, 0, "the Vietnamese toggle must reach the live engine")
        XCTAssertFalse(AppBehaviorDetector.shared.windowTitleRulesEnabled,
                       "the Window Title Rules master switch must reach the live detector")
    }
}

/// TapEventSource's tap-feeding AX work only pays for itself while THIS process owns
/// the keystroke path. `isActiveHost` is the required field that says so, and these
/// tests pin the gate itself, not the plumbing.
///
/// Shape: this is the first of the two shapes Task 9b allows — invoke
/// `handleFocusCheck()` on a gated source and on an ungated one and assert the
/// difference — rather than the weaker shape that only checks both hosts supply the
/// field. `handleFocusCheck()` is the cheapest observable seam: it is internal, needs
/// no running tap, and reports the result of its AX pass through host callbacks.
final class TapEventSourceActiveHostGateTests: XCTestCase {

    override func setUpWithError() throws {
        try skipIfXKeyIMIsRunning()
    }

    private var originalTempOffToolbarEnabled = false

    override func setUp() {
        super.setUp()
        // With the temp-off toolbar enabled, an ungated handleFocusCheck() always
        // reports through exactly one of onNoFocusedElement (no focused element) or
        // onCheckToolbarForFocusedElement (one was found). That keeps the assertions
        // below independent of whether the test process happens to have Accessibility
        // permission and a real focused AX element.
        originalTempOffToolbarEnabled = SharedSettings.shared.tempOffToolbarEnabled
        SharedSettings.shared.tempOffToolbarEnabled = true
    }

    override func tearDown() {
        SharedSettings.shared.tempOffToolbarEnabled = originalTempOffToolbarEnabled
        super.tearDown()
    }

    /// True when handleFocusCheck() got as far as its AX pass.
    /// The pass is asynchronous now — the AX reads run on the source's own serial queue
    /// and report back on the main thread — so this waits for the report instead of
    /// reading a flag on the line after the call. A gated source schedules no pass at
    /// all, and its "did not run" is this wait timing out.
    private func focusCheckReachedAXPass(isActiveHost: @escaping () -> Bool) -> Bool {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: isActiveHost)
        let reported = expectation(description: "focus check reported its AX pass")
        var reached = false
        source.onNoFocusedElement = {
            reached = true
            reported.fulfill()
        }
        source.onCheckToolbarForFocusedElement = { _ in
            reached = true
            reported.fulfill()
        }
        source.handleFocusCheck()
        _ = XCTWaiter().wait(for: [reported], timeout: 2)
        return reached
    }

    func testFocusCheckRunsWhenThisProcessOwnsInput() {
        XCTAssertTrue(focusCheckReachedAXPass(isActiveHost: { true }),
                      "the owning host must still do its own focus checks")
    }

    func testFocusCheckIsSkippedWhenAnotherProcessOwnsInput() {
        XCTAssertFalse(focusCheckReachedAXPass(isActiveHost: { false }),
                       "a non-owning host must not spend AX round-trips on a tap that transforms nothing")
    }

}

final class TapEventSourceInactiveMutationTests: XCTestCase {
    func testAppSwitchDoesNotMutateInactiveHandlerTypingState() {
        let handler = KeyboardEventHandler()
        _ = handler.engine.processKey(
            character: "a",
            keyCode: VietnameseData.KEY_A,
            isUppercase: false
        )
        let source = TapEventSource(handler: handler, isActiveHost: { false })
        source.start()
        defer { source.stop() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        XCTAssertEqual(handler.engine.getCurrentWord(), "a")
    }
}

/// The overlay open/close callback takes a full AX snapshot (detectInjectionMethod).
/// Snapshot and app-policy mutation both feed THIS process's active session, so both
/// are gated on ownership.
final class TapEventSourceOverlayGateTests: XCTestCase {

    override func tearDown() {
        // start() installs this callback on a shared singleton and stop() clears it,
        // but tear it down here too so a failed assertion can't leak a live closure
        // into the next test.
        OverlayAppDetector.shared.onOverlayVisibilityChanged = nil
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        super.tearDown()
    }

    /// Drives one "overlay opened" transition through a source with the given ownership
    /// and reports whether the AX snapshot ran and whether the non-AX work still ran.
    private func runOverlayOpened(
        isActiveHost: @escaping () -> Bool
    ) -> (didSnapshotAX: Bool, didRunSmartSwitch: Bool) {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: isActiveHost)
        var didRunSmartSwitch = false
        source.onAppContext = { _ in didRunSmartSwitch = true }
        source.start()
        defer { source.stop() }

        // detectInjectionMethod() is the AX snapshot; setConfirmedInjectionMethod() is
        // where its result lands, so a non-nil confirmed method is the observable proof
        // that the snapshot ran. The snapshot is asynchronous now, and the injection log
        // line is emitted right after that result lands — so it says when to look.
        let snapshotApplied = expectation(description: "overlay AX snapshot applied")
        source.onLogEvent = { message in
            if message.contains("Injection:") { snapshotApplied.fulfill() }
        }
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        OverlayAppDetector.shared.onOverlayVisibilityChanged?(true, "Raycast")
        _ = XCTWaiter().wait(for: [snapshotApplied], timeout: 2)

        return (AppBehaviorDetector.shared.confirmedInjectionMethod != nil, didRunSmartSwitch)
    }

    func testOverlayCallbackSnapshotsAXWhenThisProcessOwnsInput() {
        XCTAssertTrue(runOverlayOpened(isActiveHost: { true }).didSnapshotAX,
                      "the owning host must still detect the overlay's injection method")
    }

    func testOverlayCallbackSkipsAXSnapshotWhenAnotherProcessOwnsInput() {
        let result = runOverlayOpened(isActiveHost: { false })
        XCTAssertFalse(result.didSnapshotAX,
                       "a non-owning host must not duplicate an AX snapshot into the overlay")
        XCTAssertFalse(result.didRunSmartSwitch,
                       "a non-owning host must never mutate app policy or typing state")
    }

    func testOverlayClosePublishesUnderlyingAppPolicyFromResolvedSnapshot() {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        var contexts: [AppContext] = []
        source.onAppContext = { contexts.append($0) }
        let snapshotApplied = expectation(description: "overlay-close AX snapshot applied")
        source.onLogEvent = { message in
            if message.contains("Overlay closed — Injection:") { snapshotApplied.fulfill() }
        }
        source.start()
        defer { source.stop() }

        OverlayAppDetector.shared.onOverlayVisibilityChanged?(false, "Raycast")
        wait(for: [snapshotApplied], timeout: 2)

        XCTAssertTrue(contexts.last?.hasResolvedWindowTitleRules == true,
                      "overlay close must restore policy from the same resolved AX snapshot")
    }
}

/// When tap ownership moves away, the first AX notification tears this process's
/// AXObserver down. The only two places that install one are the app-switch block and
/// start() — so ownership returning WITHOUT an app switch (the user picks a different
/// input source while staying in the same window) used to leave this process blind to
/// intra-app focus changes until the next app switch or mouse click, still injecting
/// with the method confirmed for the previous field.
final class TapEventSourceObserverSelfHealTests: XCTestCase {

    /// Every install attempt logs exactly one of three lines: "Monitoring" on success, or
    /// one of the two "Failed …" lines. Counting the bare "AXObserver:" prefix instead
    /// would score a single install as two against any app that does not support
    /// kAXTitleChangedNotification, because a SUCCESSFUL install of such an app also logs
    /// "AXObserver: Title notification not supported".
    private static func isInstallOutcome(_ message: String) -> Bool {
        message.hasPrefix("AXObserver: Monitoring") || message.hasPrefix("AXObserver: Failed")
    }

    /// setupAXObserverForApp bails silently only when there is no frontmost app or it is
    /// this process itself. Skipping that one case is what lets an outcome line be read as
    /// "an install was attempted", whether or not the test host has Accessibility
    /// permission.
    private func skipUnlessFrontmostAppIsObservable() throws {
        let frontmost = NSWorkspace.shared.frontmostApplication
        try XCTSkipIf(frontmost == nil || frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier,
                      "no frontmost app for this process to observe")
    }

    func testFocusCheckReinstallsAXObserverAfterOwnershipReturns() throws {
        try skipUnlessFrontmostAppIsObservable()

        var isActive = true
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { isActive })
        var installAttempts = 0
        var refusals = 0
        source.onLogEvent = { message in
            if Self.isInstallOutcome(message) { installAttempts += 1 }
            if message.hasPrefix("AXObserver: Failed") { refusals += 1 }
        }
        defer { source.stop() }

        source.start()
        XCTAssertEqual(installAttempts, 1, "start() installs the observer for the frontmost app")

        // Re-arming is deliberately suppressed for an app whose install was refused, so
        // this case needs a frontmost app whose AX server accepted one. Without
        // Accessibility permission every install is refused, and the suppression itself is
        // what testFocusCheckDoesNotRetryTheAppWhoseInstallFailed covers instead.
        try XCTSkipIf(refusals > 0, "the frontmost app refused the AXObserver install")

        // Ownership moves to the other process: the next AX notification tears the
        // observer down and clears the observed PID.
        isActive = false
        source.handleAXTitleChanged()

        // Ownership returns with no app switch. handleFocusCheck() is the only thing
        // that runs on that path.
        isActive = true
        source.handleFocusCheck()

        XCTAssertEqual(installAttempts, 2,
                       "handleFocusCheck must re-install the AXObserver once ownership returns")
    }

    /// A refused install leaves `focusObserver` nil, so the re-arm's "no observer" condition
    /// stays true forever. handleFocusCheck runs on every mouse-up and every app activation,
    /// and re-attempting against an AX server that is slow or refusing costs up to the AX
    /// messaging timeout each time — a per-click stall for as long as that app stays
    /// frontmost. The next app switch is what retries it.
    func testFocusCheckDoesNotRetryTheAppWhoseInstallFailed() throws {
        try skipUnlessFrontmostAppIsObservable()

        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        var installAttempts = 0
        var refusals = 0
        source.onLogEvent = { message in
            if Self.isInstallOutcome(message) { installAttempts += 1 }
            if message.hasPrefix("AXObserver: Failed") { refusals += 1 }
        }
        defer { source.stop() }

        source.start()
        try XCTSkipIf(refusals == 0, "the frontmost app accepted the install; nothing was left to retry")

        source.handleFocusCheck()
        source.handleFocusCheck()

        XCTAssertEqual(installAttempts, 1,
                       "a refused install must not be retried until the frontmost app changes")
    }

    /// The two tests above never both run on one host: the first needs an install the
    /// frontmost app accepted, the second one it refused. Without Accessibility
    /// permission — this project's CI runner included — only the second runs, and its
    /// `installAttempts == 1` is equally true of a build carrying no re-arm at all, so
    /// deleting the re-arm block leaves both green. This closes that hole from the
    /// refused side: clearing the suppression by hand is what the next app switch does
    /// for real, and the re-arm in handleFocusCheck is then the only thing that can
    /// produce a second install attempt.
    func testFocusCheckRetriesTheFailedAppOnceTheSuppressionIsCleared() throws {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        var installAttempts = 0
        source.onLogEvent = { message in
            if Self.isInstallOutcome(message) { installAttempts += 1 }
        }
        defer { source.stop() }

        source.start()

        // The precondition stated in its own terms rather than through the frontmost app:
        // only an install that was actually attempted and refused leaves a non-zero failed
        // PID. It stays zero both when the install succeeded and when there was no
        // observable frontmost app to attempt one against, so this test needs neither
        // Accessibility permission nor skipUnlessFrontmostAppIsObservable().
        try XCTSkipIf(source.focusObserverFailedPID == 0,
                      "no install was attempted, or the frontmost app accepted it")
        XCTAssertEqual(installAttempts, 1, "start() attempts the install once")

        source.focusObserverFailedPID = 0
        source.handleFocusCheck()

        XCTAssertEqual(installAttempts, 2,
                       "handleFocusCheck must re-arm the AXObserver once the suppression is lifted")
    }
}
