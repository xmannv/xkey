//
//  PreferencesView.swift
//  XKey
//
//  SwiftUI Preferences View with Tab Layout
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedTab: Int
    
    var onSave: ((Preferences) -> Void)?
    var onClose: (() -> Void)?
    
    init(selectedTab: Int = 0, onSave: ((Preferences) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self._selectedTab = State(initialValue: selectedTab)
        self.onSave = onSave
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Cài đặt XKey")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // Tab View
            TabView(selection: $selectedTab) {
                // Tab 0: Giới thiệu
                AboutTab()
                    .tabItem {
                        Label("Giới thiệu", systemImage: "info.circle")
                    }
                    .tag(0)
                
                // Tab 1: Cơ bản
                BasicSettingsTab(viewModel: viewModel)
                    .tabItem {
                        Label("Cơ bản", systemImage: "gearshape")
                    }
                    .tag(1)
                
                // Tab 2: Gõ nhanh
                QuickTypingTab(viewModel: viewModel)
                    .tabItem {
                        Label("Gõ nhanh", systemImage: "keyboard")
                    }
                    .tag(2)
                
                // Tab 3: Nâng cao
                AdvancedTab(viewModel: viewModel)
                    .tabItem {
                        Label("Nâng cao", systemImage: "slider.horizontal.3")
                    }
                    .tag(3)
                
                // Tab 4: Chuyển đổi
                ConvertToolTab()
                    .tabItem {
                        Label("Chuyển đổi", systemImage: "arrow.left.arrow.right")
                    }
                    .tag(4)
                
                // Tab 5: Giao diện
                UISettingsTab(viewModel: viewModel)
                    .tabItem {
                        Label("Giao diện", systemImage: "paintbrush")
                    }
                    .tag(5)
            }
            .padding(.horizontal, 8)
            
            // Buttons
            HStack {
                Spacer()
                
                Button("Hủy") {
                    onClose?()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Lưu") {
                    viewModel.save()
                    onSave?(viewModel.preferences)
                    onClose?()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 580, height: 500)
    }
}

// MARK: - Tab 0: About

struct AboutTab: View {
    @StateObject private var updateChecker = UpdateChecker()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // App Icon & Name
                VStack(spacing: 12) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    
                    Text("XKey")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Phiên bản \(AppVersion.current)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Description
                VStack(spacing: 8) {
                    Text("Bộ gõ tiếng Việt cho macOS")
                        .font(.body)
                    
                    Text("Hỗ trợ Telex, VNI, VIQR và nhiều tính năng khác")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .padding(.horizontal, 40)
                
                // Links
                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/xmannv/xkey")!) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                            Text("GitHub Repository")
                        }
                    }
                    
                    Text("© 2025 XKey Contributors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                
                // Update Check Section
                GroupBox {
                    VStack(spacing: 12) {
                        switch updateChecker.updateStatus {
                        case .checking:
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Đang kiểm tra cập nhật...")
                                    .font(.subheadline)
                            }
                            
                        case .upToDate:
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green)
                                Text("Bạn đang sử dụng phiên bản mới nhất")
                                    .font(.subheadline)
                            }
                            
                        case .updateAvailable(let version, let url, let releaseNotes):
                            VStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue)
                                
                                Text("Có phiên bản mới: \(version)")
                                    .font(.headline)
                                
                                if !releaseNotes.isEmpty {
                                    ScrollView {
                                        Text(releaseNotes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .frame(maxHeight: 100)
                                }
                                
                                Button("Tải về") {
                                    if let downloadURL = URL(string: url) {
                                        NSWorkspace.shared.open(downloadURL)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            
                        case .error(let message):
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        Button("Kiểm tra cập nhật") {
                            Task {
                                await updateChecker.checkForUpdates()
                            }
                        }
                        .disabled(updateChecker.updateStatus == .checking)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tab 1: Basic Settings

struct BasicSettingsTab: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hotkey
                GroupBox("Phím tắt") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bật/tắt tiếng Việt:")
                            Spacer()
                            HotkeyRecorderView(hotkey: $viewModel.preferences.toggleHotkey)
                                .frame(width: 150)
                        }
                        
                        Toggle("Phát âm thanh khi bật/tắt", isOn: $viewModel.preferences.beepOnToggle)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Hoàn tác gõ tiếng Việt bằng phím Esc", isOn: $viewModel.preferences.undoTypingEnabled)
                            
                            Text("Nhấn Esc ngay sau khi gõ để hoàn tác việc bỏ dấu")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Input Method
                GroupBox("Kiểu gõ") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(InputMethod.allCases, id: \.self) { method in
                            RadioButton(
                                title: method.displayName,
                                isSelected: viewModel.preferences.inputMethod == method
                            ) {
                                viewModel.preferences.inputMethod = method
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Code Table
                GroupBox("Bảng mã") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(CodeTable.allCases, id: \.self) { table in
                            RadioButton(
                                title: table.displayName,
                                isSelected: viewModel.preferences.codeTable == table
                            ) {
                                viewModel.preferences.codeTable = table
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Basic Options
                GroupBox("Tùy chọn") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Kiểu gõ hiện đại (oà/uý)", isOn: $viewModel.preferences.modernStyle)
                        Toggle("Kiểm tra chính tả", isOn: $viewModel.preferences.spellCheckEnabled)
                        Toggle("Sửa lỗi tự động hoàn thành", isOn: $viewModel.preferences.fixAutocomplete)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Tab 2: Quick Typing

struct QuickTypingTab: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Quick Telex") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick Telex", isOn: $viewModel.preferences.quickTelexEnabled)
                        
                        Text("cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu, tt→th")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Quick Consonant - Đầu từ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick Start Consonant", isOn: $viewModel.preferences.quickStartConsonantEnabled)
                        
                        Text("f→ph, j→gi, w→qu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Quick Consonant - Cuối từ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Quick End Consonant", isOn: $viewModel.preferences.quickEndConsonantEnabled)
                        
                        Text("g→ng, h→nh, k→ch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Tab 3: Advanced

struct AdvancedTab: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Chính tả & Viết hoa") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Khôi phục nếu sai chính tả", isOn: $viewModel.preferences.restoreIfWrongSpelling)
                        Toggle("Tự động viết hoa chữ đầu câu", isOn: $viewModel.preferences.upperCaseFirstChar)
                        Toggle("Cho phép phụ âm Z, F, W, J", isOn: $viewModel.preferences.allowConsonantZFWJ)
                        Toggle("Đặt dấu tự do (Free Mark)", isOn: $viewModel.preferences.freeMarkEnabled)
                        Toggle("Tạm tắt chính tả bằng Ctrl", isOn: $viewModel.preferences.tempOffSpellingEnabled)
                        Toggle("Tạm tắt gõ tiếng Việt bằng Option", isOn: $viewModel.preferences.tempOffEngineEnabled)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Macro (Text Shortcuts)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Macro", isOn: $viewModel.preferences.macroEnabled)
                            .onChange(of: viewModel.preferences.macroEnabled) { newValue in
                                if !newValue {
                                    viewModel.preferences.macroInEnglishMode = false
                                    viewModel.preferences.autoCapsMacro = false
                                }
                            }
                        
                        if viewModel.preferences.macroEnabled {
                            Toggle("Dùng macro trong chế độ tiếng Anh", isOn: $viewModel.preferences.macroInEnglishMode)
                                .padding(.leading, 16)
                            Toggle("Tự động viết hoa macro", isOn: $viewModel.preferences.autoCapsMacro)
                                .padding(.leading, 16)
                            
                            Button("Quản lý Macro...") {
                                print("Open macro management")
                            }
                            .padding(.leading, 16)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Smart Switch") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Nhớ ngôn ngữ theo ứng dụng", isOn: $viewModel.preferences.smartSwitchEnabled)
                        
                        Text("Tự động chuyển ngôn ngữ khi chuyển app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Debug") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật chế độ Debug", isOn: $viewModel.preferences.debugModeEnabled)
                        
                        Text("Hiển thị cửa sổ debug để theo dõi hoạt động của bộ gõ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Tab 4: UI Settings

struct UISettingsTab: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Thanh menu") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Biểu tượng menubar:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                                RadioButton(
                                    title: style.displayName,
                                    isSelected: viewModel.preferences.menuBarIconStyle == style
                                ) {
                                    viewModel.preferences.menuBarIconStyle = style
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Dock") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Hiển thị biểu tượng trên thanh Dock", isOn: $viewModel.preferences.showDockIcon)
                        
                        Text("Khi bật, XKey sẽ hiển thị icon trên Dock như các ứng dụng thông thường")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                GroupBox("Khởi động") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Khởi động cùng hệ thống", isOn: $viewModel.preferences.startAtLogin)
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Tab 4: Convert Tool

struct ConvertToolTab: View {
    @StateObject private var viewModel = ConvertToolViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Input text
                GroupBox("Văn bản gốc") {
                    TextEditor(text: $viewModel.inputText)
                        .font(.body)
                        .frame(height: 80)
                        .border(Color.gray.opacity(0.2), width: 1)
                        .cornerRadius(4)
                }
                
                // Conversion options
                GroupBox("Chuyển đổi chữ hoa/thường") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
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
                        
                        HStack(spacing: 16) {
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
                        
                        Toggle("Xóa dấu tiếng Việt", isOn: $viewModel.removeMark)
                    }
                    .padding(.vertical, 4)
                }
                
                // Code table conversion
                GroupBox("Chuyển đổi bảng mã") {
                    HStack(spacing: 12) {
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
                            .frame(width: 180)
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
                            .frame(width: 180)
                        }
                    }
                    .padding(.vertical, 4)
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
                GroupBox("Kết quả") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.outputText)
                            .font(.body)
                            .frame(height: 80)
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

// MARK: - Radio Button Component

struct RadioButton: View {
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

#Preview {
    PreferencesView()
}
