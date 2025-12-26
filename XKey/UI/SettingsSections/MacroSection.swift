//
//  MacroSection.swift
//  XKey
//
//  Shared Macro Settings Section
//

import SwiftUI

struct MacroSection: View {
    @StateObject private var viewModel = MacroManagementViewModel()
    @ObservedObject var prefsViewModel: PreferencesViewModel
    @State private var newMacroText: String = ""
    @State private var newMacroContent: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var editingMacro: MacroItem? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Settings Group
                SettingsGroup(title: "Cài đặt Macro") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Bật Macro", isOn: $prefsViewModel.preferences.macroEnabled)
                        
                        if prefsViewModel.preferences.macroEnabled {
                            Toggle("Dùng macro trong chế độ tiếng Anh", isOn: $prefsViewModel.preferences.macroInEnglishMode)
                                .padding(.leading, 20)
                            Toggle("Tự động viết hoa macro", isOn: $prefsViewModel.preferences.autoCapsMacro)
                                .padding(.leading, 20)
                        }
                    }
                }
                
                // Add new macro
                SettingsGroup(title: "Thêm macro mới") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Từ viết tắt")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("vd: btw", text: $newMacroText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .onChange(of: newMacroText) { newValue in
                                        // Filter out Vietnamese diacritics and spaces
                                        let filtered = filterMacroAbbreviation(newValue)
                                        if filtered != newValue {
                                            newMacroText = filtered
                                        }
                                    }
                                Text("Không hỗ trợ dấu tiếng Việt và khoảng cách")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nội dung thay thế")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("vd: by the way", text: $newMacroContent)
                                    .textFieldStyle(.roundedBorder)
                                Text(" ")
                                    .font(.system(size: 9))
                                    .foregroundColor(.clear)
                            }
                            
                            Button("Thêm") {
                                addMacro()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newMacroText.isEmpty || newMacroContent.isEmpty)
                        }
                        
                        if showError {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                // Macro list
                SettingsGroup(title: "Danh sách macro (\(viewModel.macros.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Action buttons
                        HStack(spacing: 12) {
                            Button(action: viewModel.importMacros) {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: viewModel.exportMacros) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            if !viewModel.macros.isEmpty {
                                Button(role: .destructive) {
                                    viewModel.clearAll()
                                } label: {
                                    Label("Xóa tất cả", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                        
                        // Macro list
                        if viewModel.macros.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "text.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Chưa có macro nào")
                                    .foregroundColor(.secondary)
                                Text("Thêm macro để tự động thay thế từ viết tắt")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.macros) { macro in
                                    MacroRowView(
                                        macro: macro,
                                        onEdit: {
                                            editMacro(macro)
                                        },
                                        onDelete: {
                                            viewModel.deleteMacro(macro)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .sheet(item: $editingMacro) { macro in
            EditMacroSheet(
                macro: macro,
                viewModel: viewModel,
                isPresented: Binding(
                    get: { editingMacro != nil },
                    set: { if !$0 { editingMacro = nil } }
                )
            )
        }
        .onAppear {
            viewModel.loadMacros()
        }
    }
    
    
    private func addMacro() {
        let trimmedText = newMacroText.trimmingCharacters(in: .whitespaces)
        let trimmedContent = newMacroContent.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedText.isEmpty && !trimmedContent.isEmpty else {
            showErrorMessage("Vui lòng nhập đầy đủ thông tin")
            return
        }
        
        guard trimmedText.count >= 2 else {
            showErrorMessage("Từ viết tắt phải có ít nhất 2 ký tự")
            return
        }
        
        if viewModel.addMacro(text: trimmedText, content: trimmedContent) {
            newMacroText = ""
            newMacroContent = ""
            showError = false
        } else {
            showErrorMessage("Macro '\(trimmedText)' đã tồn tại")
        }
    }
    
    private func editMacro(_ macro: MacroItem) {
        editingMacro = macro
    }

    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showError = false
        }
    }
    
    /// Filter out Vietnamese diacritics and spaces from macro abbreviation
    /// Vietnamese characters with diacritics are converted to their base ASCII form
    private func filterMacroAbbreviation(_ text: String) -> String {
        // Remove spaces first
        let noSpaces = text.replacingOccurrences(of: " ", with: "")
        
        // Convert Vietnamese characters to ASCII equivalents
        // This removes diacritics: á → a, é → e, etc.
        let normalized = noSpaces.folding(options: .diacriticInsensitive, locale: .current)
        
        // Only keep ASCII characters (letters, numbers, and common symbols)
        let filtered = normalized.unicodeScalars.filter { scalar in
            // Allow ASCII printable characters (except space which we already removed)
            return scalar.value >= 33 && scalar.value <= 126
        }
        
        return String(String.UnicodeScalarView(filtered))
    }
}

// MARK: - Macro Row View

struct MacroRowView: View {
    let macro: MacroItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Shortcut text
            Text(macro.text)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
                .frame(minWidth: 80, alignment: .center)
            
            // Arrow
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 12, weight: .medium))
            
            // Content
            Text(macro.content)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action buttons
            HStack(spacing: 8) {
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.gray.opacity(0.03))
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Edit Macro Sheet

struct EditMacroSheet: View {
    let macro: MacroItem
    @ObservedObject var viewModel: MacroManagementViewModel
    @Binding var isPresented: Bool
    
    @State private var editedText: String
    @State private var editedContent: String
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    init(macro: MacroItem, viewModel: MacroManagementViewModel, isPresented: Binding<Bool>) {
        self.macro = macro
        self.viewModel = viewModel
        self._isPresented = isPresented
        self._editedText = State(initialValue: macro.text)
        self._editedContent = State(initialValue: macro.content)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sửa Macro")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Form
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Từ viết tắt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("vd: btw", text: $editedText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onChange(of: editedText) { newValue in
                            let filtered = filterMacroAbbreviation(newValue)
                            if filtered != newValue {
                                editedText = filtered
                            }
                        }
                    
                    Text("Không hỗ trợ dấu tiếng Việt và khoảng cách")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nội dung thay thế")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("vd: by the way", text: $editedContent)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                if showError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            Divider()
            
            // Footer buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("Hủy") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Button("Cập nhật") {
                    updateMacro()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editedText.isEmpty || editedContent.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func updateMacro() {
        let trimmedText = editedText.trimmingCharacters(in: .whitespaces)
        let trimmedContent = editedContent.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedText.isEmpty && !trimmedContent.isEmpty else {
            showErrorMessage("Vui lòng nhập đầy đủ thông tin")
            return
        }
        
        guard trimmedText.count >= 2 else {
            showErrorMessage("Từ viết tắt phải có ít nhất 2 ký tự")
            return
        }
        
        if viewModel.updateMacro(macro, newText: trimmedText, newContent: trimmedContent) {
            isPresented = false
        } else {
            showErrorMessage("Macro '\(trimmedText)' đã tồn tại")
        }
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showError = false
        }
    }
    
    private func filterMacroAbbreviation(_ text: String) -> String {
        let noSpaces = text.replacingOccurrences(of: " ", with: "")
        let normalized = noSpaces.folding(options: .diacriticInsensitive, locale: .current)
        let filtered = normalized.unicodeScalars.filter { scalar in
            return scalar.value >= 33 && scalar.value <= 126
        }
        return String(String.UnicodeScalarView(filtered))
    }
}

