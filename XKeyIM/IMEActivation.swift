//
//  IMEActivation.swift
//  XKeyIM
//
//  Tracks whether XKeyIM is the active input source, robust to IMKit delivering
//  activateServer / deactivateServer out of order across clients.
//
//  macOS remembers the input source PER APP. A system-wide event tap must therefore
//  only act while XKeyIM is actually the active IME, or it would type Vietnamese
//  into an app the user has set to ABC.
//
//  The ordering hazard: when focus moves between two clients that both use XKeyIM,
//  IMKit may call the NEW client's activateServer BEFORE the OLD client's
//  deactivateServer. Both write one shared flag, so a naive `deactivate -> false`
//  clobbers the fresh activate: the tap goes dormant while XKeyIM is STILL the
//  selected source, and typing passes through untransformed with no visible cause.
//
//  Rule: the OS-selected input source is the single source of truth; the lifecycle
//  callbacks are only hints.
//

import Foundation

struct IMEActivation: Equatable {
    private(set) var isActive: Bool

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    /// activateServer: XKeyIM is active for the focused client. `isSelected` is whether
    /// XKeyIM is the OS-selected keyboard input source at this instant. A late,
    /// out-of-order activate can arrive after TIS has already moved to another source —
    /// ignore it, or the tap arms and types Vietnamese into an app set to ABC. Once
    /// selection does catch up, selectionChanged tells us authoritatively.
    mutating func activate(isSelected: Bool) {
        if isSelected { isActive = true }
    }

    /// deactivateServer: a client lost XKeyIM. `stillSelected` is whether XKeyIM is
    /// STILL the OS-selected keyboard input source at this instant. A late,
    /// out-of-order deactivate from a previously focused client fires while XKeyIM
    /// is still selected — ignore it so it cannot disarm the tap under our feet.
    mutating func deactivate(stillSelected: Bool) {
        if !stillSelected { isActive = false }
    }

    /// TIS "selected keyboard input source changed" — authoritative in both
    /// directions. Also covers per-document switching, which can skip
    /// activateServer entirely.
    mutating func selectionChanged(isXKeyIM: Bool) {
        isActive = isXKeyIM
    }
}
