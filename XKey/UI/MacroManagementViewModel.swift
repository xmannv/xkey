//
//  MacroManagementViewModel.swift
//  XKey
//
//  ViewModel for macro management
//

import Foundation
import AppKit

// Notification names
extension Notification.Name {
    static let macrosDidChange = Notification.Name("XKey.macrosDidChange")
}

struct MacroItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let content: String
    
    init(id: UUID = UUID(), text: String, content: String) {
        self.id = id
        self.text = text
        self.content = content
    }
}

class MacroManagementViewModel: ObservableObject {
    @Published var macros: [MacroItem] = []
    
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
            
            // Sync to MacroManager (if available)
            if let manager = getMacroManager() {
                for macro in macros {
                    _ = manager.addMacro(text: macro.text, content: macro.content)
                }
            }
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
            macros[index] = MacroItem(id: macro.id, text: newText, content: newContent)
            macros.sort { $0.text < $1.text }
            
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
        
        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    func clearAll() {
        log("clearAll called")
        macros.removeAll()
        
        // Save to plist first
        saveMacros()
        
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
        panel.message = "Chọn file macro để import (định dạng: text=content mỗi dòng)"
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
                importedCount += 1
            }
            
            if importedCount > 0 {
                macros.sort { $0.text < $1.text }
                saveMacros()
                NotificationCenter.default.post(name: .macrosDidChange, object: nil)
                showAlert(title: "Thành công", message: "Đã import \(importedCount) macro mới")
            } else {
                showAlert(title: "Thông báo", message: "Không có macro mới để import")
            }
        } catch {
            showAlert(title: "Lỗi", message: "Không thể đọc file: \(error.localizedDescription)")
        }
    }
    
    func exportMacros() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.exportMacros() }
            return
        }
        
        guard !macros.isEmpty else {
            showAlert(title: "Thông báo", message: "Không có macro nào để export")
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        let panel = NSSavePanel()
        panel.title = "Export Macros"
        panel.message = "Lưu file macro"
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
            showAlert(title: "Thành công", message: "Đã export \(macros.count) macro")
        } catch {
            showAlert(title: "Lỗi", message: "Không thể lưu file: \(error.localizedDescription)")
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
