//
//  AXErrorExtension.swift
//  XKey
//
//  Centralized human-readable descriptions for AXError cases
//  Used by ForceAccessibilityManager, DebugViewModel, and any future AX code
//

import Cocoa

extension AXError {
    /// Human-readable description for this AXError case
    var humanReadableDescription: String {
        switch self {
        case .success: return "Success"
        case .failure: return "General failure"
        case .illegalArgument: return "Illegal argument"
        case .invalidUIElement: return "Invalid UI element"
        case .invalidUIElementObserver: return "Invalid observer"
        case .cannotComplete: return "Cannot complete"
        case .attributeUnsupported: return "Attribute unsupported"
        case .actionUnsupported: return "Action unsupported"
        case .notificationUnsupported: return "Notification unsupported"
        case .notImplemented: return "Not implemented"
        case .notificationAlreadyRegistered: return "Already registered"
        case .notificationNotRegistered: return "Not registered"
        case .apiDisabled: return "API disabled - grant Accessibility permission"
        case .noValue: return "No value"
        case .parameterizedAttributeUnsupported: return "Parameterized attribute unsupported"
        case .notEnoughPrecision: return "Not enough precision"
        @unknown default: return "Unknown error (\(self.rawValue))"
        }
    }
}
