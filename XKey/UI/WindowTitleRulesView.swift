//
//  WindowTitleRulesView.swift
//  XKey
//
//  View for managing Window Title Rules
//  Allows viewing built-in rules and creating custom rules for context-specific behavior
//

import SwiftUI

// MARK: - Window Title Rules View

@available(macOS 13.0, *)
struct WindowTitleRulesView: View {
    @StateObject private var viewModel = WindowTitleRulesViewModel()
    @State private var showAddRule = false
    @State private var editingRule: WindowTitleRule?
    @State private var showBuiltInRules = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quy tắc theo Window Title")
                        .font(.headline)
                    Text("Cho phép xử lý đặc biệt dựa trên tiêu đề cửa sổ (ví dụ: Google Docs trong Safari)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showAddRule = true }) {
                    Label("Thêm quy tắc", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Divider()
            
            // Current detection info
            if viewModel.isDetectionAvailable {
                CurrentDetectionInfoView(viewModel: viewModel)
            }
            
            // Custom Rules
            GroupBox(label: Label("Quy tắc tùy chỉnh (\(viewModel.customRules.count))", systemImage: "person.crop.circle.badge.plus")) {
                if viewModel.customRules.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Chưa có quy tắc tùy chỉnh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Nhấn \"Thêm quy tắc\" để tạo mới")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.customRules) { rule in
                            RuleRowView(rule: rule, isBuiltIn: false) {
                                editingRule = rule
                            } onDelete: {
                                viewModel.deleteRule(rule)
                            } onToggle: { enabled in
                                viewModel.toggleRule(rule, enabled: enabled)
                            }
                        }
                    }
                }
            }
            
            // Built-in Rules (Collapsible)
            DisclosureGroup(
                isExpanded: $showBuiltInRules,
                content: {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.builtInRules) { rule in
                            RuleRowView(rule: rule, isBuiltIn: true, onEdit: nil, onDelete: nil, onToggle: nil)
                        }
                    }
                    .padding(.top, 8)
                },
                label: {
                    Label("Quy tắc mặc định (\(viewModel.builtInRules.count))", systemImage: "building.2.crop.circle")
                        .font(.subheadline)
                }
            )
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showAddRule) {
            AddRuleSheet(viewModel: viewModel, existingRule: nil)
        }
        .sheet(item: $editingRule) { rule in
            AddRuleSheet(viewModel: viewModel, existingRule: rule)
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

// MARK: - Current Detection Info

@available(macOS 13.0, *)
struct CurrentDetectionInfoView: View {
    @ObservedObject var viewModel: WindowTitleRulesViewModel
    
    var body: some View {
        GroupBox(label: Label("Phát hiện hiện tại", systemImage: "eye")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("App:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(viewModel.currentAppName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Bundle ID:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(viewModel.currentBundleId.isEmpty ? "(không có)" : viewModel.currentBundleId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            if !viewModel.currentBundleId.isEmpty {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(viewModel.currentBundleId, forType: .string)
                            }
                        }
                        .help("Click để copy Bundle ID")
                }
                
                HStack {
                    Text("Window Title:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(viewModel.currentWindowTitle.isEmpty ? "(không có)" : viewModel.currentWindowTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if let ruleName = viewModel.matchedRuleName {
                    HStack {
                        Text("Rule Match:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(ruleName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Button("Làm mới") {
                    viewModel.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Rule Row View

@available(macOS 13.0, *)
struct RuleRowView: View {
    let rule: WindowTitleRule
    let isBuiltIn: Bool
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggle: ((Bool) -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(rule.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            // Rule info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isBuiltIn {
                        Text("Mặc định")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Text("Pattern:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if rule.titlePattern.isEmpty {
                        Text("(Tất cả windows)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    } else {
                        Text("\"\(rule.titlePattern)\"")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        Text("(\(rule.matchMode.rawValue))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Behavior badges
            HStack(spacing: 4) {
                if rule.useMarkedText == false {
                    BehaviorBadge(text: "No Mark", color: .orange)
                }
                if let method = rule.injectionMethod {
                    BehaviorBadge(text: methodString(method), color: .purple)
                }
                if let textMethod = rule.textSendingMethod {
                    BehaviorBadge(text: textMethod == .oneByOne ? "1-by-1" : "Chunk", color: .cyan)
                }
            }
            
            // Actions (only for custom rules)
            if !isBuiltIn {
                HStack(spacing: 8) {
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                    
                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                .opacity(isHovered ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.gray.opacity(0.03))
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func methodString(_ method: InjectionMethod) -> String {
        switch method {
        case .fast: return "Fast"
        case .slow: return "Slow"
        case .selection: return "Select"
        case .autocomplete: return "Auto"
        }
    }
}

@available(macOS 13.0, *)
struct BehaviorBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Add/Edit Rule Sheet

@available(macOS 13.0, *)
struct AddRuleSheet: View {
    @ObservedObject var viewModel: WindowTitleRulesViewModel
    let existingRule: WindowTitleRule?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var bundleIdPattern: String = "*"
    @State private var titlePattern: String = ""
    @State private var matchMode: WindowTitleMatchMode = .contains
    @State private var useMarkedText: Bool = true
    @State private var overrideMarkedText: Bool = false
    @State private var hasMarkedTextIssues: Bool = false
    @State private var commitDelay: String = ""
    @State private var injectionMethod: InjectionMethod = .fast
    @State private var overrideInjection: Bool = false
    @State private var overrideDelays: Bool = false
    @State private var backspaceDelay: String = "1000"
    @State private var waitDelay: String = "3000"
    @State private var textDelay: String = "1500"
    @State private var textSendingMethod: TextSendingMethod = .chunked
    @State private var description: String = ""
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAppPicker = false
    
    var isEditing: Bool { existingRule != nil }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(isEditing ? "Sửa quy tắc" : "Thêm quy tắc mới")
                .font(.headline)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info
                    GroupBox(label: Label("Thông tin cơ bản", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Tên:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("VD: Google Docs", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack {
                                Text("Bundle ID:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("* = tất cả apps", text: $bundleIdPattern)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: { showAppPicker = true }) {
                                    Label("Chọn app", systemImage: "apps.iphone")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("Ví dụ: com.apple.Safari hoặc * để match tất cả")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    GroupBox(label: Label("Pattern matching", systemImage: "text.magnifyingglass")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Title Pattern:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("VD: Google Docs (để trống = tất cả)", text: $titlePattern)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Text("💡 Để trống Title Pattern để áp dụng cho tất cả windows của app")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            HStack {
                                Text("Match mode:")
                                    .frame(width: 100, alignment: .leading)
                                Picker("", selection: $matchMode) {
                                    ForEach(WindowTitleMatchMode.allCases, id: \.self) { mode in
                                        Text(matchModeDisplayName(mode)).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                                .disabled(titlePattern.isEmpty)  // Disable when pattern is empty
                            }
                            
                            if !titlePattern.isEmpty {
                                Text(matchModeDescription(matchMode))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Behavior Overrides
                    GroupBox(label: Label("Ghi đè behavior", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Marked text override
                            Toggle("Ghi đè Marked Text", isOn: $overrideMarkedText)
                            
                            if overrideMarkedText {
                                HStack {
                                    Toggle("Sử dụng Marked Text (gạch chân)", isOn: $useMarkedText)
                                }
                                .padding(.leading, 20)
                                
                                Toggle("Có vấn đề với Marked Text", isOn: $hasMarkedTextIssues)
                                    .padding(.leading, 20)
                            }
                            
                            Divider()
                            
                            // Injection method override
                            Toggle("Ghi đè Injection Method", isOn: $overrideInjection)
                            
                            if overrideInjection {
                                Picker("Method:", selection: $injectionMethod) {
                                    Text("Fast").tag(InjectionMethod.fast)
                                    Text("Slow").tag(InjectionMethod.slow)
                                    Text("Selection").tag(InjectionMethod.selection)
                                    Text("Autocomplete").tag(InjectionMethod.autocomplete)
                                }
                                .frame(width: 200)
                                .padding(.leading, 20)
                                
                                // Injection delays (inside overrideInjection)
                                Toggle("Tùy chỉnh Injection Delays", isOn: $overrideDelays)
                                    .padding(.leading, 20)
                                    .padding(.top, 8)
                                
                                if overrideDelays {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Backspace (µs):")
                                                .frame(width: 100, alignment: .leading)
                                                .font(.caption)
                                            TextField("1000", text: $backspaceDelay)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 80)
                                            Text("Delay sau mỗi backspace")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack {
                                            Text("Wait (µs):")
                                                .frame(width: 100, alignment: .leading)
                                                .font(.caption)
                                            TextField("3000", text: $waitDelay)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 80)
                                            Text("Delay sau tất cả backspaces")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack {
                                            Text("Text (µs):")
                                                .frame(width: 100, alignment: .leading)
                                                .font(.caption)
                                            TextField("1500", text: $textDelay)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 80)
                                            Text("Delay giữa các ký tự")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.leading, 40)
                                    .padding(.top, 4)
                                }
                                
                                // Text Sending Method
                                Divider()
                                    .padding(.leading, 20)
                                    .padding(.vertical, 4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Picker("Phương thức gửi text:", selection: $textSendingMethod) {
                                        ForEach(TextSendingMethod.allCases, id: \.self) { method in
                                            Text(method.displayName).tag(method)
                                        }
                                    }
                                    .frame(width: 300)
                                    .padding(.leading, 20)
                                    
                                    Text(textSendingMethod.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 20)
                                }
                            }
                            
                            Divider()
                            
                            // Commit delay
                            HStack {
                                Text("Commit Delay (µs):")
                                    .frame(width: 120, alignment: .leading)
                                TextField("VD: 5000", text: $commitDelay)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("(để trống = mặc định)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Description
                    GroupBox(label: Label("Ghi chú", systemImage: "text.alignleft")) {
                        TextField("Mô tả (tùy chọn)", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Hủy") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(isEditing ? "Lưu" : "Thêm") {
                    saveRule()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)  // Only name is required, titlePattern can be empty
            }
        }
        .padding()
        .frame(width: 520, height: 720)
        .onAppear {
            if let rule = existingRule {
                loadExistingRule(rule)
            }
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView { selectedApp in
                // Fill in the bundle ID
                bundleIdPattern = selectedApp.bundleIdentifier
                // If name is empty, use app name as suggestion
                if name.isEmpty {
                    name = selectedApp.appName
                }
            }
        }
    }
    
    private func loadExistingRule(_ rule: WindowTitleRule) {
        name = rule.name
        bundleIdPattern = rule.bundleIdPattern
        titlePattern = rule.titlePattern
        matchMode = rule.matchMode
        description = rule.description ?? ""
        
        if let useMarked = rule.useMarkedText {
            overrideMarkedText = true
            useMarkedText = useMarked
        }
        if let hasIssues = rule.hasMarkedTextIssues {
            hasMarkedTextIssues = hasIssues
        }
        if let delay = rule.commitDelay {
            commitDelay = String(delay)
        }
        if let method = rule.injectionMethod {
            overrideInjection = true
            injectionMethod = method
        }
        if let delays = rule.injectionDelays, delays.count >= 3 {
            overrideDelays = true
            backspaceDelay = String(delays[0])
            waitDelay = String(delays[1])
            textDelay = String(delays[2])
        }
        if let textMethod = rule.textSendingMethod {
            textSendingMethod = textMethod
        }
    }
    
    private func saveRule() {
        guard !name.isEmpty else {
            showErrorMessage("Vui lòng nhập tên quy tắc")
            return
        }
        // Note: titlePattern can be empty (means match all windows of the app)
        
        // Build injection delays array if overriding
        var injectionDelaysArray: [UInt32]? = nil
        if overrideInjection && overrideDelays {
            let bs = UInt32(backspaceDelay) ?? 1000
            let wait = UInt32(waitDelay) ?? 3000
            let txt = UInt32(textDelay) ?? 1500
            injectionDelaysArray = [bs, wait, txt]
        }
        
        let rule = WindowTitleRule(
            name: name,
            bundleIdPattern: bundleIdPattern,
            titlePattern: titlePattern,
            matchMode: matchMode,
            isEnabled: true,
            useMarkedText: overrideMarkedText ? useMarkedText : nil,
            hasMarkedTextIssues: overrideMarkedText ? hasMarkedTextIssues : nil,
            commitDelay: UInt32(commitDelay) ?? nil as UInt32?,
            injectionMethod: overrideInjection ? injectionMethod : nil,
            injectionDelays: injectionDelaysArray,
            textSendingMethod: overrideInjection ? textSendingMethod : nil,
            description: description.isEmpty ? nil : description
        )
        
        if isEditing {
            viewModel.updateRule(rule, originalId: existingRule?.id)
        } else {
            viewModel.addRule(rule)
        }
        
        dismiss()
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showError = false
        }
    }
    
    private func matchModeDisplayName(_ mode: WindowTitleMatchMode) -> String {
        switch mode {
        case .contains: return "Chứa"
        case .prefix: return "Bắt đầu bằng"
        case .suffix: return "Kết thúc bằng"
        case .exact: return "Khớp chính xác"
        case .regex: return "Regex"
        }
    }
    
    private func matchModeDescription(_ mode: WindowTitleMatchMode) -> String {
        switch mode {
        case .contains: return "Title cửa sổ chứa pattern (không phân biệt hoa/thường)"
        case .prefix: return "Title cửa sổ bắt đầu bằng pattern"
        case .suffix: return "Title cửa sổ kết thúc bằng pattern"
        case .exact: return "Title cửa sổ khớp chính xác với pattern"
        case .regex: return "Pattern là biểu thức Regular Expression"
        }
    }
}

// MARK: - View Model

@available(macOS 13.0, *)
class WindowTitleRulesViewModel: ObservableObject {
    @Published var customRules: [WindowTitleRule] = []
    @Published var builtInRules: [WindowTitleRule] = []
    @Published var currentAppName = ""
    @Published var currentBundleId = ""
    @Published var currentWindowTitle = ""
    @Published var matchedRuleName: String?
    
    /// Observer for app activation changes
    private var appActivationObserver: NSObjectProtocol?
    
    var isDetectionAvailable: Bool {
        !currentAppName.isEmpty
    }
    
    init() {
        refresh()
        setupAppActivationObserver()
    }
    
    deinit {
        // Remove observer when ViewModel is deallocated
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    /// Setup observer to detect when user switches to another app
    private func setupAppActivationObserver() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Small delay to let the system fully switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.refreshDetectionOnly()
            }
        }
    }
    
    /// Refresh only detection info (not rules) - called on app switch
    private func refreshDetectionOnly() {
        let detector = AppBehaviorDetector.shared
        detector.clearCache()
        
        if let bundleId = detector.getCurrentBundleId() {
            let isXKey = bundleId == "com.codetay.XKey" || bundleId == "com.codetay.XKey.debug"
            
            if !isXKey {
                currentAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleId
                currentBundleId = bundleId
                currentWindowTitle = detector.getCachedWindowTitle()
                matchedRuleName = detector.findMatchingRule()?.name
            }
        }
    }
    
    func refresh() {
        let detector = AppBehaviorDetector.shared
        
        // Clear cache to get fresh data
        detector.clearCache()
        
        // Load rules
        customRules = detector.getCustomRules()
        builtInRules = detector.getBuiltInRules()
        
        // Get current detection
        // Skip updating if current app is XKey itself (user is viewing settings)
        // This keeps the previously detected app info visible
        if let bundleId = detector.getCurrentBundleId() {
            let isXKey = bundleId == "com.codetay.XKey" || bundleId == "com.codetay.XKey.debug"
            
            if !isXKey {
                // Only update when not XKey
                currentAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundleId
                currentBundleId = bundleId
                currentWindowTitle = detector.getCachedWindowTitle()
                matchedRuleName = detector.findMatchingRule()?.name
            }
            // If XKey, keep previous values (don't update)
        } else if currentAppName.isEmpty {
            // First time, no previous value
            currentAppName = ""
            currentBundleId = ""
            currentWindowTitle = ""
            matchedRuleName = nil
        }
    }
    
    func addRule(_ rule: WindowTitleRule) {
        AppBehaviorDetector.shared.addCustomRule(rule)
        refresh()
    }
    
    func updateRule(_ rule: WindowTitleRule, originalId: UUID?) {
        if let id = originalId {
            // Create new rule with original ID
            var updatedRule = rule
            // Update the rule (need to delete and re-add since ID is immutable)
            AppBehaviorDetector.shared.removeCustomRule(id: id)
            AppBehaviorDetector.shared.addCustomRule(rule)
        }
        refresh()
    }
    
    func deleteRule(_ rule: WindowTitleRule) {
        AppBehaviorDetector.shared.removeCustomRule(id: rule.id)
        refresh()
    }
    
    func toggleRule(_ rule: WindowTitleRule, enabled: Bool) {
        var updatedRule = rule
        updatedRule.isEnabled = enabled
        AppBehaviorDetector.shared.updateCustomRule(updatedRule)
        refresh()
    }
}
