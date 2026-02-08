//
//  FloatingToolbarStyle.swift
//  XKey
//
//  Shared SwiftUI styling for floating toolbar capsule backgrounds
//  Used by TempOffToolbarView and TranslationToolbarView
//

import SwiftUI

/// Applies the standard floating toolbar capsule appearance
/// (translucent material background, shadow, subtle border)
struct FloatingToolbarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Apply the standard floating toolbar capsule style
    func floatingToolbarStyle() -> some View {
        modifier(FloatingToolbarStyle())
    }
}
