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
    
    private let userDefaultsKey = "XKey.Macros"
    
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
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
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
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    // MARK: - CRUD Operations
    
    func addMacro(text: String, content: String) -> Bool {
        log("📝 addMacro called: '\(text)' → '\(content)'")
        
        // Check if already exists
        if macros.contains(where: { $0.text == text }) {
            log("   ❌ Macro '\(text)' already exists")
            return false
        }
        
        let macro = MacroItem(text: text, content: content)
        macros.append(macro)
        macros.sort { $0.text < $1.text }
        
        // Save to UserDefaults first
        saveMacros()
        
        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
        
        return true
    }
    
    func deleteMacro(_ macro: MacroItem) {
        log("🗑️ deleteMacro called: '\(macro.text)'")
        macros.removeAll { $0.id == macro.id }
        
        // Save to UserDefaults first
        saveMacros()
        
        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    func clearAll() {
        log("🗑️ clearAll called")
        macros.removeAll()
        
        // Save to UserDefaults first
        saveMacros()
        
        // Always post notification to ensure engine reloads macros
        log("   📢 Posting macrosDidChange notification...")
        NotificationCenter.default.post(name: .macrosDidChange, object: nil)
    }
    
    // MARK: - Import/Export
    
    func importMacros() {
        guard let manager = getMacroManager() else {
            showAlert(title: "Lỗi", message: "Không thể kết nối với MacroManager")
            return
        }
        
        let panel = NSOpenPanel()
        panel.title = "Import Macros"
        panel.message = "Chọn file macro để import"
        panel.allowedContentTypes = [.text, .plainText]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            if manager.loadFromFile(path: url.path, append: true) {
                // Reload from manager
                let allMacros = manager.getAllMacros()
                macros.removeAll()
                for (_, text, content) in allMacros {
                    let macro = MacroItem(text: text, content: content)
                    if !macros.contains(where: { $0.text == macro.text }) {
                        macros.append(macro)
                    }
                }
                macros.sort { $0.text < $1.text }
                saveMacros()
                
                showAlert(title: "Thành công", message: "Đã import \(allMacros.count) macro")
            } else {
                showAlert(title: "Lỗi", message: "Không thể đọc file macro")
            }
        }
    }
    
    func exportMacros() {
        guard let manager = getMacroManager() else {
            showAlert(title: "Lỗi", message: "Không thể kết nối với MacroManager")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = "Export Macros"
        panel.message = "Lưu file macro"
        panel.nameFieldStringValue = "macros.txt"
        panel.allowedContentTypes = [.text, .plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            if manager.saveToFile(path: url.path) {
                showAlert(title: "Thành công", message: "Đã export \(macros.count) macro")
            } else {
                showAlert(title: "Lỗi", message: "Không thể lưu file macro")
            }
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
