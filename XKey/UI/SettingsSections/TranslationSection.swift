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
                    // Hotkey Settings
                    SettingsGroup(title: "Phím tắt") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Dịch text đang chọn:")
                                Spacer()
                                HotkeyRecorderView(hotkey: $viewModel.preferences.translationHotkey, minimumModifiers: 2)
                                    .frame(width: 150)
                            }
                            
                            Text("Chọn text và nhấn phím tắt để dịch. Nếu không chọn text, sẽ dịch toàn bộ nội dung.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Language Settings
                    SettingsGroup(title: "Ngôn ngữ") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ngôn ngữ nguồn:")
                                Spacer()
                                Picker("", selection: $viewModel.preferences.translationSourceLanguage) {
                                    ForEach(TranslationLanguage.allCases) { lang in
                                        Text("\(lang.flag) \(lang.displayName)")
                                            .tag(lang)
                                    }
                                }
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Ngôn ngữ đích:")
                                Spacer()
                                Picker("", selection: $viewModel.preferences.translationTargetLanguage) {
                                    ForEach(TranslationLanguage.allCases.filter { $0 != .auto }) { lang in
                                        Text("\(lang.flag) \(lang.displayName)")
                                            .tag(lang)
                                    }
                                }
                                .frame(width: 200)
                            }
                            
                            Toggle("Thay thế text gốc bằng bản dịch", isOn: $viewModel.preferences.translationReplaceOriginal)
                            
                            if !viewModel.preferences.translationReplaceOriginal {
                                Text("Bản dịch sẽ được copy vào clipboard")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                        from: viewModel.preferences.translationSourceLanguage,
                                        to: viewModel.preferences.translationTargetLanguage
                                    )
                                }
                                .disabled(translationVM.testText.isEmpty || translationVM.isTranslating)
                                
                                if translationVM.isTranslating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                
                                Spacer()
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
    @Published var providers: [TranslationProvider] = []
    @Published var testText: String = ""
    @Published var testResult: String?
    @Published var testError: String?
    @Published var isTranslating: Bool = false
    
    private let service = TranslationService.shared
    
    init() {
        providers = service.sortedProviders
    }
    
    func isProviderEnabled(_ id: String) -> Bool {
        return service.isProviderEnabled(id)
    }
    
    func setProviderEnabled(_ id: String, enabled: Bool) {
        service.setProviderEnabled(id, enabled: enabled)
        objectWillChange.send()
    }
    
    func testTranslation(from source: TranslationLanguage, to target: TranslationLanguage) {
        guard !testText.isEmpty else { return }
        
        isTranslating = true
        testResult = nil
        testError = nil
        
        Task {
            do {
                let result = try await service.translate(
                    text: testText,
                    from: source,
                    to: target
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
