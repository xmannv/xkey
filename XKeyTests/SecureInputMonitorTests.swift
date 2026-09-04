import Cocoa
import XCTest
@testable import XKey

final class SecureInputMonitorTests: XCTestCase {
    private final class Detector: SecureInputDetecting {
        var observation: SecureInputObservation = .inactive
    }

    private final class ConcurrentDetector: SecureInputDetecting {
        private let lock = NSLock()
        private var samples: [SecureInputObservation]
        private(set) var maximumConcurrentReads = 0
        private var concurrentReads = 0

        init(samples: [SecureInputObservation]) {
            self.samples = samples
        }

        var observation: SecureInputObservation {
            lock.lock()
            concurrentReads += 1
            maximumConcurrentReads = max(maximumConcurrentReads, concurrentReads)
            let sample = samples.removeFirst()
            lock.unlock()

            usleep(1_000)

            lock.lock()
            concurrentReads -= 1
            lock.unlock()
            return sample
        }
    }

    private final class Presenter: SecureInputPresenting {
        private(set) var shownAppNames: [String] = []
        private(set) var hideCount = 0

        func show(appName: String) {
            shownAppNames.append(appName)
        }

        func hide() {
            hideCount += 1
        }
    }

    private final class DeliveryQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [@Sendable () -> Void] = []

        func schedule(_ action: @escaping @Sendable () -> Void) {
            lock.lock()
            actions.append(action)
            lock.unlock()
        }

        func drain() {
            lock.lock()
            let pending = actions
            actions.removeAll()
            lock.unlock()
            pending.forEach { $0() }
        }
    }

    func testHolderLifecycleEmitsAndUpdatesPresentationExactlyOncePerChange() {
        let detector = Detector()
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  transitions: transitions)

        let holderA = observation(pid: 101, name: "1Password")
        detector.observation = holderA
        XCTAssertEqual(monitor.evaluate().transition, .becameActive(holderA))
        XCTAssertNil(monitor.evaluate().transition)
        monitor.waitForPendingDeliveries()

        let holderB = observation(pid: 202, name: "Terminal")
        detector.observation = holderB
        XCTAssertEqual(monitor.evaluate().transition, .holderChanged(holderB))
        monitor.waitForPendingDeliveries()

        detector.observation = .inactive
        XCTAssertEqual(monitor.evaluate().transition, .becameInactive)
        XCTAssertNil(monitor.evaluate().transition)
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(transitions.values,
                       [.becameActive(holderA), .holderChanged(holderB), .becameInactive])
        XCTAssertEqual(presenter.shownAppNames, ["1Password", "Terminal"])
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testSamePIDNameRefinementUpdatesTransitionStatusAndPresenter() {
        let detector = Detector()
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  transitions: transitions)

        let unknown = observation(pid: 101, name: "Unknown")
        detector.observation = unknown
        XCTAssertEqual(monitor.evaluate().transition, .becameActive(unknown))
        monitor.waitForPendingDeliveries()

        let refined = observation(pid: 101, name: "1Password")
        detector.observation = refined
        XCTAssertEqual(monitor.evaluate().transition, .holderChanged(refined))
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(transitions.values, [.becameActive(unknown), .holderChanged(refined)])
        XCTAssertEqual(presenter.shownAppNames, ["Unknown", "1Password"])
    }

    func testUnsupportedCapabilitySuppressesPresentationButNotDetection() {
        let detector = Detector()
        let holder = observation(pid: 101, name: "1Password")
        detector.observation = holder
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  capabilities: XKey.HostCapabilities(supported: []),
                                  transitions: transitions)

        let result = monitor.evaluate()
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(result.transition, .becameActive(holder))
        XCTAssertTrue(result.isActive)
        XCTAssertEqual(result.observation, holder)
        XCTAssertEqual(transitions.values, [.becameActive(holder)])
        XCTAssertTrue(presenter.shownAppNames.isEmpty)
    }

    func testQueuedShowIsSuppressedWhenOwnershipChangesBeforeMainDelivery() {
        let detector = Detector()
        detector.observation = observation(pid: 101, name: "1Password")
        let presenter = Presenter()
        let delivery = DeliveryQueue()
        var ownsPresentation = true
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  ownsPresentation: { ownsPresentation },
                                  transitions: TransitionRecorder(),
                                  deliver: delivery.schedule)

        _ = monitor.evaluate()
        monitor.waitForPendingDeliveries()
        ownsPresentation = false
        _ = monitor.evaluate()
        monitor.waitForPendingDeliveries()
        delivery.drain()

        XCTAssertTrue(presenter.shownAppNames.isEmpty)
        XCTAssertEqual(presenter.hideCount, 0)
    }

    func testPresentationEligibilityIsSampledOnMainForBackgroundEvaluation() {
        let detector = Detector()
        detector.observation = observation(pid: 101, name: "1Password")
        let presenter = Presenter()
        let ownershipRead = expectation(description: "ownership sampled")
        let settingRead = expectation(description: "presentation setting sampled")
        let monitor = SecureInputMonitor(
            detector: detector,
            capabilities: .xkeyIM,
            presenter: presenter,
            ownsPresentation: {
                XCTAssertTrue(Thread.isMainThread)
                ownershipRead.fulfill()
                return true
            },
            presentationEnabled: {
                XCTAssertTrue(Thread.isMainThread)
                settingRead.fulfill()
                return true
            },
            onTransition: { _ in }
        )

        DispatchQueue.global().async {
            _ = monitor.evaluate()
        }

        wait(for: [ownershipRead, settingRead], timeout: 2)
        XCTAssertEqual(presenter.shownAppNames, ["1Password"])
    }

    func testOnlyLatestQueuedHolderUpdatePresents() {
        let detector = Detector()
        let presenter = Presenter()
        let delivery = DeliveryQueue()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  transitions: TransitionRecorder(),
                                  deliver: delivery.schedule)

        detector.observation = observation(pid: 101, name: "A")
        _ = monitor.evaluate()
        monitor.waitForPendingDeliveries()
        delivery.drain()

        detector.observation = observation(pid: 202, name: "B")
        _ = monitor.evaluate()
        detector.observation = observation(pid: 303, name: "C")
        _ = monitor.evaluate()
        monitor.waitForPendingDeliveries()
        delivery.drain()

        XCTAssertEqual(presenter.shownAppNames, ["A", "C"])
    }

    func testPhysicalAndMarkedTextEntryPointsUseAtomicEvaluationResult() {
        let detector = Detector()
        detector.observation = observation(pid: 101, name: "1Password")
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  transitions: transitions)
        let runtime = SecureInputHostRuntime(monitor: monitor)

        XCTAssertTrue(runtime.evaluatePhysicalInput())
        XCTAssertTrue(runtime.evaluateMarkedTextInput())
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(presenter.shownAppNames, ["1Password"])
        XCTAssertEqual(transitions.values.count, 1)
    }

    func testConcurrentEvaluationsSerializeSamplingAndReturnTheirOwnObservation() {
        let samples = (1...20).map {
            SecureInputObservation(isEnabled: $0.isMultiple(of: 2),
                                   holderPID: pid_t($0),
                                   holderAppName: "App \($0)")
        }
        let detector = ConcurrentDetector(samples: samples)
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let monitor = SecureInputMonitor(
            detector: detector,
            capabilities: XKey.HostCapabilities(supported: []),
            presenter: presenter,
            ownsPresentation: { false },
            deliverOnMain: { $0() },
            onTransition: { transitions.append($0) }
        )
        let resultsLock = NSLock()
        var results: [SecureInputEvaluation] = []

        DispatchQueue.concurrentPerform(iterations: samples.count) { _ in
            let result = monitor.evaluate()
            resultsLock.lock()
            results.append(result)
            resultsLock.unlock()
        }
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(detector.maximumConcurrentReads, 1)
        XCTAssertEqual(Set(results.map { $0.observation.holderPID }), Set(samples.map(\.holderPID)))
        XCTAssertTrue(results.allSatisfy { $0.isActive == $0.observation.isEnabled })
    }

    func testInvalidateHidesShownPresenterOnceAndSuppressesPendingCallback() {
        let detector = Detector()
        let holderA = observation(pid: 101, name: "1Password")
        detector.observation = holderA
        let presenter = Presenter()
        let transitions = TransitionRecorder()
        let delivery = DeliveryQueue()
        let monitor = makeMonitor(detector: detector,
                                  presenter: presenter,
                                  transitions: transitions,
                                  deliver: delivery.schedule)

        _ = monitor.evaluate()
        monitor.waitForPendingDeliveries()
        delivery.drain()
        XCTAssertEqual(presenter.shownAppNames, ["1Password"])

        detector.observation = observation(pid: 202, name: "Terminal")
        _ = monitor.evaluate()
        monitor.invalidate()
        monitor.waitForPendingDeliveries()
        delivery.drain()
        monitor.invalidate()
        monitor.waitForPendingDeliveries()

        XCTAssertEqual(presenter.shownAppNames, ["1Password"])
        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(transitions.values, [.becameActive(holderA)])
    }

    func testOverlayPanelIsPassiveAndNonActivating() {
        let panel = FloatingOverlay.makePanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40))

        XCTAssertTrue(panel is PassiveOverlayPanel)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isAccessibilityElement())
    }

    func testSecureInputWarningStyleMatchesSharedVisualContract() {
        XCTAssertEqual(SecureInputWarningStyle.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(SecureInputWarningStyle.layoutSpacing, 8)
        XCTAssertEqual(SecureInputWarningStyle.cornerRadius, 10)
        XCTAssertEqual(SecureInputWarningStyle.borderWidth, 1)
        XCTAssertEqual(SecureInputWarningStyle.borderOpacity, 0.4)
        XCTAssertEqual(SecureInputWarningStyle.backgroundOpacity, 0.9)
        XCTAssertEqual(SecureInputWarningStyle.fadeDuration, 0.25)
    }

    private func observation(pid: pid_t, name: String) -> SecureInputObservation {
        SecureInputObservation(isEnabled: true, holderPID: pid, holderAppName: name)
    }

    private func makeMonitor(
        detector: SecureInputDetecting,
        presenter: Presenter,
        capabilities: XKey.HostCapabilities = .xkeyIM,
        ownsPresentation: @escaping () -> Bool = { true },
        transitions: TransitionRecorder,
        deliver: @escaping (@escaping @Sendable () -> Void) -> Void = { $0() }
    ) -> SecureInputMonitor {
        SecureInputMonitor(
            detector: detector,
            stateMachine: SecureInputStateMachine(),
            capabilities: capabilities,
            presenter: presenter,
            ownsPresentation: ownsPresentation,
            deliverOnMain: deliver,
            onTransition: { transitions.append($0) }
        )
    }
}

private final class TransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecureInputTransition] = []

    var values: [SecureInputTransition] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ transition: SecureInputTransition) {
        lock.lock()
        storage.append(transition)
        lock.unlock()
    }
}
