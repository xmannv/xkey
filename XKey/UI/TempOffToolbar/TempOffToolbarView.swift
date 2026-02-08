//
//  TempOffToolbarView.swift
//  XKey
//
//  SwiftUI view for the floating temp off toolbar
//

import SwiftUI

struct TempOffToolbarView: View {
    @ObservedObject var viewModel: TempOffToolbarViewModel

    var body: some View {
        HStack(spacing: 3) {
            // Spelling toggle button (icon only)
            if viewModel.showSpellingButton {
                SpellingButton(
                    isActive: !viewModel.isSpellingTempOff,
                    action: { viewModel.toggleSpelling() }
                )
            }

            // Engine toggle button (VI/EN text)
            if viewModel.showEngineButton {
                EngineButton(
                    isEnglish: viewModel.isEngineTempOff,
                    action: { viewModel.toggleEngine() }
                )
            }
        }
        .floatingToolbarStyle()
    }
}

// MARK: - Spelling Button

private struct SpellingButton: View {
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .white : Color(nsColor: .secondaryLabelColor))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(buttonBackgroundColor)
                )
                .overlay(
                    Circle()
                        .strokeBorder(buttonBorderColor, lineWidth: isActive ? 0 : 0.5)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help("Chính tả")
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var buttonBackgroundColor: Color {
        if isActive {
            return Color(nsColor: .systemGreen)
        } else if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return Color(nsColor: .tertiaryLabelColor).opacity(0.2)
        }
    }

    private var buttonBorderColor: Color {
        if isActive {
            return .clear
        } else {
            return Color(nsColor: .separatorColor)
        }
    }
}

// MARK: - Engine Button

private struct EngineButton: View {
    let isEnglish: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(isEnglish ? "EN" : "VI")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(isEnglish ? Color(nsColor: .secondaryLabelColor) : .white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(buttonBackgroundColor)
                )
                .overlay(
                    Circle()
                        .strokeBorder(buttonBorderColor, lineWidth: isEnglish ? 0.5 : 0)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(isEnglish ? "English" : "Tiếng Việt")
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var buttonBackgroundColor: Color {
        if !isEnglish {
            return Color(nsColor: .systemGreen)
        } else if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return Color(nsColor: .tertiaryLabelColor).opacity(0.2)
        }
    }

    private var buttonBorderColor: Color {
        if !isEnglish {
            return .clear
        } else {
            return Color(nsColor: .separatorColor)
        }
    }
}

// MARK: - Preview

#Preview {
    TempOffToolbarView(viewModel: TempOffToolbarViewModel())
        .frame(width: 100, height: 50)
}
