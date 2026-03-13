//
//  AppearanceSection.swift
//  XKey
//
//  Shared Appearance Settings Section
//

import SwiftUI

struct AppearanceSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Thanh menu") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Biểu tượng menubar:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                                SettingsRadioButton(
                                    title: style.displayName,
                                    isSelected: viewModel.preferences.menuBarIconStyle == style
                                ) {
                                    viewModel.preferences.menuBarIconStyle = style
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                
                SettingsGroup(title: "Dock") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Hiển thị biểu tượng trên thanh Dock", isOn: $viewModel.preferences.showDockIcon)
                        
                        Text("Khi bật, XKey sẽ hiển thị icon trên Dock như các ứng dụng thông thường")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsGroup(title: "Khởi động") {
                    Toggle("Khởi động cùng hệ thống", isOn: $viewModel.preferences.startAtLogin)
                    Toggle("Tự động kiểm tra bản cập nhật", isOn: $viewModel.preferences.autoCheckForUpdates)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
