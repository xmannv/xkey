import XCTest
@testable import XKey

final class SettingsReloadDebouncerTests: XCTestCase {
    private final class ScheduledAction {
        let delay: TimeInterval
        let action: () -> Void
        var isCancelled = false

        init(delay: TimeInterval, action: @escaping () -> Void) {
            self.delay = delay
            self.action = action
        }
    }

    func testRapidSubmissionsProduceOneFinalTrailingReload() {
        var now: TimeInterval = 0
        var scheduled: [ScheduledAction] = []
        var reloadCount = 0
        let debouncer = SettingsReloadDebouncer(
            interval: 0.5,
            now: { now },
            schedule: { delay, action in
                let scheduledAction = ScheduledAction(delay: delay, action: action)
                scheduled.append(scheduledAction)
                return { scheduledAction.isCancelled = true }
            }
        )

        debouncer.submit { reloadCount += 1 }
        now = 0.1
        debouncer.submit { reloadCount += 1 }
        now = 0.2
        debouncer.submit { reloadCount += 1 }

        XCTAssertEqual(reloadCount, 1)
        XCTAssertEqual(scheduled.map(\.delay), [0.5, 0.5])
        XCTAssertTrue(scheduled[0].isCancelled)

        now = 0.7
        for item in scheduled where !item.isCancelled {
            item.action()
        }

        XCTAssertEqual(reloadCount, 2)
    }

    func testCancelPreventsPendingReload() {
        var now: TimeInterval = 0
        var scheduled: ScheduledAction?
        var reloadCount = 0
        let debouncer = SettingsReloadDebouncer(
            interval: 0.5,
            now: { now },
            schedule: { delay, action in
                let item = ScheduledAction(delay: delay, action: action)
                scheduled = item
                return { item.isCancelled = true }
            }
        )

        debouncer.submit { reloadCount += 1 }
        now = 0.1
        debouncer.submit { reloadCount += 1 }
        debouncer.cancel()
        scheduled?.action()

        XCTAssertEqual(reloadCount, 1)
        XCTAssertTrue(scheduled?.isCancelled == true)
    }
}
