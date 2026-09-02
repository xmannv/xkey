//
//  MacroManagementViewModel.swift
//  XKey
//
//  ViewModel for macro management
//

import Foundation
import AppKit
import UniformTypeIdentifiers

struct MacroItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let content: String
    var isEnabled: Bool
    
    init(id: UUID = UUID(), text: String, content: String, isEnabled: Bool = true) {
        self.id = id
        self.text = text
        self.content = content
        self.isEnabled = isEnabled
    }
    
    // Custom decoding to handle backward compatibility (old data without isEnabled)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        content = try container.decode(String.self, forKey: .content)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

class MacroManagementViewModel: ObservableObject {
    @Published var macros: [MacroItem] = []

    private var macrosChangedObserver: NSObjectProtocol?

    init() {
        // Keep an open Macro tab in sync with the store. When an iCloud pull applies a remote
        // edit/delete it posts .macrosDidChange; without observing it here the list would show
        // stale rows until the tab is reopened. Engine reload is handled separately by
        // KeyboardEventHandler's own observer, so this only refreshes the published list.
        macrosChangedObserver = NotificationCenter.default.addObserver(
            forName: .macrosDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadPublishedMacros()
        }
    }

    deinit {
        if let observer = macrosChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-read the published list from the store without touching the typing engine.
    /// Idempotent: safe even when the change originated from this view model's own edits.
    private func reloadPublishedMacros() {
        if let data = SharedSettings.shared.getMacrosData(),
           let decoded = try? JSONDecoder().decode([MacroItem].self, from: data) {
            macros = decoded
        } else {
            macros = []
        }
    }

    // Get app delegate
    private func getAppDelegate() -> AppDelegate? {
        if Thread.isMainThread {
            return NSApplication.shared.delegate as? AppDelegate
        } else {
            var result: AppDelegate?
            DispatchQueue.main.sync {
                result = NSApplication.shared.delegate as? AppDelegate
            }
            return result
        }
    }
    
    // Get macro manager from app delegate - always get fresh reference
    private func getMacroManager() -> MacroManager? {
        return getAppDelegate()?.getMacroManager()
    }
    
    // Log to debug window
    private func log(_ message: String) {
        getAppDelegate()?.logToDebugWindow(message)
    }
    
    // MARK: - Load/Save
    
    func loadMacros() {
        // Load from plist storage
        if let data = SharedSettings.shared.getMacrosData(),
           let decoded = try? JSONDecoder().decode([MacroItem].self, from: data) {
            macros = decoded
            
            // Sync only enabled macros to MacroManager
            syncEnabledMacrosToEngine()
        }
    }
    
    /// Sync only enabled macros to MacroManager (engine core)
    private func syncEnabledMacrosToEngine() {
        guard let manager = getMacroManager() else { return }
        manager.clearAll()
        for macro in macros where macro.isEnabled {
            _ = manager.addMacro(text: macro.text, content: macro.content)
        }
    }
    
    private func saveMacros() {
        if let encoded = try? JSONEncoder().encode(macros) {
            SharedSettings.shared.setMacrosData(encoded)
        }
    }
    
    // MARK: - CRUD Operations
    
    func addMacro(text: String, content: String) -> Bool {
        log("📝 addMacro called: '\(text)' → '\(content)'")
        
        // Check if already exists
        if macros.contains(where: { $0.text == text }) {
            log("   Macro '\(text)' already exists")
            return false
        }
        
        let macro = MacroItem(text: text, content: content)
        macros.append(macro)
        macros.sort { $0.text < $1.text }

        // Save to plist first
        saveMacros()

        // Clear any stale tombstone for this abbreviation so the local store stays consistent
        // (a live macro must not carry a tombstone). Cross-peer correctness is independent: the
        // re-add gets a new UUID -> new signature -> fresh `now` timestamp, which already beats a
        // peer's older tombstone on merge.
        SyncTombstoneStore.shared.remove(category: .macros, id: macro.text)

        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)

        return true
    }
    
    func updateMacro(_ macro: MacroItem, newText: String, newContent: String) -> Bool {
        log("updateMacro called: '\(macro.text)' → '\(newText)' with content '\(newContent)'")
        
        // Check if new text conflicts with another macro (but not itself)
        if newText != macro.text && macros.contains(where: { $0.text == newText }) {
            log("   Macro '\(newText)' already exists")
            return false
        }
        
        // Find and update the macro
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = MacroItem(id: macro.id, text: newText, content: newContent, isEnabled: macro.isEnabled)
            macros.sort { $0.text < $1.text }
            
            // A rename changes the sync identity (which is `text`): tombstone the old abbreviation
            // so peers drop it, and clear any stale tombstone on the new one to keep the local
            // store consistent. The renamed entry carries a fresh timestamp, so it beats a peer's
            // older tombstone for the new abbreviation on merge regardless.
            if newText != macro.text {
                SyncTombstoneStore.shared.record(category: .macros, id: macro.text)
                SyncTombstoneStore.shared.remove(category: .macros, id: newText)
            }
            
            // Save to plist first
            saveMacros()
            
            // Always post notification to ensure engine reloads macros
            log("   📢 Posting macrosDidChange notification...")
            NotificationCenter.default.post(name: .macrosDidChange, object: nil)
            
            return true
        }
        
        return false
    }
    
    func deleteMacro(_ macro: MacroItem) {
        log("deleteMacro called: '\(macro.text)'")
        macros.removeAll { $0.id == macro.id }

        // Save to plist first
        saveMacros()

        // Record tombstone so the deletion propagates via iCloud sync instead of being
        // overwritten by a peer that still has the entry. Keyed by `text` (the sync identity).
        SyncTombstoneStore.shared.record(category: .macros, id: macro.text)

        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    func toggleMacro(_ macro: MacroItem) {
        log("toggleMacro called: '\(macro.text)' → \(!macro.isEnabled)")
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index].isEnabled.toggle()
            
            saveMacros()
            
            log("   📢 Posting macrosDidChange notification...")
            NotificationCenter.default.post(name: .macrosDidChange, object: nil)
        }
    }
    
    func enableAllMacros() {
        log("enableAllMacros called")
        for index in macros.indices {
            macros[index].isEnabled = true
        }
        saveMacros()
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    func disableAllMacros() {
        log("disableAllMacros called")
        for index in macros.indices {
            macros[index].isEnabled = false
        }
        saveMacros()
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    func clearAll() {
        log("clearAll called")
        let deletedTexts = macros.map { $0.text }
        macros.removeAll()

        // Save to plist first
        saveMacros()

        // Tombstone every cleared macro (keyed by `text`) so the deletion propagates to peers.
        for text in deletedTexts {
            SyncTombstoneStore.shared.record(category: .macros, id: text)
        }

        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    // MARK: - Import/Export
    
    func importMacros() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.importMacros() }
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSOpenPanel()
        panel.title = "Import Macros"
        panel.message = String(localized: "Chọn file macro để import (định dạng: text=content mỗi dòng)")
        panel.allowedContentTypes = [.text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.level = .modalPanel
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            var importedCount = 0
            
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let equalIndex = trimmed.firstIndex(of: "=") else { continue }
                
                let text = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let macroContent = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                
                guard !text.isEmpty, !macroContent.isEmpty,
                      !macros.contains(where: { $0.text == text }) else { continue }
                
                // Decode escaped newlines (\n -> actual newline) for multi-line support
                let decodedContent = macroContent.replacingOccurrences(of: "\\n", with: "\n")
                macros.append(MacroItem(text: text, content: decodedContent))
                // Re-importing a previously-deleted abbreviation clears its tombstone, keeping the
                // local store consistent (a live macro must not carry a tombstone) — same as addMacro.
                SyncTombstoneStore.shared.remove(category: .macros, id: text)
                importedCount += 1
            }
            
            if importedCount > 0 {
                macros.sort { $0.text < $1.text }
                saveMacros()
                NotificationCenter.default.post(name: .macrosDidChange, object: nil)
                showAlert(title: String(localized: "Thành công"), message: String(localized: "Đã import \(importedCount) macro mới"))
            } else {
                showAlert(title: String(localized: "Thông báo"), message: String(localized: "Không có macro mới để import"))
            }
        } catch {
            showAlert(title: String(localized: "Lỗi"), message: String(localized: "Không thể đọc file: \(error.localizedDescription)"))
        }
    }
    
    func exportMacros() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.exportMacros() }
            return
        }
        
        guard !macros.isEmpty else {
            showAlert(title: String(localized: "Thông báo"), message: String(localized: "Không có macro nào để export"))
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSSavePanel()
        panel.title = "Export Macros"
        panel.message = String(localized: "Lưu file macro")
        panel.nameFieldStringValue = "macros.txt"
        panel.allowedContentTypes = [.text, .plainText]
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        do {
            var lines = ["# XKey Macros", "# Format: shortcut=replacement (use \\n for newlines)", ""]
            // Encode newlines in content as \n for multi-line support
            lines.append(contentsOf: macros.map { 
                let escapedContent = $0.content.replacingOccurrences(of: "\n", with: "\\n")
                return "\($0.text)=\(escapedContent)"
            })
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            showAlert(title: String(localized: "Thành công"), message: String(localized: "Đã export \(macros.count) macro"))
        } catch {
            showAlert(title: String(localized: "Lỗi"), message: String(localized: "Không thể lưu file: \(error.localizedDescription)"))
        }
    }

    // MARK: - macOS Text Replacements Interop

    /// Enabled macros only — macOS Text Replacements has no per-entry disabled state.
    var enabledMacros: [MacroItem] {
        macros.filter { $0.isEnabled }
    }

    /// Import shortcuts from the macOS system Text Replacements list.
    /// Read-only via the public `NSSpellChecker.userReplacementsDictionary` API
    /// (there is no public API to write back, so this is intentionally one-way).
    func importFromTextReplacements() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.importFromTextReplacements() }
            return
        }

        let replacements = NSSpellChecker.shared.userReplacementsDictionary
        guard !replacements.isEmpty else {
            showAlert(title: String(localized: "Thông báo"),
                      message: String(localized: "macOS Text Replacements đang trống"))
            return
        }

        // Keys are the typed shortcuts, values are the expansion phrases.
        var added = 0
        for (shortcut, phrase) in replacements {
            let text = shortcut.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !phrase.isEmpty,
                  !macros.contains(where: { $0.text == text }) else { continue }
            macros.append(MacroItem(text: text, content: phrase))
            // Keep the local store consistent: a re-imported abbreviation must not retain a
            // tombstone (mirrors addMacro / importMacros).
            SyncTombstoneStore.shared.remove(category: .macros, id: text)
            added += 1
        }

        if added > 0 {
            macros.sort { $0.text < $1.text }
            saveMacros()
            NotificationCenter.default.post(name: .macrosDidChange, object: nil)
            showAlert(title: String(localized: "Thành công"),
                      message: String(localized: "Đã nhập \(added) macro từ Text Replacements"))
        } else {
            showAlert(title: String(localized: "Thông báo"),
                      message: String(localized: "Không có mục mới để nhập"))
        }
    }

    /// Export enabled macros to a `.plist` file the user can drag into
    /// System Settings > Keyboard > Text Replacements. XKey never writes the
    /// system store directly — the user performs the supported drag-drop import.
    func exportToTextReplacementsPlist() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.exportToTextReplacementsPlist() }
            return
        }

        let items = enabledMacros
        guard !items.isEmpty else {
            showAlert(title: String(localized: "Thông báo"),
                      message: String(localized: "Không có macro nào đang bật để export"))
            return
        }
        guard let data = TextReplacementsExporter.plistData(for: items) else {
            showAlert(title: String(localized: "Lỗi"),
                      message: String(localized: "Không thể tạo file .plist"))
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "Export Text Replacements"
        panel.message = String(localized: "Lưu file .plist rồi kéo vào System Settings > Keyboard > Text Replacements")
        panel.nameFieldStringValue = "XKey Text Replacements.plist"
        panel.allowedContentTypes = [.propertyList]
        panel.canCreateDirectories = true
        panel.level = .modalPanel

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
            showAlert(title: String(localized: "Thành công"),
                      message: String(localized: "Đã export \(items.count) macro. File đang hiện trong Finder — kéo nó vào danh sách Text Replacements."))
            // Reveal AFTER the alert so Finder ends up frontmost, ready for the drag step
            // (NSAlert.runModal reactivates this app, so revealing earlier would be undone).
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showAlert(title: String(localized: "Lỗi"),
                      message: String(localized: "Không thể lưu file: \(error.localizedDescription)"))
        }
    }

    /// Open System Settings at the Keyboard pane. This is the deepest public
    /// deep-link available; the user then taps "Text Replacements…" to open the sheet.
    func openTextReplacementsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Helpers
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


/// Encodes macros into the macOS Text Replacements drag-drop `.plist` format:
/// a root array of `{ "phrase": ..., "shortcut": ... }` dictionaries — the exact
/// schema macOS produces when dragging entries out of System Settings (verified
/// on macOS 26.5.1). XKey only generates this file; the user performs the import.
enum TextReplacementsExporter {
    static func plistData(for macros: [MacroItem]) -> Data? {
        let items: [[String: String]] = macros.map {
            ["shortcut": $0.text, "phrase": $0.content]
        }
        return try? PropertyListSerialization.data(fromPropertyList: items, format: .xml, options: 0)
    }
}
