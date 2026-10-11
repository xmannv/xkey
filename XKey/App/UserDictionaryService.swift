//
//  UserDictionaryService.swift
//  XKey
//
//  Shared "add selected text to the personal dictionary" pipeline used by
//  both entry points: the macOS Services menu item (ServicesProvider) and
//  the global hotkey (AppDelegate host command). Owns word extraction,
//  dedup-aware insertion, the confirmation alert, and HUD feedback so the
//  two paths can't drift apart.
//

import AppKit

final class UserDictionaryService {

    static let shared = UserDictionaryService()

    /// Max words accepted from a single selection.
    static let maxWords = 100

    /// Max characters of the incoming selection scanned for words.
    static let maxInputLength = 10_000

    /// Max words shown in a single preview line (HUD detail / alert body).
    private static let previewLimit = 5

    // MARK: - Text → words (pure)

    /// Lowercase + strip edge punctuation/whitespace — the one normalization
    /// every token goes through.
    private static func normalizeWord(_ token: Substring) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }

    /// Split selected text into individual words for the personal dictionary.
    /// Whitespace/newline separated, edge punctuation stripped, lowercased,
    /// deduplicated preserving first-occurrence order, capped at `maxWords`.
    static func extractWords(from text: String) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = normalizeWord(token)
            guard !word.isEmpty, seen.insert(word).inserted else { continue }
            words.append(word)
            if words.count >= maxWords { break }
        }
        return words
    }

    /// Convenience for raw selections — extracts words from `text` capped at
    /// `maxInputLength` characters.
    static func extractWords(fromSelection text: String) -> [String] {
        let prefix = String(text.prefix(maxInputLength))
        var words = extractWords(from: prefix)
        // A selection longer than the cap can cut the last token mid-word —
        // drop that token's word so a truncated fragment isn't stored. Only
        // when the cut token actually produced the last word: a punctuation-
        // only token produces nothing, and a token whose word already appeared
        // complete earlier was skipped by dedup.
        if text.count > maxInputLength,
           let cut = text[text.index(text.startIndex, offsetBy: maxInputLength)...].first,
           !cut.isWhitespace {
            let tokens = prefix.split(whereSeparator: { $0.isWhitespace })
            if let lastToken = tokens.last {
                let lastWord = normalizeWord(lastToken)
                let seenEarlier = tokens.dropLast().contains { normalizeWord($0) == lastWord }
                if lastWord == words.last, !seenEarlier {
                    words.removeLast()
                }
            }
        }
        return words
    }

    // MARK: - Dictionary mutation

    /// Outcome of an add attempt: which words were inserted vs already present.
    struct AddResult {
        let added: [String]
        let alreadyPresent: [String]
    }

    /// Insert words into the personal dictionary, skipping duplicates.
    /// Call on the main thread — SharedSettings notifies observers on write.
    ///
    /// One read-modify-write for the whole batch: a single plist write and a
    /// single `XKey.settingsDidChange` post. Per-word `addUserDictionaryWord`
    /// calls would cost one write + one distributed notification each — for a
    /// 100-word selection XKeyIM would rebuild its tap environment 100 times.
    @discardableResult
    func addWords(_ words: [String]) -> AddResult {
        var all = SharedSettings.shared.getUserDictionaryWords()
        var added: [String] = []
        var existing: [String] = []
        for word in words {
            let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
            guard !normalized.isEmpty else { continue }
            if all.contains(normalized) {
                existing.append(normalized)
            } else {
                all.insert(normalized)
                added.append(normalized)
            }
        }
        if !added.isEmpty {
            SharedSettings.shared.setUserDictionaryWords(all)
            for word in added {
                // Match addUserDictionaryWord's tombstone clearing — a re-added
                // word must not stay shadowed by its old deletion on next sync.
                SyncTombstoneStore.shared.remove(category: .userDict, id: word)
            }
        }
        return AddResult(added: added, alreadyPresent: existing)
    }

    // MARK: - Pipelines shared by both entry points (main thread)

    /// No-confirmation path — used by the Services menu item: add whatever is
    /// selectable, then report via HUD.
    func addFromText(_ text: String) {
        let words = Self.extractWords(fromSelection: text)
        let result = addWords(words)
        showHUD(result: result, requested: words)
        AppDelegate.shared?.logToDebugWindow(
            "UserDictionary: added \(result.added.count)/\(words.count) word(s)"
        )
    }

    /// Confirmation path — used by the hotkey: preview the words in an alert
    /// and only write on "Thêm". When there is nothing new to add the alert is
    /// skipped and the existing-word HUD is shown instead.
    func confirmThenAddFromText(_ text: String) {
        let words = Self.extractWords(fromSelection: text)
        let pending = words.filter { !SharedSettings.shared.isWordInUserDictionary($0) }
        guard !pending.isEmpty else {
            // All extracted words already exist (or selection had none) — no
            // confirmation needed, just report.
            showHUD(result: AddResult(added: [], alreadyPresent: words), requested: words)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Thêm vào từ điển cá nhân")
        var body = Self.preview(of: pending, limit: Self.previewLimit)
        let skipped = words.count - pending.count
        if skipped > 0 {
            body += "\n" + String(localized: "(\(skipped) từ đã có trong từ điển)")
        }
        alert.informativeText = body
        alert.addButton(withTitle: String(localized: "Thêm"))
        alert.addButton(withTitle: String(localized: "Hủy"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let result = addWords(pending)
        showHUD(result: result, requested: words)
        AppDelegate.shared?.logToDebugWindow(
            "UserDictionary: confirmed add \(result.added.count)/\(words.count) word(s)"
        )
    }

    // MARK: - Formatting & HUD

    /// "a, b, c…và 4 từ khác" — shared preview line for HUD detail and the
    /// confirmation alert. Each shown word is capped so a pathological token
    /// can't blow the alert/HUD wide open.
    static func preview(of words: [String], limit: Int) -> String {
        let shown = words.prefix(limit)
            .map { $0.count > 30 ? String($0.prefix(30)) + "…" : $0 }
            .joined(separator: ", ")
        let remaining = words.count - limit
        return remaining > 0
            ? shown + "…" + String(localized: "và \(remaining) từ khác")
            : shown
    }

    /// Centered HUD for an add attempt (adds, all-duplicate, or empty input).
    func showHUD(result: AddResult, requested words: [String]) {
        if words.isEmpty {
            ToggleHUDWindow.shared.showMessage(
                title: String(localized: "Không có văn bản để thêm"),
                success: false
            )
            return
        }

        let shown = result.added.isEmpty ? words : result.added
        let detail = Self.preview(of: shown, limit: 3)
        if result.added.isEmpty {
            ToggleHUDWindow.shared.showMessage(
                title: String(localized: "Đã có trong từ điển"),
                detail: detail
            )
        } else if result.added.count == 1 {
            ToggleHUDWindow.shared.showMessage(
                title: String(localized: "Đã thêm vào từ điển"),
                detail: detail
            )
        } else {
            ToggleHUDWindow.shared.showMessage(
                title: String(localized: "Đã thêm \(result.added.count) từ vào từ điển"),
                detail: detail
            )
        }
    }
}
