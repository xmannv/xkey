//
//  SettingsView.swift
//  XKey
//
//  Unified Settings View with Apple-style sidebar navigation
//  Supports macOS 26 Tahoe Liquid Glass design
//

import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "Cơ bản"
    case quickTyping = "Gõ nhanh"
    case advanced = "Nâng cao"
    case macro = "Macro"
    case convertTool = "Chuyển đổi"
    case appearance = "Giao diện"
    case about = "Giới thiệu"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .quickTyping: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .macro: return "text.badge.plus"
        case .convertTool: return "arrow.left.arrow.right"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Main Settings View

@available(macOS 13.0, *)
struct SettingsView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedSection: SettingsSection
    
    var onSave: ((Preferences) -> Void)?
    var onClose: (() -> Void)?
    
    init(selectedSection: SettingsSection = .general, onSave: ((Preferences) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self._selectedSection = State(initialValue: selectedSection)
        self.onSave = onSave
        self.onClose = onClose
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Content
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsSection(viewModel: viewModel)
                case .quickTyping:
                    QuickTypingSettingsSection(viewModel: viewModel)
                case .advanced:
                    AdvancedSettingsSection(viewModel: viewModel)
                case .macro:
                    MacroSettingsSection()
                case .convertTool:
                    ConvertToolSection()
                case .appearance:
                    AppearanceSettingsSection(viewModel: viewModel)
                case .about:
                    AboutSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 750, height: 550)
        .onReceive(viewModel.objectWillChange) { _ in
            // Auto-save when any preference changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.save()
                onSave?(viewModel.preferences)
            }
        }
    }
}


// MARK: - General Settings Section

struct GeneralSettingsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey
                SettingsGroup(title: "Phím tắt") {
                    HStack {
                        Text("Bật/tắt tiếng Việt:")
                        Spacer()
                        HotkeyRecorderView(hotkey: $viewModel.preferences.toggleHotkey)
                            .frame(width: 150)
                    }
                }
                
                // Input Method
                SettingsGroup(title: "Kiểu gõ") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(InputMethod.allCases, id: \.self) { method in
                            SettingsRadioButton(
                                title: method.displayName,
                                isSelected: viewModel.preferences.inputMethod == method
                            ) {
                                viewModel.preferences.inputMethod = method
                            }
                        }
                    }
                }
                
                // Code Table
                SettingsGroup(title: "Bảng mã") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(CodeTable.allCases, id: \.self) { table in
                            SettingsRadioButton(
                                title: table.displayName,
                                isSelected: viewModel.preferences.codeTable == table
                            ) {
                                viewModel.preferences.codeTable = table
                            }
                        }
                    }
                }
                
                // Basic Options
                SettingsGroup(title: "Tùy chọn") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Kiểu gõ hiện đại (oà/uý)", isOn: $viewModel.preferences.modernStyle)
                        Toggle("Kiểm tra chính tả", isOn: $viewModel.preferences.spellCheckEnabled)
                        Toggle("Sửa lỗi tự động hoàn thành", isOn: $viewModel.preferences.fixAutocomplete)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Quick Typing Settings Section

struct QuickTypingSettingsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Quick Telex") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick Telex", isOn: $viewModel.preferences.quickTelexEnabled)
                        
                        Text("cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu, tt→th")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsGroup(title: "Quick Consonant - Đầu từ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick Start Consonant", isOn: $viewModel.preferences.quickStartConsonantEnabled)
                        
                        Text("f→ph, j→gi, w→qu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsGroup(title: "Quick Consonant - Cuối từ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick End Consonant", isOn: $viewModel.preferences.quickEndConsonantEnabled)
                        
                        Text("g→ng, h→nh, k→ch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Advanced Settings Section

struct AdvancedSettingsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Chính tả & Viết hoa") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Khôi phục nếu sai chính tả", isOn: $viewModel.preferences.restoreIfWrongSpelling)
                        Toggle("Tự động viết hoa chữ đầu câu", isOn: $viewModel.preferences.upperCaseFirstChar)
                        Toggle("Cho phép phụ âm Z, F, W, J", isOn: $viewModel.preferences.allowConsonantZFWJ)
                    }
                }
                
                SettingsGroup(title: "Đặt dấu") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Đặt dấu tự do (Free Mark)", isOn: $viewModel.preferences.freeMarkEnabled)
                        
                        Text("Cho phép đặt dấu ở bất kỳ vị trí nào trong từ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsGroup(title: "Tạm tắt") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Tạm tắt chính tả bằng phím Ctrl", isOn: $viewModel.preferences.tempOffSpellingEnabled)
                            
                            Text("Giữ Ctrl khi gõ để tạm thời tắt kiểm tra chính tả")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Tạm tắt gõ tiếng Việt bằng phím Option", isOn: $viewModel.preferences.tempOffEngineEnabled)
                            
                            Text("Giữ Option (⌥) khi gõ để tạm thời tắt bộ gõ")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                SettingsGroup(title: "Smart Switch") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Nhớ ngôn ngữ theo ứng dụng", isOn: $viewModel.preferences.smartSwitchEnabled)
                        
                        Text("Tự động chuyển ngôn ngữ khi chuyển app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsGroup(title: "Debug") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật chế độ Debug", isOn: $viewModel.preferences.debugModeEnabled)
                        
                        Text("Hiển thị cửa sổ debug để theo dõi hoạt động của bộ gõ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Thanh trạng thái") {
                    Toggle("Hiển thị biểu tượng trên thanh trạng thái", isOn: $viewModel.preferences.showStatusBarIcon)
                }
                
                SettingsGroup(title: "Khởi động") {
                    Toggle("Khởi động cùng hệ thống", isOn: $viewModel.preferences.startAtLogin)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - About Settings Section

struct AboutSettingsSection: View {
    @State private var showDonationDialog = false
    @StateObject private var updateChecker = UpdateChecker()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App Logo
                if let logo = NSImage(named: "XKeyLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .padding(.top, 20)
                } else {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                        .padding(.top, 20)
                }
                
                // App Name & Version
                VStack(spacing: 4) {
                    Text("XKey")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("Vietnamese Input Method for macOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Version \(AppVersion.current)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                Divider()
                    .padding(.horizontal, 80)
                
                // Credits & Donation
                VStack(spacing: 8) {
                    Text("Made with ❤️ & ☕")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showDonationDialog = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy me a coffee")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                    .padding(.horizontal, 80)
                
                // Update Check Section - Compact
                VStack(spacing: 10) {
                    switch updateChecker.updateStatus {
                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Đang kiểm tra cập nhật...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case .upToDate:
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                            Text("Đang dùng phiên bản mới nhất")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case .updateAvailable(let version, let url, let releaseNotes):
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                                Text("Có phiên bản mới: \(version)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            if !releaseNotes.isEmpty {
                                ScrollView {
                                    Text(releaseNotes)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .frame(maxHeight: 80)
                                .padding(.horizontal, 20)
                            }
                            
                            Button("Tải về") {
                                if let downloadURL = URL(string: url) {
                                    NSWorkspace.shared.open(downloadURL)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                    case .error(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                            Text(message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Button("Kiểm tra cập nhật") {
                        Task {
                            await updateChecker.checkForUpdates()
                        }
                    }
                    .controlSize(.small)
                    .disabled(updateChecker.updateStatus == .checking)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Copyright
                Text("Inspired by Openkey & Unikey.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showDonationDialog) {
            DonationView()
        }
    }
}


// MARK: - Macro Settings Section (Embedded)

struct MacroSettingsSection: View {
    @StateObject private var viewModel = MacroManagementViewModel()
    @State private var newMacroText: String = ""
    @State private var newMacroContent: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Add new macro section
            VStack(alignment: .leading, spacing: 12) {
                Text("Thêm macro mới:")
                    .font(.headline)
                
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Từ viết tắt:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("vd: btw", text: $newMacroText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nội dung thay thế:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("vd: by the way", text: $newMacroContent)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 200)
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
            .padding()
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Macro list header
            HStack {
                Text("Danh sách macro (\(viewModel.macros.count)):")
                    .font(.headline)
                
                Spacer()
                
                Button("Import...") {
                    viewModel.importMacros()
                }
                .buttonStyle(.borderless)
                
                Button("Export...") {
                    viewModel.exportMacros()
                }
                .buttonStyle(.borderless)
                
                if !viewModel.macros.isEmpty {
                    Button("Xóa tất cả") {
                        viewModel.clearAll()
                    }
                    .foregroundColor(.red)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Macro list
            if viewModel.macros.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Chưa có macro nào")
                        .foregroundColor(.secondary)
                    Text("Thêm macro để tự động thay thế text shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.macros) { macro in
                            MacroRowCompact(macro: macro) {
                                viewModel.deleteMacro(macro)
                            }
                        }
                    }
                    .padding()
                }
            }
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
        
        if viewModel.addMacro(text: trimmedText, content: trimmedContent) {
            newMacroText = ""
            newMacroContent = ""
            showError = false
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
}

struct MacroRowCompact: View {
    let macro: MacroItem
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Text(macro.text)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .frame(width: 100, alignment: .leading)
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.caption)
            
            Text(macro.content)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
}


// MARK: - Convert Tool Section (Embedded)

struct ConvertToolSection: View {
    @StateObject private var viewModel = ConvertToolViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Input text
                SettingsGroup(title: "Văn bản gốc") {
                    TextEditor(text: $viewModel.inputText)
                        .font(.body)
                        .frame(height: 100)
                        .border(Color.gray.opacity(0.2), width: 1)
                        .cornerRadius(4)
                }
                
                // Conversion options
                SettingsGroup(title: "Chuyển đổi chữ hoa/thường") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 20) {
                            Toggle("Viết hoa tất cả", isOn: $viewModel.toAllCaps)
                                .onChange(of: viewModel.toAllCaps) { newValue in
                                    if newValue {
                                        viewModel.toAllNonCaps = false
                                        viewModel.toCapsFirstLetter = false
                                        viewModel.toCapsEachWord = false
                                    }
                                }
                            
                            Toggle("Viết thường tất cả", isOn: $viewModel.toAllNonCaps)
                                .onChange(of: viewModel.toAllNonCaps) { newValue in
                                    if newValue {
                                        viewModel.toAllCaps = false
                                        viewModel.toCapsFirstLetter = false
                                        viewModel.toCapsEachWord = false
                                    }
                                }
                        }
                        
                        HStack(spacing: 20) {
                            Toggle("Viết hoa chữ đầu", isOn: $viewModel.toCapsFirstLetter)
                                .onChange(of: viewModel.toCapsFirstLetter) { newValue in
                                    if newValue {
                                        viewModel.toAllCaps = false
                                        viewModel.toAllNonCaps = false
                                        viewModel.toCapsEachWord = false
                                    }
                                }
                            
                            Toggle("Viết hoa mỗi từ", isOn: $viewModel.toCapsEachWord)
                                .onChange(of: viewModel.toCapsEachWord) { newValue in
                                    if newValue {
                                        viewModel.toAllCaps = false
                                        viewModel.toAllNonCaps = false
                                        viewModel.toCapsFirstLetter = false
                                    }
                                }
                        }
                    }
                }
                
                SettingsGroup(title: "Tùy chọn khác") {
                    Toggle("Xóa dấu tiếng Việt", isOn: $viewModel.removeMark)
                }
                
                // Code table conversion
                SettingsGroup(title: "Chuyển đổi bảng mã") {
                    HStack(spacing: 15) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Từ:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.fromCode) {
                                Text("Unicode").tag(0)
                                Text("TCVN3").tag(1)
                                Text("VNI").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sang:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $viewModel.toCode) {
                                Text("Unicode").tag(0)
                                Text("TCVN3").tag(1)
                                Text("VNI").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                }
                
                // Convert button
                HStack {
                    Button("Xóa") {
                        viewModel.clear()
                    }
                    
                    Spacer()
                    
                    Button("Chuyển đổi") {
                        viewModel.convert()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.inputText.isEmpty)
                }
                
                // Output text
                SettingsGroup(title: "Kết quả") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.outputText)
                            .font(.body)
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.2), width: 1)
                            .cornerRadius(4)
                        
                        if !viewModel.outputText.isEmpty {
                            Button("Copy kết quả") {
                                viewModel.copyToClipboard()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Reusable Components

struct SettingsGroup<Content: View>: View {
    let title: String
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

struct SettingsRadioButton: View {
    let title: String
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

// MARK: - Preview

@available(macOS 13.0, *)
#Preview {
    SettingsView()
}
