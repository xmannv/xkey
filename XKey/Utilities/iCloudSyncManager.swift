//
//  iCloudSyncManager.swift
//  XKey
//
//  Multi-key iCloud settings sync with CRDT-lite per-entry merge for list categories.
//  Replaces the single-blob design from PR #277 — adds:
//    - per-category KVS keys (each within Apple's 1 MB cap)
//    - SyncEnvelope wrapper (schemaVersion, deviceId, updatedAt)
//    - per-entry merge with tombstones for macros / rules / excluded apps / user dictionary
//    - first-enable detection (no more silent overwrite of cloud data)
//    - quota pre-check before push
//    - forward-compat guard against payloads from newer app versions
//

import Foundation

// MARK: - Manager

final class iCloudSyncManager: NSObject {

    // MARK: - Singleton

    static let shared = iCloudSyncManager()

    // MARK: - Dependencies

    private let kvStore: KeyValueStoreProtocol
    private let tombstones: SyncTombstoneStore
    private let defaults: UserDefaults

    // MARK: - Persistent keys

    private let enabledKey            = "XKey.iCloudSyncEnabled"
    private let lastSyncDateKey       = "XKey.lastCloudSyncDate"
    private let hasPushedBeforeKey    = "XKey.sync.hasPushedBefore"
    private let scalarsLocalUpdatedAtKey = "XKey.sync.scalars.localUpdatedAt"
    private let entrySigPrefix        = "XKey.sync.entrySig."
    private let pushedSigPrefix       = "XKey.sync.pushedSig."

    // MARK: - Mutable state

    private var perCategoryStatus: [SyncCategory: SyncCategoryStatus] = [:]
    private var pushTimers: [SyncCategory: Timer] = [:]
    private var dirtyCategories: Set<SyncCategory> = []
    private var isPulling = false
    private var isObserving = false
    private var awaitingFirstEnableDecision = false

    private let pushDebounce: TimeInterval = 2.0

    // MARK: - Init

    override private init() {
        self.kvStore = NSUbiquitousKeyValueStore.default
        self.tombstones = .shared
        self.defaults = .standard
        super.init()
    }

    init(store: KeyValueStoreProtocol,
         tombstones: SyncTombstoneStore = .shared,
         defaults: UserDefaults = .standard) {
        self.kvStore = store
        self.tombstones = tombstones
        self.defaults = defaults
        super.init()
    }

    // MARK: - Availability

    /// True when the ubiquity-kvstore-identifier entitlement is present and KVS is reachable.
    /// synchronize() returns false when the entitlement is absent — safe to call always.
    ///
    /// NOTE: A notarized Developer ID (non-App-Store) build CAN use iCloud KVS. The earlier
    /// "SIGKILL on launch" was NOT a platform ban — it was a code-signing mismatch: the binary
    /// was signed with a Developer ID cert that was not listed in the embedded provisioning
    /// profile's DeveloperCertificates, so amfid rejected the restricted entitlement with
    /// -413 "No matching profile found". Signing with the cert the profile authorizes fixes it.
    /// On macOS 26 KVS is CloudKit-backed under the hood (syncdefaultsd → cloudd → iCloud).
    static var isKVSAvailable: Bool {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - Public state

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set {
            guard Self.isKVSAvailable else { return }
            let wasEnabled = isEnabled
            defaults.set(newValue, forKey: enabledKey)
            if newValue && !wasEnabled {
                handleEnable()
            } else if !newValue && wasEnabled {
                handleDisable()
            }
        }
    }

    var lastSyncDate: Date? {
        defaults.object(forKey: lastSyncDateKey) as? Date
    }

    /// Total bytes across all category keys.
    var syncDataSizeBytes: Int? {
        let total = SyncCategory.allCases.reduce(0) { acc, c in
            acc + (kvStore.data(forKey: c.rawValue)?.count ?? 0)
        }
        return total == 0 ? nil : total
    }

    func bytes(for category: SyncCategory) -> Int? {
        kvStore.data(forKey: category.rawValue)?.count
    }

    /// Aggregated status surfaced to the UI.
    var status: iCloudSyncStatus {
        guard isEnabled else { return .disabled }
        if awaitingFirstEnableDecision { return .idle }
        let statuses = SyncCategory.allCases.map { perCategoryStatus[$0] ?? .idle }
        // Quota violation surfaces as an error — the quota meter already shows which category.
        if statuses.contains(.quotaExceeded) {
            return .error(String(localized: "Dung lượng iCloud vượt giới hạn — xem chi tiết bên dưới"))
        }
        if let firstError = statuses.first(where: {
            if case .error = $0 { return true } else { return false }
        }), case .error(let msg) = firstError {
            return .error(msg)
        }
        if statuses.contains(.pulling) { return .pulling }
        if statuses.contains(.pushing) { return .pushing }
        if statuses.allSatisfy({
            if case .synced = $0 { return true } else { return false }
        }) { return .synced }
        return .idle
    }

    func categoryStatus(_ category: SyncCategory) -> SyncCategoryStatus {
        perCategoryStatus[category] ?? .disabled
    }

    // MARK: - Setup (called from AppDelegate)

    func setup() {
        guard Self.isKVSAvailable else {
            setAllCategories(.disabled)
            return
        }
        guard isEnabled else {
            setAllCategories(.disabled)
            return
        }
        startObserving()
        for c in SyncCategory.allCases { perCategoryStatus[c] = .idle }
        kvStore.synchronize()
        // KVS will fire .didChangeExternallyNotification with InitialSyncChange shortly;
        // do not pre-emptively pull here — let the observer drive it.
    }

    // MARK: - Enable / disable flow

    private func handleEnable() {
        startObserving()
        kvStore.synchronize()

        let decision = detectFirstEnable()
        switch decision {
        case .noRemoteData:
            for c in SyncCategory.allCases { perCategoryStatus[c] = .idle }
            if !defaults.bool(forKey: hasPushedBeforeKey) {
                // True first time — no remote data exists, push local as seed.
                pushAll()
                defaults.set(true, forKey: hasPushedBeforeKey)
            }
            // On re-enable (hasPushedBefore=true), do NOT push immediately — remote may have
            // newer data written by another device while this one had sync disabled.
            // The KVS InitialSyncChange notification fired by kvStore.synchronize() will drive
            // a pull-merge shortly via kvStoreDidChange.
            notifyStatusChanged()
        case .remoteHasData:
            // Need user to choose. Block automatic push until applyFirstEnableChoice() is called.
            awaitingFirstEnableDecision = true
            for c in SyncCategory.allCases { perCategoryStatus[c] = .idle }
            notifyStatusChanged()
            postFirstEnablePrompt()
        }
    }

    private func handleDisable() {
        stopObserving()
        setAllCategories(.disabled)
        awaitingFirstEnableDecision = false
        notifyStatusChanged()
    }

    private func detectFirstEnable() -> SyncFirstEnableDecision {
        if defaults.bool(forKey: hasPushedBeforeKey) {
            return .noRemoteData  // already initialised; subsequent enables behave normally
        }
        let hasRemote = SyncCategory.allCases.contains { c in
            kvStore.data(forKey: c.rawValue) != nil
        }
        return hasRemote ? .remoteHasData : .noRemoteData
    }

    /// Categories that currently have non-empty remote envelopes. Used by the UI prompt
    /// so the user knows what data is at stake before picking an action.
    func categoriesWithRemoteData() -> [SyncCategory] {
        SyncCategory.allCases.filter { kvStore.data(forKey: $0.rawValue) != nil }
    }

    /// Resolve the first-enable prompt with the user's choice.
    func applyFirstEnableChoice(_ action: SyncFirstEnableAction) {
        guard awaitingFirstEnableDecision else { return }
        switch action {
        case .cancel:
            // User backed out — turn the toggle back off without pushing or pulling.
            awaitingFirstEnableDecision = false
            defaults.set(false, forKey: enabledKey)
            handleDisable()
            return
        case .useLocal:
            awaitingFirstEnableDecision = false
            pushAll()
            defaults.set(true, forKey: hasPushedBeforeKey)
        case .useRemote:
            awaitingFirstEnableDecision = false
            pullAllOverwriteLocal()
            defaults.set(true, forKey: hasPushedBeforeKey)
        case .merge:
            awaitingFirstEnableDecision = false
            mergeAll()
            defaults.set(true, forKey: hasPushedBeforeKey)
        }
        notifyStatusChanged()
    }

    // MARK: - Push

    /// Manual "Sync now" from the UI.
    func pushAll() {
        for c in SyncCategory.allCases { pushCategory(c) }
    }

    func pushCategory(_ category: SyncCategory) {
        guard isEnabled, !isPulling, !awaitingFirstEnableDecision else { return }
        setCategoryStatus(category, .pushing)
        do {
            let envelope = try buildOutgoingEnvelope(for: category)
            let payloadSignature = canonicalSignature(of: envelope.payload)
            if payloadSignature == lastPushedSignature(for: category) {
                // Nothing new to send — only the envelope's own updatedAt would differ. Paying a
                // store write for that is what turns a change carrying no synced key (the
                // Vietnamese toggle, and every other key in scalarsExcludedKeys) into one
                // NSUbiquitousKeyValueStore write per category.
                setCategoryStatus(category, .synced(Date()))
                notifyStatusChanged()
                return
            }
            let encoded = try envelope.encoded()
            if encoded.count > category.softQuotaBytes {
                setCategoryStatus(category, .quotaExceeded)
                sharedLogWarning("iCloud sync: \(category.rawValue) payload \(encoded.count) B exceeds soft quota — not pushed")
                notifyStatusChanged()
                return
            }
            kvStore.setData(encoded, forKey: category.rawValue)
            kvStore.synchronize()
            defaults.set(payloadSignature, forKey: pushedSignatureKey(category))
            defaults.set(Date(), forKey: lastSyncDateKey)
            setCategoryStatus(category, .synced(Date()))
            sharedLogSuccess("iCloud sync: pushed \(category.rawValue) (\(encoded.count) B)")
        } catch {
            setCategoryStatus(category, .error(error.localizedDescription))
            sharedLogError("iCloud sync: push failed for \(category.rawValue): \(error)")
        }
        notifyStatusChanged()
    }

    private func buildOutgoingEnvelope(for category: SyncCategory) throws -> SyncEnvelope {
        if category.usesPerEntryMerge {
            let liveEntries = snapshotLiveEntries(for: category)
            // Never emit a tombstone for an id that is currently live — that would be contradictory
            // state. Re-add paths already clear the tombstone, so this is defensive; it also keeps
            // the payload minimal. (A re-added entry gets a fresh `now` timestamp via its new UUID
            // signature, so it wins over any peer's older tombstone on merge regardless.)
            let liveIDs = Set(liveEntries.map { $0.id })
            let tombstoneEntries = tombstones.tombstoneEntries(for: category)
                .filter { !liveIDs.contains($0.id) }
            tombstones.prune(category: category)
            let payload = SyncCollectionPayload(entries: liveEntries + tombstoneEntries)
                .prunedTombstones(retention: category.tombstoneRetention)
            return SyncEnvelope(payload: try payload.encoded())
        } else {
            // scalars whole-blob
            let blob = SharedSettings.shared.exportScalarsForSync() ?? Data()
            let updatedAt = (defaults.object(forKey: scalarsLocalUpdatedAtKey) as? Date) ?? Date()
            return SyncEnvelope(payload: blob, updatedAt: updatedAt)
        }
    }

    // MARK: - Push memo

    private func pushedSignatureKey(_ category: SyncCategory) -> String {
        "\(pushedSigPrefix)\(category.rawValue)"
    }

    /// Fingerprint of the payload this device last pushed for `category`, or nil when there is
    /// nothing to match against — including when the store holds no value for it, which retires
    /// the memo after a store reset so the next push runs instead of being skipped as a repeat.
    private func lastPushedSignature(for category: SyncCategory) -> String? {
        guard kvStore.data(forKey: category.rawValue) != nil else { return nil }
        return defaults.string(forKey: pushedSignatureKey(category))
    }

    /// Point the scalars memo at the state this device now holds. An import moves that state
    /// without going through a push, so without this the memo keeps describing the payload we
    /// pushed before the import.
    ///
    /// Signed over the export rather than over the bytes that arrived, because both readers of
    /// this memo compare it against exportScalarsForSync(): the push's own skip check, and the
    /// stamp guard in localSettingsDidChange. A stale value reopens both — a change that returns
    /// the payload to the previously pushed value is skipped as a repeat and never leaves this
    /// Mac, and a device that only ever receives keeps a memo nothing matches, so every settings
    /// change stamps a fresh updatedAt and pushes.
    private func refreshScalarsPushMemo() {
        defaults.set(canonicalSignature(of: SharedSettings.shared.exportScalarsForSync() ?? Data()),
                     forKey: pushedSignatureKey(.scalars))
    }

    /// Content fingerprint of a payload, stable across launches.
    ///
    /// The payload's own bytes are not: exportScalarsForSync() serialises a Swift Dictionary,
    /// whose iteration order is seeded per process, and the binary plist writer emits keys in
    /// that order. The XML writer sorts them, so re-serialising through it makes unchanged
    /// settings fingerprint the same in every launch instead of looking new once per launch.
    private func canonicalSignature(of payload: Data) -> String {
        guard let plist = try? PropertyListSerialization.propertyList(from: payload, format: nil),
              let canonical = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        else { return signature(of: payload) }
        return signature(of: canonical)
    }

    // MARK: - Pull

    /// Force pull every category, overwriting local state. Used when user picks "use remote" on first-enable.
    func pullAllOverwriteLocal() {
        for c in SyncCategory.allCases {
            pullCategory(c, mode: .overwriteLocal)
        }
    }

    /// Pull every category and merge into local (CRDT for collections, newer-wins for scalars).
    func pullAll() {
        for c in SyncCategory.allCases {
            pullCategory(c, mode: .mergeWithLocal)
        }
    }

    /// Manual "Sync now" from the UI. Bidirectional: pull-merge every category FIRST so deletes and
    /// edits made on other devices are adopted here, THEN push the merged result so our state
    /// propagates back. The old behavior (push-only) overwrote a peer's tombstone with our still-live
    /// entry — a delete made elsewhere never landed here, and the push un-deleted it for everyone.
    func syncNow() {
        guard isEnabled, !awaitingFirstEnableDecision else { return }
        kvStore.synchronize()
        pullMergeThenPushAll()
    }

    /// Pull-merge every category into local, then push the merged result back. Shared by the manual
    /// "Sync now" button and the first-enable "merge" action — both need the same bidirectional pass
    /// so a delete/edit from either side survives instead of one side clobbering the other.
    private func pullMergeThenPushAll() {
        for c in SyncCategory.allCases {
            pullCategory(c, mode: .mergeWithLocal)
            pushCategory(c)
        }
    }

    private enum PullMode { case mergeWithLocal, overwriteLocal }

    private func pullCategory(_ category: SyncCategory, mode: PullMode) {
        guard let data = kvStore.data(forKey: category.rawValue) else {
            // No remote data — nothing to apply. Mark synced if currently idle.
            if perCategoryStatus[category] == .idle {
                setCategoryStatus(category, .synced(Date()))
                notifyStatusChanged()
            }
            return
        }
        setCategoryStatus(category, .pulling)
        do {
            let envelope = try SyncEnvelope.decode(from: data)
            guard envelope.isCompatibleWithCurrentSchema else {
                setCategoryStatus(category, .error(String(localized: "Bản XKey mới hơn đã ghi data này")))
                notifyStatusChanged()
                return
            }
            // Skip echoes of our own push — initial sync after relaunch can re-deliver the value
            // this device just wrote, and re-applying it would needlessly churn local state.
            if envelope.deviceId == SyncDeviceID.current && mode == .mergeWithLocal {
                setCategoryStatus(category, .synced(Date()))
                notifyStatusChanged()
                return
            }
            try applyEnvelope(envelope, category: category, mode: mode)
            defaults.set(Date(), forKey: lastSyncDateKey)
            setCategoryStatus(category, .synced(Date()))
            sharedLogSuccess("iCloud sync: pulled \(category.rawValue) (\(data.count) B)")
        } catch {
            setCategoryStatus(category, .error(error.localizedDescription))
            sharedLogError("iCloud sync: pull failed for \(category.rawValue): \(error)")
        }
        notifyStatusChanged()
    }

    private func applyEnvelope(_ envelope: SyncEnvelope, category: SyncCategory, mode: PullMode) throws {
        let apply = { [weak self] in
            guard let self = self else { return }
            self.isPulling = true
            defer { self.isPulling = false }
            if category.usesPerEntryMerge {
                guard let remotePayload = try? SyncCollectionPayload.decode(from: envelope.payload) else { return }
                // Local payload must include local tombstones, not just live entries. Otherwise a
                // local delete (a fresh tombstone) has nothing to compare against and a stale remote
                // live entry resurrects it on merge — silently losing the deletion. Including the
                // tombstone lets last-write-wins keep the newer delete.
                let local = SyncCollectionPayload(
                    entries: self.snapshotLiveEntries(for: category)
                        + self.tombstones.tombstoneEntries(for: category)
                )
                let merged: SyncCollectionPayload
                switch mode {
                case .overwriteLocal:
                    merged = remotePayload
                case .mergeWithLocal:
                    merged = local.merged(with: remotePayload)
                }
                self.applyCollection(merged, to: category)
                // Retire the memo left by our last push: it describes a payload the store no longer
                // holds, and a push whose payload happens to match it would be skipped as a repeat
                // even though the store never received it. The remote bytes are the right value
                // here rather than the merged result — pullMergeThenPushAll pushes immediately
                // after this, and that push must still go out whenever the merge produced anything
                // the store does not already have.
                self.defaults.set(self.canonicalSignature(of: envelope.payload),
                                  forKey: self.pushedSignatureKey(category))
            } else {
                // scalars whole-blob
                switch mode {
                case .overwriteLocal:
                    SharedSettings.shared.importScalarsForSync(from: envelope.payload)
                    self.refreshScalarsPushMemo()
                case .mergeWithLocal:
                    let localTimestamp = (self.defaults.object(forKey: self.scalarsLocalUpdatedAtKey) as? Date) ?? .distantPast
                    if envelope.updatedAt > localTimestamp {
                        SharedSettings.shared.importScalarsForSync(from: envelope.payload)
                        self.defaults.set(envelope.updatedAt, forKey: self.scalarsLocalUpdatedAtKey)
                        self.refreshScalarsPushMemo()
                    }
                }
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync { apply() }
        }
    }

    // MARK: - Merge (first-enable "merge" action)

    private func mergeAll() {
        // For collections: pull-merge, then push the merged result. For scalars: newer timestamp wins.
        pullMergeThenPushAll()
    }

    // MARK: - Snapshot helpers (delegate to SharedSettings)

    private func snapshotLiveEntries(for category: SyncCategory) -> [SyncEntry] {
        switch category {
        case .scalars:
            return []
        case .macros:
            return SharedSettings.shared.snapshotMacrosForSync(timestampProvider: timestampProvider(for: .macros))
        case .rules:
            return SharedSettings.shared.snapshotRulesForSync(timestampProvider: timestampProvider(for: .rules))
        case .excludedApps:
            return SharedSettings.shared.snapshotExcludedAppsForSync(timestampProvider: timestampProvider(for: .excludedApps))
        case .userDict:
            return SharedSettings.shared.snapshotUserDictForSync(timestampProvider: timestampProvider(for: .userDict))
        }
    }

    private func applyCollection(_ payload: SyncCollectionPayload, to category: SyncCategory) {
        let live = payload.liveEntries
        let remoteTombstones = payload.entries.filter { $0.deleted }
        switch category {
        case .scalars:
            return
        case .macros:
            SharedSettings.shared.applyMacrosFromSync(liveEntries: live)
        case .rules:
            SharedSettings.shared.applyRulesFromSync(liveEntries: live)
        case .excludedApps:
            SharedSettings.shared.applyExcludedAppsFromSync(liveEntries: live)
        case .userDict:
            SharedSettings.shared.applyUserDictFromSync(liveEntries: live)
        }
        // Adopt remote tombstones preserving their original deletion timestamps so the
        // 30-day retention window is measured from the actual deletion, not from sync time.
        for entry in remoteTombstones {
            tombstones.record(category: category, id: entry.id, at: entry.updatedAt)
        }
        tombstones.prune(category: category)
        refreshEntrySignatures(category: category, liveIDs: Set(live.map { $0.id }))
    }

    // MARK: - Per-entry timestamps (content-hash based)

    /// Returns a closure SharedSettings calls per entry: given (id, contentData) -> updatedAt.
    /// Tracks last-seen signature so the timestamp only bumps when the entry actually changed.
    private func timestampProvider(for category: SyncCategory) -> (String, Data) -> Date {
        return { [weak self] id, data in
            guard let self = self else { return Date() }
            let sig = self.signature(of: data)
            let sigKey = "\(self.entrySigPrefix)\(category.rawValue).\(id).sig"
            let dateKey = "\(self.entrySigPrefix)\(category.rawValue).\(id).date"
            if let prevSig = self.defaults.string(forKey: sigKey),
               let prevDate = self.defaults.object(forKey: dateKey) as? Date,
               prevSig == sig {
                return prevDate
            }
            let now = Date()
            self.defaults.set(sig, forKey: sigKey)
            self.defaults.set(now, forKey: dateKey)
            return now
        }
    }

    /// Prune signature cache so entries removed locally don't accumulate metadata forever.
    private func refreshEntrySignatures(category: SyncCategory, liveIDs: Set<String>) {
        let prefix = "\(entrySigPrefix)\(category.rawValue)."
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            let suffix = key.dropFirst(prefix.count)
            let parts = suffix.split(separator: ".")
            guard parts.count >= 2 else { continue }
            let id = parts.dropLast().joined(separator: ".")
            if !liveIDs.contains(id) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func signature(of data: Data) -> String {
        // Stable 64-bit FNV-1a fingerprint. Swift.Hasher is process-seeded (non-stable across
        // launches), so we cannot use it — a mismatched signature would reset every entry's
        // timestamp on every app restart, making CRDT timestamps meaningless.
        // Collisions are tolerable: we err on the side of a fresher timestamp, not data loss.
        var hash: UInt64 = 14695981039346656037  // FNV offset basis
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211          // FNV prime (overflow-safe)
        }
        return String(hash)
    }

    // MARK: - Observers

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localSettingsDidChange),
            name: .sharedSettingsDidChange,
            object: nil)
    }

    private func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        NotificationCenter.default.removeObserver(self,
            name: .sharedSettingsDidChange, object: nil)
        for (_, t) in pushTimers { t.invalidate() }
        pushTimers.removeAll()
        dirtyCategories.removeAll()
    }

    @objc private func localSettingsDidChange() {
        guard isEnabled, !isPulling, !awaitingFirstEnableDecision else { return }
        // Bump the scalars timestamp on any local change the scalars payload actually carries.
        // Coarse but safe — the manager doesn't know which category a setting belongs to, so
        // every list category is marked dirty to recompute signatures, and the push drops the
        // ones whose payload turns out to be unchanged.
        //
        // A change confined to keys the payload excludes (scalarsExcludedKeys — the Vietnamese
        // toggle among them) must not stamp: a fresher updatedAt on a payload that is identical
        // to the last push still wins the merge at the other end, and reverts the preference a
        // peer set in the meantime with our copy that predates it.
        if canonicalSignature(of: SharedSettings.shared.exportScalarsForSync() ?? Data())
            != lastPushedSignature(for: .scalars) {
            defaults.set(Date(), forKey: scalarsLocalUpdatedAtKey)
        }
        for c in SyncCategory.allCases { dirtyCategories.insert(c) }
        schedulePush()
    }

    private func schedulePush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for c in self.dirtyCategories {
                self.pushTimers[c]?.invalidate()
                self.pushTimers[c] = Timer.scheduledTimer(withTimeInterval: self.pushDebounce, repeats: false) { [weak self] _ in
                    self?.dirtyCategories.remove(c)
                    self?.pushCategory(c)
                }
            }
        }
    }

    @objc private func kvStoreDidChange(_ notification: Notification) {
        guard isEnabled, !awaitingFirstEnableDecision else { return }
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        else { return }

        // Account change carries no changedKeys — handle before the keys guard.
        if reason == NSUbiquitousKeyValueStoreAccountChange {
            defaults.set(false, forKey: hasPushedBeforeKey)
            tombstones.clearAll()
            // The push memo fingerprints what this device wrote to the previous account's
            // store. Keeping it would let the first push to the new account be skipped as a
            // repeat of something that account never received.
            for c in SyncCategory.allCases { defaults.removeObject(forKey: pushedSignatureKey(c)) }
            sharedLogWarning("iCloud account changed — re-sync state cleared")
            return
        }

        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
        let categories = changedKeys.compactMap(SyncCategory.init(rawValue:))
        guard !categories.isEmpty else { return }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            for c in categories { pullCategory(c, mode: .mergeWithLocal) }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            for c in categories { setCategoryStatus(c, .quotaExceeded) }
            sharedLogWarning("iCloud KVS quota exceeded — partial sync paused")
            notifyStatusChanged()
        default:
            break
        }
    }

    // MARK: - Export to file (for Backup tab)

    /// Aggregate every category's live payload into a single .plist for the "Export from iCloud" UI.
    func exportCloudData() -> Data? {
        var combined: [String: Any] = [:]
        var any = false
        for c in SyncCategory.allCases {
            guard let raw = kvStore.data(forKey: c.rawValue),
                  let envelope = try? SyncEnvelope.decode(from: raw),
                  envelope.isCompatibleWithCurrentSchema else { continue }
            any = true
            if c.usesPerEntryMerge {
                if let payload = try? SyncCollectionPayload.decode(from: envelope.payload) {
                    combined[c.rawValue] = payload.liveEntries.compactMap { $0.data }
                }
            } else {
                if let dict = try? PropertyListSerialization.propertyList(from: envelope.payload, format: nil) as? [String: Any] {
                    combined[c.rawValue] = dict
                }
            }
        }
        guard any else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: combined, format: .xml, options: 0)
    }

    // MARK: - Internal status helpers

    private func setCategoryStatus(_ category: SyncCategory, _ newStatus: SyncCategoryStatus) {
        perCategoryStatus[category] = newStatus
    }

    private func setAllCategories(_ newStatus: SyncCategoryStatus) {
        for c in SyncCategory.allCases { perCategoryStatus[c] = newStatus }
    }

    private func notifyStatusChanged() {
        NotificationCenter.default.post(name: .iCloudSyncStatusDidChange, object: nil)
    }

    private func postFirstEnablePrompt() {
        let names = categoriesWithRemoteData().map { $0.rawValue }
        NotificationCenter.default.post(
            name: .iCloudSyncFirstEnablePrompt,
            object: nil,
            userInfo: ["categoriesWithRemote": names])
    }

    // MARK: - Testing hooks

    /// Reset internal state for tests. Wipes both KVS and UserDefaults keys this manager owns.
    func _resetForTesting() {
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: lastSyncDateKey)
        defaults.removeObject(forKey: hasPushedBeforeKey)
        defaults.removeObject(forKey: scalarsLocalUpdatedAtKey)
        for c in SyncCategory.allCases {
            defaults.removeObject(forKey: c.rawValue)
            defaults.removeObject(forKey: pushedSignatureKey(c))
            kvStore.setData(nil, forKey: c.rawValue)
        }
        tombstones.clearAll()
        perCategoryStatus.removeAll()
        dirtyCategories.removeAll()
        awaitingFirstEnableDecision = false
        isPulling = false
    }
}
