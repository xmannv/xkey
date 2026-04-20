//
//  StatusBarManager.swift
//  XKey
//
//  Manager for Status Bar with Glass Design Popover
//

import SwiftUI
import Cocoa
import Combine

class StatusBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    let viewModel: StatusBarViewModel
    private var menuBarIconStyle: MenuBarIconStyle = .x
    weak var debugWindowController: DebugWindowController?
    var onCheckForUpdates: (() -> Void)?
    
    init(keyboardHandler: KeyboardEventHandler?, eventTapManager: EventTapManager?) {
        self.viewModel = StatusBarViewModel(
            keyboardHandler: keyboardHandler,
            eventTapManager: eventTapManager
        )
        // Load icon style from preferences
        self.menuBarIconStyle = SharedSettings.shared.loadPreferences().menuBarIconStyle
    }
    
    private func log(_ message: String) {
        debugWindowController?.logEvent(message)
    }
    
    func setupStatusBar() {
        // Connect viewModel's debug callback to our debugWindowController
        viewModel.debugLogCallback = { [weak self] message in
            self?.debugWindowController?.logEvent(message)
        }
        
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            log("Failed to create status bar button")
            return
        }
        
        // Set initial icon
        updateStatusIcon()
        
        // Handle click to toggle popover (no NSMenu)
        button.action = #selector(togglePopover)
        button.target = self
        
        // Create popover with glass design
        setupPopover()
        
        // Observe changes to update icon
        viewModel.$isVietnameseEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
        
        viewModel.$currentInputMethod
            .receive(on: DispatchQueue.main)
            .sink { [weak self] method in
                self?.log("📋 currentInputMethod changed to \(method.displayName)")
            }
            .store(in: &cancellables)
        
        viewModel.$currentCodeTable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] table in
                self?.log("📋 currentCodeTable changed to \(table.displayName)")
            }
            .store(in: &cancellables)

        viewModel.$debugModeEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.log("🐛 Debug mode changed to \(enabled)")
            }
            .store(in: &cancellables)

        log("Status bar setup complete (glass popover)")
    }
    
    // MARK: - Popover Setup
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient  // Close when clicking outside
        popover.animates = true
        
        // Create SwiftUI content view
        let contentView = StatusBarPopoverView(
            viewModel: viewModel,
            onCheckForUpdates: { [weak self] in
                self?.onCheckForUpdates?()
            },
            onDismiss: { [weak self] in
                self?.closePopover()
            }
        )
        
        // Use NSHostingController to host SwiftUI in the popover
        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
        
        // Apply glass/vibrancy effect to the popover's content view
        // This creates the frosted glass appearance like macOS system menus
        popover.contentViewController?.view.wantsLayer = true
        
        self.popover = popover
    }
    
    // MARK: - Popover Toggle
    
    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            // Recreate content view to ensure fresh state
            let contentView = StatusBarPopoverView(
                viewModel: viewModel,
                onCheckForUpdates: { [weak self] in
                    self?.onCheckForUpdates?()
                },
                onDismiss: { [weak self] in
                    self?.closePopover()
                }
            )
            let hostingController = NSHostingController(rootView: contentView)
            popover.contentViewController = hostingController
            
            // Activate app so popover receives keyboard focus
            NSApp.activate(ignoringOtherApps: true)
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // Ensure popover window becomes key window for focus
            popover.contentViewController?.view.window?.makeKey()
            log("Popover shown")
            
            // Start monitoring for clicks outside popover
            startEventMonitor()
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        stopEventMonitor()
        log("Popover closed")
    }
    
    // MARK: - Event Monitor (click outside to close)
    
    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // MARK: - Status Icon
    
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        
        switch menuBarIconStyle {
        case .icon:
            let iconText = viewModel.isVietnameseEnabled ? "🇻🇳" : "🇬🇧"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16),
            ]

            button.image = nil
            button.imagePosition = .noImage
            button.title = ""
            button.attributedTitle = NSAttributedString(string: iconText, attributes: attributes)
            return

        case .x, .v:
            break
        }

        let iconText = menuBarIconStyle == .x
            ? (viewModel.isVietnameseEnabled ? "X" : "E")
            : (viewModel.isVietnameseEnabled ? "V" : "E")
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw border around the icon
            let borderRect = NSRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 2.5, yRadius: 2.5)
            NSColor.white.setStroke()
            borderPath.lineWidth = 1.0
            borderPath.stroke()
            
            // Draw text centered
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
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = image
    }
    
    func updateHotkeyDisplay(_ hotkey: Hotkey) {
        viewModel.updateHotkeyDisplay(hotkey)
    }
    
    func updateMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style
        updateStatusIcon()
        log("🎨 Menu bar icon style updated to: \(style.rawValue)")
    }
    
    private var cancellables = Set<AnyCancellable>()
}
