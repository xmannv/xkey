//
//  WindowTitleRulesView.swift
//  XKey
//
//  View for managing Window Title Rules
//  Allows viewing built-in rules and creating custom rules for context-specific behavior
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Rules Document for FileExporter

struct RulesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var rules: [WindowTitleRule]
    
    init(rules: [WindowTitleRule]) {
        self.rules = rules
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        rules = try JSONDecoder().decode([WindowTitleRule].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        return .init(regularFileWithContents: data)
    }
}

// MARK: - Pre-fill Info for Quick Add

struct DetectedAppInfo: Identifiable {
    let id = UUID()
    var appName: String
    var bundleId: String
    var windowTitle: String
}

// MARK: - Window Title Rules View

@available(macOS 13.0, *)
struct WindowTitleRulesView: View {
    @StateObject private var viewModel = WindowTitleRulesViewModel()
    @State private var showAddRule = false
    @State private var editingRule: WindowTitleRule?
    @State private var quickAddInfo: DetectedAppInfo?
    @State private var showBuiltInRules = false
    
    // Import/Export states
    @State private var showImportSheet = false
    @State private var showExportSheet = false
    @State private var exportDocument: RulesDocument?
    @State private var showImportAlert = false
    @State private var importAlertMessage = ""
    @State private var importAlertIsError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cho phép hiệu chỉnh XKey Engine xử lý Tiếng Việt theo từng ứng dụng cụ thể (ví dụ: Google Docs trong Safari)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Import/Export buttons
                HStack(spacing: 8) {
                    Button(action: { showImportSheet = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { prepareExport() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.customRules.isEmpty)
                    
                    Button(action: { showAddRule = true }) {
                        Label("Thêm quy tắc", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Current detection info
            if viewModel.isDetectionAvailable {
                CurrentDetectionInfoView(viewModel: viewModel) {
                    // Quick add callback - pre-fill detected info
                    quickAddInfo = DetectedAppInfo(
                        appName: viewModel.currentAppName,
                        bundleId: viewModel.currentBundleId,
                        windowTitle: viewModel.currentWindowTitle
                    )
                }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("💡 Kéo thả để sắp xếp thứ tự. Rules phía dưới sẽ override rules phía trên.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.bottom, 4)
                        
                        List {
                            ForEach(viewModel.customRules) { rule in
                                RuleRowView(rule: rule, isBuiltIn: false) {
                                    editingRule = rule
                                } onDelete: {
                                    viewModel.deleteRule(rule)
                                } onToggle: { enabled in
                                    viewModel.toggleRule(rule, enabled: enabled)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onMove { source, destination in
                                viewModel.moveRules(from: source, to: destination)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: max(80, CGFloat(viewModel.customRules.count) * 70), maxHeight: 400)
                    }
                }
            }
            
            // Built-in Rules (Collapsible)
            DisclosureGroup(
                isExpanded: $showBuiltInRules,
                content: {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.builtInRules) { rule in
                            RuleRowView(rule: rule, isBuiltIn: true, onEdit: nil, onDelete: nil) { enabled in
                                viewModel.toggleBuiltInRule(rule, enabled: enabled)
                            }
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
            AddRuleSheet(viewModel: viewModel, existingRule: nil, prefillInfo: nil)
        }
        .sheet(item: $editingRule) { rule in
            AddRuleSheet(viewModel: viewModel, existingRule: rule, prefillInfo: nil)
        }
        .sheet(item: $quickAddInfo) { prefill in
            AddRuleSheet(viewModel: viewModel, existingRule: nil, prefillInfo: prefill)
        }
        .fileImporter(
            isPresented: $showImportSheet,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showExportSheet,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "xkey_window_rules.json"
        ) { result in
            handleExportResult(result)
        }
        .alert(importAlertIsError ? "Lỗi" : "Thành công", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importAlertMessage)
        }
        .onAppear {
            viewModel.refresh()
        }
    }
    
    // MARK: - Import/Export Methods
    
    private func prepareExport() {
        let rules = viewModel.customRules
        guard !rules.isEmpty else { return }
        
        exportDocument = RulesDocument(rules: rules)
        showExportSheet = true
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(_):
            importAlertMessage = "Đã xuất \(viewModel.customRules.count) quy tắc thành công"
            importAlertIsError = false
            showImportAlert = true
        case .failure(let error):
            // User cancelled - don't show error
            if (error as NSError).code == NSUserCancelledError {
                return
            }
            importAlertMessage = "Lỗi khi lưu file: \(error.localizedDescription)"
            importAlertIsError = true
            showImportAlert = true
        }
        exportDocument = nil
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importRules(from: url)
        case .failure(let error):
            importAlertMessage = "Lỗi khi chọn file: \(error.localizedDescription)"
            importAlertIsError = true
            showImportAlert = true
        }
    }
    
    private func importRules(from url: URL) {
        do {
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                importAlertMessage = "Không có quyền truy cập file"
                importAlertIsError = true
                showImportAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let importedRules = try decoder.decode([WindowTitleRule].self, from: data)
            
            guard !importedRules.isEmpty else {
                importAlertMessage = "File không chứa quy tắc nào"
                importAlertIsError = true
                showImportAlert = true
                return
            }
            
            // Add imported rules (with new UUIDs to avoid conflicts)
            var importedCount = 0
            for rule in importedRules {
                // Create new rule with fresh UUID
                let newRule = WindowTitleRule(
                    name: rule.name,
                    bundleIdPattern: rule.bundleIdPattern,
                    titlePattern: rule.titlePattern,
                    matchMode: rule.matchMode,
                    isEnabled: rule.isEnabled,
                    // AX matching patterns
                    axRolePattern: rule.axRolePattern,
                    axDescriptionPattern: rule.axDescriptionPattern,
                    axIdentifierPattern: rule.axIdentifierPattern,
                    axDOMClassList: rule.axDOMClassList,
                    // Behavior overrides
                    useMarkedText: rule.useMarkedText,
                    hasMarkedTextIssues: rule.hasMarkedTextIssues,
                    commitDelay: rule.commitDelay,
                    injectionMethod: rule.injectionMethod,
                    injectionDelays: rule.injectionDelays,
                    textSendingMethod: rule.textSendingMethod,
                    enableForceAccessibility: rule.enableForceAccessibility,
                    targetInputSourceId: rule.targetInputSourceId,
                    description: rule.description
                )
                viewModel.addRule(newRule)
                importedCount += 1
            }
            
            importAlertMessage = "Đã import \(importedCount) quy tắc thành công"
            importAlertIsError = false
            showImportAlert = true
            
        } catch let decodingError as DecodingError {
            var errorDetail = "Lỗi định dạng JSON"
            switch decodingError {
            case .keyNotFound(let key, _):
                errorDetail = "Thiếu trường: \(key.stringValue)"
            case .typeMismatch(let type, let context):
                errorDetail = "Sai kiểu dữ liệu cho \(context.codingPath.last?.stringValue ?? "unknown"): cần \(type)"
            case .valueNotFound(_, let context):
                errorDetail = "Thiếu giá trị: \(context.codingPath.last?.stringValue ?? "unknown")"
            case .dataCorrupted(let context):
                errorDetail = "Dữ liệu bị lỗi: \(context.debugDescription)"
            @unknown default:
                errorDetail = decodingError.localizedDescription
            }
            importAlertMessage = errorDetail
            importAlertIsError = true
            showImportAlert = true
        } catch {
            importAlertMessage = "Lỗi: \(error.localizedDescription)"
            importAlertIsError = true
            showImportAlert = true
        }
    }
}

// MARK: - Current Detection Info

@available(macOS 13.0, *)
struct CurrentDetectionInfoView: View {
    @ObservedObject var viewModel: WindowTitleRulesViewModel
    var onQuickAdd: (() -> Void)?
    
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
                
                HStack(spacing: 8) {
                    Button("Làm mới") {
                        viewModel.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    if let onQuickAdd = onQuickAdd, !viewModel.currentBundleId.isEmpty {
                        Button {
                            onQuickAdd()
                        } label: {
                            Label("Thêm nhanh", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .help("Tạo quy tắc mới với thông tin đã phát hiện")
                    }
                }
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
    @State private var showCopiedFeedback = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Status dot + Name + Actions (always visible)
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(rule.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                // Rule name
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
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
                
                Spacer()
                
                // Toggle for both built-in and custom rules
                if let onToggle = onToggle {
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(rule.isEnabled ? "Tắt quy tắc này" : "Bật quy tắc này")
                }
                
                // Edit/Delete/Copy actions (only for custom rules)
                if !isBuiltIn {
                    HStack(spacing: 8) {
                        // Copy JSON button
                        Button(action: copyRuleJSON) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(showCopiedFeedback ? .green : .purple)
                        .help("Copy JSON của quy tắc")
                        
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
            
            // Row 2: Pattern + Behavior badges (below name, indented to align with text)
            HStack(spacing: 0) {
                // Indent to align with name (8px dot + 12px spacing)
                Color.clear.frame(width: 20, height: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Pattern info
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
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("(\(rule.matchMode.rawValue))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    
                    // Behavior badges - wrap naturally
                    let hasBadges = rule.hasAXPatterns || rule.enableForceAccessibility == true || rule.useMarkedText == false || rule.injectionMethod != nil || rule.textSendingMethod != nil || (rule.targetInputSourceId != nil && !rule.targetInputSourceId!.isEmpty)
                    
                    if hasBadges {
                        FlowLayoutView(spacing: 4) {
                            // AX Patterns badge
                            if rule.hasAXPatterns {
                                BehaviorBadge(text: "🎯AX", color: .mint)
                                    .help(rule.axPatternsSummary)
                            }
                            // Force Accessibility badge
                            if rule.enableForceAccessibility == true {
                                BehaviorBadge(text: "AX", color: .indigo)
                            }
                            if rule.useMarkedText == false {
                                BehaviorBadge(text: "NoMark", color: .orange)
                            }
                            if let method = rule.injectionMethod {
                                BehaviorBadge(text: methodString(method), color: method == .passthrough ? .red : .purple)
                            }
                            if let textMethod = rule.textSendingMethod {
                                BehaviorBadge(text: textMethod == .oneByOne ? "1x1" : "Chunk", color: .cyan)
                            }
                            // Input source badge
                            if let inputSourceId = rule.targetInputSourceId, !inputSourceId.isEmpty {
                                BehaviorBadge(text: "→\(inputSourceShortName(inputSourceId))", color: .teal)
                            }
                        }
                    }
                }
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
        case .axDirect: return "AX"
        case .passthrough: return "Pass"
        }
    }
    
    /// Get short display name for input source badge
    private func inputSourceShortName(_ bundleId: String) -> String {
        // Common input sources - show abbreviated names
        let lowerId = bundleId.lowercased()
        if lowerId.contains("abc") || lowerId.contains("us") {
            return "ABC"
        } else if lowerId.contains("vietnamese") || lowerId.contains("viet") {
            return "VN"
        } else if lowerId.contains("french") {
            return "FR"
        } else if lowerId.contains("german") {
            return "DE"
        } else if lowerId.contains("japanese") {
            return "JP"
        } else if lowerId.contains("chinese") || lowerId.contains("pinyin") {
            return "CN"
        } else if lowerId.contains("korean") {
            return "KR"
        }
        // Fallback: extract last component
        let parts = bundleId.components(separatedBy: ".")
        if let last = parts.last, last.count <= 10 {
            return last
        }
        return "IM"
    }
    
    private func copyRuleJSON() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode([rule])
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(jsonString, forType: .string)
                
                // Show feedback
                withAnimation {
                    showCopiedFeedback = true
                }
                
                // Reset feedback after 1.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopiedFeedback = false
                    }
                }
            }
        } catch {
            print("Failed to encode rule to JSON: \(error)")
        }
    }
}


// MARK: - Flow Layout for wrapping badges
@available(macOS 13.0, *)
struct FlowLayoutView: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                // Wrap to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        
        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

@available(macOS 13.0, *)
struct BehaviorBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Tab Selection for AddRuleSheet
enum RuleSheetTab: String, CaseIterable {
    case basic = "Cơ bản"
    case axMatching = "AX Matching"
    case behavior = "Hành vi"
    
    var icon: String {
        switch self {
        case .basic: return "info.circle"
        case .axMatching: return "accessibility"
        case .behavior: return "slider.horizontal.3"
        }
    }
}

// MARK: - Add/Edit Rule Sheet

@available(macOS 13.0, *)
struct AddRuleSheet: View {
    @ObservedObject var viewModel: WindowTitleRulesViewModel
    let existingRule: WindowTitleRule?
    let prefillInfo: DetectedAppInfo?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: RuleSheetTab = .basic
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
    @State private var enableForceAccessibility: Bool = false
    @State private var overrideInputSource: Bool = false
    @State private var targetInputSourceId: String = ""
    @State private var availableInputSources: [(id: String, name: String)] = []
    @State private var description: String = ""
    
    // AX Matching patterns (Phase 1)
    @State private var showAXPatterns: Bool = false
    @State private var axRolePattern: String = ""
    @State private var axDescriptionPattern: String = ""
    @State private var axIdentifierPattern: String = ""
    @State private var axDOMClassListText: String = ""  // Comma-separated list
    @State private var ruleIsEnabled: Bool = true  // Preserve enabled state when editing
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAppPicker = false
    
    var isEditing: Bool { existingRule != nil }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack {
                Text(isEditing ? "Sửa quy tắc" : "Thêm quy tắc mới")
                    .font(.headline)
                Spacer()
                // Show current rule name if editing
                if !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Tab Selector
            Picker("", selection: $selectedTab) {
                ForEach(RuleSheetTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            // Tab Content - Switch-based, no native TabView
            Group {
                switch selectedTab {
                case .basic:
                    basicInfoTab
                case .axMatching:
                    axMatchingTab
                case .behavior:
                    behaviorTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // Error message
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Hủy") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                // Navigation hints
                HStack(spacing: 4) {
                    if selectedTab != .basic {
                        Button(action: { withAnimation { selectedTab = previousTab } }) {
                            Label("Quay lại", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if selectedTab != .behavior {
                        Button(action: { withAnimation { selectedTab = nextTab } }) {
                            Label("Tiếp theo", systemImage: "chevron.right")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Button(isEditing ? "Lưu" : "Thêm") {
                    saveRule()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(minHeight: 450, maxHeight: 550)
        .frame(width: 560)
        .onAppear {
            // Load available input sources for the picker
            loadAvailableInputSources()
            
            if let rule = existingRule {
                loadExistingRule(rule)
            } else if let prefill = prefillInfo {
                // Pre-fill from detected app info
                name = prefill.appName
                bundleIdPattern = prefill.bundleId
                titlePattern = prefill.windowTitle
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
    
    // MARK: - Tab Navigation Helpers
    
    private var previousTab: RuleSheetTab {
        switch selectedTab {
        case .basic: return .basic
        case .axMatching: return .basic
        case .behavior: return .axMatching
        }
    }
    
    private var nextTab: RuleSheetTab {
        switch selectedTab {
        case .basic: return .axMatching
        case .axMatching: return .behavior
        case .behavior: return .behavior
        }
    }
    
    // MARK: - Tab 1: Basic Info
    
    private var basicInfoTab: some View {
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
                
                // Pattern matching
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
                            .disabled(titlePattern.isEmpty && !showAXPatterns)
                        }
                        
                        if !titlePattern.isEmpty {
                            Text(matchModeDescription(matchMode))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Description (moved here for basic info)
                GroupBox(label: Label("Ghi chú", systemImage: "text.alignleft")) {
                    TextField("Mô tả (tùy chọn)", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Tab 2: AX Matching
    
    private var axMatchingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(label: Label("AX Matching (Nâng cao)", systemImage: "accessibility")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Sử dụng AX patterns để match", isOn: $showAXPatterns)
                        
                        if showAXPatterns {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Cho phép match theo thuộc tính AX của focused element. Dùng Debug > App Detector để xem AX info.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("AX Role:")
                                        .frame(width: 100, alignment: .leading)
                                        .font(.caption)
                                    TextField("VD: AXTextArea", text: $axRolePattern)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack {
                                    Text("AX Description:")
                                        .frame(width: 100, alignment: .leading)
                                        .font(.caption)
                                    TextField("VD: Terminal 1", text: $axDescriptionPattern)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack {
                                    Text("AX Identifier:")
                                        .frame(width: 100, alignment: .leading)
                                        .font(.caption)
                                    TextField("VD: urlbar-input", text: $axIdentifierPattern)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                HStack(alignment: .top) {
                                    Text("DOM Classes:")
                                        .frame(width: 100, alignment: .leading)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 2) {
                                        TextField("VD: notranslate, code-block", text: $axDOMClassListText)
                                            .textFieldStyle(.roundedBorder)
                                        Text("Phân cách bằng dấu phẩy. Match nếu có BẤT KỲ class nào.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Text("⚠️ Match mode cũng áp dụng cho AX patterns. Nếu muốn match chính xác, chọn 'Khớp chính xác'.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Force Accessibility
                GroupBox(label: Label("Force Accessibility", systemImage: "hand.raised")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bật Force Accessibility (AXManualAccessibility)", isOn: $enableForceAccessibility)
                        
                        Text("Dùng cho các app Electron/Chromium không expose đầy đủ Accessibility API.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if !showAXPatterns {
                    VStack(spacing: 12) {
                        Image(systemName: "accessibility")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Bật 'Sử dụng AX patterns' ở trên để cấu hình AX Matching")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Tab 3: Behavior Overrides
    
    private var behaviorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Input Source Switching
                GroupBox(label: Label("Chuyển Input Source", systemImage: "keyboard")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Tự động chuyển Input Source", isOn: $overrideInputSource)
                        
                        if overrideInputSource {
                            if availableInputSources.isEmpty {
                                Text("Đang tải danh sách Input Sources...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            } else {
                                Picker("Input Source:", selection: $targetInputSourceId) {
                                    Text("Không chuyển (giữ nguyên)").tag("")
                                    Divider()
                                    ForEach(availableInputSources, id: \.id) { source in
                                        Text(source.name).tag(source.id)
                                    }
                                }
                                .padding(.leading, 20)
                                
                                Text("XKey sẽ tự động chuyển sang Input Source đã chọn.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Marked Text override
                GroupBox(label: Label("Marked Text", systemImage: "underline")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Ghi đè Marked Text", isOn: $overrideMarkedText)
                        
                        if overrideMarkedText {
                            Toggle("Sử dụng Marked Text (gạch chân)", isOn: $useMarkedText)
                                .padding(.leading, 20)
                            
                            Toggle("Có vấn đề với Marked Text", isOn: $hasMarkedTextIssues)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Injection Method override
                GroupBox(label: Label("Injection Method", systemImage: "arrow.right.doc.on.clipboard")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Ghi đè Injection Method", isOn: $overrideInjection)
                        
                        if overrideInjection {
                            Picker("Method:", selection: $injectionMethod) {
                                ForEach(InjectionMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .frame(width: 200)
                            .padding(.leading, 20)
                            
                            Text(injectionMethod.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                            
                            // Injection delays
                            Toggle("Tùy chỉnh Injection Delays", isOn: $overrideDelays)
                                .padding(.leading, 20)
                                .padding(.top, 4)
                            
                            if overrideDelays {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Backspace (µs):")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.caption)
                                        TextField("1000", text: $backspaceDelay)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    
                                    HStack {
                                        Text("Wait (µs):")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.caption)
                                        TextField("3000", text: $waitDelay)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    
                                    HStack {
                                        Text("Text (µs):")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.caption)
                                        TextField("1500", text: $textDelay)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                }
                                .padding(.leading, 40)
                            }
                            
                            // Text Sending Method
                            Divider()
                                .padding(.leading, 20)
                                .padding(.vertical, 4)
                            
                            Picker("Phương thức gửi text:", selection: $textSendingMethod) {
                                ForEach(TextSendingMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .frame(width: 300)
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Commit delay
                GroupBox(label: Label("Commit Delay", systemImage: "clock")) {
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
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func loadExistingRule(_ rule: WindowTitleRule) {
        name = rule.name
        bundleIdPattern = rule.bundleIdPattern
        titlePattern = rule.titlePattern
        matchMode = rule.matchMode
        description = rule.description ?? ""
        ruleIsEnabled = rule.isEnabled  // Preserve enabled state
        
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
        // Simple toggles: just load the values (default false if nil)
        enableForceAccessibility = rule.enableForceAccessibility ?? false
        
        // Input source override
        if let inputSourceId = rule.targetInputSourceId, !inputSourceId.isEmpty {
            overrideInputSource = true
            targetInputSourceId = inputSourceId
        }
        
        // AX Matching patterns
        if rule.hasAXPatterns {
            showAXPatterns = true
            axRolePattern = rule.axRolePattern ?? ""
            axDescriptionPattern = rule.axDescriptionPattern ?? ""
            axIdentifierPattern = rule.axIdentifierPattern ?? ""
            if let classes = rule.axDOMClassList, !classes.isEmpty {
                axDOMClassListText = classes.joined(separator: ", ")
            }
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
        
        // Parse AX DOM Class List from comma-separated text
        var axDOMClassList: [String]? = nil
        if showAXPatterns && !axDOMClassListText.isEmpty {
            axDOMClassList = axDOMClassListText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if axDOMClassList?.isEmpty == true {
                axDOMClassList = nil
            }
        }
        
        let rule = WindowTitleRule(
            name: name,
            bundleIdPattern: bundleIdPattern,
            titlePattern: titlePattern,
            matchMode: matchMode,
            isEnabled: isEditing ? ruleIsEnabled : true,  // Preserve enabled state when editing
            // AX matching patterns
            axRolePattern: showAXPatterns && !axRolePattern.isEmpty ? axRolePattern : nil,
            axDescriptionPattern: showAXPatterns && !axDescriptionPattern.isEmpty ? axDescriptionPattern : nil,
            axIdentifierPattern: showAXPatterns && !axIdentifierPattern.isEmpty ? axIdentifierPattern : nil,
            axDOMClassList: axDOMClassList,
            // Behavior overrides
            useMarkedText: overrideMarkedText ? useMarkedText : nil,
            hasMarkedTextIssues: overrideMarkedText ? hasMarkedTextIssues : nil,
            commitDelay: UInt32(commitDelay) ?? nil as UInt32?,
            injectionMethod: overrideInjection ? injectionMethod : nil,
            injectionDelays: injectionDelaysArray,
            textSendingMethod: overrideInjection ? textSendingMethod : nil,
            enableForceAccessibility: enableForceAccessibility ? true : nil,
            targetInputSourceId: overrideInputSource && !targetInputSourceId.isEmpty ? targetInputSourceId : nil,
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
    
    /// Load all available input sources for the picker
    private func loadAvailableInputSources() {
        // Use InputSourceManager which properly deduplicates sources
        var sources = InputSourceManager.getAllInputSources()
        
        // Add XKey at the beginning (it's filtered out by getAllInputSources)
        let xkeySource = InputSourceInfo(
            id: InputSourceSwitcher.xkeyIMBundleId,
            name: "XKey"
        )
        sources.insert(xkeySource, at: 0)
        
        // Map to our tuple format
        availableInputSources = sources.map { (id: $0.id, name: $0.displayName) }
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
                matchedRuleName = detector.getMergedRuleResult().hasMatches ? detector.getMergedRuleResult().displayName : nil
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
                let mergedResult = detector.getMergedRuleResult()
                matchedRuleName = mergedResult.hasMatches ? mergedResult.displayName : nil
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
    
    func toggleBuiltInRule(_ rule: WindowTitleRule, enabled: Bool) {
        AppBehaviorDetector.shared.toggleBuiltInRule(rule.name, enabled: enabled)
        refresh()
    }
    
    /// Move rules from source indices to destination index (drag & drop reordering)
    func moveRules(from source: IndexSet, to destination: Int) {
        customRules.move(fromOffsets: source, toOffset: destination)
        
        // Save the new order to AppBehaviorDetector
        AppBehaviorDetector.shared.reorderCustomRules(customRules)
    }
}
