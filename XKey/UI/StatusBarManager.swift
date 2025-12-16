//
//  StatusBarManager.swift
//  XKey
//
//  Manager for SwiftUI Status Bar
//

import SwiftUI
import Cocoa
import Combine

class StatusBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    let viewModel: StatusBarViewModel
    #if DEBUG
    weak var debugWindowController: DebugWindowController?
    #endif
    
    init(keyboardHandler: KeyboardEventHandler?, eventTapManager: EventTapManager?) {
        self.viewModel = StatusBarViewModel(
            keyboardHandler: keyboardHandler,
            eventTapManager: eventTapManager
        )
    }
    
    private func log(_ message: String) {
        #if DEBUG
        debugWindowController?.logEvent(message)
        #endif
    }
    
    func setupStatusBar() {
        // Connect viewModel's debug callback to our debugWindowController
        #if DEBUG
        viewModel.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        #endif
        
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            log("❌ Failed to create status bar button")
            return
        }
        
        // Set initial icon
        updateStatusIcon()
        
        // Create traditional NSMenu instead of popover
        let menu = createMenu()
        statusItem?.menu = menu
        
        // Observe changes to update icon and menu
        viewModel.$isVietnameseEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$currentInputMethod
            .receive(on: DispatchQueue.main)
            .sink { [weak self] method in
                self?.log("📋 currentInputMethod changed to \(method.displayName)")
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$currentCodeTable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] table in
                self?.log("📋 currentCodeTable changed to \(table.displayName)")
                self?.updateMenu()
            }
            .store(in: &cancellables)
        
        // Observe hotkey changes to rebuild menu
        viewModel.$hotkeyKeyEquivalent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.log("🔑 Hotkey changed, rebuilding menu")
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$hotkeyModifiers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.log("🔑 Hotkey modifiers changed, rebuilding menu")
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
        
        log("✅ Status bar setup complete")
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Toggle Vietnamese
        let toggleItem = menu.addItem(
            withTitle: viewModel.isVietnameseEnabled ? "Tắt Tiếng Việt" : "Bật Tiếng Việt",
            action: #selector(toggleVietnamese),
            keyEquivalent: String(viewModel.hotkeyKeyEquivalent.character)
        )
        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = convertToNSEventModifiers(viewModel.hotkeyModifiers)
        toggleItem.state = viewModel.isVietnameseEnabled ? .on : .off
        toggleItem.tag = 1
        
        menu.addItem(.separator())
        
        // Input Method submenu
        let inputMethodMenu = NSMenu()
        for method in InputMethod.allCases {
            let item = inputMethodMenu.addItem(
                withTitle: method.displayName,
                action: #selector(selectInputMethod(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = method.rawValue
            item.state = (method == viewModel.currentInputMethod) ? .on : .off
        }
        
        let inputMethodItem = menu.addItem(
            withTitle: "Kiểu gõ",
            action: nil,
            keyEquivalent: ""
        )
        inputMethodItem.submenu = inputMethodMenu
        
        // Code Table submenu
        let codeTableMenu = NSMenu()
        for table in CodeTable.allCases {
            let item = codeTableMenu.addItem(
                withTitle: table.displayName,
                action: #selector(selectCodeTable(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = table.rawValue
            item.state = (table == viewModel.currentCodeTable) ? .on : .off
        }
        
        let codeTableItem = menu.addItem(
            withTitle: "Bảng mã",
            action: nil,
            keyEquivalent: ""
        )
        codeTableItem.submenu = codeTableMenu
        
        menu.addItem(.separator())
        
        // Advanced Tools
        let macroItem = menu.addItem(
            withTitle: "Quản lý Macro...",
            action: #selector(openMacroManagement),
            keyEquivalent: ""
        )
        macroItem.target = self
        
        let convertItem = menu.addItem(
            withTitle: "Công cụ chuyển đổi...",
            action: #selector(openConvertTool),
            keyEquivalent: ""
        )
        convertItem.target = self
        
        menu.addItem(.separator())
        
        // Preferences
        let prefsItem = menu.addItem(
            withTitle: "Bảng điều khiển...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        
        #if DEBUG
        menu.addItem(.separator())
        
        // Debug Window
        let debugItem = menu.addItem(
            withTitle: "Mở Debug Window",
            action: #selector(openDebugWindow),
            keyEquivalent: "d"
        )
        debugItem.target = self
        #endif
        
        menu.addItem(.separator())
        
        // Quit
        let quitItem = menu.addItem(
            withTitle: "Thoát XKey",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        
        return menu
    }
    
    private func updateMenu() {
        guard let menu = statusItem?.menu else {
            log("⚠️ updateMenu: menu is nil!")
            return
        }
        
        log("📋 updateMenu: currentInputMethod=\(viewModel.currentInputMethod.displayName)")
        
        // Update toggle item
        if let toggleItem = menu.item(withTag: 1) {
            toggleItem.title = viewModel.isVietnameseEnabled ? "Tắt Tiếng Việt" : "Bật Tiếng Việt"
            toggleItem.state = viewModel.isVietnameseEnabled ? .on : .off
        }
        
        // Update input method submenu
        if let inputMethodItem = menu.item(withTitle: "Kiểu gõ"),
           let submenu = inputMethodItem.submenu {
            for method in InputMethod.allCases {
                if let item = submenu.item(withTag: method.rawValue) {
                    let shouldBeOn = (method == viewModel.currentInputMethod)
                    item.state = shouldBeOn ? .on : .off
                }
            }
        }
        
        // Update code table submenu
        if let codeTableItem = menu.item(withTitle: "Bảng mã"),
           let submenu = codeTableItem.submenu {
            for table in CodeTable.allCases {
                if let item = submenu.item(withTag: table.rawValue) {
                    item.state = (table == viewModel.currentCodeTable) ? .on : .off
                }
            }
        }
    }
    
    @objc private func toggleVietnamese() {
        viewModel.toggleVietnamese()
    }
    
    @objc private func selectInputMethod(_ sender: NSMenuItem) {
        log("📋 selectInputMethod: tag=\(sender.tag), title=\(sender.title)")
        
        guard let method = InputMethod(rawValue: sender.tag) else {
            log("⚠️ selectInputMethod: Invalid tag \(sender.tag)")
            return
        }
        
        viewModel.selectInputMethod(method)
        
        // Update menu item states immediately (synchronously)
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.tag == method.rawValue) ? .on : .off
            }
            log("✅ Updated submenu items directly")
        }
    }
    
    @objc private func selectCodeTable(_ sender: NSMenuItem) {
        guard let table = CodeTable(rawValue: sender.tag) else { return }
        
        log("📋 selectCodeTable: tag=\(sender.tag), title=\(sender.title)")
        
        viewModel.selectCodeTable(table)
        
        // Update menu item states immediately (synchronously)
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item.tag == table.rawValue) ? .on : .off
            }
        }
    }
    
    @objc private func openPreferences() {
        viewModel.openPreferences()
    }
    
    @objc private func openMacroManagement() {
        viewModel.openMacroManagement()
    }
    
    @objc private func openConvertTool() {
        viewModel.openConvertTool()
    }
    
    @objc private func quit() {
        viewModel.quit()
    }
    
    #if DEBUG
    @objc private func openDebugWindow() {
        debugWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
    
    private func convertToNSEventModifiers(_ modifiers: EventModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }
    
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        
        let iconText = viewModel.isVietnameseEnabled ? "X" : "E"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            // Vẽ viền trắng bao quanh
            let borderRect = NSRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 2.5, yRadius: 2.5)
            NSColor.white.setStroke()
            borderPath.lineWidth = 1.0
            borderPath.stroke()
            
            // Vẽ chữ ở giữa
            let textSize = (iconText as NSString).size(withAttributes: attributes)
            let textRect = NSRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (iconText as NSString).draw(in: textRect, withAttributes: attributes)
            return true
        }
        
        image.isTemplate = true
        button.image = image
    }
    
    func updateHotkeyDisplay(_ hotkey: Hotkey) {
        viewModel.updateHotkeyDisplay(hotkey)
    }
    
    private func rebuildMenu() {
        guard statusItem != nil else { return }
        
        log("🔄 Rebuilding menu with new hotkey")
        
        // Create new menu with updated hotkey
        let menu = createMenu()
        statusItem?.menu = menu
        
        log("✅ Menu rebuilt successfully")
    }
    
    private var cancellables = Set<AnyCancellable>()
}
