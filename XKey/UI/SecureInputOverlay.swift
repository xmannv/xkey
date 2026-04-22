//
//  SecureInputOverlay.swift
//  XKey
//
//  Thin wrapper around FloatingOverlay for Secure Input warnings.
//  Uses its own FloatingOverlay instance to avoid conflicts with other overlays.
//

import Foundation
import SwiftUI

class SecureInputOverlay {
    
    static let shared = SecureInputOverlay()
    
    /// Own overlay instance — independent from TranslationLoadingOverlay etc.
    private let overlay = FloatingOverlay()
    
    private init() {}
    
    /// Show warning overlay with the name of the app holding Secure Input
    func show(appName: String) {
        overlay.show(
            content: AnyView(OverlayWarningView(
                title: "Secure Input đang bật",
                subtitle: "\(appName) đang chặn XKey xử lý Tiếng Việt"
            )),
            position: .bottomCenter,
            autoHideAfter: 5.0
        )
    }
    
    /// Hide the overlay
    func hide() {
        overlay.hide()
    }
}
