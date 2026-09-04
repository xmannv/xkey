//
//  SecureInputStateMachine.swift
//  XKey
//
//  Pure decision logic for Secure Input warnings.
//  Deliberately free of AppKit and IOKit so it can be unit tested without
//  NSApplication or a real Secure Input holder.
//

import Darwin

enum SecureInputTransition: Equatable, Sendable {
    case becameActive(SecureInputObservation)
    case holderChanged(SecureInputObservation)
    case becameInactive
}

struct SecureInputStateMachine {
    private var state: SecureInputState
    private var observation: SecureInputObservation

    init(initialObservation: SecureInputObservation = .inactive) {
        state = SecureInputState(pid: initialObservation.statePID, vietnamese: true)
        observation = initialObservation
    }

    var isActive: Bool {
        state.pid != 0
    }

    mutating func evaluate(_ observation: SecureInputObservation) -> SecureInputTransition? {
        let previous = state
        let previousObservation = self.observation
        let next = SecureInputState(pid: observation.statePID, vietnamese: true)
        let actions = secureInputActions(from: previous,
                                         to: next,
                                         appName: observation.holderAppName)
        state = next
        self.observation = observation
        if actions.contains(.logReleased) {
            return .becameInactive
        }
        if actions.contains(where: { if case .logHeld = $0 { return true }; return false }) {
            return previous.pid == 0
                ? .becameActive(observation)
                : .holderChanged(observation)
        }
        if observation.isEnabled && observation != previousObservation {
            return .holderChanged(observation)
        }
        return nil
    }
}

/// Everything that decides whether a Secure Input warning is warranted.
struct SecureInputState: Equatable {
    /// PID of the process holding Secure Input; 0 when Secure Input is off.
    var pid: pid_t = 0
    /// Whether XKey is currently in Vietnamese mode.
    var vietnamese: Bool = false
}

/// A side effect for the caller to perform. The state machine never performs them itself.
enum SecureInputAction: Equatable {
    case showOverlay(appName: String)
    case hideOverlay
    case logHeld(appName: String)
    case logReleased
}

/// Decide which side effects a state transition warrants.
///
/// Edge-triggered: an unchanged state yields no actions. That is what makes the
/// caller safe to invoke from a poll timer and several event hooks at once.
///
/// `appName` describes the holder in `new`, and is ignored when `new.pid == 0`.
func secureInputActions(from old: SecureInputState,
                        to new: SecureInputState,
                        appName: String) -> [SecureInputAction] {
    guard new != old else { return [] }

    var actions: [SecureInputAction] = []

    // The overlay is visible only while Secure Input is held AND the XKey engine is on.
    // Note `vietnamese` means "the XKey engine is on", not "the user types Vietnamese":
    // XKeyIM mode also clears it while the user keeps typing Vietnamese through IMKit.
    if new.pid != 0 && new.vietnamese {
        actions.append(.showOverlay(appName: appName))
    } else if old.pid != 0 && old.vietnamese {
        actions.append(.hideOverlay)
    }

    // Log only when the holder itself changes. Keying this off the whole state
    // would log a spurious "released" every time Vietnamese mode toggles.
    if new.pid != old.pid {
        actions.append(new.pid != 0 ? .logHeld(appName: appName) : .logReleased)
    }

    return actions
}
