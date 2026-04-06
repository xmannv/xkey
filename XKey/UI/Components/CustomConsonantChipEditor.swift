//
//  CustomConsonantChipEditor.swift
//  XKey
//
//  Chip-based editor for managing custom consonants (Z, F, W, J, K, etc.)
//

import SwiftUI

/// A toggle + chip editor for custom consonants
/// Uses separate bindings for enabled state and consonants list
struct CustomConsonantChipEditor: View {
    @Binding var isEnabled: Bool
    @Binding var customConsonants: String
    @State private var newConsonantInput: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    /// Parse current consonants into a sorted array
    private var consonantList: [String] {
        guard !customConsonants.isEmpty else { return [] }
        return customConsonants
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Master toggle
            Toggle("Cho phép phụ âm tùy chỉnh (mặc định: Z,F,W,J)", isOn: $isEnabled)

            // Chip editor (only visible when enabled)
            if isEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    // Chips row using simple HStack wrapping
                    chipRow

                    // Error message
                    if showError {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .transition(.opacity)
                    }

                    Text("Các phụ âm này sẽ được phép sử dụng trong bộ gõ Tiếng Việt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Chip Row

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(consonantList, id: \.self) { consonant in
                ChipView(text: consonant) {
                    removeConsonant(consonant)
                }
            }

            // Add button/input
            addConsonantView
        }
    }

    // MARK: - Add Consonant View

    private var addConsonantView: some View {
        HStack(spacing: 4) {
            TextField("", text: $newConsonantInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 36)
                .onChange(of: newConsonantInput) { newValue in
                    // Only allow single alphabetic characters
                    let filtered = String(newValue.prefix(1)).uppercased()
                    if filtered != newValue {
                        newConsonantInput = filtered
                    }
                }
                .onSubmit {
                    addConsonant()
                }

            Button(action: addConsonant) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(newConsonantInput.isEmpty)
        }
    }

    // MARK: - Actions

    private func addConsonant() {
        let input = newConsonantInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !input.isEmpty else { return }

        // Validate: must be a single letter
        guard input.count == 1, input.first?.isLetter == true else {
            showErrorMessage("Chỉ cho phép ký tự chữ cái đơn")
            return
        }

        // Check if already exists
        if consonantList.contains(input) {
            showErrorMessage("Phụ âm '\(input)' đã có trong danh sách")
            return
        }

        // Add to list
        if customConsonants.isEmpty {
            customConsonants = input
        } else {
            customConsonants += ",\(input)"
        }

        newConsonantInput = ""
        showError = false
    }

    private func removeConsonant(_ consonant: String) {
        var list = consonantList
        list.removeAll { $0 == consonant }

        if list.isEmpty {
            // Last consonant removed — keep empty string but don't disable
            customConsonants = ""
        } else {
            customConsonants = list.joined(separator: ",")
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        withAnimation {
            showError = true
        }
        // Auto-hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showError = false
            }
        }
    }
}

// MARK: - Chip View

/// A removable chip/tag view for a consonant
struct ChipView: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}
