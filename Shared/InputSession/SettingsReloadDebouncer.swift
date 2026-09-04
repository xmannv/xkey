//
//  SettingsReloadDebouncer.swift
//  XKey
//

import Foundation

final class SettingsReloadDebouncer {
    typealias Schedule = (_ delay: TimeInterval,
                          _ action: @escaping () -> Void) -> () -> Void

    private final class PendingAction {
        var isCancelled = false
        var cancelScheduled: (() -> Void)?
    }

    private let interval: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: Schedule
    private var lastExecutionTime = -TimeInterval.infinity
    private var pendingAction: PendingAction?

    init(interval: TimeInterval,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Schedule = { delay, action in
             let workItem = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
             return { workItem.cancel() }
         }) {
        self.interval = interval
        self.now = now
        self.schedule = schedule
    }

    func submit(_ action: @escaping () -> Void) {
        cancel()

        let currentTime = now()
        guard currentTime - lastExecutionTime < interval else {
            lastExecutionTime = currentTime
            action()
            return
        }

        let pending = PendingAction()
        pendingAction = pending
        pending.cancelScheduled = schedule(interval) { [weak self, weak pending] in
            guard let self,
                  let pending,
                  !pending.isCancelled,
                  self.pendingAction === pending else { return }
            self.pendingAction = nil
            self.lastExecutionTime = self.now()
            action()
        }
    }

    func cancel() {
        pendingAction?.isCancelled = true
        pendingAction?.cancelScheduled?()
        pendingAction = nil
    }
}
