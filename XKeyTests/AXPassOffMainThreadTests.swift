//
//  AXPassOffMainThreadTests.swift
//  XKeyTests
//
//  The freeze these cover was measured, not inferred: `sample` of XKeyIM's main
//  thread while typing in Chrome put 90% of it blocked in
//  AXUIElementCopyAttributeValue → mach_msg2_trap, under
//  TapEventSource.handleAXFocusChanged → FocusedElementInfo.from. The CGEventTap
//  callback runs on that same thread, so keystrokes queued behind the AX reads.
//
//  No test can observe a stalled main thread directly. What it can observe is the
//  property that removes the stall — the entry point returns to its caller before
//  the AX work is done — plus the two rules that make overlapping passes safe:
//  only the newest is applied, and stop() drops the ones in flight.
//

import XCTest
@testable import XKey

final class AXPassOffMainThreadTests: XCTestCase {

    private var originalTempOffToolbarEnabled = false

    override func setUp() {
        super.setUp()
        // With the temp-off toolbar enabled, a focus pass always reports through exactly
        // one of onNoFocusedElement (nothing focused) or onCheckToolbarForFocusedElement
        // (something was), whether or not this process has Accessibility permission.
        originalTempOffToolbarEnabled = SharedSettings.shared.tempOffToolbarEnabled
        SharedSettings.shared.tempOffToolbarEnabled = true
    }

    override func tearDown() {
        SharedSettings.shared.tempOffToolbarEnabled = originalTempOffToolbarEnabled
        // start() installs this on a shared singleton; clear it so a failed assertion
        // cannot leak a live closure into the next test.
        OverlayAppDetector.shared.onOverlayVisibilityChanged = nil
        // A test that leaves the overlay cache positive would arm the detector's 0.5s
        // monitor timer — which then does real AX polling underneath every later test.
        resetOverlayDetector()
        AppBehaviorDetector.shared.clearConfirmedInjectionMethod()
        // Both also live on a shared singleton that start() writes to.
        AppBehaviorDetector.shared.clearInjectionMethodFallback()
        AppBehaviorDetector.shared.scheduleInjectionMethodDetection = nil
        super.tearDown()
    }

    /// Return the shared detector to "nothing visible, nothing armed".
    ///
    /// Its state is private, so the probe API is the only way in, and only the dismiss
    /// branch clears every field at once (cache, name, wasOverlayVisible, probeNeeded) —
    /// hence the deliberate detour through a positive find first. Every step is
    /// synchronous on the main thread and needs no Accessibility permission: the AX read
    /// is the half that is being substituted for.
    private func resetOverlayDetector() {
        let detector = OverlayAppDetector.shared
        detector.onOverlayVisibilityChanged = nil
        // Cleared before the arms below, or a chase left running by an earlier test would
        // start reading AX in the middle of this reset.
        detector.onProbeArmed = nil
        // Same singleton, same reason: a source that failed its assertions before stop()
        // would otherwise keep the 0.5s monitor reading AX on its queue for the rest of
        // the run.
        detector.onOverlayReadNeeded = nil
        detector.armProbe()
        guard let found = detector.beginProbe() else { return }
        detector.finishProbe(found, overlayName: "Spotlight")
        detector.armProbe()
        guard let gone = detector.beginProbe() else { return }
        detector.finishProbe(gone, overlayName: nil)
    }

    /// Spin the main run loop until `condition` holds, or fail.
    ///
    /// For the chase, whose pace is set by how long each AX read takes: a fixed sleep that
    /// is long enough on an idle machine is a flake on a loaded one, and one long enough
    /// for a loaded machine is dead time on every run.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 20,
                           condition: @escaping () -> Bool) {
        let met = expectation(description: description)
        let poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard condition() else { return }
            timer.invalidate()
            met.fulfill()
        }
        wait(for: [met], timeout: timeout)
        poll.invalidate()
    }

    /// Counts the passes that reached their main-thread stage, and fulfils on the first.
    private func countReports(on source: TapEventSource,
                              expectation: XCTestExpectation?) -> () -> Int {
        var reports = 0
        let record: () -> Void = {
            reports += 1
            expectation?.fulfill()
        }
        source.onNoFocusedElement = record
        source.onCheckToolbarForFocusedElement = { _ in record() }
        return { reports }
    }

    /// The property the fix is: the AX round-trips happen after the entry point has
    /// already returned to its caller. Deterministic rather than timing-dependent — the
    /// pass reports back through DispatchQueue.main.async, which cannot run while this
    /// test method is still on the main thread.
    func testFocusCheckReturnsBeforeItsAXPassCompletes() {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        let reported = expectation(description: "the AX pass reported back")
        let reports = countReports(on: source, expectation: reported)

        source.handleFocusCheck()

        XCTAssertEqual(reports(), 0,
                       "handleFocusCheck must return before its AX reads finish — doing them inline is the stall")
        wait(for: [reported], timeout: 5)
        XCTAssertEqual(reports(), 1)
    }

    /// Two passes scheduled back to back: the second arrives while the first is in
    /// flight. The first must be dropped when it lands — its snapshot describes a
    /// context that has already been superseded — and the second must still run.
    /// Exactly one application, not two, and not zero.
    func testOnlyTheNewestOfTwoOverlappingPassesIsApplied() {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        let reported = expectation(description: "a pass reported back")
        reported.assertForOverFulfill = false
        let reports = countReports(on: source, expectation: reported)

        source.handleFocusCheck()
        source.handleFocusCheck()

        wait(for: [reported], timeout: 5)
        // Give the second pass room to land too, so "1" means one was dropped rather
        // than one being merely slower than the other.
        let settled = expectation(description: "both passes had time to land")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(reports(), 1,
                       "the superseded pass must be dropped, and the newest one must still be applied")
    }

    /// stop() bumps the generation, so a pass already on the queue lands on nothing.
    /// deinit calls stop(), which is what keeps a released source from being reached by
    /// its own in-flight work.
    func testStopDropsAPassThatIsAlreadyInFlight() {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        let neverReported = expectation(description: "no pass reports after stop()")
        neverReported.isInverted = true
        let reports = countReports(on: source, expectation: neverReported)

        source.start()
        source.handleFocusCheck()
        source.stop()

        wait(for: [neverReported], timeout: 2)
        XCTAssertEqual(reports(), 0, "a pass in flight when stop() runs must apply nothing")
    }

    // MARK: - The overlay probe, once its read runs on another thread

    /// A nil read that left the main thread while nothing was visible must not dismiss an
    /// overlay that was found while it was in flight.
    ///
    /// The interleaving, all on main except the read: Cmd+Space arms a probe; an AX pass
    /// begins it and hands the read to axPassQueue, where it sees nothing because
    /// Spotlight is not up yet; Spotlight appears; the first keystroke's own probe finds
    /// it and turns the cache positive; only then does the pass's nil come back. Without
    /// the guard that nil takes the dismiss branch and fires the whole "overlay closed"
    /// sequence with the overlay still open, and the state does not heal for the rest of
    /// the session: checkOverlayStateChange() returns immediately once wasOverlayVisible
    /// is false, and probes are armed by modifier keys, Esc and mouse-up only — never by
    /// typing inside the overlay.
    func testStaleNilReadDoesNotDismissAnOverlayFoundWhileItWasInFlight() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        var transitions: [Bool] = []
        detector.onOverlayVisibilityChanged = { isVisible, _ in transitions.append(isVisible) }

        // The pass takes its token and leaves for the queue.
        detector.armProbe()
        guard let inFlight = detector.beginProbe() else {
            return XCTFail("an armed probe must hand out a token")
        }

        // Spotlight appears; a keystroke's own probe finds it before the read returns.
        guard let keystroke = detector.beginProbe() else {
            return XCTFail("the probe stays armed until something finds an overlay")
        }
        XCTAssertTrue(detector.finishProbe(keystroke, overlayName: "Spotlight"))
        XCTAssertEqual(transitions, [true])

        // The queue's nil finally lands.
        let stillVisible = detector.finishProbe(inFlight, overlayName: nil)

        XCTAssertTrue(stillVisible,
                      "a nil decided against an empty cache must not overrule the find that followed it")
        XCTAssertEqual(detector.lastKnownOverlayName, "Spotlight",
                       "the overlay is still open — its cache entry must survive the stale nil")
        XCTAssertEqual(transitions, [true],
                       "no 'overlay closed' may fire while the overlay is open")
    }

    /// The positive control for the guard above: a nil read decided against a cache that
    /// was already positive still dismisses. This is the Esc/Return/click path — the one
    /// the probe's fresh branch exists for — and the stale-read guard must not cost it.
    func testFreshNilReadStillDismissesAnOverlayThatWasVisibleWhenTheReadBegan() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        var transitions: [Bool] = []
        var closingName: String?
        detector.onOverlayVisibilityChanged = { isVisible, name in
            transitions.append(isVisible)
            closingName = name
        }

        detector.armProbe()
        guard let opening = detector.beginProbe() else {
            return XCTFail("an armed probe must hand out a token")
        }
        XCTAssertTrue(detector.finishProbe(opening, overlayName: "Spotlight"))

        // Esc arms a fresh probe; this one begins with the cache already positive.
        detector.armProbe()
        guard let closing = detector.beginProbe() else {
            return XCTFail("an armed probe must hand out a token")
        }
        let stillVisible = detector.finishProbe(closing, overlayName: nil)

        XCTAssertFalse(stillVisible, "a nil read that began against a visible overlay still dismisses")
        XCTAssertNil(detector.lastKnownOverlayName)
        XCTAssertEqual(transitions, [true, false])
        XCTAssertEqual(closingName, "Spotlight",
                       "the closing name is what Smart Switch saves the overlay's language under")
    }

    // MARK: - The app-switch work that must not ride on a droppable pass

    /// The AXObserver install and the Secure Input re-evaluation must be done by the
    /// app-switch block itself, not by the AX pass it schedules.
    ///
    /// The pass is droppable by design — scheduleAXPass bumps the generation even when
    /// the pass only lands in the pending slot, and the coalescer evicts whatever is in
    /// that slot — and neither of those two is a detection result that a later pass would
    /// redo. Losing the observer install in particular does not heal at all: it is the
    /// only place the observer moves to the new app.
    ///
    /// What this pins is the property that makes them undroppable: they complete before
    /// the app-switch block returns, i.e. before the pass can even reach its main-thread
    /// stage. The checkpoint is enqueued from onSmartSwitch, which the block calls on its
    /// first line — before scheduleAXPass exists to hand anything to axPassQueue — so the
    /// main queue runs it strictly ahead of anything that pass enqueues.
    func testAppSwitchInstallsItsObserverAndChecksSecureInputBeforeTheAXPass() {
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        var secureInputChecks = 0
        source.onEvaluateSecureInput = { secureInputChecks += 1 }

        var checksWhenBlockReturned = -1
        var methodConfirmedWhenBlockReturned = true
        let blockReturned = expectation(description: "the app-switch block returned")
        source.onSmartSwitch = { _ in
            DispatchQueue.main.async {
                checksWhenBlockReturned = secureInputChecks
                methodConfirmedWhenBlockReturned = AppBehaviorDetector.shared.confirmedInjectionMethod != nil
                blockReturned.fulfill()
            }
        }

        source.start()
        defer { source.stop() }

        // The app-switch block reads its NSRunningApplication out of this userInfo, the
        // same way NSWorkspace delivers a real activation.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        wait(for: [blockReturned], timeout: 5)

        XCTAssertFalse(methodConfirmedWhenBlockReturned,
                       "the checkpoint must land before the pass applies, or it proves nothing")
        XCTAssertEqual(checksWhenBlockReturned, 1,
                       "Secure Input must be re-evaluated by the app-switch block itself — inside the pass it is lost every time the pass is dropped")
    }

    // MARK: - No AX on the tap thread

    /// The keystroke path must read OverlayAppDetector's cache and never run its probe.
    ///
    /// `isOverlayAppVisible()` asks the frontmost app's focused element four questions plus
    /// AXHelper.getFocusedElement() — up to five blocking round-trips per keystroke, and
    /// 680 of the 936 CGEventTap-callback samples in the profile behind this change.
    ///
    /// The detector is left holding a visible overlay AND a fresh probe, which is the state
    /// where a probe and a cache read differ observably: a real probe here would read AX,
    /// find nothing (no launcher is open under a test run, and without Accessibility
    /// permission the read cannot even be made), take finishProbe's fresh-nil branch and
    /// dismiss the overlay. So a surviving cache, an unspent probe and no visibility
    /// transition together mean no probe ran.
    func testTheTapPathReadsTheOverlayCacheWithoutRunningItsProbe() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        detector.armProbe()
        guard let opening = detector.beginProbe() else {
            return XCTFail("an armed probe must hand out a token")
        }
        XCTAssertTrue(detector.finishProbe(opening, overlayName: "Spotlight"))
        detector.armProbe()

        var transitions: [Bool] = []
        detector.onOverlayVisibilityChanged = { isVisible, _ in transitions.append(isVisible) }

        // Window Title Rules off for the duration: with them on, effectiveVietnameseEnabled()
        // can be forced either way by whatever rules this machine has stored, and the
        // vLanguage checkpoint below would stop proving anything.
        let originalRulesEnabled = AppBehaviorDetector.shared.windowTitleRulesEnabled
        AppBehaviorDetector.shared.windowTitleRulesEnabled = false
        defer { AppBehaviorDetector.shared.windowTitleRulesEnabled = originalRulesEnabled }

        let handler = KeyboardEventHandler()
        handler.setVietnamese(true)
        handler.engine.vLanguage = 0
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true) else {
            return XCTFail("could not synthesise a keyDown")
        }

        _ = handler.shouldProcessEvent(event, type: .keyDown)

        // shouldProcessEvent writes vLanguage on the line after isCurrentAppExcluded()
        // returns, so this is the checkpoint that the overlay branch was actually reached —
        // without it the assertions below would also hold for a call that returned early at
        // the tap-ownership guard above them.
        XCTAssertEqual(handler.engine.vLanguage, 1,
                       "the call must reach past isCurrentAppExcluded() — a 0 here means it returned at the tap-ownership guard, so another process owns the tap in this environment")
        XCTAssertTrue(detector.lastKnownOverlayVisible,
                      "the overlay is still open — the tap path must not have dismissed it")
        XCTAssertEqual(detector.lastKnownOverlayName, "Spotlight")
        XCTAssertTrue(detector.isProbeArmed,
                      "the probe must still be armed — spending it here means the AX read happened on the tap thread")
        XCTAssertEqual(transitions, [],
                       "no visibility transition may be produced by a keystroke")
    }

    /// Nothing on the keystroke path spends an overlay probe any more, so the source has to
    /// — across both of the probe's windows, and then stop.
    ///
    /// armProbe() is the moment an overlay MAY be opening (Cmd+Space, a click, Esc). With no
    /// launcher actually opening, every read the chase makes comes back nil and leaves the
    /// probe armed, so the chain retries until beginProbe() expires the probe at the end of
    /// its 0.8s window and hands out the find-only last-chance read — the one the first
    /// keystroke used to make. The chase re-arms once on that read coming back empty,
    /// because after it nothing would ever look again: the tap path reads the cache and
    /// never probes, ordinary characters arm no probe, and the 0.5s monitor returns on
    /// `guard wasOverlayVisible`. A launcher that cold-starts past 0.8s (Raycast or Alfred
    /// on first launch, Spotlight on a loaded machine) would otherwise never be detected,
    /// and the first character typed into it would go through the underlying app's
    /// injection method and be scrambled by the launcher's inline autocomplete.
    ///
    /// Three failures are in scope here: a probe still armed at the end means the arming
    /// signal reached nobody; one arm means a late launcher is never seen; more than two
    /// means a Cmd+C leaves a chain reading AX for good.
    ///
    /// Counted through onProbeArmed rather than timed, because how long the chain takes is
    /// set by how long each AX read takes — under a parallel test run, not something a
    /// fixed sleep can bound. The second arm can only be the chase's: this test arms one
    /// probe itself and no other signal reaches the detector.
    func testAChaseResolvesAnArmedProbeAcrossBothWindowsAndThenStops() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.start()
        defer { source.stop() }

        // Replaces the source's own handler: this test is about the probe being spent, and
        // a find would otherwise schedule an injection-method pass that outlives the test.
        var transitions: [Bool] = []
        detector.onOverlayVisibilityChanged = { isVisible, _ in transitions.append(isVisible) }

        // Wraps the source's handler instead of replacing it — replacing it would leave
        // nothing to run the chase whose re-arm this counts.
        let startChase = detector.onProbeArmed
        var arms = 0
        detector.onProbeArmed = {
            arms += 1
            startChase?()
        }

        detector.armProbe()
        XCTAssertTrue(detector.isProbeArmed)

        // arms == 2 rules out the first window's expiry, where the probe is also briefly
        // disarmed; both together can only be the second window closing.
        waitUntil("the chase spent the probe for good") {
            arms == 2 && !detector.isProbeArmed
        }

        // Long enough for another chase step to have woken and read: the chain must be
        // over, not merely between reads.
        let settled = expectation(description: "the chain had room to continue if it were still alive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(arms, 2,
                       "one window is not enough for a launcher that is still starting up, and a chase that kept re-arming would never stop")
        XCTAssertFalse(detector.isProbeArmed,
                       "an armed probe must be resolved off the keystroke path — nothing on it reads AX any more")
        XCTAssertFalse(detector.lastKnownOverlayVisible)
        XCTAssertEqual(transitions, [], "no launcher opened, so no transition may be reported")
    }

    /// The chase's backoff is measured from the arming signal, not from the burst that
    /// signal arrives in.
    ///
    /// Arming signals come in bursts: Cmd goes down, and the chord that opens the launcher
    /// follows tens or hundreds of milliseconds later. A backoff that counted the chain's
    /// own reads would already be in its long gaps by the time the chord arrives — with
    /// Cmd held 100ms the reads land at chord−100, −50 and +50, then not again until +250,
    /// which is past a first character at ~chord+200ms. That character goes out on the
    /// underlying app's injection method and is scrambled by the launcher's inline
    /// autocomplete.
    ///
    /// The index is what this asserts because the interval it selects is not observable
    /// from outside: with no launcher open every chase read resolves to nil, which leaves
    /// the probe armed and the cache where it was, so the reads themselves leave no trace.
    func testANewArmingSignalRestartsTheChaseBackoff() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.start()
        defer { source.stop() }

        // Cmd goes down: the burst's first arm, and the chain starts on it.
        detector.armProbe()

        // Index 2 of [0.05, 0.1, 0.2, 0.4] is already a 200ms gap, four times the first —
        // the regime a chord must not be left in. Two reads get there, ~50ms into the
        // probe's 0.8s window, so the chain is still alive for the arm below.
        waitUntil("the chase backed off past its short gaps") {
            source.overlayChaseBackoff >= 2
        }
        let backedOff = source.overlayChaseBackoff

        // The chord. armProbe() reaches startOverlayChase() synchronously through
        // onProbeArmed, so the restart has already happened when this returns.
        detector.armProbe()

        XCTAssertEqual(source.overlayChaseBackoff, 0,
                       "a new arming signal must restart the backoff — left at index \(backedOff), the chain's next read lands hundreds of milliseconds after the character the launcher would have taken")
        XCTAssertTrue(detector.isProbeArmed,
                      "the arm under test must still be live — a spent probe would mean the chain ended rather than restarted")

    }

    /// An arming signal must leave no chase read sleeping.
    ///
    /// Restarting the backoff is only half of aiming the chase at the chord. The gap the
    /// PREVIOUS arm scheduled is already on the main queue, and a restart does not move it:
    /// reads land at 0, 50, 150, 350, 750ms from the chain's start, so a chord arriving
    /// just after one of them waits out the whole gap already running — up to 400ms,
    /// against a first character at roughly chord+200ms. On the losing side of that the
    /// launcher takes the character on the underlying app's injection method, and its
    /// inline autocomplete scrambles it.
    ///
    /// Two things are asserted, because either on its own can hold while the chase still
    /// waits: that nothing is left sleeping, and that a read was actually taken. The second
    /// rides on axPassQueue being serial. The test puts a read of its own on that queue
    /// through the detector's onOverlayReadNeeded hook — the same queue the chase uses —
    /// immediately after the arm, so a chase read the arm enqueued must run, and report
    /// back on main, ahead of it. That report is what advances the backoff off 0, so a
    /// backoff still at 0 when this test's own read returns means the arm took no read.
    func testAnArmingSignalTakesTheSleepingChaseReadNow() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.start()
        defer { source.stop() }

        guard let readOnAXPassQueue = detector.onOverlayReadNeeded else {
            XCTFail("start() must install the off-main overlay read this test rides on")
            return
        }

        // Cmd goes down: the burst's first arm, and the chain starts on it.
        detector.armProbe()

        // Index 3 of [0.05, 0.1, 0.2, 0.4] is reached by the third read, ~150ms in, and the
        // step then sleeping was scheduled with index 2's 200ms — the regime a chord must
        // not be left waiting in. Both halves of the condition matter: the chain must be
        // between reads, or there is no sleep for the arm below to drop.
        waitUntil("the chase is sleeping out one of its long gaps") {
            source.overlayChaseBackoff >= 3 && source.overlayChaseStepWorkItem != nil
        }

        // The chord. armProbe() reaches startOverlayChase() synchronously through
        // onProbeArmed, so everything that signal does has happened when this returns.
        detector.armProbe()

        XCTAssertNil(source.overlayChaseStepWorkItem,
                     "a chase read left sleeping would not wake for up to another 200ms — past the first character the launcher takes")
        XCTAssertEqual(source.overlayChaseBackoff, 0,
                       "the restart this builds on must still happen")

        let mine = expectation(description: "the test's own read on axPassQueue came back")
        var backoffWhenMineReturned = -1
        readOnAXPassQueue { _ in
            backoffWhenMineReturned = source.overlayChaseBackoff
            mine.fulfill()
        }
        wait(for: [mine], timeout: 20)

        XCTAssertGreaterThanOrEqual(backoffWhenMineReturned, 1,
                                    "the arm must have put a read on the serial queue ahead of this one — a backoff still at 0 means the sleeping step was dropped rather than taken")
        XCTAssertTrue(detector.isProbeArmed,
                      "no launcher opened, so the reads resolve to nil and the probe stays armed — a spent probe would mean this measured the chain ending")
    }

    /// A cleared cache must be answered from the last confirmation, not by detecting.
    ///
    /// The marker method is what makes this a proof rather than a smoke test: a live
    /// detection would describe whatever app is frontmost under the test runner, and could
    /// not return a description this test invented.
    func testAnInjectionMethodCacheMissIsAnsweredWithoutDetecting() {
        let detector = AppBehaviorDetector.shared
        detector.clearInjectionMethodFallback()

        let marker = InjectionMethodInfo(method: .slow,
                                         delays: (1, 2, 3),
                                         textSendingMethod: .oneByOne,
                                         description: "unit-test marker")
        detector.setConfirmedInjectionMethod(marker)
        detector.clearConfirmedInjectionMethod()

        let answer = detector.getConfirmedInjectionMethod()

        XCTAssertEqual(answer.description, marker.description,
                       "the tap must fall back to the last confirmation instead of running a live AX detection")
        XCTAssertNil(detector.confirmedInjectionMethod,
                     "answering a miss must not confirm anything — the fallback is not a detection result")
    }

    /// A launcher's method must never become the fallback.
    ///
    /// An overlay is a transient surface: while it is up the confirmed slot is set and
    /// nothing falls back, and the keystroke right after it closes runs on a cleared cache
    /// (the close path calls resetWithCursorMoved). Retained, .axDirect would take that
    /// keystroke and inject into the underlying app through the AX text-field path.
    func testAnOverlayMethodNeverBecomesTheFallback() {
        let detector = AppBehaviorDetector.shared
        detector.clearInjectionMethodFallback()

        let overlayMarker = InjectionMethodInfo(method: .axDirect,
                                                delays: InjectionMethod.axDirect.defaultDelays,
                                                textSendingMethod: .chunked,
                                                description: "unit-test overlay marker",
                                                isOverlay: true)
        detector.setConfirmedInjectionMethod(overlayMarker)
        detector.clearConfirmedInjectionMethod()

        let answer = detector.getConfirmedInjectionMethod()

        XCTAssertNotEqual(answer.description, overlayMarker.description,
                          "the launcher is gone by the time this is read — its method must not answer for the app underneath")
        XCTAssertEqual(answer.description, InjectionMethodInfo.defaultFast.description,
                       "with nothing else ever confirmed, the answer is the default")
    }

    /// The fallback describes the app it was confirmed in, so an app switch drops it.
    func testAnAppSwitchDropsTheInjectionMethodFallback() {
        let detector = AppBehaviorDetector.shared
        let marker = InjectionMethodInfo(method: .slow,
                                         delays: (1, 2, 3),
                                         textSendingMethod: .oneByOne,
                                         description: "unit-test marker")

        detector.setConfirmedInjectionMethod(marker)
        detector.clearConfirmedInjectionMethod()
        detector.clearInjectionMethodFallback()

        let answer = detector.getConfirmedInjectionMethod()
        XCTAssertNotEqual(answer.description, marker.description,
                          "the app the user just left must not keep answering for the one they switched to")
        XCTAssertEqual(answer.description, InjectionMethodInfo.defaultFast.description,
                       "with no fallback left, the answer is the default")
    }

    /// The app-switch block is what actually drops it. The test above calls
    /// clearInjectionMethodFallback() itself and so says nothing about whether anything in
    /// production does.
    ///
    /// Read from onSmartSwitch, which the block reaches after both clears and before the
    /// AX pass it schedules can refill anything — that pass hops to axPassQueue first, so
    /// none of it can run while this callback is on the main thread.
    func testTheAppSwitchBlockDropsTheInjectionMethodFallback() {
        let detector = AppBehaviorDetector.shared
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })

        let marker = InjectionMethodInfo(method: .slow,
                                         delays: (1, 2, 3),
                                         textSendingMethod: .oneByOne,
                                         description: "unit-test marker")

        var answerAtSwitch: String?
        let switched = expectation(description: "the app-switch block reached Smart Switch")
        source.onSmartSwitch = { _ in
            answerAtSwitch = detector.getConfirmedInjectionMethod().description
            switched.fulfill()
        }

        source.start()
        defer { source.stop() }

        detector.setConfirmedInjectionMethod(marker)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        wait(for: [switched], timeout: 5)

        XCTAssertEqual(answerAtSwitch, InjectionMethodInfo.defaultFast.description,
                       "the app the user just left must stop answering for the one they switched to — the block has to drop the fallback, not only the confirmed slot")
    }

    /// One request per cleared-cache episode, not one per keystroke.
    ///
    /// Each request bumps axPassGeneration, which drops the pass already in flight. A
    /// request on every keystroke would keep superseding the detection meant to end the
    /// misses, and the faster the user typed the longer the cache would stay empty.
    func testACacheMissAsksForExactlyOneDetectionUntilOneLands() {
        let detector = AppBehaviorDetector.shared
        var requests = 0
        detector.scheduleInjectionMethodDetection = { _ in requests += 1 }
        defer { detector.scheduleInjectionMethodDetection = nil }

        detector.clearConfirmedInjectionMethod()
        for _ in 0..<5 {
            _ = detector.getConfirmedInjectionMethod()
        }
        XCTAssertEqual(requests, 1, "five keystrokes on an empty cache must ask once")

        // A confirmation ends the episode; the next clear starts a new one.
        detector.setConfirmedInjectionMethod(.defaultFast)
        detector.clearConfirmedInjectionMethod()
        _ = detector.getConfirmedInjectionMethod()
        XCTAssertEqual(requests, 2, "a later clear must be able to ask again")
    }

    /// The 0.5s dismissal poll must not read AX on the run loop the tap callback runs on.
    ///
    /// `guard wasOverlayVisible` keeps it free at steady state, but while a launcher IS
    /// open it is up to five blocking round-trips every half second — during the exact
    /// moments the user is typing into that launcher, which is the
    /// kCGEventTapDisabledByTimeout failure this work exists to remove.
    ///
    /// The overlay is made visible before start(), so no chase is running and the reads
    /// counted here can only be the monitor's.
    func testTheDismissalMonitorTakesItsAXReadOffTheTapRunLoop() {
        let detector = OverlayAppDetector.shared
        resetOverlayDetector()

        detector.armProbe()
        guard let opening = detector.beginProbe() else {
            return XCTFail("an armed probe must hand out a token")
        }
        XCTAssertTrue(detector.finishProbe(opening, overlayName: "Spotlight"))

        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.start()
        defer { source.stop() }

        var transitions: [Bool] = []
        detector.onOverlayVisibilityChanged = { isVisible, _ in transitions.append(isVisible) }

        guard let hostRead = detector.onOverlayReadNeeded else {
            return XCTFail("start() must give the monitor somewhere other than this thread to read")
        }
        var offThreadReads = 0
        detector.onOverlayReadNeeded = { completion in
            offThreadReads += 1
            hostRead(completion)
        }

        waitUntil("the monitor polled and applied what it read") {
            offThreadReads >= 1 && !transitions.isEmpty
        }

        XCTAssertGreaterThanOrEqual(offThreadReads, 1,
                                    "while an overlay is open the monitor polls — every one of those reads must leave this thread")
        XCTAssertEqual(transitions, [false],
                       "no launcher is really open under a test run, so the poll must still dismiss the one this test staged")
    }

    // MARK: - The browser chord's re-detection budget

    /// The reprobe schedules twice, and the second shot is far enough out to be settle
    /// time rather than a second guess at the same moment.
    ///
    /// It matters because the pass RECORDS what it finds: setConfirmedInjectionMethod
    /// writes the confirmed slot and the tap's fallback and clears
    /// injectionMethodDetectionRequested, so a single shot fired before Chrome has moved
    /// focus pins the pre-chord method with only the 100ms-throttled AXObserver left to
    /// undo it.
    ///
    /// Driven past the browser gate, which is the half no test can open: it reads the
    /// frontmost application, and that is never a browser under a test run.
    func testTheBrowserChordReprobeSchedulesTwiceWithSettleTime() {
        let detector = AppBehaviorDetector.shared
        var delays: [TimeInterval] = []
        detector.scheduleInjectionMethodDetection = { delays.append($0) }
        defer { detector.scheduleInjectionMethodDetection = nil }

        detector.scheduleMethodReprobe()

        XCTAssertEqual(delays.count, 2,
                       "one shot is the browser's entire budget, and whatever it reads is recorded")
        XCTAssertEqual(delays.first, 0.05,
                       "the first shot must land ahead of a first character at ~200ms")
        XCTAssertGreaterThanOrEqual(delays.last ?? 0, 0.2,
                                    "the second shot is the settle time — a browser opening a tab on a loaded machine needs more than 50ms to move focus")
    }

    /// The gate itself: chord-driven focus jumps into autocomplete fields are a browser
    /// pattern, and every other app keeps the event-driven paths.
    ///
    /// Asserted on the predicate rather than on armMethodReprobe(), which reads the
    /// frontmost application: a test that did that would pass or fail on whichever window
    /// happened to be in front when the suite ran.
    func testTheReprobeGateIsBrowsersOnly() {
        XCTAssertTrue(AppBehaviorDetector.isReprobeBrowser("com.google.Chrome"))
        XCTAssertTrue(AppBehaviorDetector.isReprobeBrowser("org.mozilla.firefox"))
        XCTAssertFalse(AppBehaviorDetector.isReprobeBrowser("com.apple.finder"))
        XCTAssertFalse(AppBehaviorDetector.isReprobeBrowser("com.apple.Terminal"))
    }

    /// An overlay must not erase the policy the tap falls back on.
    ///
    /// detectInjectionMethod's overlay branch confirms `(nil, nil)` — right while a
    /// launcher is up, wrong the moment it closes. The close path calls
    /// resetWithCursorMoved() synchronously from onOverlayVisibilityChanged, so the
    /// keystrokes between the close and the async pass that re-confirms read the fallback:
    /// if the launcher's `(nil, nil)` were mirrored into it, a window the user configured
    /// "force disable Vietnamese" would have Vietnamese on for that whole window.
    ///
    /// Window Title Rules stay ON for this one. Turning them off is what the other tests
    /// here do to keep the environment quiet, but findAllMatchingRules() returns on that
    /// master switch before it matches anything, so with it off there is no policy to
    /// compute and nothing to lose.
    func testAnOverlayDoesNotEraseTheInputMethodPolicyFallback() {
        let detector = AppBehaviorDetector.shared
        guard detector.getCurrentBundleId() != nil else {
            return XCTFail("no frontmost app — detectInjectionMethod returns before it merges any rule")
        }

        // Custom rules only reach findAllMatchingRules() through the shared store, so this
        // writes to it. Restored byte for byte rather than through reorderCustomRules(),
        // which would persist whatever the in-memory list happened to hold.
        let savedRulesData = SharedSettings.shared.getWindowTitleRulesData() ?? Data("[]".utf8)
        let savedRulesEnabled = detector.windowTitleRulesEnabled
        defer {
            SharedSettings.shared.setWindowTitleRulesData(savedRulesData)
            detector.loadCustomRules()
            detector.windowTitleRulesEnabled = savedRulesEnabled
            detector.overlayAppNameProvider = nil
            detector.clearConfirmedInjectionMethod()
            detector.clearInjectionMethodFallback()
        }

        detector.windowTitleRulesEnabled = true
        detector.reorderCustomRules([
            WindowTitleRule(name: "unit-test force disable",
                            bundleIdPattern: "*",
                            titlePattern: "",
                            matchMode: .contains,
                            inputMethodPolicy: .disable)
        ])

        // The window the user is typing in: its policy is confirmed and remembered.
        detector.overlayAppNameProvider = nil
        detector.clearInjectionMethodFallback()
        _ = detector.detectInjectionMethod()
        XCTAssertEqual(detector.getInputMethodPolicyOverride().policy, .disable,
                       "the rule must match under the test runner, or the rest of this proves nothing")

        // A launcher opens over it: no window-title rule applies inside the launcher.
        detector.overlayAppNameProvider = { "Spotlight" }
        _ = detector.detectInjectionMethod()
        XCTAssertNil(detector.getInputMethodPolicyOverride().policy,
                     "the underlying window's rules must not leak into the launcher")

        // It closes; resetWithCursorMoved() empties the confirmed slot, and the next
        // keystroke is answered from the fallback.
        detector.overlayAppNameProvider = nil
        detector.clearConfirmedInjectionMethod()

        XCTAssertEqual(detector.getInputMethodPolicyOverride().policy, .disable,
                       "the window's policy must survive the launcher that covered it")
    }

    /// The request the tap makes is answered by an AX pass, after the request returns.
    ///
    /// Pins the wiring end to end: start() installs the callback, and what it runs is a
    /// scheduleAXPass, so the detection the tap could not make itself still happens —
    /// somewhere else, and later.
    func testTheTapsDetectionRequestIsAnsweredByAnOffMainPass() {
        let detector = AppBehaviorDetector.shared
        let source = TapEventSource(handler: KeyboardEventHandler(), isActiveHost: { true })
        source.start()
        defer { source.stop() }

        detector.clearConfirmedInjectionMethod()
        detector.clearInjectionMethodFallback()

        _ = detector.getConfirmedInjectionMethod()

        XCTAssertNil(detector.confirmedInjectionMethod,
                     "the request must not have been answered on this thread")

        let settled = expectation(description: "the requested detection landed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertNotNil(detector.confirmedInjectionMethod,
                        "nothing else would refill the cache — the request is what the tap has instead of detecting")
    }
}
