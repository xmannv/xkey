//
//  SecureInputOverlay.swift
//  XKey
//
//  Shared Secure Input warning presenter for XKey.app and standalone XKeyIM.
//

import Foundation
import SwiftUI

final class SecureInputOverlay: SecureInputPresenting {
    static let shared = SecureInputOverlay()

    /// Independent from translation and other overlays.
    private let overlay = FloatingOverlay()

    private init() {}

    func show(appName: String) {
        overlay.show(
            content: AnyView(OverlayWarningView(
                title: String(localized: "Secure Input đang bật"),
                subtitle: String(localized: "\(appName) đang chặn XKey xử lý Tiếng Việt")
            )),
            position: .bottomCenter,
            autoHideAfter: 5
        )
    }

    func hide() {
        overlay.hide()
    }
}
