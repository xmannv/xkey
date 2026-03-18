//
//  AXHelper.swift
//  XKey
//
//  Centralized helper for safe Accessibility API queries.
//  Wraps raw AXUIElementCopyAttributeValue calls with:
//  - Consistent error handling
//  - Type-safe attribute access
//  - Reduced boilerplate (~1 line vs ~4 lines per call)
//

import Cocoa
import ApplicationServices

/// Centralized helper for safe Accessibility API queries
enum AXHelper {
    
    // MARK: - Get Focused Element
    
    /// Get the currently focused AXUIElement from system-wide element
    /// This is the most common entry point for AX queries
    static func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        ) == .success, let element = ref else {
            return nil
        }
        return (element as! AXUIElement)
    }
    
    // MARK: - Read String Attributes
    
    /// Get a string attribute from an AXUIElement
    static func getString(_ element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref as? String else {
            return nil
        }
        return value
    }
    
    /// Get a string attribute using a plain String key (e.g., "AXDOMIdentifier")
    static func getString(_ element: AXUIElement, attribute: String) -> String? {
        return getString(element, attribute: attribute as CFString)
    }
    
    // MARK: - Read Numeric Attributes
    
    /// Get an integer attribute from an AXUIElement
    static func getInt(_ element: AXUIElement, attribute: String) -> Int? {
        return getInt(element, attribute: attribute as CFString)
    }
    
    /// Get an integer attribute from an AXUIElement using CFString key
    static func getInt(_ element: AXUIElement, attribute: CFString) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref as? Int else {
            return nil
        }
        return value
    }
    
    // MARK: - Read Range Attributes
    
    /// Get a CFRange attribute from an AXUIElement (e.g., selected text range)
    static func getRange(_ element: AXUIElement, attribute: String) -> CFRange? {
        return getRange(element, attribute: attribute as CFString)
    }
    
    /// Get a CFRange attribute from an AXUIElement using CFString key
    static func getRange(_ element: AXUIElement, attribute: CFString) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let axValue = ref else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }
    
    // MARK: - Read Element Attributes
    
    /// Get an AXUIElement child attribute (e.g., focused window)
    static func getElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        return getElement(element, attribute: attribute as CFString)
    }
    
    /// Get an AXUIElement child attribute using CFString key
    static func getElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref else {
            return nil
        }
        return (value as! AXUIElement)
    }
    
    // MARK: - Read Array Attributes
    
    /// Get an array of AXUIElements (e.g., windows list)
    static func getElementArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        return getElementArray(element, attribute: attribute as CFString)
    }
    
    /// Get an array of AXUIElements using CFString key
    static func getElementArray(_ element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let array = ref as? [AXUIElement], !array.isEmpty else {
            return nil
        }
        return array
    }
    
    /// Get a string array attribute (e.g., AXDOMClassList)
    static func getStringArray(_ element: AXUIElement, attribute: String) -> [String]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let array = ref as? [String] else {
            return nil
        }
        return array
    }
    
    // MARK: - Read Raw Attributes
    
    /// Get a raw CFTypeRef attribute (for callers that need custom type handling)
    static func getRaw(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        return getRaw(element, attribute: attribute as CFString)
    }
    
    /// Get a raw CFTypeRef attribute using CFString key
    static func getRaw(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref
    }
    
    // MARK: - Write Attributes
    
    /// Set an attribute value on an AXUIElement
    /// Returns the AXError for callers that need to check specific error codes
    @discardableResult
    static func setValue(_ element: AXUIElement, attribute: CFString, value: CFTypeRef) -> AXError {
        return AXUIElementSetAttributeValue(element, attribute, value)
    }
    
    /// Set an attribute value using a plain String key
    @discardableResult
    static func setValue(_ element: AXUIElement, attribute: String, value: CFTypeRef) -> AXError {
        return AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
    
    // MARK: - Convenience: Window Title
    
    /// Get window title for an app element (tries focused window → main window → first window)
    /// This cascade pattern is used in multiple places across the codebase
    static func getWindowTitle(for appElement: AXUIElement) -> String? {
        // Try focused window first
        if let window = getElement(appElement, attribute: kAXFocusedWindowAttribute),
           let title = getString(window, attribute: kAXTitleAttribute) {
            return title
        }
        
        // Try main window
        if let window = getElement(appElement, attribute: kAXMainWindowAttribute),
           let title = getString(window, attribute: kAXTitleAttribute) {
            return title
        }
        
        // Try first window from windows array
        if let windows = getElementArray(appElement, attribute: kAXWindowsAttribute),
           let firstWindow = windows.first,
           let title = getString(firstWindow, attribute: kAXTitleAttribute) {
            return title
        }
        
        return nil
    }
    
    // MARK: - Convenience: Selected Text Range
    
    /// Get the selected text range (cursor position) as CFRange
    static func getSelectedRange(_ element: AXUIElement) -> CFRange? {
        return getRange(element, attribute: kAXSelectedTextRangeAttribute)
    }
    
    // MARK: - Raw Query (for advanced usage that needs AXError code)
    
    /// Perform a raw AX query returning a tuple of (AXError, CFTypeRef?)
    /// Convenient for callers that use tuple destructuring
    static func query(_ element: AXUIElement, attribute: String) -> (AXError, CFTypeRef?) {
        return query(element, attribute: attribute as CFString)
    }
    
    /// Perform a raw AX query returning a tuple of (AXError, CFTypeRef?)
    static func query(_ element: AXUIElement, attribute: CFString) -> (AXError, CFTypeRef?) {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &ref)
        return (error, ref)
    }
    
    /// Perform a raw AX query returning the AXError code (inout variant)
    /// Use when caller needs to inspect the specific error (e.g., .attributeUnsupported)
    static func query(_ element: AXUIElement, attribute: CFString, result: inout CFTypeRef?) -> AXError {
        return AXUIElementCopyAttributeValue(element, attribute, &result)
    }
}
