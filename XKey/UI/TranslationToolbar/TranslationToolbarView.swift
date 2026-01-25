//
//  TranslationToolbarView.swift
//  XKey
//
//  SwiftUI view for the floating translation toolbar
//

import SwiftUI

struct TranslationToolbarView: View {
    @ObservedObject var viewModel: TranslationToolbarViewModel
    
    var body: some View {
        HStack(spacing: 3) {
            // Source language button
            LanguageButton(
                language: viewModel.sourceLanguage,
                isSource: true,
                showPicker: $viewModel.showSourcePicker,
                onSelect: { code in
                    viewModel.setSourceLanguage(code)
                },
                presets: viewModel.sourcePresets
            )
            
            // Swap button (disabled if source is auto)
            SwapButton(
                isDisabled: viewModel.sourceLanguageCode == "auto",
                action: { viewModel.swapLanguages() }
            )
            
            // Target language button
            LanguageButton(
                language: viewModel.targetLanguage,
                isSource: false,
                showPicker: $viewModel.showTargetPicker,
                onSelect: { code in
                    viewModel.setTargetLanguage(code)
                },
                presets: viewModel.targetPresets
            )
            
            // Translate button
            TranslateButton(
                isTranslating: viewModel.isTranslating,
                action: { viewModel.translate() }
            )
        }
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

// MARK: - Language Button with Picker

private struct LanguageButton: View {
    let language: TranslationLanguage
    let isSource: Bool
    @Binding var showPicker: Bool
    let onSelect: (String) -> Void
    let presets: [TranslationLanguage]
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { showPicker.toggle() }) {
            HStack(spacing: 3) {
                Text(language.flag)
                    .font(.system(size: 13))
                Text(language.code.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(height: 26)
            .frame(minWidth: 52)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(buttonBackgroundColor)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(isSource ? "Ngôn ngữ nguồn: \(language.displayName)" : "Ngôn ngữ đích: \(language.displayName)")
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            LanguagePickerPopover(
                selectedCode: language.code,
                presets: presets,
                onSelect: { code in
                    onSelect(code)
                    showPicker = false
                }
            )
        }
    }
    
    private var buttonBackgroundColor: Color {
        if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return Color(nsColor: .tertiaryLabelColor).opacity(0.2)
        }
    }
}

// MARK: - Language Picker Popover

private struct LanguagePickerPopover: View {
    let selectedCode: String
    let presets: [TranslationLanguage]
    let onSelect: (String) -> Void
    
    @State private var searchText = ""
    
    var filteredPresets: [TranslationLanguage] {
        if searchText.isEmpty {
            return presets
        }
        return presets.filter { lang in
            lang.displayName.localizedCaseInsensitiveContains(searchText) ||
            lang.code.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Tìm kiếm...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            // Language list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPresets) { lang in
                        LanguageRow(
                            language: lang,
                            isSelected: lang.code == selectedCode,
                            onSelect: { onSelect(lang.code) }
                        )
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 220)
    }
}

// MARK: - Language Row

private struct LanguageRow: View {
    let language: TranslationLanguage
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(language.flag)
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text(language.code.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(rowBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return .clear
        }
    }
}

// MARK: - Swap Button

private struct SwapButton: View {
    let isDisabled: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isDisabled ? Color(nsColor: .tertiaryLabelColor) : .primary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(buttonBackgroundColor)
                )
                .scaleEffect(isHovered && !isDisabled ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? "Không thể đổi khi nguồn là 'Tự động'" : "Đổi ngôn ngữ nguồn ↔ đích")
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var buttonBackgroundColor: Color {
        if isDisabled {
            return Color(nsColor: .tertiaryLabelColor).opacity(0.1)
        } else if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return Color(nsColor: .tertiaryLabelColor).opacity(0.2)
        }
    }
}

// MARK: - Translate Button

private struct TranslateButton: View {
    let isTranslating: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Group {
                if isTranslating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(buttonBackgroundColor)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isTranslating)
        .help("Dịch text đang chọn")
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var buttonBackgroundColor: Color {
        if isTranslating {
            return Color(nsColor: .systemGray)
        } else if isHovered {
            return Color(nsColor: .systemBlue).opacity(0.9)
        } else {
            return Color(nsColor: .systemBlue)
        }
    }
}

// MARK: - Preview

#Preview {
    TranslationToolbarView(viewModel: TranslationToolbarViewModel())
        .frame(width: 250, height: 50)
}
