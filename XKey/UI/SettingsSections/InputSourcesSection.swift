//
//  InputSourcesSection.swift
//  XKey
//
//  Shared Input Sources Settings Section
//

import SwiftUI

struct InputSourcesSection: View {
    @ObservedObject var preferencesViewModel: PreferencesViewModel
    @StateObject private var viewModel = InputSourcesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with explanation
                SettingsGroup(title: "Quản lý Input Sources") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("XKey có thể tự động bật/tắt tính năng thêm dấu tiếng Việt dựa trên Input Source hiện tại của hệ điều hành.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Divider()

                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Input Source hiện tại:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(viewModel.currentInputSource?.displayName ?? "Unknown")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            Spacer()
                            Button("Làm mới") {
                                viewModel.refresh()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }


                
                // IMKit Mode (Experimental)
                SettingsGroup(title: "Input Method Kit (Thử nghiệm)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("XKeyIM là Input Method chạy song song với XKey, cho phép gõ tiếng Việt trong các ứng dụng có độ trễ phản hồi thấp hoặc có cơ chế autocomplete như Terminal/Spotlight/Address Bar một cách mượt mà.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Hiển thị gạch chân khi gõ (Khuyến nghị)", isOn: $preferencesViewModel.preferences.imkitUseMarkedText)

                            Text(preferencesViewModel.preferences.imkitUseMarkedText ?
                                "✓ Chuẩn IMKit - Hiển thị gạch chân khi đang gõ. Ổn định và tương thích tốt với mọi ứng dụng." :
                                "⚠️ Direct Mode - Không có gạch chân nhưng có thể gặp lỗi thêm dấu/double ký tự trong một số trường hợp trên các app khác nhau. Nếu gặp lỗi như vậy hãy bật tính năng này lên và thử lại.")
                                .font(.caption)
                                .foregroundColor(preferencesViewModel.preferences.imkitUseMarkedText ? .secondary : .orange)
                        }
                        
                        Divider()
                        
                        // Note about ESC key for undo
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Phím hoàn tác tiếng Việt")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("XKeyIM sử dụng phím ESC làm phím hoàn tác mặc định (không thể tùy chỉnh do hạn chế của Input Method Kit). Bấm ESC khi đang gõ từ có dấu tiếng Việt (\"thử\") sẽ hoàn tác thành \"thur\". Nếu từ chưa có dấu (\"thu\") hoặc không có gì để hoàn tác, ESC sẽ được gửi tới ứng dụng như bình thường.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(6)
                        
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
                                    get: { preferencesViewModel.preferences.switchToXKeyHotkey ?? Hotkey(keyCode: 0, modifiers: []) },
                                    set: { newValue in
                                        // Set to nil if empty, otherwise save the hotkey
                                        if newValue.keyCode == 0 && newValue.modifiers.isEmpty {
                                            preferencesViewModel.preferences.switchToXKeyHotkey = nil
                                        } else {
                                            preferencesViewModel.preferences.switchToXKeyHotkey = newValue
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

                // Input Sources List
                SettingsGroup(title: "Cấu hình theo Input Source") {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.inputSources.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Đang tải danh sách Input Sources...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            VStack(spacing: 8) {
                                ForEach(viewModel.inputSources) { source in
                                    InputSourceRowView(
                                        source: source,
                                        isEnabled: viewModel.isEnabled(for: source.id),
                                        isCurrent: viewModel.currentInputSource?.id == source.id
                                    ) { enabled in
                                        viewModel.setEnabled(enabled, for: source.id)
                                    }
                                }
                            }
                        }

                        Divider()
                            .padding(.top, 8)

                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Bật = XKey sẽ tự động thêm dấu tiếng Việt khi Input Source này được chọn")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Vietnamese Input Sources Detection
                if !viewModel.vietnameseInputSources.isEmpty {
                    SettingsGroup(title: "Input Sources tiếng Việt đã phát hiện") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.vietnameseInputSources) { source in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.displayName)
                                            .font(.body)
                                        Text(source.id)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }

                            Divider()

                            Text("💡 Với các Input Source tiếng Việt khác (Telex, VNI...), bạn có thể tắt XKey để tránh xung đột.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onAppear {
            viewModel.loadInputSources()
        }
    }
}

// MARK: - Input Source Row View

struct InputSourceRowView: View {
    let source: InputSourceInfo
    let isEnabled: Bool
    let isCurrent: Bool
    let onToggle: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Current indicator
            Circle()
                .fill(isCurrent ? Color.green : Color.clear)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            // Source info
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(source.id)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCurrent ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Input Sources ViewModel

class InputSourcesViewModel: ObservableObject {
    @Published var inputSources: [InputSourceInfo] = []
    @Published var currentInputSource: InputSourceInfo?

    private var manager: InputSourceManager?
    private var notificationObserver: Any?

    init() {
        // Use shared singleton - same instance as AppDelegate
        manager = InputSourceManager.shared

        // Listen for input source changes
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .inputSourceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Auto-refresh when input source changes
            self?.refresh()
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var vietnameseInputSources: [InputSourceInfo] {
        inputSources.filter { InputSourceManager.isVietnameseInputSource($0) }
    }

    func loadInputSources() {
        inputSources = InputSourceManager.getAllInputSources()
        currentInputSource = InputSourceManager.getCurrentInputSource()
    }

    func refresh() {
        loadInputSources()
    }

    func isEnabled(for inputSourceID: String) -> Bool {
        return manager?.isEnabled(for: inputSourceID) ?? true
    }

    func setEnabled(_ enabled: Bool, for inputSourceID: String) {
        manager?.setEnabled(enabled, for: inputSourceID)
        objectWillChange.send()
    }
}
