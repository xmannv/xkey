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
        let hostingController = NSHostingController(rootView: toolbarView)

        // Create panel with special styling for floating toolbar
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 44),
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

        // Gap between toolbar and cursor (similar to macOS Fn popup)
        let gap: CGFloat = isCursorRect ? 4 : 8

        // Position ABOVE the target (like macOS Fn popup)
        // In Cocoa coords: higher Y = above
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
    /// Returns coordinates in Cocoa screen space (origin at bottom-left)
    private func getCursorRectFromAccessibility() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement

        // Try Method 1: Get cursor position via AXBoundsForRange (works in most apps)
        if let cursorRect = getCursorBoundsViaRange(axElement) {
            return cursorRect
        }

        // Method 2: Try AXInsertionPointLineNumber combined with element bounds
        // This is useful for text editors that don't support AXBoundsForRange
        if let insertionRect = getInsertionPointBounds(axElement) {
            return insertionRect
        }

        // Fallback: Return nil to use mouse position
        return nil
    }

    /// Try to get insertion point bounds by combining line number with element bounds
    private func getInsertionPointBounds(_ element: AXUIElement) -> NSRect? {
        // Get visible character range to estimate line height
        var visibleRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeRef) == .success else {
            return nil
        }

        // Try to get bounds for visible range (gives us element content area)
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            visibleRangeRef!,
            &boundsRef
        ) == .success,
              let boundsValue = boundsRef else {
            return nil
        }

        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        // Validate bounds - some apps return invalid bounds (width=0, height=0)
        if axBounds.width == 0 && axBounds.height == 0 {
            return nil
        }

        return convertAXToCocoaCoordinates(axBounds)
    }


    /// Get cursor bounds using AXBoundsForRangeParameterizedAttribute
    private func getCursorBoundsViaRange(_ element: AXUIElement) -> NSRect? {
        // Get selected text range (cursor position)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return nil
        }
        
        // Extract CFRange to check position
        var selectedRange = CFRange(location: 0, length: 0)
        _ = AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange)

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

        // Validate bounds - check if both width AND height are 0
        // This indicates invalid/missing cursor position data
        if axBounds.width == 0 && axBounds.height == 0 {
            return nil
        }
        
        // If height is 0 but we have valid position, assume default line height
        if axBounds.height == 0 {
            axBounds.size.height = 18 // Default line height
        }

        let result = convertAXToCocoaCoordinates(axBounds)
        
        guard let convertedRect = result else {
            return nil
        }

        // Validate: Check if the converted rect falls within any screen
        // This catches coordinate conversion errors on multi-monitor setups
        let centerPoint = NSPoint(x: convertedRect.midX, y: convertedRect.midY)
        var isOnAnyScreen = false
        for screen in NSScreen.screens {
            // Allow some tolerance for cursors at screen edges
            let expandedFrame = screen.frame.insetBy(dx: -100, dy: -100)
            if expandedFrame.contains(centerPoint) {
                isOnAnyScreen = true
                break
            }
        }
        
        if !isOnAnyScreen {
            return nil
        }

        return convertedRect
    }


    /// Convert AX coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
    private func convertAXToCocoaCoordinates(_ axRect: CGRect) -> NSRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        // Flip Y axis using primary screen height as pivot
        
        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - axRect.origin.y - axRect.height
        
        // X coordinate stays the same (both systems use same X axis)
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
