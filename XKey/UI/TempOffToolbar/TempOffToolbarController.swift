//
//  TempOffToolbarController.swift
//  XKey
//
//  Controller for the floating temp off toolbar near cursor
//  Similar to macOS Fn popup behavior
//

import Cocoa
import SwiftUI

class TempOffToolbarController {

    // MARK: - Singleton

    static let shared = TempOffToolbarController()

    // MARK: - Properties

    private var panel: NSPanel?
    
    /// Lazy-initialized ViewModel - only created when toolbar is first shown
    /// This saves memory when the TempOff toolbar feature is disabled
    private var _viewModel: TempOffToolbarViewModel?
    private var viewModel: TempOffToolbarViewModel {
        if _viewModel == nil {
            let vm = TempOffToolbarViewModel()
            setupCallbacks(for: vm)
            _viewModel = vm
        }
        return _viewModel!
    }
    
    private var hideTimer: Timer?
    private var modifierMonitor: Any?  // Monitor for Ctrl/Option key

    /// Auto-hide delay in seconds (0 = never auto-hide)
    var autoHideDelay: TimeInterval = 3.0

    /// Callback when temp off states change
    var onStateChange: ((Bool, Bool) -> Void)?  // (spellingTempOff, engineTempOff)
    
    /// Saved mouse position at the time show() is called
    /// This is used as fallback when cursor position cannot be obtained
    private var savedMousePosition: NSPoint?

    // MARK: - Initialization

    private init() {
        // Lazy initialization - ViewModel and callbacks will be setup when first accessed
    }

    private func setupCallbacks(for vm: TempOffToolbarViewModel) {
        vm.onSpellingToggle = { [weak self] isOff in
            self?.notifyStateChange()
        }

        vm.onEngineToggle = { [weak self] isOff in
            self?.notifyStateChange()
        }
    }

    private func notifyStateChange() {
        onStateChange?(viewModel.isSpellingTempOff, viewModel.isEngineTempOff)
    }

    // MARK: - Panel Management

    private func createPanel() -> NSPanel {
        let toolbarView = TempOffToolbarView(viewModel: viewModel)
        return FloatingToolbarPositioning.createPanel(rootView: toolbarView, initialWidth: 80)
    }

    // MARK: - Show/Hide

    /// Show the toolbar at the current cursor position
    /// Uses mouse position as fallback if caret position not available
    func show() {
        // Create panel if needed
        if panel == nil {
            panel = createPanel()
        }

        guard let panel = panel else { return }

        // Always show both buttons when toolbar is enabled
        viewModel.updateVisibility(showSpelling: true, showEngine: true)

        // Resize panel based on visible buttons
        resizePanelForContent()

        // Position near cursor
        positionNearCursor()

        // Show panel
        panel.orderFront(nil)

        // Setup auto-hide if configured
        setupAutoHide()

        // Setup modifier key monitor (Ctrl/Option toggle)
        setupModifierMonitor()
    }

    /// Hide the toolbar
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        removeModifierMonitor()
        panel?.orderOut(nil)
    }

    /// Toggle toolbar visibility
    func toggle() {
        // Reset modifier state to prevent Ctrl/Option toggle from firing
        // when user presses hotkey like ⌘⌥T
        resetModifierState()
        
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Check if toolbar is visible
    var isVisible: Bool {
        return panel?.isVisible == true
    }

    /// Update toolbar position (call when cursor moves)
    func updatePosition() {
        guard panel?.isVisible == true else { return }
        positionNearCursor()
    }

    // MARK: - Modifier Key Monitor (Ctrl/Option toggle)

    /// Track last modifier state to detect key press (not just holding)
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    
    /// Track if Ctrl was pressed alone (for toggle on release)
    private var ctrlPressedAlone = false
    /// Track if Option was pressed alone (for toggle on release)
    private var optionPressedAlone = false
    /// Track if any key was pressed while holding modifier (cancels toggle)
    private var keyPressedDuringModifier = false
    /// Key monitor to detect key presses during modifier hold
    private var keyDuringModifierMonitor: Any?
    /// Timestamp of last hotkey toggle (for cooldown)
    private var lastHotkeyToggleTime: Date?

    private func setupModifierMonitor() {
        // Remove existing monitor
        removeModifierMonitor()

        // Monitor for modifier key changes (Ctrl/Option) - use GLOBAL monitor
        // so it works even when other apps are focused
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
        }
        
        // Also monitor key presses to cancel modifier toggle if user is typing a hotkey combo
        keyDuringModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            // Any key press during modifier hold cancels the toggle
            self?.keyPressedDuringModifier = true
            self?.ctrlPressedAlone = false
            self?.optionPressedAlone = false
        }
    }

    private func removeModifierMonitor() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        if let monitor = keyDuringModifierMonitor {
            NSEvent.removeMonitor(monitor)
            keyDuringModifierMonitor = nil
        }
        resetModifierState()
    }
    
    /// Reset modifier tracking state (call when hotkey toggles toolbar)
    private func resetModifierState() {
        lastModifierFlags = []
        ctrlPressedAlone = false
        optionPressedAlone = false
        keyPressedDuringModifier = true  // Assume key was pressed to prevent toggle
        lastHotkeyToggleTime = Date()  // Set cooldown timestamp
    }

    private func handleModifierChange(_ event: NSEvent) {
        guard panel?.isVisible == true else { return }
        
        // Cooldown: Ignore modifier events for 500ms after hotkey toggle
        // This prevents race conditions where Option release happens after ⌘⌥T
        if let toggleTime = lastHotkeyToggleTime,
           Date().timeIntervalSince(toggleTime) < 0.5 {
            // Still in cooldown, just update state but don't trigger toggle
            lastModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Check for Ctrl key state changes
        let ctrlDown = flags.contains(.control)
        let ctrlWasDown = lastModifierFlags.contains(.control)
        
        // Check for Option key state changes
        let optionDown = flags.contains(.option)
        let optionWasDown = lastModifierFlags.contains(.option)
        
        // Check if other modifiers are present (indicates hotkey combo, not single modifier)
        let hasOtherModifiers = flags.contains(.command) || flags.contains(.shift)
        
        // --- CTRL KEY ---
        // Pressed: Mark as pressed alone if no other modifiers
        if ctrlDown && !ctrlWasDown {
            if !hasOtherModifiers && !optionDown {
                ctrlPressedAlone = true
                keyPressedDuringModifier = false
            } else {
                ctrlPressedAlone = false
            }
        }
        // Released: Toggle if was pressed alone and no key was pressed during hold
        if !ctrlDown && ctrlWasDown {
            if ctrlPressedAlone && !keyPressedDuringModifier && !hasOtherModifiers {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.viewModel.toggleSpelling()
                    
                }
            }
            ctrlPressedAlone = false
        }
        // Cancel if other modifiers are added while holding
        if ctrlDown && hasOtherModifiers {
            ctrlPressedAlone = false
        }
        
        // --- OPTION KEY ---
        // Pressed: Mark as pressed alone if no other modifiers
        if optionDown && !optionWasDown {
            if !hasOtherModifiers && !ctrlDown {
                optionPressedAlone = true
                keyPressedDuringModifier = false
            } else {
                optionPressedAlone = false
            }
        }
        // Released: Toggle if was pressed alone and no key was pressed during hold
        if !optionDown && optionWasDown {
            if optionPressedAlone && !keyPressedDuringModifier && !hasOtherModifiers {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.viewModel.toggleEngine()
                    
                }
            }
            optionPressedAlone = false
        }
        // Cancel if other modifiers are added while holding
        if optionDown && hasOtherModifiers {
            optionPressedAlone = false
        }

        // Update last state
        lastModifierFlags = flags
    }

    // MARK: - Positioning

    /// Position toolbar near cursor/caret
    /// Uses mouse position as fallback if caret position not available
    private func positionNearCursor() {
        guard let panel = panel else { return }
        FloatingToolbarPositioning.positionNearCursor(panel, cursorGap: 4, mouseGap: 8)
    }

    // MARK: - Auto-hide

    private func setupAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard autoHideDelay > 0 else { return }

        hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    // MARK: - State Management

    /// Update temp off states from external source
    func updateStates(spellingTempOff: Bool, engineTempOff: Bool) {
        viewModel.updateStates(spellingTempOff: spellingTempOff, engineTempOff: engineTempOff)
    }

    /// Get current spelling temp off state
    var isSpellingTempOff: Bool {
        return viewModel.isSpellingTempOff
    }

    /// Get current engine temp off state
    var isEngineTempOff: Bool {
        return viewModel.isEngineTempOff
    }

    // MARK: - Resize

    private func resizePanelForContent() {
        guard let panel = panel,
              let hostingController = panel.contentViewController as? NSHostingController<TempOffToolbarView> else {
            return
        }

        // Update root view to trigger size recalculation
        hostingController.rootView = TempOffToolbarView(viewModel: viewModel)

        // Get fitting size
        let fittingSize = hostingController.view.fittingSize
        panel.setContentSize(fittingSize)
    }
}
