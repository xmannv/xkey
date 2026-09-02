//
//  iCloudSyncManagerTests.swift
//  XKeyTests
//
//  Covers the multi-key sync surface: envelope encoding, CRDT merge with tombstones,
//  first-enable detection, and manager push/pull lifecycle against a mock KVS.
//

import XCTest
@testable import XKey

// MARK: - Mock KVS

class MockKeyValueStore: KeyValueStoreProtocol {
    var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? { storage[key] }

    func setData(_ data: Data?, forKey key: String) {
        if let data = data { storage[key] = data } else { storage.removeValue(forKey: key) }
    }

    @discardableResult func synchronize() -> Bool { true }
}

// MARK: - Helpers

private func makeIsolatedDefaults(_ tag: String = UUID().uuidString) -> UserDefaults {
    let suiteName = "XKeyTests.iCloudSync.\(tag)"
    let d = UserDefaults(suiteName: suiteName)!
    d.removePersistentDomain(forName: suiteName)
    return d
}

/// An envelope as a peer would have written it. SyncEnvelope always stamps this device's id, and
/// pullCategory drops a merge-mode envelope carrying that id as an echo of our own push — so a
/// pull can only be exercised through a hand-encoded one.
private func foreignEnvelope(payload: Data, updatedAt: Date = Date()) throws -> Data {
    struct Foreign: Codable {
        let schemaVersion: Int
        let deviceId: String
        let updatedAt: Date
        let payload: Data
    }
    return try PropertyListEncoder().encode(
        Foreign(schemaVersion: SyncSchema.currentVersion,
                deviceId: "peer-device",
                updatedAt: updatedAt,
                payload: payload))
}

// MARK: - SyncCollectionPayload (CRDT merge)

final class SyncCollectionPayloadTests: XCTestCase {

    func testMergeKeepsNewerEntry() {
        let older = SyncEntry(id: "a", updatedAt: Date(timeIntervalSince1970: 100), data: Data("v1".utf8))
        let newer = SyncEntry(id: "a", updatedAt: Date(timeIntervalSince1970: 200), data: Data("v2".utf8))
        let merged = SyncCollectionPayload(entries: [older]).merged(with: SyncCollectionPayload(entries: [newer]))
        XCTAssertEqual(merged.entries.first?.data, Data("v2".utf8))
    }

    func testMergeUnionsDisjointEntries() {
        let a = SyncEntry(id: "a", data: Data())
        let b = SyncEntry(id: "b", data: Data())
        let merged = SyncCollectionPayload(entries: [a]).merged(with: SyncCollectionPayload(entries: [b]))
        XCTAssertEqual(Set(merged.entries.map(\.id)), Set(["a", "b"]))
    }

    func testTombstoneWinsOverOlderLiveEntry() {
        let live = SyncEntry(id: "a", updatedAt: Date(timeIntervalSince1970: 100), deleted: false, data: Data())
        let tomb = SyncEntry.tombstone(id: "a", at: Date(timeIntervalSince1970: 200))
        let merged = SyncCollectionPayload(entries: [live]).merged(with: SyncCollectionPayload(entries: [tomb]))
        XCTAssertEqual(merged.entries.first?.deleted, true)
        XCTAssertEqual(merged.liveEntries.count, 0)
    }

    func testLiveEntryWinsOverOlderTombstone() {
        let tomb = SyncEntry.tombstone(id: "a", at: Date(timeIntervalSince1970: 100))
        let live = SyncEntry(id: "a", updatedAt: Date(timeIntervalSince1970: 200), deleted: false, data: Data("v".utf8))
        let merged = SyncCollectionPayload(entries: [tomb]).merged(with: SyncCollectionPayload(entries: [live]))
        XCTAssertEqual(merged.liveEntries.count, 1)
        XCTAssertEqual(merged.liveEntries.first?.data, Data("v".utf8))
    }

    func testPrunedTombstonesDropsOldDeletions() {
        let now = Date()
        let ancient = SyncEntry.tombstone(id: "a", at: now.addingTimeInterval(-60 * 24 * 3600))
        let recent = SyncEntry.tombstone(id: "b", at: now.addingTimeInterval(-1 * 24 * 3600))
        let payload = SyncCollectionPayload(entries: [ancient, recent])
            .prunedTombstones(retention: 30 * 24 * 3600, now: now)
        XCTAssertEqual(Set(payload.entries.map(\.id)), Set(["b"]))
    }

    func testPrunedTombstonesKeepsLiveEntriesIndependentOfAge() {
        let now = Date()
        let oldLive = SyncEntry(id: "a", updatedAt: now.addingTimeInterval(-365 * 24 * 3600), deleted: false, data: Data())
        let payload = SyncCollectionPayload(entries: [oldLive])
            .prunedTombstones(retention: 30 * 24 * 3600, now: now)
        XCTAssertEqual(payload.entries.count, 1)
    }

    // MARK: Deterministic ordering (Window Title Rule cascade priority depends on it)

    /// merged() must keep the local order even when the remote sends the same ids in a different
    /// order and updates one of them. `Array(map.values)` used to scramble this on every merge.
    func testMergePreservesLocalOrderWhenRemoteUpdatesAndReorders() {
        let a = SyncEntry(id: "a", updatedAt: Date(timeIntervalSince1970: 100), data: Data("a".utf8))
        let b = SyncEntry(id: "b", updatedAt: Date(timeIntervalSince1970: 100), data: Data("b".utf8))
        let c = SyncEntry(id: "c", updatedAt: Date(timeIntervalSince1970: 100), data: Data("c".utf8))
        let local = SyncCollectionPayload(entries: [a, b, c])
        // Remote reorders and ships a newer "b".
        let bNew = SyncEntry(id: "b", updatedAt: Date(timeIntervalSince1970: 200), data: Data("b2".utf8))
        let remote = SyncCollectionPayload(entries: [bNew, c, a])
        let merged = local.merged(with: remote)
        XCTAssertEqual(merged.entries.map(\.id), ["a", "b", "c"], "local order must be preserved")
        XCTAssertEqual(merged.entries[1].data, Data("b2".utf8), "newer remote value should still win")
    }

    /// New remote-only entries are appended after local ones, in their remote order — deterministic.
    func testMergeAppendsNewRemoteEntriesAfterLocalInOrder() {
        let a = SyncEntry(id: "a", data: Data())
        let b = SyncEntry(id: "b", data: Data())
        let c = SyncEntry(id: "c", data: Data())
        let merged = SyncCollectionPayload(entries: [a]).merged(with: SyncCollectionPayload(entries: [b, c]))
        XCTAssertEqual(merged.entries.map(\.id), ["a", "b", "c"])
    }

    /// Regression for the reported bug: deleting "test" on one Mac did not propagate. applyEnvelope
    /// now builds the local payload as live + local tombstones, so a fresh local delete survives a
    /// merge against a stale remote that still has the entry live (instead of being resurrected).
    func testFreshLocalTombstoneSurvivesStaleRemoteLiveEntry() {
        let freshLocalTomb = SyncEntry.tombstone(id: "test", at: Date(timeIntervalSince1970: 200))
        let staleRemoteLive = SyncEntry(id: "test", updatedAt: Date(timeIntervalSince1970: 100), deleted: false, data: Data("x".utf8))
        // local payload = live (none) + local tombstone, exactly as applyEnvelope constructs it.
        let local = SyncCollectionPayload(entries: [freshLocalTomb])
        let merged = local.merged(with: SyncCollectionPayload(entries: [staleRemoteLive]))
        XCTAssertEqual(merged.liveEntries.count, 0, "a fresh local delete must not be resurrected by a stale remote live entry")
    }
}

// MARK: - SyncEnvelope

final class SyncEnvelopeTests: XCTestCase {

    func testRoundTripPreservesFields() throws {
        let payload = Data("hello".utf8)
        let env = SyncEnvelope(payload: payload, updatedAt: Date(timeIntervalSince1970: 1234))
        let data = try env.encoded()
        let decoded = try SyncEnvelope.decode(from: data)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 1234))
        XCTAssertEqual(decoded.schemaVersion, SyncSchema.currentVersion)
        XCTAssertFalse(decoded.deviceId.isEmpty)
    }

    func testForwardCompatGuardRejectsNewerSchema() throws {
        // Forge a higher-version envelope manually and verify the guard catches it.
        struct ForgedEnvelope: Codable {
            let schemaVersion: Int
            let deviceId: String
            let updatedAt: Date
            let payload: Data
        }
        let forged = ForgedEnvelope(
            schemaVersion: SyncSchema.currentVersion + 99,
            deviceId: "dev",
            updatedAt: Date(),
            payload: Data())
        let data = try PropertyListEncoder().encode(forged)
        let decoded = try SyncEnvelope.decode(from: data)
        XCTAssertFalse(decoded.isCompatibleWithCurrentSchema)
    }
}

// MARK: - SyncTombstoneStore

final class SyncTombstoneStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: SyncTombstoneStore!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        store = SyncTombstoneStore(defaults: defaults)
    }

    func testRecordPersists() {
        store.record(category: .macros, id: "abc")
        XCTAssertNotNil(store.all(for: .macros)["abc"])
    }

    func testRemoveDropsEntry() {
        store.record(category: .macros, id: "abc")
        store.remove(category: .macros, id: "abc")
        XCTAssertNil(store.all(for: .macros)["abc"])
    }

    func testPruneDropsOldTombstones() {
        let old = Date().addingTimeInterval(-60 * 24 * 3600)
        store.record(category: .macros, id: "old", at: old)
        store.record(category: .macros, id: "new")
        store.prune(category: .macros)
        XCTAssertNil(store.all(for: .macros)["old"])
        XCTAssertNotNil(store.all(for: .macros)["new"])
    }

    func testTombstoneEntriesAreFlaggedDeleted() {
        store.record(category: .macros, id: "x")
        let entries = store.tombstoneEntries(for: .macros)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].deleted)
        XCTAssertEqual(entries[0].id, "x")
    }

    /// The outgoing payload is fingerprinted byte for byte against the push memo, so the entry
    /// order must not follow the backing Dictionary's per-process iteration order — two tombstones
    /// inside the retention window would otherwise make an unchanged category look new once per
    /// launch, and push.
    func testTombstoneEntriesAreOrderedById() {
        for id in ["c", "a", "b"] { store.record(category: .macros, id: id) }
        XCTAssertEqual(store.tombstoneEntries(for: .macros).map(\.id), ["a", "b", "c"])
    }
}

// MARK: - SyncCategory

final class SyncCategoryTests: XCTestCase {

    func testScalarsUsesWholeBlobMerge() {
        XCTAssertFalse(SyncCategory.scalars.usesPerEntryMerge)
    }

    func testCollectionCategoriesUsePerEntryMerge() {
        for c in [SyncCategory.macros, .rules, .excludedApps, .userDict] {
            XCTAssertTrue(c.usesPerEntryMerge, "\(c) should use per-entry merge")
        }
    }

    func testSoftQuotaBelowOneMB() {
        for c in SyncCategory.allCases {
            XCTAssertLessThan(c.softQuotaBytes, 1_048_576, "\(c) soft quota must stay under iCloud's 1 MB hard cap")
        }
    }
}

// MARK: - iCloudSyncManager — first-enable & lifecycle

final class iCloudSyncManagerTests: XCTestCase {

    private var mockStore: MockKeyValueStore!
    private var defaults: UserDefaults!
    private var tombstones: SyncTombstoneStore!
    private var sut: iCloudSyncManager!

    override func setUp() {
        super.setUp()
        mockStore = MockKeyValueStore()
        defaults = makeIsolatedDefaults()
        tombstones = SyncTombstoneStore(defaults: defaults)
        sut = iCloudSyncManager(store: mockStore, tombstones: tombstones, defaults: defaults)
    }

    override func tearDown() {
        sut._resetForTesting()
        sut = nil
        mockStore = nil
        defaults = nil
        tombstones = nil
        super.tearDown()
    }

    // MARK: Initial state

    func testInitialStatusIsDisabled() {
        XCTAssertEqual(sut.status, .disabled)
    }

    func testIsEnabledDefaultsFalse() {
        XCTAssertFalse(sut.isEnabled)
    }

    func testLastSyncDateDefaultsNil() {
        XCTAssertNil(sut.lastSyncDate)
    }

    func testSyncDataSizeBytesReturnsNilWhenEmpty() {
        XCTAssertNil(sut.syncDataSizeBytes)
    }

    /// Turn sync on, or skip.
    ///
    /// `iCloudSyncManager.isEnabled`'s setter opens with `guard Self.isKVSAvailable`,
    /// and that checks the REAL NSUbiquitousKeyValueStore rather than the mock these
    /// tests inject. A machine with no iCloud entitlement — a CI runner building with
    /// CODE_SIGNING_ALLOWED=NO — makes the assignment a silent no-op, so every
    /// assertion downstream of it fails for the environment rather than the code.
    private func enableSyncOrSkip() throws {
        sut.isEnabled = true
        try XCTSkipUnless(sut.isEnabled,
                          "needs a real iCloud key-value store; this machine has no iCloud entitlement")
    }

    // MARK: First-enable detection

    func testFirstEnableNoRemoteDataPushes() throws {
        // No remote data → enable should push and mark hasPushedBefore.
        try enableSyncOrSkip()
        XCTAssertTrue(defaults.bool(forKey: "XKey.sync.hasPushedBefore"))
    }

    func testFirstEnableWithRemoteDataAwaitsUserChoice() {
        // Seed the store with a remote envelope so the manager detects existing data.
        let envelope = SyncEnvelope(payload: Data("remote".utf8))
        mockStore.storage[SyncCategory.scalars.rawValue] = try! envelope.encoded()

        sut.isEnabled = true
        // hasPushedBefore must stay false until user resolves the prompt.
        XCTAssertFalse(defaults.bool(forKey: "XKey.sync.hasPushedBefore"))
        // Categories with remote data should be reported for the prompt.
        XCTAssertEqual(sut.categoriesWithRemoteData(), [.scalars])
    }

    func testCancelFirstEnableTurnsToggleOff() {
        let envelope = SyncEnvelope(payload: Data("remote".utf8))
        mockStore.storage[SyncCategory.scalars.rawValue] = try! envelope.encoded()
        sut.isEnabled = true

        sut.applyFirstEnableChoice(.cancel)

        XCTAssertFalse(sut.isEnabled)
        XCTAssertEqual(sut.status, .disabled)
    }

    func testFirstEnableUseRemoteMarksHasPushed() throws {
        let envelope = SyncEnvelope(payload: Data())
        mockStore.storage[SyncCategory.scalars.rawValue] = try! envelope.encoded()
        try enableSyncOrSkip()

        sut.applyFirstEnableChoice(.useRemote)

        XCTAssertTrue(defaults.bool(forKey: "XKey.sync.hasPushedBefore"))
    }

    // MARK: Disable

    func testDisableSetsStatusToDisabled() {
        sut.isEnabled = true
        sut.isEnabled = false
        XCTAssertEqual(sut.status, .disabled)
    }

    // MARK: Schema guard

    func testPullSkipsIncompatibleEnvelope() throws {
        // Forge a forward-incompatible envelope on the wire.
        struct Forged: Codable {
            let schemaVersion: Int
            let deviceId: String
            let updatedAt: Date
            let payload: Data
        }
        let forged = Forged(schemaVersion: SyncSchema.currentVersion + 1, deviceId: "x", updatedAt: Date(), payload: Data())
        mockStore.storage[SyncCategory.scalars.rawValue] = try PropertyListEncoder().encode(forged)

        try enableSyncOrSkip()
        sut.applyFirstEnableChoice(.useRemote)

        // Expect an error status because the envelope was rejected.
        if case .error = sut.status { XCTAssertTrue(true) } else {
            XCTFail("Expected .error status after incompatible pull, got \(sut.status)")
        }
    }

    // MARK: Push category

    func testPushCategoryWritesEnvelopeForList() throws {
        try enableSyncOrSkip()
        defaults.set(true, forKey: "XKey.sync.hasPushedBefore")

        sut.pushCategory(.macros)
        let raw = mockStore.storage[SyncCategory.macros.rawValue]
        XCTAssertNotNil(raw, "List category push should write an envelope")
        let env = try? SyncEnvelope.decode(from: raw ?? Data())
        XCTAssertEqual(env?.schemaVersion, SyncSchema.currentVersion)
    }

    func testPushDoesNothingWhenDisabled() {
        sut.pushAll()
        XCTAssertNil(mockStore.storage[SyncCategory.macros.rawValue])
    }

    /// A push whose payload is the one already in the store carries nothing: only the envelope's
    /// own updatedAt would differ. Every settings change schedules a push for all five
    /// categories, so writing those anyway spends five KVS writes on a change that touched one.
    func testPushSkipsTheStoreWriteWhenThePayloadIsUnchanged() {
        defaults.set(true, forKey: "XKey.iCloudSyncEnabled")
        defaults.set(true, forKey: "XKey.sync.hasPushedBefore")

        sut.pushCategory(.macros)
        let first = mockStore.storage[SyncCategory.macros.rawValue]
        XCTAssertNotNil(first, "the first push must seed the store")

        sut.pushCategory(.macros)
        XCTAssertEqual(mockStore.storage[SyncCategory.macros.rawValue], first,
                       "an unchanged payload must not be written to the store a second time")
    }

    /// Pressing the Vietnamese toggle changes nothing the scalars payload carries — the key is in
    /// scalarsExcludedKeys, which TapOwnershipTests.testVietnameseToggleIsNotSyncedAcrossMachines
    /// pins — but it still posts the settings-changed notification. Stamping a fresher updatedAt
    /// for that would let a keystroke carrying no setting win the merge on another Mac, against a
    /// payload that predates the preference that Mac just set.
    ///
    /// Posts the notification instead of writing vietnameseEnabled: the shared plist is the real
    /// one, and a write here invalidates the settings cache of every other test process.
    func testSettingsChangeCarryingNoSyncedKeyDoesNotAdvanceScalarsTimestamp() throws {
        sut.isEnabled = true
        try XCTSkipUnless(sut.isEnabled, "iCloud KVS unavailable — the manager never started observing")

        sut.pushCategory(.scalars)
        let stamped = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(stamped, forKey: "XKey.sync.scalars.localUpdatedAt")

        NotificationCenter.default.post(name: .sharedSettingsDidChange, object: nil)

        XCTAssertEqual(defaults.object(forKey: "XKey.sync.scalars.localUpdatedAt") as? Date, stamped,
                       "a change the scalars payload does not carry must not advance its timestamp")
    }

    /// The positive control for the suppression above: a change the scalars payload DOES carry must
    /// still advance updatedAt and must still reach the store. Without it, a comparison that is too
    /// eager — one that suppressed every push — would pass the whole suite.
    ///
    /// What makes a change "real" to the manager is that the push memo no longer describes the
    /// payload this Mac holds. Seeding a stale memo reproduces exactly that, without writing the
    /// shared plist: that plist is the real one, and a write here would change the developer's own
    /// settings and invalidate the settings cache of every other test process.
    func testSettingsChangeCarryingASyncedKeyAdvancesTheTimestampAndPushes() throws {
        sut.isEnabled = true
        try XCTSkipUnless(sut.isEnabled, "iCloud KVS unavailable — the manager never started observing")

        sut.pushCategory(.scalars)
        let seeded = mockStore.storage[SyncCategory.scalars.rawValue]
        XCTAssertNotNil(seeded, "the first push must seed the store")

        let stamped = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(stamped, forKey: "XKey.sync.scalars.localUpdatedAt")
        defaults.set("stale-payload-signature",
                     forKey: "XKey.sync.pushedSig.\(SyncCategory.scalars.rawValue)")

        NotificationCenter.default.post(name: .sharedSettingsDidChange, object: nil)

        XCTAssertGreaterThan(defaults.object(forKey: "XKey.sync.scalars.localUpdatedAt") as? Date ?? .distantPast,
                             stamped,
                             "a change the scalars payload carries must advance its timestamp")

        sut.pushCategory(.scalars)
        XCTAssertNotEqual(mockStore.storage[SyncCategory.scalars.rawValue], seeded,
                          "a change the scalars payload carries must reach the store")
    }

    /// A device that only ever receives never writes the push memo, so everything it holds looks new
    /// to the skip check: it re-pushes what it just pulled, and the very next settings change stamps
    /// a fresh updatedAt over a payload a peer had just set — the revert-by-a-keystroke the
    /// suppression above exists to stop, arriving from the pull side instead. Importing must leave
    /// the memo describing what this device now holds.
    ///
    /// The payload is empty on purpose: importScalarsForSync rejects it, so the machine's real
    /// settings are neither read into the assertion nor written. What is under test is that the pull
    /// refreshes the memo at all.
    func testPullRefreshesThePushMemoSoAReceivingDeviceStopsRePushing() throws {
        defaults.set(true, forKey: "XKey.iCloudSyncEnabled")
        defaults.set(true, forKey: "XKey.sync.hasPushedBefore")

        let remote = try foreignEnvelope(payload: Data())
        mockStore.storage[SyncCategory.scalars.rawValue] = remote

        sut.pullAll()
        sut.pushCategory(.scalars)

        XCTAssertEqual(mockStore.storage[SyncCategory.scalars.rawValue], remote,
                       "pushing the state we just pulled must not write the store")
    }

    // MARK: Sync now (bidirectional)

    /// syncNow() must respect the enabled guard — a disabled manager writes nothing, same as push.
    func testSyncNowDoesNothingWhenDisabled() {
        sut.syncNow()
        for c in SyncCategory.allCases {
            XCTAssertNil(mockStore.storage[c.rawValue], "\(c) must not be written while sync is disabled")
        }
    }
}
