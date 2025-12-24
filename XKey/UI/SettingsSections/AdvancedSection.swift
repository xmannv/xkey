//
//  AdvancedSection.swift
//  XKey
//
//  Shared Advanced Settings Section
//

import SwiftUI

struct AdvancedSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    
    // State properties for dictionary section (moved from SpellCheckSection)
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var showDownloadSuccess = false
    
    // State properties for user dictionary section
    @State private var newUserWord = ""
    @State private var userDictionaryWords: [String] = []
    @State private var showUserDictionaryList = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Chính tả & Viết hoa") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Kiểm tra chính tả", isOn: $viewModel.preferences.spellCheckEnabled)
                            .onChange(of: viewModel.preferences.spellCheckEnabled) { newValue in
                                if newValue {
                                    // Auto-load dictionary if available
                                    VNDictionaryManager.shared.loadIfAvailable()
                                } else {
                                    // Cascade disable: turn off child settings when spell check is disabled
                                    viewModel.preferences.restoreIfWrongSpelling = false
                                    viewModel.preferences.instantRestoreOnWrongSpelling = false
                                }
                            }
                        
                        // Sub-options for spell check (only visible when spell check is enabled)
                        if viewModel.preferences.spellCheckEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Khôi phục nếu sai chính tả (Thử nghiệm)", isOn: $viewModel.preferences.restoreIfWrongSpelling)
                                    .padding(.leading, 20)
                                    .onChange(of: viewModel.preferences.restoreIfWrongSpelling) { newValue in
                                        if !newValue {
                                            // Cascade disable: turn off instant restore when restore is disabled
                                            viewModel.preferences.instantRestoreOnWrongSpelling = false
                                        }
                                    }
                                
                                if viewModel.preferences.restoreIfWrongSpelling {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Toggle("Khôi phục ngay lập tức", isOn: $viewModel.preferences.instantRestoreOnWrongSpelling)
                                            .padding(.leading, 40)
                                        
                                        Text("Nếu bật: Restore ngay khi thêm dấu không hợp lệ, có thể sẽ gây lỗi từ Tiếng Việt hợp lệ không mong muốn. Nếu tắt: Chờ nhấn Space để restore.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 40)
                                    }
                                }
                            }
                        }
                        
                        Toggle("Tự động viết hoa chữ đầu câu", isOn: $viewModel.preferences.upperCaseFirstChar)
                        Toggle("Cho phép phụ âm Z, F, W, J", isOn: $viewModel.preferences.allowConsonantZFWJ)
                        
                        // Dictionary options (only shown when spell check is enabled)
                        if viewModel.preferences.spellCheckEnabled {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 10) {
                                // Auto-select dictionary based on modernStyle
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                    Text("Bộ từ điển: \(viewModel.preferences.modernStyle ? "Dấu mới (xoà)" : "Dấu cũ (xóa)")")
                                        .font(.caption)
                                    Text("- tự động theo kiểu gõ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                                
                                // Dictionary status
                                dictionaryStatusView
                                
                                // Download section (only when not loaded)
                                if !isDictionaryLoaded {
                                    downloadSection
                                }
                                
                                // License info (always visible)
                                dictionaryInfoView
                                
                                // Info text
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Từ điển chứa các từ đơn tiếng Việt.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Từ điển được chia sẻ giữa XKey và XKeyIM.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                                
                                // User Dictionary section
                                userDictionarySection
                            }
                            .padding(.leading, 20)
                        }
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
                    VStack(alignment: .leading, spacing: 12) {
                        // Main Smart Switch toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Nhớ ngôn ngữ theo ứng dụng", isOn: $viewModel.preferences.smartSwitchEnabled)

                            Text("Tự động chuyển ngôn ngữ khi chuyển app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Overlay app detection (sub-option, only shown when Smart Switch is enabled)
                        if viewModel.preferences.smartSwitchEnabled {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Hỗ trợ phát hiện Spotlight/Raycast/Alfred", isOn: $viewModel.preferences.detectOverlayApps)

                                // Info message
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Tránh ghi đè ngôn ngữ của app bên dưới khi bạn toggle trong Spotlight/Raycast")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.05))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.leading, 20)  // Indent sub-option
                        }
                    }
                }
                
                // Window Title Rules
                SettingsGroup(title: "Hiệu chỉnh XKey Engine theo ứng dụng") {
                    if #available(macOS 13.0, *) {
                        WindowTitleRulesView()
                    } else {
                        Text("Tính năng này yêu cầu macOS 13.0 trở lên")
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
                
                // IMKit Mode (Experimental)
                SettingsGroup(title: "Input Method Kit (Thử nghiệm)") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Bật IMKit Mode", isOn: $viewModel.preferences.imkitEnabled)

                            Text("Sử dụng Input Method Kit thay vì CGEvent injection. Giúp gõ mượt hơn trong Terminal app và IDE Terminal.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if viewModel.preferences.imkitEnabled {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Hiển thị gạch chân khi gõ (Khuyến nghị)", isOn: $viewModel.preferences.imkitUseMarkedText)
                                    .padding(.leading, 20)

                                Text(viewModel.preferences.imkitUseMarkedText ?
                                    "✓ Chuẩn IMKit - Hiển thị gạch chân khi đang gõ. Ổn định và tương thích tốt với mọi ứng dụng." :
                                    "⚠️ Direct Mode - Không có gạch chân nhưng có thể gặp lỗi thêm dấu/double ký tự trong một số trường hợp trên các app khác nhau. Nếu gặp lỗi như vậy hãy bật tính năng này lên và thử lại.")
                                    .font(.caption)
                                    .foregroundColor(viewModel.preferences.imkitUseMarkedText ? .secondary : .orange)
                                    .padding(.leading, 20)
                            }
                            
                            Divider()
                            
                            // Install XKeyIM button
                            HStack {
                                Text("XKeyIM Input Method:")
                                    .font(.caption)
                                Spacer()
                                Button("Cài đặt XKeyIM...") {
                                    IMKitHelper.installXKeyIM()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("Sau khi cài đặt, vào System Settings → Keyboard → Input Sources để thêm XKey Vietnamese")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Divider()
                            
                            // Quick switch hotkey
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Phím tắt chuyển nhanh sang XKey:")
                                        .font(.caption)
                                    Spacer()
                                    // Use custom binding for optional hotkey
                                    HotkeyRecorderView(hotkey: Binding(
                                        get: { viewModel.preferences.switchToXKeyHotkey ?? Hotkey(keyCode: 0, modifiers: []) },
                                        set: { newValue in
                                            // Set to nil if empty, otherwise save the hotkey
                                            if newValue.keyCode == 0 && newValue.modifiers.isEmpty {
                                                viewModel.preferences.switchToXKeyHotkey = nil
                                            } else {
                                                viewModel.preferences.switchToXKeyHotkey = newValue
                                            }
                                        }
                                    ))
                                        .frame(width: 150)
                                }
                                
                                Text("Phím tắt này sẽ toggle giữa XKey và ABC. Nếu đang dùng XKey → chuyển sang ABC (hoặc bộ gõ tiếng Anh khác), ngược lại → XKey")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                // Quick switch button
                                HStack {
                                    Button("Chuyển sang XKey ngay") {
                                        InputSourceSwitcher.shared.switchToXKey()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
    
    // MARK: - Dictionary Status View (moved from SpellCheckSection)
    
    private var dictionaryStatusView: some View {
        HStack(spacing: 8) {
            Image(systemName: isDictionaryLoaded ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isDictionaryLoaded ? .green : .secondary)

            if isDictionaryLoaded {
                Text("Đã tải từ điển (\(wordCount) từ)")
                    .font(.caption)
            } else if isDictionaryAvailable {
                Text("Từ điển đã tải về nhưng chưa được nạp")
                    .font(.caption)

                Button("Nạp") {
                    try? VNDictionaryManager.shared.loadDictionary()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Chưa tải từ điển")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Download Section (moved from SpellCheckSection)
    
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = downloadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if showDownloadSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Tải từ điển thành công!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Download button
            HStack(spacing: 8) {
                Button(action: downloadDictionary) {
                    HStack {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isDownloading ? "Đang tải..." : "Tải từ điển (~200KB)")
                    }
                }
                .disabled(isDownloading)
                .buttonStyle(.borderedProminent)
            }
            
            Text("Bấm \"Tải từ điển\" đồng nghĩa bạn đồng ý với giấy phép GPL.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    // MARK: - Dictionary Info View (always visible)
    
    private var dictionaryInfoView: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("• Nguồn: hunspell-vi by Minh Nguyen")
                Text("• License: GPL (GNU General Public License)")
                Text("• Một dự án mã nguồn mở")
                
                HStack(spacing: 4) {
                    Text("📎")
                    Link("github.com/1ec5/hunspell-vi", destination: URL(string: "https://github.com/1ec5/hunspell-vi")!)
                }
                .padding(.top, 4)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text("Thông tin license từ điển")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - User Dictionary Section
    
    private var userDictionarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.blue)
                Text("Từ điển cá nhân")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Text("Thêm các từ bạn muốn bỏ qua kiểm tra chính tả")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Add new word form
            HStack(spacing: 8) {
                TextField("Nhập từ mới...", text: $newUserWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 200)
                    .onChange(of: newUserWord) { newValue in
                        // Remove spaces - only single words allowed
                        let filtered = newValue.replacingOccurrences(of: " ", with: "")
                        if filtered != newValue {
                            newUserWord = filtered
                        }
                    }
                    .onSubmit {
                        addUserWord()
                    }
                
                Button(action: addUserWord) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newUserWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            // Word count and toggle list
            HStack {
                Text("\(userDictionaryWords.count) từ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !userDictionaryWords.isEmpty {
                    Button(showUserDictionaryList ? "Ẩn danh sách" : "Xem danh sách") {
                        withAnimation {
                            showUserDictionaryList.toggle()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            
            // Word list (expandable)
            if showUserDictionaryList && !userDictionaryWords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(userDictionaryWords.sorted(), id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(.caption)
                            
                            Spacer()
                            
                            Button(action: {
                                removeUserWord(word)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            loadUserDictionaryWords()
        }
    }

    // MARK: - Computed Properties (moved from SpellCheckSection)
    
    private var isDictionaryLoaded: Bool {
        VNDictionaryManager.shared.isDictionaryLoaded(
            style: viewModel.preferences.modernStyle ? .dauMoi : .dauCu
        )
    }

    private var isDictionaryAvailable: Bool {
        VNDictionaryManager.shared.isDictionaryAvailable(
            style: viewModel.preferences.modernStyle ? .dauMoi : .dauCu
        )
    }

    private var wordCount: Int {
        let stats = VNDictionaryManager.shared.getDictionaryStats()
        let key = viewModel.preferences.modernStyle ? "DauMoi" : "DauCu"
        return stats[key] ?? 0
    }

    // MARK: - Actions (moved from SpellCheckSection)
    
    private func downloadDictionary() {
        isDownloading = true
        downloadError = nil
        showDownloadSuccess = false

        let style: VNDictionaryManager.DictionaryStyle = viewModel.preferences.modernStyle ? .dauMoi : .dauCu

        VNDictionaryManager.shared.downloadAndLoad(style: style) { result in
            DispatchQueue.main.async {
                isDownloading = false

                switch result {
                case .success:
                    showDownloadSuccess = true
                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showDownloadSuccess = false
                    }
                case .failure(let error):
                    downloadError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - User Dictionary Actions
    
    private func loadUserDictionaryWords() {
        userDictionaryWords = Array(SharedSettings.shared.getUserDictionaryWords())
    }
    
    private func addUserWord() {
        let word = newUserWord.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty else { return }
        
        SharedSettings.shared.addUserDictionaryWord(word)
        loadUserDictionaryWords()
        newUserWord = ""
    }
    
    private func removeUserWord(_ word: String) {
        SharedSettings.shared.removeUserDictionaryWord(word)
        loadUserDictionaryWords()
    }
}
