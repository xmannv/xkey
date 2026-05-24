//
//  AppearanceSection.swift
//  XKey
//
//  Shared Appearance Settings Section
//

import SwiftUI

struct AppearanceSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var showRestartAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Thanh menu") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Biểu tượng menubar:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                                SettingsRadioButton(
                                    title: LocalizedStringKey(style.displayName),
                                    isSelected: viewModel.preferences.menuBarIconStyle == style
                                ) {
                                    viewModel.preferences.menuBarIconStyle = style
                                }
                            }
                        }
                        .padding(.leading, 8)

                        Text("Emoji sẽ hiển thị 🇻🇳 khi ở tiếng Việt và 🇬🇧 khi ở tiếng Anh.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                
                SettingsGroup(title: "Ngôn ngữ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $viewModel.preferences.appLanguage) {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .onChange(of: viewModel.preferences.appLanguage) { _ in
                            viewModel.save()
                            showRestartAlert = true
                        }
                    }
                }
                .alert(String(localized: "Khởi động lại XKey?"), isPresented: $showRestartAlert) {
                    Button(String(localized: "Khởi động lại"), role: .destructive) {
                        restartApp()
                    }
                    Button(String(localized: "Để sau"), role: .cancel) {}
                } message: {
                    Text("Ngôn ngữ mới sẽ được áp dụng sau khi khởi động lại ứng dụng.")
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

    private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.1
        done
        open "\(bundlePath)"
        """
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}
