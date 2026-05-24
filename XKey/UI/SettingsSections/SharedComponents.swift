//
//  SharedComponents.swift
//  XKey
//
//  Shared UI Components for Settings
//

import SwiftUI

// MARK: - Settings Group

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
        }
    }
}

// MARK: - Settings Radio Button

struct SettingsRadioButton: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
