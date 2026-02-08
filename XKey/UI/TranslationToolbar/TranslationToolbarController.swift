//
//  TranslationToolbarController.swift
//  XKey
//
//  Controller for the floating translation toolbar near cursor
//  Allows quick language selection without opening settings
//

import Cocoa
import SwiftUI

class TranslationToolbarController {

    // MARK: - Singleton

    static let shared = TranslationToolbarController()

    // MARK: - Properties

    private var panel: NSPanel?
    
    /// Lazy-initialized ViewModel - only created when toolbar is first shown
    /// This defers memory allocation and TranslationLanguage.presets loading
    /// until the translation toolbar feature is actually used
    private var _viewModel: TranslationToolbarViewModel?
    private var viewModel: TranslationToolbarViewModel {
        if _viewModel == nil {
            let vm = TranslationToolbarViewModel()
            setupCallbacks(for: vm)
            _viewModel = vm
        }
        return _viewModel!
    }
    
    private var hideTimer: Timer?

    /// Auto-hide delay in seconds (0 = never auto-hide)
    var autoHideDelay: TimeInterval = 5.0

    /// Callback when translation is requested
    var onTranslateRequested: (() -> Void)?
    
    /// Saved mouse position at the time show() is called
    private var savedMousePosition: NSPoint?
    
    /// Time when toolbar was last shown (to prevent immediate hide)
    private var lastShowTime: Date?
    
    /// Minimum time toolbar should stay visible before allowing hide (in seconds)
    private let minimumDisplayDuration: TimeInterval = 0.5

    // MARK: - Initialization

    private init() {
        // Lazy initialization - ViewModel and callbacks will be setup when first accessed
    }

    private func setupCallbacks(for vm: TranslationToolbarViewModel) {
        vm.onTranslateRequested = { [weak self] in
            self?.onTranslateRequested?()
            // Hide toolbar after translation request
            self?.hide()
        }
        
        vm.onSourceLanguageChange = { [weak self] _ in
            // Restart auto-hide timer when language changes
            self?.restartAutoHideTimer()
        }
        
        vm.onTargetLanguageChange = { [weak self] _ in
            self?.restartAutoHideTimer()
        }
        
        vm.onSwapLanguages = { [weak self] in
            self?.restartAutoHideTimer()
        }
    }

    // MARK: - Panel Management

    private func createPanel() -> NSPanel {
        let toolbarView = TranslationToolbarView(viewModel: viewModel)
        return FloatingToolbarPositioning.createPanel(rootView: toolbarView, initialWidth: 200)
    }

    // MARK: - Show/Hide

    /// Show the toolbar at the current cursor position
    /// Only shows if caret position can be determined, or uses mouse position as fallback
    func show() {
        // Reload preferences in case languages changed externally
        viewModel.loadFromPreferences()
        
        // Create panel if needed
        if panel == nil {
            panel = createPanel()
        }

        guard let panel = panel else { return }

        // Resize panel based on content
        resizePanelForContent()

        // Position near cursor
        positionNearCursor()

        // Show panel
        panel.orderFront(nil)
        
        // Record show time
        lastShowTime = Date()

        // Setup auto-hide if configured
        setupAutoHide()
    }

    /// Hide the toolbar
    func hide() {
        // Don't hide if shown too recently (prevents flickering from rapid focus changes)
        if let showTime = lastShowTime {
            let elapsed = Date().timeIntervalSince(showTime)
            if elapsed < minimumDisplayDuration {
                return
            }
        }
        
        hideTimer?.invalidate()
        hideTimer = nil
        viewModel.closePickers()
        panel?.orderOut(nil)
        lastShowTime = nil
    }
    
    /// Force hide the toolbar (ignores minimum display duration)
    func forceHide() {
        hideTimer?.invalidate()
        hideTimer = nil
        viewModel.closePickers()
        panel?.orderOut(nil)
        lastShowTime = nil
    }

    /// Toggle toolbar visibility
    func toggle() {
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
    
    /// Check if user is currently interacting with toolbar (picker open)
    var isInteracting: Bool {
        return viewModel.showSourcePicker || viewModel.showTargetPicker
    }
    
    /// Check if the given AX element belongs to this toolbar's window
    func isFocusInsideToolbar(_ element: AXUIElement) -> Bool {
        guard let panel = panel, panel.isVisible else { return false }
        
        // Get the window of the focused element
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
              windowRef != nil else {
            return false
        }
        
        // Get window title or other attribute to compare
        // For now, we'll just return true if toolbar is visible and interacting
        // This is a simpler approach that works well in practice
        return isInteracting
    }

    /// Update toolbar position (call when cursor moves)
    func updatePosition() {
        guard panel?.isVisible == true else { return }
        positionNearCursor()
    }

    // MARK: - Positioning

    /// Position toolbar near cursor/caret
    /// Uses mouse position as fallback if caret position not available
    private func positionNearCursor() {
        guard let panel = panel else { return }
        FloatingToolbarPositioning.positionNearCursor(panel, cursorGap: 8, mouseGap: 12)
    }

    // MARK: - Auto-hide

    private func setupAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard autoHideDelay > 0 else { return }

        hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Don't auto-hide if user is interacting with picker
            if self.isInteracting {
                // Restart timer to check again later
                self.restartAutoHideTimer() 
                return
            }
            
            self.hide()
        }
    }
    
    private func restartAutoHideTimer() {
        setupAutoHide()
    }
    
    /// Cancel auto-hide timer (call when user starts interacting)
    func cancelAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Resize

    private func resizePanelForContent() {
        guard let panel = panel,
              let hostingController = panel.contentViewController as? NSHostingController<TranslationToolbarView> else {
            return
        }

        // Update root view to trigger size recalculation
        hostingController.rootView = TranslationToolbarView(viewModel: viewModel)

        // Get fitting size
        let fittingSize = hostingController.view.fittingSize
        panel.setContentSize(fittingSize)
    }
    
    // MARK: - State Management
    
    /// Update translating state
    func setTranslating(_ isTranslating: Bool) {
        viewModel.isTranslating = isTranslating
    }
}
