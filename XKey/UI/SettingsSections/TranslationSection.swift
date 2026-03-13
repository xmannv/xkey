//
//  TranslationSection.swift
//  XKey
//
//  Settings UI for Translation feature
//

import SwiftUI

@available(macOS 13.0, *)
struct TranslationSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @StateObject private var translationVM = TranslationSectionViewModel()
    
    // Custom language input states
    @State private var showCustomSourceInput = false
    @State private var showCustomTargetInput = false
    @State private var customSourceCode = ""
    @State private var customTargetCode = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Enable/Disable Translation
                SettingsGroup(title: "Dịch thuật") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Bật tính năng dịch thuật", isOn: $viewModel.preferences.translationEnabled)
                        
                        Text("Dịch nhanh text đang chọn hoặc toàn bộ nội dung input bằng phím tắt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if viewModel.preferences.translationEnabled {
                    // Language Settings
                    SettingsGroup(title: "Ngôn ngữ") {
                        VStack(alignment: .leading, spacing: 16) {
                            // Source Language
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Ngôn ngữ nguồn:")
                                    Spacer()
                                    
                                    Picker("", selection: Binding(
                                        get: { viewModel.preferences.translationSourceLanguageCode },
                                        set: { newCode in
                                            if newCode == "__custom__" {
                                                showCustomSourceInput = true
                                            } else {
                                                viewModel.preferences.translationSourceLanguageCode = newCode
                                            }
                                        }
                                    )) {
                                        ForEach(TranslationLanguage.sourcePresets) { lang in
                                            Text("\(lang.flag) \(lang.displayName)")
                                                .tag(lang.code)
                                        }
                                        Divider()
                                        Text("🌍 Nhập mã ngôn ngữ khác...").tag("__custom__")
                                    }
                                    .frame(width: 280)
                                }
                                
                                // Show current custom language if using one
                                if !TranslationLanguage.sourcePresets.contains(where: { $0.code == viewModel.preferences.translationSourceLanguageCode }) {
                                    HStack {
                                        Text("Đang dùng mã tùy chỉnh:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(viewModel.preferences.translationSourceLanguageCode.uppercased())
                                            .font(.caption.monospaced())
                                            .foregroundColor(.blue)
                                        Button("Đổi") {
                                            showCustomSourceInput = true
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                            
                            // Target Language
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Ngôn ngữ đích:")
                                    Spacer()
                                    
                                    Picker("", selection: Binding(
                                        get: { viewModel.preferences.translationTargetLanguageCode },
                                        set: { newCode in
                                            if newCode == "__custom__" {
                                                showCustomTargetInput = true
                                            } else {
                                                viewModel.preferences.translationTargetLanguageCode = newCode
                                            }
                                        }
                                    )) {
                                        ForEach(TranslationLanguage.targetPresets) { lang in
                                            Text("\(lang.flag) \(lang.displayName)")
                                                .tag(lang.code)
                                        }
                                        Divider()
                                        Text("🌍 Nhập mã ngôn ngữ khác...").tag("__custom__")
                                    }
                                    .frame(width: 280)
                                }
                                
                                // Show current custom language if using one
                                if !TranslationLanguage.targetPresets.contains(where: { $0.code == viewModel.preferences.translationTargetLanguageCode }) {
                                    HStack {
                                        Text("Đang dùng mã tùy chỉnh:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(viewModel.preferences.translationTargetLanguageCode.uppercased())
                                            .font(.caption.monospaced())
                                            .foregroundColor(.blue)
                                        Button("Đổi") {
                                            showCustomTargetInput = true
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                            
                            // Info about supported languages
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Hỗ trợ 130+ ngôn ngữ theo chuẩn ISO 639-1. ")
                                    .foregroundColor(.secondary)
                                Link("Xem danh sách", destination: URL(string: "https://cloud.google.com/translate/docs/languages")!)
                            }
                            .font(.caption)
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            Toggle("Hiển thị thanh công cụ dịch thuật", isOn: $viewModel.preferences.translationToolbarEnabled)
                                .onChange(of: viewModel.preferences.translationToolbarEnabled) { _ in
                                    viewModel.save()
                                    NotificationCenter.default.post(name: .translationToolbarSettingsDidChange, object: nil)
                                }
                            
                            Text("Khi focus vào ô nhập liệu, thanh công cụ nhỏ sẽ hiện ra cho phép bạn đổi ngôn ngữ nguồn/đích nhanh chóng mà không cần mở Thiết lập.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Feature 1: Translate to Target Language
                    SettingsGroup(title: "🌐 Dịch sang ngôn ngữ đích") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dịch text đang chọn từ ngôn ngữ nguồn sang ngôn ngữ đích. Nếu không chọn text, sẽ dịch toàn bộ nội dung.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Phím tắt:")
                                Spacer()
                                HotkeyRecorderView(hotkey: $viewModel.preferences.translationHotkey, minimumModifiers: 2)
                                    .frame(width: 150)
                            }
                            
                            Divider()
                            
                            TranslationDirectionOptions(
                                replaceOriginal: $viewModel.preferences.translationReplaceOriginal,
                                copyToClipboard: $viewModel.preferences.translationCopyToClipboard,
                                showPopup: $viewModel.preferences.translationShowPopup,
                                autoHideSeconds: $viewModel.preferences.translationResultAutoHideSeconds
                            )
                        }
                    }
                    
                    // Feature 2: Translate to Source Language (reverse direction)
                    SettingsGroup(title: "🔄 Dịch sang ngôn ngữ nguồn") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dịch ngược text đang chọn từ ngôn ngữ đích sang ngôn ngữ nguồn. Text gốc được giữ nguyên theo mặc định.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Phím tắt:")
                                Spacer()
                                HotkeyRecorderView(hotkey: $viewModel.preferences.translateToSourceHotkey, minimumModifiers: 2)
                                    .frame(width: 150)
                            }
                            
                            Divider()
                            
                            TranslationDirectionOptions(
                                replaceOriginal: $viewModel.preferences.translateToSourceReplaceOriginal,
                                copyToClipboard: $viewModel.preferences.translateToSourceCopyToClipboard,
                                showPopup: $viewModel.preferences.translateToSourceShowPopup,
                                autoHideSeconds: $viewModel.preferences.translateToSourceAutoHideSeconds
                            )
                        }
                    }
                    
                    // Providers Management
                    SettingsGroup(title: "Nhà cung cấp dịch") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(translationVM.providers, id: \.id) { provider in
                                ProviderRow(
                                    name: provider.name,
                                    description: provider.description,
                                    isEnabled: translationVM.isProviderEnabled(provider.id),
                                    onToggle: { enabled in
                                        translationVM.setProviderEnabled(provider.id, enabled: enabled)
                                    }
                                )
                            }
                            
                            if translationVM.providers.isEmpty {
                                Text("Không có nhà cung cấp dịch nào được cài đặt")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Test Translation
                    SettingsGroup(title: "Thử nghiệm") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Nhập text để thử dịch...", text: $translationVM.testText)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Button("Dịch thử") {
                                    translationVM.testTranslation(
                                        from: viewModel.preferences.translationSourceLanguageCode,
                                        to: viewModel.preferences.translationTargetLanguageCode
                                    )
                                }
                                .disabled(translationVM.testText.isEmpty || translationVM.isTranslating)
                                
                                if translationVM.isTranslating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                
                                Spacer()
                                
                                // Display current language pair
                                let sourceLang = TranslationLanguage.find(byCode: viewModel.preferences.translationSourceLanguageCode)
                                let targetLang = TranslationLanguage.find(byCode: viewModel.preferences.translationTargetLanguageCode)
                                Text("\(sourceLang.flag) → \(targetLang.flag)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let result = translationVM.testResult {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Kết quả:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(result)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                            
                            if let error = translationVM.testError {
                                Text("⚠️ \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        // Custom Source Language Input Sheet
        .sheet(isPresented: $showCustomSourceInput) {
            CustomLanguageInputView(
                title: "Nhập mã ngôn ngữ nguồn",
                code: $customSourceCode,
                isPresented: $showCustomSourceInput,
                onSave: { code in
                    viewModel.preferences.translationSourceLanguageCode = code.lowercased()
                }
            )
        }
        // Custom Target Language Input Sheet
        .sheet(isPresented: $showCustomTargetInput) {
            CustomLanguageInputView(
                title: "Nhập mã ngôn ngữ đích",
                code: $customTargetCode,
                isPresented: $showCustomTargetInput,
                onSave: { code in
                    viewModel.preferences.translationTargetLanguageCode = code.lowercased()
                }
            )
        }
    }
}

// MARK: - Custom Language Input View

struct CustomLanguageInputView: View {
    let title: String
    @Binding var code: String
    @Binding var isPresented: Bool
    let onSave: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Nhập mã ngôn ngữ ISO 639-1 (2 ký tự):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("VD: pt, ar, hi, bn...", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Text("Một số mã phổ biến: pt (Bồ Đào Nha), ar (Ả Rập), hi (Hindi), bn (Bengal), sw (Swahili), af (Afrikaans)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack(spacing: 16) {
                Button("Hủy") {
                    code = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Lưu") {
                    let trimmedCode = code.trimmingCharacters(in: .whitespaces).lowercased()
                    if !trimmedCode.isEmpty {
                        onSave(trimmedCode)
                    }
                    code = ""
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Translation Direction Options (reusable component)

@available(macOS 13.0, *)
private struct TranslationDirectionOptions: View {
    @Binding var replaceOriginal: Bool
    @Binding var copyToClipboard: Bool
    @Binding var showPopup: Bool
    @Binding var autoHideSeconds: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Thay thế text gốc bằng bản dịch", isOn: $replaceOriginal)
            
            Text("Text đang chọn sẽ bị thay thế bằng bản dịch trong ô nhập liệu.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Toggle("Tự động copy bản dịch vào clipboard", isOn: $copyToClipboard)
            
            Text("Bản dịch sẽ được copy vào clipboard để bạn có thể dán (paste) ở nơi khác.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Toggle("Hiển thị popup kết quả dịch", isOn: $showPopup)
            
            Text("Hiển thị bản dịch trong popup overlay — không thay đổi nội dung gốc.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if showPopup {
                HStack {
                    Text("Tự ẩn popup sau:")
                    Spacer()
                    TextField("", value: $autoHideSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                    Text("giây")
                        .foregroundStyle(.secondary)
                }
                
                Text("Bằng 0 = không tự ẩn, click bên ngoài để ẩn")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let name: String
    let description: String
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
class TranslationSectionViewModel: ObservableObject {
    @Published var testText: String = ""
    @Published var testResult: String?
    @Published var testError: String?
    @Published var isTranslating: Bool = false
    
    /// Provider list - only computed when accessed to defer memory allocation
    /// This prevents TranslationService.shared from being initialized when Settings opens
    var providers: [TranslationProvider] {
        return TranslationService.shared.sortedProviders
    }
    
    init() {
        // Do not access TranslationService.shared here!
        // Providers will be loaded lazily when the view section is displayed
    }
    
    func isProviderEnabled(_ id: String) -> Bool {
        return TranslationService.shared.isProviderEnabled(id)
    }
    
    func setProviderEnabled(_ id: String, enabled: Bool) {
        TranslationService.shared.setProviderEnabled(id, enabled: enabled)
        objectWillChange.send()
    }
    
    func testTranslation(from sourceCode: String, to targetCode: String) {
        guard !testText.isEmpty else { return }
        
        isTranslating = true
        testResult = nil
        testError = nil
        
        Task {
            do {
                let result = try await TranslationService.shared.translate(
                    text: testText,
                    from: sourceCode,
                    to: targetCode
                )
                await MainActor.run {
                    self.testResult = result.translatedText
                    self.isTranslating = false
                }
            } catch {
                await MainActor.run {
                    self.testError = error.localizedDescription
                    self.isTranslating = false
                }
            }
        }
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
#Preview {
    TranslationSection(viewModel: PreferencesViewModel())
}
