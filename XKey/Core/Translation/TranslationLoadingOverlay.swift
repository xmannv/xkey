//
//  TranslationLoadingOverlay.swift
//  XKey
//
//  Thin wrapper around FloatingOverlay for backward compatibility.
//  Uses its own FloatingOverlay instance to avoid conflicts with other overlays.
//

import Foundation

class TranslationLoadingOverlay {
    
    static let shared = TranslationLoadingOverlay()
    
    /// Own overlay instance — independent from SecureInputOverlay etc.
    private let overlay = FloatingOverlay()
    
    private init() {}
    
    /// Show loading overlay (spinning indicator) near the current mouse position
    func show() {
        overlay.showLoading()
    }
    
    /// Show a brief message overlay (e.g., "Copied ✓") that auto-hides
    func showBrief(message: String, duration: TimeInterval = 1.2) {
        overlay.showBrief(message, duration: duration)
    }
    
    /// Hide the overlay
    func hide() {
        overlay.hide()
    }
}
