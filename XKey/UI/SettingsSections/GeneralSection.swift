//
//  GeneralSection.swift
//  XKey
//
//  Shared General Settings Section
//

import SwiftUI

struct GeneralSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey
                SettingsGroup(title: "Phím tắt") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Bật/tắt tiếng Việt:")
                            Spacer()
                            HotkeyRecorderView(hotkey: $viewModel.preferences.toggleHotkey)
                                .frame(width: 150)
                        }
                        
                        // Show hint when using Fn or Ctrl+Space
                        if viewModel.preferences.toggleHotkey.modifiers.contains(.function) ||
                           (viewModel.preferences.toggleHotkey.modifiers == [.control] && 
                            viewModel.preferences.toggleHotkey.keyCode == 49) { // Space keyCode
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Lưu ý: Phím tắt này có thể trùng với macOS")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                Text("Để tránh xung đột, vào System Settings → Keyboard → Keyboard Shortcuts → Input Sources và tắt các phím tắt chuyển đổi nguồn nhập.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        
                        Toggle("Phát âm thanh khi bật/tắt", isOn: $viewModel.preferences.beepOnToggle)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Hoàn tác gõ tiếng Việt", isOn: $viewModel.preferences.undoTypingEnabled)
                            
                            if viewModel.preferences.undoTypingEnabled {
                                HStack {
                                    Text("Phím tắt:")
                                    Spacer()
                                    HotkeyRecorderView(
                                        hotkey: Binding(
                                            get: { 
                                                viewModel.preferences.undoTypingHotkey ?? 
                                                Hotkey(keyCode: VietnameseData.KEY_ESC, modifiers: [], isModifierOnly: false) // Default Esc
                                            },
                                            set: { newValue in
                                                // If user sets Esc with no modifiers, treat as default (nil)
                                                if newValue.keyCode == VietnameseData.KEY_ESC && newValue.modifiers.isEmpty && !newValue.isModifierOnly {
                                                    viewModel.preferences.undoTypingHotkey = nil
                                                } else {
                                                    viewModel.preferences.undoTypingHotkey = newValue
                                                }
                                            }
                                        )
                                    )
                                    .frame(width: 150)
                                }
                                
                                Text("Mặc định: Esc. Hỗ trợ tổ hợp phím modifier như Ctrl+Shift (không áp dụng cho XKeyIM)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Nhấn phím tắt ngay sau khi gõ để hoàn tác việc bỏ dấu (ví dụ: \"tiếng\" → \"tieesng\")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

                // Đặt dấu
                SettingsGroup(title: "Đặt dấu") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Đặt dấu tự do (Free Mark)", isOn: $viewModel.preferences.freeMarkEnabled)

                        Text("Cho phép thêm dấu ở bất kỳ vị trí nào trong từ thay vì phải thêm dấu ngay tại chữ đang gõ (a+n+h+s hoặc a+s+n+h)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Code Table
                SettingsGroup(title: "Bảng mã") {
                    // Filter out experimental code tables (not fully tested yet)
                    let supportedCodeTables = CodeTable.allCases.filter { table in
                        table != .unicodeCompound && table != .vietnameseLocaleCP1258
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(supportedCodeTables, id: \.self) { table in
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
                    }
                }                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
