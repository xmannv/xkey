//
//  FloatingToolbarPositioning.swift
//  XKey
//
//  Shared positioning logic for floating toolbar panels (TempOff, Translation)
//  Handles cursor detection, AX coordinate conversion, and screen-aware placement
//

import Cocoa
import SwiftUI

/// Provides cursor-aware positioning for floating NSPanel toolbars
/// Handles AX-based cursor detection, coordinate conversion, and multi-monitor placement
class FloatingToolbarPositioning {
    
    // MARK: - Panel Factory
    
    /// Create a standard floating toolbar panel with the given SwiftUI view
    /// Configures a non-activating, transparent, always-on-top panel sized to fit content
    static func createPanel<V: View>(rootView: V, initialWidth: CGFloat = 80) -> NSPanel {
        let hostingController = NSHostingController(rootView: rootView)
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
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
    
    // MARK: - Position Near Cursor
    
    /// Position the given panel near the text cursor
    /// Falls back to mouse position if caret position cannot be determined
    /// - Parameters:
    ///   - panel: The panel to position
    ///   - cursorGap: Gap between panel and cursor position (points)
    ///   - mouseGap: Gap between panel and mouse position (points)
    static func positionNearCursor(_ panel: NSPanel, cursorGap: CGFloat = 4, mouseGap: CGFloat = 8) {
        if let cursorRect = getCursorRectFromAccessibility() {
            positionPanel(panel, relativeTo: cursorRect, gap: cursorGap)
        } else {
            let mouseLocation = NSEvent.mouseLocation
            let mouseRect = NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 20)
            positionPanel(panel, relativeTo: mouseRect, gap: mouseGap)
        }
    }
    
    // MARK: - Panel Positioning
    
    /// Position panel relative to a target rect, keeping it on-screen
    /// Places panel above target by default, below if not enough space above
    static func positionPanel(_ panel: NSPanel, relativeTo targetRect: NSRect, gap: CGFloat) {
        let panelSize = panel.frame.size
        
        // Center horizontally on target cursor position
        var x = targetRect.origin.x - panelSize.width / 2 + targetRect.width / 2
        
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
    
    // MARK: - Screen Distance
    
    /// Calculate shortest distance from a point to a screen's frame
    static func distanceToScreen(point: NSPoint, screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        let clampedX = max(frame.minX, min(point.x, frame.maxX))
        let clampedY = max(frame.minY, min(point.y, frame.maxY))
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - AX Cursor Detection
    
    /// Get cursor rectangle from focused text element via Accessibility API
    /// Returns coordinates in Cocoa screen space (origin at bottom-left)
    /// Tries three methods: AXBoundsForRange, insertion point bounds, then falls back to nil
    static func getCursorRectFromAccessibility() -> NSRect? {
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
        
        // Method 2: Try visible character range bounds (useful for editors
        // that don't support AXBoundsForRange for the cursor position)
        if let insertionRect = getInsertionPointBounds(axElement) {
            return insertionRect
        }
        
        // Fallback: Return nil to use mouse position
        return nil
    }
    
    /// Try to get insertion point bounds by combining visible range with element bounds
    static func getInsertionPointBounds(_ element: AXUIElement) -> NSRect? {
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
    static func getCursorBoundsViaRange(_ element: AXUIElement) -> NSRect? {
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
        
        // Validate bounds - check if both width AND height are 0
        if axBounds.width == 0 && axBounds.height == 0 {
            return nil
        }
        
        // If height is 0 but we have valid position, assume default line height
        if axBounds.height == 0 {
            axBounds.size.height = 18
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
    
    // MARK: - Coordinate Conversion
    
    /// Convert AX coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
    static func convertAXToCocoaCoordinates(_ axRect: CGRect) -> NSRect? {
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }
        
        // Flip Y axis using primary screen height as pivot
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
}
