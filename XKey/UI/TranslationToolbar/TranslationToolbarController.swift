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
        let hostingController = NSHostingController(rootView: toolbarView)

        // Create panel with special styling for floating toolbar
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .popUpMenu  // Above most windows
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // We use SwiftUI shadow
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Size to fit content
        if let contentSize = hostingController.view.fittingSize as NSSize? {
            panel.setContentSize(contentSize)
        }

        return panel
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
              let axWindow = windowRef else {
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

        // Try to get cursor position from text field via Accessibility API
        if let cursorRect = getCursorRectFromAccessibility() {
            positionPanel(panel, relativeTo: cursorRect, isCursorRect: true)
        } else {
            // Fallback: position near mouse position
            let mouseLocation = NSEvent.mouseLocation
            let mouseRect = NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 20)
            positionPanel(panel, relativeTo: mouseRect, isCursorRect: false)
        }
    }

    private func positionPanel(_ panel: NSPanel, relativeTo targetRect: NSRect, isCursorRect: Bool) {
        let panelSize = panel.frame.size

        // Center horizontally on target cursor position
        var x = targetRect.origin.x - panelSize.width / 2 + targetRect.width / 2

        // Gap between toolbar and cursor
        let gap: CGFloat = isCursorRect ? 8 : 12

        // Position ABOVE the target (like macOS Fn popup)
        var y = targetRect.origin.y + targetRect.height + gap

        // Find the screen that contains the target position
        let targetPoint = NSPoint(x: targetRect.midX, y: targetRect.midY)
        var containingScreen: NSScreen? = nil

        for screen in NSScreen.screens {
            if screen.frame.contains(targetPoint) {
                containingScreen = screen
                break
            }
        }

        // If no screen contains the point, find the nearest screen
        if containingScreen == nil {
            containingScreen = NSScreen.screens.min(by: { screen1, screen2 in
                let dist1 = distanceToScreen(point: targetPoint, screen: screen1)
                let dist2 = distanceToScreen(point: targetPoint, screen: screen2)
                return dist1 < dist2
            })
        }

        if let screen = containingScreen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Adjust horizontal position to stay within screen bounds
            x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - panelSize.width - 10))

            // If toolbar would go above screen top, position below target instead
            if y + panelSize.height > screenFrame.maxY {
                y = targetRect.origin.y - panelSize.height - gap
            }

            // Ensure not below screen bottom
            if y < screenFrame.minY {
                y = screenFrame.minY + 10
            }
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func distanceToScreen(point: NSPoint, screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        let clampedX = max(frame.minX, min(point.x, frame.maxX))
        let clampedY = max(frame.minY, min(point.y, frame.maxY))
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return sqrt(dx * dx + dy * dy)
    }

    /// Get cursor rectangle from focused text element via Accessibility API
    private func getCursorRectFromAccessibility() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement

        // Try to get cursor bounds via AXBoundsForRange
        if let cursorRect = getCursorBoundsViaRange(axElement) {
            return cursorRect
        }

        return nil
    }

    /// Get cursor bounds using AXBoundsForRangeParameterizedAttribute
    private func getCursorBoundsViaRange(_ element: AXUIElement) -> NSRect? {
        // Get selected text range (cursor position)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return nil
        }

        // Get bounds for the cursor position
        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        )

        if boundsResult != .success {
            return nil
        }

        guard let boundsValue = boundsRef else {
            return nil
        }

        // Extract CGRect from AXValue
        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        // Validate bounds
        if axBounds.width == 0 && axBounds.height == 0 {
            return nil
        }

        if axBounds.height == 0 {
            axBounds.size.height = 18
        }

        return convertAXToCocoaCoordinates(axBounds)
    }

    /// Convert AX coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
    private func convertAXToCocoaCoordinates(_ axRect: CGRect) -> NSRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - axRect.origin.y - axRect.height
        let cocoaX = axRect.origin.x

        return NSRect(
            x: cocoaX,
            y: cocoaY,
            width: axRect.width,
            height: axRect.height
        )
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
