import XCTest
@testable import XKey

/// IMEActivation is compiled directly into the XKeyTests target (see pbxproj),
/// so no import beyond XKey is needed.
final class IMEActivationTests: XCTestCase {

    func testStartsInactive() {
        XCTAssertFalse(IMEActivation().isActive)
    }

    func testActivateWhileSelectedMakesActive() {
        var a = IMEActivation()
        a.activate(isSelected: true)
        XCTAssertTrue(a.isActive)
    }

    /// The mirror of the late-deactivate hazard below: an activateServer can arrive
    /// AFTER TIS has already moved to another source. Honouring it would arm the tap
    /// and type Vietnamese into an app where the user selected ABC. The TIS
    /// notification remains the way activation arrives once selection catches up.
    func testLateActivateWhileNoLongerSelectedIsIgnored() {
        var a = IMEActivation()
        a.activate(isSelected: false)
        XCTAssertFalse(a.isActive)
    }

    /// The ordinary case: the user switched to another input source, so the
    /// deactivate is genuine.
    func testDeactivateWhenNoLongerSelectedTurnsOff() {
        var a = IMEActivation(isActive: true)
        a.deactivate(stillSelected: false)
        XCTAssertFalse(a.isActive)
    }

    /// The hazard this type exists for: focus moved between two clients that both
    /// use XKeyIM. IMK can deliver the OLD client's deactivate AFTER the NEW
    /// client's activate. Honouring it would silently disarm the tap while XKeyIM
    /// is still the selected source.
    func testLateDeactivateWhileStillSelectedIsIgnored() {
        var a = IMEActivation()
        a.activate(isSelected: true)          // new client
        a.deactivate(stillSelected: true)     // old client, arriving late
        XCTAssertTrue(a.isActive)
    }

    /// TIS notification is authoritative in both directions — it also covers
    /// per-document switching that skips activateServer entirely.
    func testSelectionChangedIsAuthoritative() {
        var a = IMEActivation(isActive: true)
        a.selectionChanged(isXKeyIM: false)
        XCTAssertFalse(a.isActive)
        a.selectionChanged(isXKeyIM: true)
        XCTAssertTrue(a.isActive)
    }

    /// A late deactivate must not resurrect-then-clobber after TIS already said no.
    func testLateDeactivateAfterAuthoritativeOffStaysOff() {
        var a = IMEActivation(isActive: true)
        a.selectionChanged(isXKeyIM: false)
        a.deactivate(stillSelected: false)
        XCTAssertFalse(a.isActive)
    }
}
