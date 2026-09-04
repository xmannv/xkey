@preconcurrency import Foundation

protocol SecureInputPresenting: AnyObject {
    func show(appName: String)
    func hide()
}

struct SecureInputEvaluation: Equatable, Sendable {
    let observation: SecureInputObservation
    let transition: SecureInputTransition?

    var isActive: Bool {
        observation.isEnabled
    }
}

final class SecureInputMonitor: @unchecked Sendable {
    private enum PresentationAction: Sendable {
        case show(String)
        case hide
    }

    private struct PresentationDecision: Sendable {
        let generation: UInt64
        let desired: SecureInputObservation?
    }

    private let detector: SecureInputDetecting
    private let capabilities: HostCapabilities
    private let presenter: SecureInputPresenting
    private let ownsPresentation: () -> Bool
    private let presentationEnabled: () -> Bool
    private let deliverOnMain: (@escaping @Sendable () -> Void) -> Void
    private let onTransition: (SecureInputTransition) -> Void
    private let stateQueue = DispatchQueue(label: "com.codetay.XKey.secure-input.state")
    private let deliveryQueue = DispatchQueue(label: "com.codetay.XKey.secure-input.delivery")
    private let stateQueueKey = DispatchSpecificKey<UInt8>()
    private let deliveryQueueKey = DispatchSpecificKey<UInt8>()

    private var stateMachine: SecureInputStateMachine
    private var currentObservation: SecureInputObservation
    private var desiredPresentation: SecureInputObservation?
    private var deliveredPresentation: SecureInputObservation?
    private var observationGeneration: UInt64 = 0
    private var presentationGeneration: UInt64 = 0
    private var validityGeneration: UInt64 = 0
    private var isValid = true

    init(
        detector: SecureInputDetecting,
        stateMachine: SecureInputStateMachine = SecureInputStateMachine(),
        capabilities: HostCapabilities,
        presenter: SecureInputPresenting,
        ownsPresentation: @escaping () -> Bool,
        presentationEnabled: @escaping () -> Bool = { true },
        deliverOnMain: ((@escaping @Sendable () -> Void) -> Void)? = nil,
        onTransition: @escaping (SecureInputTransition) -> Void
    ) {
        self.detector = detector
        self.stateMachine = stateMachine
        self.capabilities = capabilities
        self.presenter = presenter
        self.ownsPresentation = ownsPresentation
        self.presentationEnabled = presentationEnabled
        self.deliverOnMain = deliverOnMain ?? SecureInputMonitor.mainDelivery
        self.onTransition = onTransition
        currentObservation = .inactive
        stateQueue.setSpecific(key: stateQueueKey, value: 1)
        deliveryQueue.setSpecific(key: deliveryQueueKey, value: 1)
    }

    /// Samples and reduces one observation atomically. Presentation and callbacks are
    /// sequenced separately and never execute while the state executor is held.
    @discardableResult
    func evaluate() -> SecureInputEvaluation {
        withState {
            guard isValid else {
                return SecureInputEvaluation(observation: currentObservation, transition: nil)
            }

            let observation = detector.observation
            let transition = stateMachine.evaluate(observation)
            currentObservation = observation
            observationGeneration &+= 1
            enqueueEvaluationDelivery(
                observation: observation,
                observationGeneration: observationGeneration,
                transition: transition,
                validityGeneration: validityGeneration
            )

            return SecureInputEvaluation(observation: observation, transition: transition)
        }
    }

    func invalidate() {
        withState {
            guard isValid else { return }
            isValid = false
            validityGeneration &+= 1
            observationGeneration &+= 1
            desiredPresentation = nil
            presentationGeneration &+= 1
            enqueueInvalidationHide(generation: presentationGeneration)
        }
    }

    /// Test seam: waits until every delivery decision already emitted by the state
    /// executor has reached the injected main dispatcher.
    func waitForPendingDeliveries() {
        guard DispatchQueue.getSpecific(key: deliveryQueueKey) == nil else { return }
        deliveryQueue.sync {}
    }

    private func enqueueEvaluationDelivery(
        observation: SecureInputObservation,
        observationGeneration: UInt64,
        transition: SecureInputTransition?,
        validityGeneration: UInt64
    ) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.deliverOnMain { [weak self] in
                guard let self else { return }

                let isCurrent = self.withState {
                    self.isValid
                        && self.observationGeneration == observationGeneration
                        && self.currentObservation == observation
                }
                if isCurrent {
                    // These closures read AppKit/main-owned host state. Sampling happens
                    // only inside the main dispatcher; the resulting Bool is the sole
                    // eligibility value that enters the state executor.
                    let eligible = self.capabilities.supports(.secureInputFeedback)
                        && self.ownsPresentation()
                        && self.presentationEnabled()
                    if let decision = self.presentationDecision(
                        observation: observation,
                        observationGeneration: observationGeneration,
                        eligible: eligible
                    ), let action = self.validatedPresentationAction(decision) {
                        self.perform(action)
                    }
                }

                if let transition {
                    let mayDeliverTransition = self.withState {
                        self.isValid && self.validityGeneration == validityGeneration
                    }
                    if mayDeliverTransition {
                        self.onTransition(transition)
                    }
                }
            }
        }
    }

    private func enqueueInvalidationHide(generation: UInt64) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.deliverOnMain { [weak self] in
                guard let self else { return }
                let shouldHide = self.withState {
                    guard !self.isValid,
                          self.presentationGeneration == generation,
                          self.deliveredPresentation != nil
                    else { return false }
                    self.deliveredPresentation = nil
                    return true
                }
                if shouldHide {
                    self.presenter.hide()
                }
            }
        }
    }

    private func presentationDecision(
        observation: SecureInputObservation,
        observationGeneration: UInt64,
        eligible: Bool
    ) -> PresentationDecision? {
        withState {
            guard isValid,
                  self.observationGeneration == observationGeneration,
                  currentObservation == observation
            else { return nil }

            let desired = observation.isEnabled && eligible ? observation : nil
            if desired != desiredPresentation {
                desiredPresentation = desired
                presentationGeneration &+= 1
            }
            return PresentationDecision(generation: presentationGeneration, desired: desired)
        }
    }

    private func validatedPresentationAction(
        _ decision: PresentationDecision
    ) -> PresentationAction? {
        withState {
            guard isValid,
                  presentationGeneration == decision.generation,
                  desiredPresentation == decision.desired
            else { return nil }

            guard let desired = decision.desired else {
                guard deliveredPresentation != nil else { return nil }
                deliveredPresentation = nil
                return .hide
            }

            guard deliveredPresentation != desired else { return nil }
            deliveredPresentation = desired
            return .show(desired.holderAppName)
        }
    }

    private func perform(_ action: PresentationAction) {
        switch action {
        case .show(let appName):
            presenter.show(appName: appName)
        case .hide:
            presenter.hide()
        }
    }

    private func withState<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            return operation()
        }
        return stateQueue.sync(execute: operation)
    }

    private nonisolated static func mainDelivery(_ action: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            RunLoop.main.perform(inModes: [.common], block: action)
        }
    }

    static let disabled = SecureInputMonitor(
        detector: DisabledSecureInputDetector(),
        capabilities: HostCapabilities(supported: []),
        presenter: DisabledSecureInputPresenter(),
        ownsPresentation: { false },
        onTransition: { _ in }
    )
}

/// One process-level runtime can expose several detection entry points while retaining
/// one monitor state, so physical-tap and marked-text callbacks share edge deduplication.
final class SecureInputHostRuntime {
    let monitor: SecureInputMonitor

    init(monitor: SecureInputMonitor) {
        self.monitor = monitor
    }

    @discardableResult
    func evaluatePhysicalInput() -> Bool {
        monitor.evaluate().isActive
    }

    @discardableResult
    func evaluateMarkedTextInput() -> Bool {
        monitor.evaluate().isActive
    }
}

private struct DisabledSecureInputDetector: SecureInputDetecting {
    let observation: SecureInputObservation = .inactive
}

private final class DisabledSecureInputPresenter: SecureInputPresenting {
    func show(appName: String) {}
    func hide() {}
}
