//
//  ServicesProvider.swift
//  XKey
//
//  Receives macOS Services requests (context menu → Services →
//  "XKey: Thêm vào từ điển cá nhân") and adds the selected text's words
//  to the personal dictionary. This object only handles the NSServices
//  plumbing — the extraction/add/confirm/HUD pipeline lives in
//  UserDictionaryService, shared with the global-hotkey path.
//

import AppKit

/// Registered via `NSApp.servicesProvider` (see AppDelegate) — the object name
/// must match `NSPortName` in Info.plist's `NSServices` entry.
final class ServicesProvider: NSObject {

    static let shared = ServicesProvider()

    private static let serviceMessage = "addToUserDictionary"

    // MARK: - Services menu enable state

    /// macOS can register the service as *disabled* in System Settings →
    /// Keyboard → Keyboard Shortcuts → Services (seen on newer macOS when the
    /// service was first registered from a non-/Applications build). pbs
    /// persists that toggle in `~/Library/Preferences/pbs.plist` under
    /// `NSServicesStatus`, keyed by "{bundleID} - {localized menu title} -
    /// {NSMessage}". Re-enable our entry so the menu item shows without a
    /// manual trip to System Settings. Best-effort: failures leave the manual
    /// toggle path — this never touches unrelated services.
    func ensureServiceMenuEnabled() {
        ensureServiceMenuEnabled(
            bundleID: Bundle.main.bundleIdentifier ?? "com.codetay.XKey",
            suiteName: "pbs"
        )
    }

    /// Testable core — `suiteName` lets tests use a scratch domain instead of
    /// the real `pbs` preferences.
    func ensureServiceMenuEnabled(bundleID: String, suiteName: String) {
        guard let pbs = UserDefaults(suiteName: suiteName),
              var status = pbs.dictionary(forKey: "NSServicesStatus") else { return }
        let suffix = " - \(Self.serviceMessage)"
        let prefix = "\(bundleID) - "

        func isFullyEnabled(_ entry: [String: Any]) -> Bool {
            let modes = entry["presentation_modes"] as? [String: Any]
            func flag(_ value: Any?) -> Bool { (value as? Bool) ?? true }
            return flag(entry["enabled_context_menu"])
                && flag(entry["enabled_services_menu"])
                && flag(modes?["ContextMenu"])
                && flag(modes?["ServicesMenu"])
        }

        var changed = false
        var found = false
        for key in status.keys where key.hasPrefix(prefix) && key.hasSuffix(suffix) {
            found = true
            var entry = status[key] as? [String: Any] ?? [:]
            guard !isFullyEnabled(entry) else { continue }
            // Merge, don't replace — pbs also stores a user-assigned
            // `key_equivalent` here, and anything else future macOS adds.
            entry["enabled_context_menu"] = true
            entry["enabled_services_menu"] = true
            var modes = entry["presentation_modes"] as? [String: Any] ?? [:]
            modes["ContextMenu"] = true
            modes["ServicesMenu"] = true
            entry["presentation_modes"] = modes
            status[key] = entry
            changed = true
        }

        // No entry yet (System Settings never opened): seed one using the menu
        // title matching the system language, read from our own Info.plist.
        if !found, let title = localizedMenuTitle() {
            status["\(prefix)\(title)\(suffix)"] = [
                "enabled_context_menu": true,
                "enabled_services_menu": true,
                "presentation_modes": ["ContextMenu": true, "ServicesMenu": true],
            ]
            changed = true
        }

        guard changed else { return }
        pbs.set(status, forKey: "NSServicesStatus")
        pbs.synchronize()
        // Skip the rescan for non-production suites (tests).
        guard suiteName == "pbs" else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        task.arguments = ["-flush"]
        try? task.run()
    }

    /// Resolve the Services menu title the same way pbs does — the localization
    /// closest to the system language, falling back to the `default` title.
    private func localizedMenuTitle() -> String? {
        guard let services = Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]],
              let titles = services.first?["NSMenuItem"] as? [String: String] else { return nil }
        let lang = Locale.preferredLanguages.first ?? ""
        return titles[lang]
            ?? titles[String(lang.prefix(2))]
            ?? (lang.hasPrefix("zh") ? (titles["zh-Hans"] ?? titles["zh-Hant"]) : nil)
            ?? titles["en"]
            ?? titles["default"]
            ?? titles.values.first
    }

    // MARK: - NSServices entry point

    /// Invoked by the system when the user picks the service from the context
    /// menu. `NSMessage` in Info.plist is `addToUserDictionary`, so the
    /// Objective-C selector is `addToUserDictionary:userData:error:`.
    @objc(addToUserDictionary:userData:error:)
    func addToUserDictionary(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let raw = pboard.string(forType: .string)
            ?? pboard.string(forType: NSPasteboard.PasteboardType(rawValue: "NSStringPboardType"))
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            error.pointee = NSString(string: "No text on service pasteboard")
            return
        }
        DispatchQueue.main.async {
            UserDictionaryService.shared.addFromText(text)
        }
    }
}
