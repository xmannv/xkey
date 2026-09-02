import XCTest
import Foundation
import AppKit
@testable import XKey

/// Ownership of the keyboard between XKey.app's tap and XKeyIM's tap is decided by
/// a one-way App Group flag: XKeyIM arms it, XKey.app yields. A dead PID must never
/// keep XKey.app locked out — XKeyIM can be killed without a clean shutdown.
final class TapOwnershipTests: XCTestCase {

    /// Raw on-disk state of `vietnameseEnabled` before this test ran, captured in
    /// setUp() so it survives even if the test body throws, and restored in
    /// tearDown() alongside the existing disarmXKeyIMTap() cleanup. `present` tracks
    /// whether the key existed at all — restoring must reproduce "absent" exactly,
    /// not silently write `true` back, or the absent-key test stops testing anything
    /// on a second run.
    private var originalVietnameseEnabledValue: Any?
    private var originalVietnameseEnabledKeyWasPresent = false

    override func setUp() {
        super.setUp()
        let (value, present) = Self.readRawVietnameseEnabled()
        originalVietnameseEnabledValue = value
        originalVietnameseEnabledKeyWasPresent = present
    }

    override func tearDown() {
        SharedSettings.shared.disarmXKeyIMTap()
        Self.restoreRawVietnameseEnabled(originalVietnameseEnabledValue,
                                          present: originalVietnameseEnabledKeyWasPresent)
        Self.deleteKey(Self.otherProcessProbeKey)
        SharedSettings.shared.invalidateCache()
        super.tearDown()
    }

    func testNotOwningWhenDisarmed() {
        SharedSettings.shared.disarmXKeyIMTap()
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
    }

    func testNotOwningWhenArmedByThisProcess() {
        // isXKeyIMTapOwningInput answers "does some OTHER process own the tap?" —
        // the arming process is never the audience for this question. If this
        // process arms with its own PID (as XKeyIM does for itself), the answer
        // must be false, or XKeyIM's own tap delegate would yield to itself and
        // stop processing every keystroke.
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
    }

    /// Liveness alone is not identity. The flag and PID live in a persistent plist, so
    /// a kernel panic or hard power-off leaves them set — applicationWillTerminate never
    /// runs. XKeyIM is an IMK process launched at login, so its PID sits in the low range
    /// that gets reassigned early on the next boot; if the reassigned PID lands on any
    /// process owned by this user, kill(pid, 0) succeeds and XKey.app would yield the
    /// keyboard forever, with no UI indication.
    ///
    /// Spawns our own child to stand in for that unrelated process: guaranteed alive for
    /// the duration of the test, guaranteed not to be this process, and — unlike PID 1
    /// (launchd, owned by root) — owned by this same user, so kill(pid, 0) succeeds as an
    /// unprivileged existence check instead of failing with EPERM. (Under
    /// `xcodebuild test` the test process itself is already reparented to launchd, so its
    /// own getppid() is PID 1 too — that route doesn't avoid the EPERM case either.)
    func testNotOwningWhenPIDBelongsToAnUnrelatedLiveProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try! process.run()
        defer { process.terminate() }

        SharedSettings.shared.armXKeyIMTap(pid: Int(process.processIdentifier))
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput,
                       "a live process that is not XKeyIM must not lock XKey.app out of the keyboard")
    }

    /// The positive half of the same check: a PID that really is XKeyIM must still be
    /// recognised. Pins the bundle identifier the ownership check compares against —
    /// a typo there would silently stop XKey.app yielding for good. Needs an installed,
    /// running XKeyIM, so it skips where there is none.
    func testOwningWhenArmedByTheRealXKeyIM() throws {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.codetay.inputmethod.XKey")
        guard let xkeyIM = running.first, xkeyIM.processIdentifier != getpid() else {
            throw XCTSkip("no running XKeyIM to test against")
        }

        SharedSettings.shared.armXKeyIMTap(pid: Int(xkeyIM.processIdentifier))
        XCTAssertTrue(SharedSettings.shared.isXKeyIMTapOwningInput,
                      "XKey.app must yield to a live XKeyIM")
    }

    /// The bundle-identifier literal the ownership check compares against is the whole
    /// difference between "XKey.app yields to XKeyIM" and "both processes transform every
    /// keystroke, silently". testOwningWhenArmedByTheRealXKeyIM above would catch a typo,
    /// but it needs an installed, running XKeyIM and so never runs on CI — a typo would
    /// ship green. This runs everywhere and pins the literal against its real source of
    /// truth: XKeyIM's own Info.plist in this repo. Comparing it against another copy of
    /// the same string written here would prove nothing, so the expected value is read
    /// out of that file.
    func testOwnershipBundleIdentifierMatchesXKeyIMInfoPlist() throws {
        let infoPlistURL = URL(fileURLWithPath: #filePath)  // XKeyTests/TapOwnershipTests.swift
            .deletingLastPathComponent()                    // XKeyTests/
            .deletingLastPathComponent()                    // repository root
            .appendingPathComponent("XKeyIM/Info.plist")

        let data = try Data(contentsOf: infoPlistURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let declaredIdentifier = try XCTUnwrap(info["CFBundleIdentifier"] as? String)

        XCTAssertEqual(SharedSettings.xkeyIMBundleIdentifier, declaredIdentifier,
                       "the identity the tap-ownership check demands must be the identity XKeyIM actually ships with")
    }

    func testNotOwningWhenArmingProcessIsDead() {
        // PID 0 is never a live user process; stands in for a crashed XKeyIM.
        SharedSettings.shared.armXKeyIMTap(pid: 0)
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput,
                       "a dead arming process must not keep XKey.app locked out")
    }

    /// The kernel-panic case the PID check exists for: applicationWillTerminate never
    /// ran, so the flag is still armed for a process that no longer exists. Answering
    /// "not the owner" is not enough — the flag stays on disk, and XKeyIM's login-launched
    /// PID sits in the low range that gets reassigned early on the next boot, at which
    /// point kill(pid, 0) starts succeeding against an unrelated process. Clear it while
    /// we can still tell it is an orphan.
    func testOrphanedFlagWithADeadPIDClearsItself() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0"]
        try process.run()
        process.waitUntilExit()  // reaped: the PID is gone, not a zombie
        let deadPID = Int(process.processIdentifier)
        try XCTSkipIf(kill(pid_t(deadPID), 0) == 0, "PID was reused before the assertion")

        SharedSettings.shared.armXKeyIMTap(pid: deadPID)

        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, false,
                       "an ownership flag armed for a process that no longer exists must clear itself")
    }

    /// The heal writes through `mutatePlist`, which re-reads the current dictionary from
    /// disk — so clearing the flag unconditionally throws that re-read away and
    /// reintroduces the lost update the primitive exists to prevent. XKeyIM crashing and
    /// being relaunched is exactly that window: this process is still holding the dead PID
    /// when the heal fires, and clearing there leaves XKeyIM believing it owns the tap
    /// while XKey.app reads `false` and does not yield. Both processes then transform every
    /// keystroke, and the heal posts no notification that would correct it.
    func testSelfHealOnlyClearsThePIDItDecidedWasDead() throws {
        let relaunched = Process()
        relaunched.executableURL = URL(fileURLWithPath: "/bin/sleep")
        relaunched.arguments = ["30"]
        try relaunched.run()
        defer { if relaunched.isRunning { relaunched.terminate() } }
        let livePID = Int(relaunched.processIdentifier)

        let crashed = Process()
        crashed.executableURL = URL(fileURLWithPath: "/bin/sleep")
        crashed.arguments = ["0"]
        try crashed.run()
        crashed.waitUntilExit()  // reaped: the PID is gone, not a zombie
        let deadPID = Int(crashed.processIdentifier)
        try XCTSkipIf(kill(pid_t(deadPID), 0) == 0, "PID was reused before the assertion")

        // What this process last saw: the XKeyIM that has since crashed.
        SharedSettings.shared.armXKeyIMTap(pid: deadPID)

        // XKeyIM is relaunched and arms with its new PID. The bytes on disk change; this
        // process's cache still holds the dead PID because its main thread has not
        // dequeued the distributed notification yet.
        Self.writeKey(SharedSettingsKey.xkeyIMTapPID.rawValue, value: livePID)
        Self.writeKey(SharedSettingsKey.xkeyIMTapArmed.rawValue, value: true)

        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)

        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "the heal must not clear an ownership the relaunched XKeyIM has already claimed")
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapPID.rawValue] as? Int, livePID,
                       "the heal must clear only the PID it decided was dead")
    }

    /// XKey.app does not suspend its tap while XKeyIM is armed — it asks the ownership
    /// question on EVERY event — and answering it costs a kill(2) plus a LaunchServices
    /// lookup. The answer is memoised, and this pins both halves of when it may be reused.
    ///
    /// Uses the self-heal as the probe: it only fires from a real recompute, so the flag
    /// on disk says whether the read behind it recomputed or came back from the memo.
    func testOwnershipIsMemoisedThenRefreshedByTheTimeBackstop() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let pid = Int(process.processIdentifier)

        SharedSettings.shared.armXKeyIMTap(pid: pid)
        let memoisedAt = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput,
                       "a live process that is not XKeyIM must not lock XKey.app out of the keyboard")
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "an identity mismatch must never clear the flag — NSRunningApplication can return nil for a live, correct XKeyIM, and clearing there puts both processes in the keystroke path")

        process.terminate()
        process.waitUntilExit()
        try XCTSkipIf(kill(pid_t(pid), 0) == 0, "PID was reused before the assertion")

        // Nothing wrote the plist, so nothing bumped the cache generation. Inside the
        // memo window the per-keystroke read is served from the memo without touching
        // kill(2) at all — if it recomputed, the now-dead PID would trip the self-heal.
        _ = SharedSettings.shared.isXKeyIMTapOwningInput
        // The memo's bound is wall-clock, and everything above — three plist reads, a
        // terminate() and a waitUntilExit() — has to fit inside it. On a loaded runner it
        // does not, and the memo expiring is then a timing artefact, not a behaviour change:
        // drop just this assertion rather than fail. It is measured after the read it guards,
        // so a window still open here was open then too. Everything below stays hard —
        // skipping the test outright would take the backstop with it, and the backstop is what
        // matters on exactly the loaded runner this guard is for.
        if ProcessInfo.processInfo.systemUptime - memoisedAt < SharedSettings.ownershipMemoMaxAge {
            XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                           "inside the memo window the ownership answer must be reused, not recomputed")
        }

        // Past the window it recomputes on its own. This is the backstop for the change
        // no write can announce: XKeyIM dying without disarming leaves the flag armed on
        // disk, so nothing bumps the generation and the memo would answer forever.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, false,
                       "past the memo window the answer must be recomputed against the live process list")
    }

    /// A cross-process ownership change must be seen on the very next event, not after
    /// the memo's age bound. XKeyIM writes the flag and posts the distributed
    /// notification; this process's observer answers it with invalidateCache(), which
    /// bumps the same generation the memo is keyed on. Same probe as above: the memo
    /// held a `false` computed while disarmed, so a heal proves the read recomputed.
    func testCrossProcessOwnershipChangeRetiresTheMemo() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0"]
        try process.run()
        process.waitUntilExit()
        let deadPID = Int(process.processIdentifier)
        try XCTSkipIf(kill(pid_t(deadPID), 0) == 0, "PID was reused before the assertion")

        SharedSettings.shared.disarmXKeyIMTap()
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)  // memoise "not owned"

        // XKeyIM arms: the bytes on disk change, then its distributed notification
        // reaches this process as invalidateCache().
        Self.writeKey(SharedSettingsKey.xkeyIMTapPID.rawValue, value: deadPID)
        Self.writeKey(SharedSettingsKey.xkeyIMTapArmed.rawValue, value: true)
        SharedSettings.shared.invalidateCache()

        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, false,
                       "a cache invalidation must retire the memo so the next event sees the new ownership state")
    }

    func testDisarmClearsOwnership() {
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        SharedSettings.shared.disarmXKeyIMTap()
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
    }

    // MARK: - Cross-process writes
    //
    // XKey.app and XKeyIM both write this plist now. Every write serialises the
    // WHOLE dictionary, so a write that merges onto a stale in-memory cache silently
    // reverts everything the other process stored since that cache was filled.

    /// A setting the other process wrote must survive this process's next write, even
    /// though this process never saw the notification that would have invalidated its
    /// cache (`setSmartSwitchData` and friends write without notifying at all).
    func testWriteMergesOntoCurrentDiskStateNotAStaleCache() {
        // Warm this process's cache.
        _ = SharedSettings.shared.xkeyIMTapArmed

        // The other process writes straight to the shared file. No notification
        // reaches us, so our cache is now stale but still considered warm.
        Self.writeKey(Self.otherProcessProbeKey, value: Self.otherProcessProbeValue)

        // Any write at all from this process.
        SharedSettings.shared.armXKeyIMTap(pid: 0)

        XCTAssertEqual(Self.readPlistDict()[Self.otherProcessProbeKey] as? String,
                       Self.otherProcessProbeValue,
                       "a write must merge onto the current on-disk dictionary, not revert the other process's settings")
    }

    /// The worst case of the same bug: this process reverting the ownership flag puts
    /// BOTH processes back in the keystroke path — the exact outcome the flag exists to
    /// prevent — and it persists until the next arm/disarm rather than clearing itself.
    func testWriteFromAStaleCacheCannotRevertTapOwnership() {
        SharedSettings.shared.disarmXKeyIMTap()
        _ = SharedSettings.shared.xkeyIMTapArmed  // warm the cache while disarmed

        // XKeyIM arms; we are inside the notification's propagation window.
        Self.writeKey(SharedSettingsKey.xkeyIMTapArmed.rawValue, value: true)

        // XKey.app writes some unrelated setting. Reading the value first and writing
        // it straight back exercises the full read-modify-write without changing the
        // developer's real settings.
        let hotkeyCode = SharedSettings.shared.toggleExclusionHotkeyCode
        SharedSettings.shared.toggleExclusionHotkeyCode = hotkeyCode

        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "an unrelated write must not clear the flag that keeps this process out of the keystroke path")
    }

    /// `forceWriteCurrentSettings` runs just before Sparkle restarts the app. Building its
    /// dictionary from the CACHED read and writing the whole thing back is the same
    /// whole-dictionary-from-a-stale-cache shape `mutatePlist` exists to remove: if XKeyIM
    /// armed after this process's cache was filled, the flush pushes `xkeyIMTapArmed = false`
    /// to disk, nothing is notified, and after the restart both processes sit in the
    /// keystroke path until the next arm/disarm.
    func testForceWriteCurrentSettingsCannotRevertTapOwnership() {
        SharedSettings.shared.disarmXKeyIMTap()
        _ = SharedSettings.shared.xkeyIMTapArmed  // warm the cache while disarmed

        // XKeyIM arms; we are inside the notification's propagation window.
        Self.writeKey(SharedSettingsKey.xkeyIMTapArmed.rawValue, value: true)

        SharedSettings.shared.forceWriteCurrentSettings()

        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "the pre-restart settings flush must not revert the flag that keeps this process out of the keystroke path")
    }

    /// The same shape once more, from the iCloud side: an incoming scalar payload was
    /// merged onto the CACHED dictionary and the whole thing written back. Keeping the tap
    /// keys out of the payload only stops the OTHER machine's values from landing — it does
    /// nothing about this process pushing its own stale cache to disk. If XKeyIM armed
    /// while that cache still said disarmed, the pull reverts the flag, and nothing heals
    /// it: the heal only runs for a flag that reads armed.
    func testSyncImportCannotRevertTapOwnership() throws {
        SharedSettings.shared.disarmXKeyIMTap()
        _ = SharedSettings.shared.xkeyIMTapArmed  // warm the cache while disarmed

        // XKeyIM arms; we are inside the notification's propagation window.
        Self.writeKey(SharedSettingsKey.xkeyIMTapArmed.rawValue, value: true)

        let payload = try PropertyListSerialization.data(
            fromPropertyList: [Self.otherProcessProbeKey: Self.otherProcessProbeValue],
            format: .binary, options: 0)
        SharedSettings.shared.importScalarsForSync(from: payload)

        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "an iCloud pull must not revert the flag that keeps this process out of the keystroke path")
        XCTAssertEqual(Self.readPlistDict()[Self.otherProcessProbeKey] as? String,
                       Self.otherProcessProbeValue,
                       "the incoming value must still be applied")
    }

    /// Restoring a settings backup writes the WHOLE dictionary, so a backup exported while
    /// XKeyIM was not armed removes the ownership flag from the plist entirely. It then
    /// reads false, XKey.app does not yield, both processes transform every keystroke —
    /// and nothing heals it, because the heal only runs for a flag that reads armed.
    ///
    /// The backup is this machine's own settings minus the tap keys, so the import writes
    /// back exactly what was already there rather than a synthetic dictionary over the
    /// developer's real settings.
    func testImportingASettingsBackupCannotClearTapOwnership() throws {
        let snapshot = Self.readPlistDict()
        defer {
            Self.writePlistDict(snapshot)
            SharedSettings.shared.invalidateCache()
        }

        var backupDict = snapshot
        backupDict.removeValue(forKey: SharedSettingsKey.xkeyIMTapArmed.rawValue)
        backupDict.removeValue(forKey: SharedSettingsKey.xkeyIMTapPID.rawValue)
        let backup = try PropertyListSerialization.data(
            fromPropertyList: backupDict, format: .xml, options: 0)

        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        XCTAssertTrue(SharedSettings.shared.importSettings(from: backup))

        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapArmed.rawValue] as? Bool, true,
                       "restoring a backup must not drop the flag that decides which process owns the keyboard")
        XCTAssertEqual(Self.readPlistDict()[SharedSettingsKey.xkeyIMTapPID.rawValue] as? Int, Int(getpid()),
                       "the owning PID is live device state, not a setting the backup can replace")
    }

    /// `mutatePlist` re-reads the file on EVERY write, and both processes write it, so a
    /// read landing mid-write is routine rather than rare. `Data.write(to:)` truncates the
    /// destination and streams the new bytes into it, so a concurrent reader can observe a
    /// half-written file; `PropertyListSerialization` then fails and the reader falls back
    /// to whatever it already had — a stale cache (the lost update `mutatePlist` exists to
    /// prevent) or, with a cold cache, an empty dictionary that gets written back over the
    /// user's entire settings. An atomic write renames a fully-written temp file into
    /// place, so a reader sees either the whole old file or the whole new one.
    func testConcurrentReadNeverSeesATornPlist() {
        let path = SharedSettings.shared.settingsFilePath
        // Read-modify-write of the same value: exercises the full write path without
        // changing the developer's real settings.
        let hotkeyCode = SharedSettings.shared.toggleExclusionHotkeyCode

        let writerFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<300 {
                SharedSettings.shared.toggleExclusionHotkeyCode = hotkeyCode
            }
            writerFinished.signal()
        }

        // Reads until the writer signals rather than a fixed count: a fixed count can
        // finish before the first write lands, and the test would then pass without the
        // two ever overlapping — which is the only thing it is here to exercise.
        var tornReads = 0
        let deadline = Date().addingTimeInterval(60)
        while writerFinished.wait(timeout: .now()) == .timedOut {
            guard Date() < deadline else {
                XCTFail("the writer did not finish within 60s")
                break
            }
            guard let data = FileManager.default.contents(atPath: path), !data.isEmpty,
                  (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil
            else {
                tornReads += 1
                continue
            }
        }

        XCTAssertEqual(tornReads, 0,
                       "a reader must never observe a partially written plist — the other process would fall back to a stale or empty dictionary and write it back over everything")
    }

    /// vietnameseEnabled must default to true when the key is absent from the App
    /// Group plist — a false default would silently disable Vietnamese typing on a
    /// fresh install. Deletes the key straight from the plist file SharedSettings
    /// reads (the same on-disk store `vietnameseEnabled` is backed by), then
    /// invalidates the in-memory cache so the next read hits disk. tearDown()
    /// restores whatever was there before (including "absent") so this never
    /// destroys a developer's real, deliberately-set `false`.
    func testVietnameseEnabledDefaultsTrueWhenKeyAbsent() {
        Self.deleteVietnameseEnabledKey()
        SharedSettings.shared.invalidateCache()

        XCTAssertTrue(SharedSettings.shared.vietnameseEnabled,
                       "a fresh install with no stored value must default to Vietnamese typing on")
    }

    /// setupKeyboardHandling() builds a TapEnvironment carrying the shared
    /// vietnameseEnabled and applies it to the handler; setupStatusBar() runs on the very
    /// next line and re-syncs the handler from StatusBarViewModel's own copy. Seeded from
    /// anything but the shared flag, that second sync silently overrides the first — so
    /// turning Vietnamese off from XKeyIM's menu and restarting XKey.app brought it back on.
    func testStatusBarSeedsVietnameseStateFromSharedSettings() {
        SharedSettings.shared.vietnameseEnabled = false

        let viewModel = StatusBarViewModel(keyboardHandler: nil, eventTapManager: nil)

        XCTAssertFalse(viewModel.isVietnameseEnabled,
                       "the status bar must agree with the shared flag, not override what the environment just applied")
    }

    /// XKey.app seeds Vietnamese state from the shared flag but only XKeyIM ever wrote it,
    /// so turning Vietnamese off once from XKeyIM's menu made the flag `false` for good:
    /// every XKey.app launch started OFF, and turning it back on from XKey.app's own menu
    /// never survived a restart. The status-bar toggle — which the popover switch and the
    /// global hotkey both route through — is the user expressing a durable preference, so
    /// it has to write the flag it reads.
    func testTogglingVietnameseFromTheStatusBarPersistsToTheSharedFlag() {
        SharedSettings.shared.vietnameseEnabled = false
        let viewModel = StatusBarViewModel(keyboardHandler: nil, eventTapManager: nil)
        XCTAssertFalse(viewModel.isVietnameseEnabled)

        viewModel.toggleVietnamese()

        XCTAssertTrue(SharedSettings.shared.vietnameseEnabled,
                      "turning Vietnamese back on from XKey.app's own menu must survive a restart")
    }

    /// Tap ownership is per-machine state, like isRemoteDesktopTarget: machine A's PID
    /// means nothing on machine B, and importing it there makes machine B's XKey.app
    /// yield the keyboard to whatever local process happens to hold that PID.
    func testTapOwnershipKeysAreNotSyncedAcrossMachines() throws {
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))

        let data = try XCTUnwrap(SharedSettings.shared.exportScalarsForSync())
        let exported = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertNil(exported[SharedSettingsKey.xkeyIMTapArmed.rawValue],
                     "the tap-ownership flag is device-specific and must not leave this machine")
        XCTAssertNil(exported[SharedSettingsKey.xkeyIMTapPID.rawValue],
                     "a PID from another machine is meaningless here and dangerous to act on")
    }

    /// Vietnamese on/off is momentary device state — bound to a hotkey and to each
    /// machine's own menu — in the same family as isRemoteDesktopTarget, not a durable
    /// preference like input method or code table. Persisting it to the shared flag is
    /// what makes XKey.app and XKeyIM agree on ONE machine; pushing it to iCloud would
    /// make the toggle hotkey on the laptop turn the desktop off too.
    func testVietnameseToggleIsNotSyncedAcrossMachines() throws {
        SharedSettings.shared.vietnameseEnabled = false
        // Keeps the scalar payload non-empty on a machine whose plist holds little else:
        // exportScalarsForSync returns nil for an empty dictionary.
        Self.writeKey(Self.otherProcessProbeKey, value: Self.otherProcessProbeValue)
        SharedSettings.shared.invalidateCache()

        let data = try XCTUnwrap(SharedSettings.shared.exportScalarsForSync())
        let exported = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNil(exported[SharedSettingsKey.vietnameseEnabled.rawValue],
                     "the Vietnamese toggle is per-machine state and must not leave this machine")

        // The other end of the same rule: a machine still pushing the key (an older
        // version, or a payload already in the store) must not flip this one.
        let incoming = try PropertyListSerialization.data(
            fromPropertyList: [SharedSettingsKey.vietnameseEnabled.rawValue: true],
            format: .binary, options: 0)
        SharedSettings.shared.importScalarsForSync(from: incoming)

        XCTAssertFalse(SharedSettings.shared.vietnameseEnabled,
                       "an incoming sync payload must not turn Vietnamese back on here")
    }

    // MARK: - Raw plist helpers
    //
    // SharedSettings' own read/write helpers are private, so these tests go
    // straight at the on-disk App Group plist file via the public
    // `settingsFilePath`, the same file `vietnameseEnabled` is backed by.

    private static func readPlistDict() -> [String: Any] {
        let path = SharedSettings.shared.settingsFilePath
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }

    private static func writePlistDict(_ dict: [String: Any]) {
        let path = SharedSettings.shared.settingsFilePath
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// Stands in for whatever the OTHER process last stored. Deliberately not a real
    /// SharedSettingsKey: the whole-dictionary merge under test is key-agnostic, and a
    /// key of our own is removed in tearDown() instead of overwriting a real setting.
    private static let otherProcessProbeKey = "XKey.test.otherProcessProbe"
    private static let otherProcessProbeValue = "written-by-the-other-process"

    /// Write one key straight to the shared file, bypassing SharedSettings entirely —
    /// this is what a write from the other process looks like from in here: the bytes
    /// on disk change and this process's cache never hears about it.
    private static func writeKey(_ key: String, value: Any) {
        var dict = readPlistDict()
        dict[key] = value
        writePlistDict(dict)
    }

    private static func deleteKey(_ key: String) {
        var dict = readPlistDict()
        dict.removeValue(forKey: key)
        writePlistDict(dict)
    }

    private static func readRawVietnameseEnabled() -> (value: Any?, present: Bool) {
        let dict = readPlistDict()
        let key = SharedSettingsKey.vietnameseEnabled.rawValue
        guard let value = dict[key] else { return (nil, false) }
        return (value, true)
    }

    private static func deleteVietnameseEnabledKey() {
        var dict = readPlistDict()
        dict.removeValue(forKey: SharedSettingsKey.vietnameseEnabled.rawValue)
        writePlistDict(dict)
    }

    private static func restoreRawVietnameseEnabled(_ value: Any?, present: Bool) {
        var dict = readPlistDict()
        let key = SharedSettingsKey.vietnameseEnabled.rawValue
        if present, let value {
            dict[key] = value
        } else {
            dict.removeValue(forKey: key)
        }
        writePlistDict(dict)
        SharedSettings.shared.invalidateCache()
    }
}
