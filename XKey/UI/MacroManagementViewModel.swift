//
//  MacroManagementViewModel.swift
//  XKey
//
//  ViewModel for macro management
//

import Foundation
import AppKit

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
    
    private var macroManager: MacroManager?
    private let userDefaultsKey = "XKey.Macros"
    
    // Get macro manager from app delegate
    private func getMacroManager() -> MacroManager {
        if macroManager == nil {
            // Try to get from AppDelegate
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
               let manager = appDelegate.getMacroManager() {
                macroManager = manager
            } else {
                // Fallback: create new instance
                macroManager = MacroManager()
            }
        }
        return macroManager!
    }
    
    // MARK: - Load/Save
    
    func loadMacros() {
        let manager = getMacroManager()
        
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([MacroItem].self, from: data) {
            macros = decoded
            
            // Sync to MacroManager
            for macro in macros {
                _ = manager.addMacro(text: macro.text, content: macro.content)
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
        let manager = getMacroManager()
        
        // Check if already exists
        if macros.contains(where: { $0.text == text }) {
            return false
        }
        
        let macro = MacroItem(text: text, content: content)
        macros.append(macro)
        macros.sort { $0.text < $1.text }
        
        // Add to manager
        _ = manager.addMacro(text: text, content: content)
        
        saveMacros()
        return true
    }
    
    func deleteMacro(_ macro: MacroItem) {
        let manager = getMacroManager()
        
        macros.removeAll { $0.id == macro.id }
        
        // Delete from manager
        _ = manager.deleteMacro(text: macro.text)
        
        saveMacros()
    }
    
    func clearAll() {
        let manager = getMacroManager()
        
        macros.removeAll()
        manager.clearAll()
        saveMacros()
    }
    
    // MARK: - Import/Export
    
    func importMacros() {
        let manager = getMacroManager()
        
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
        let manager = getMacroManager()
        
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
