//
//  DebugView.swift
//  XKey
//
//  Professional Debug Console with modern UI design
//

import SwiftUI

// MARK: - Main Debug View

struct DebugView: View {
    @ObservedObject var viewModel: DebugViewModel
    @State private var searchText = ""
    @State private var filterLevel: LogLevel = .all
    @State private var selectedTab: DebugTab = .log
    @State private var autoScroll = true
    
    enum DebugTab: String, CaseIterable {
        case log = "Log"
        case textTest = "Text Test"
    }
    
    enum LogLevel: String, CaseIterable {
        case all = "All"
        case error = "Error"
        case warning = "Warning"
        case success = "Success"
        case debug = "Debug"
        
        var icon: String {
            switch self {
            case .all: return "line.3.horizontal.decrease.circle"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .debug: return "magnifyingglass.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .primary
            case .error: return .red
            case .warning: return .orange
            case .success: return .green
            case .debug: return .purple
            }
        }
    }
    
    var filteredLines: [String] {
        var lines = viewModel.logLines
        
        // Filter by search text
        if !searchText.isEmpty {
            lines = lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Filter by log level
        switch filterLevel {
        case .all: break
        case .error: lines = lines.filter { $0.contains("[ERROR]") || $0.contains("ERROR") }
        case .warning: lines = lines.filter { $0.contains("[WARN]") || $0.contains("WARNING") }
        case .success: lines = lines.filter { $0.contains("[OK]") || $0.contains("SUCCESS") }
        case .debug: lines = lines.filter { $0.contains("[DEBUG]") || $0.contains("DEBUG") }
        }
        
        return lines
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DebugHeaderView(viewModel: viewModel)
            
            // Tab Picker
            HStack(spacing: 0) {
                ForEach(DebugTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab == .log ? "doc.text" : "textformat.abc")
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background(
                            selectedTab == tab 
                                ? Color.blue.opacity(0.1) 
                                : Color.clear
                        )
                        .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.15)),
                alignment: .bottom
            )
            
            // Tab Content
            switch selectedTab {
            case .log:
                // Toolbar (only for Log tab)
                DebugToolbar(
                    viewModel: viewModel,
                    searchText: $searchText,
                    filterLevel: $filterLevel,
                    autoScroll: $autoScroll
                )
                
                // Log Viewer
                LogListView(
                    lines: filteredLines,
                    totalCount: viewModel.logLines.count,
                    autoScroll: $autoScroll
                )
                
            case .textTest:
                // Text Test Tab
                TextTestTabView(viewModel: viewModel)
            }
        }
        .frame(width: 900, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.windowDidBecomeVisible()
            viewModel.refreshPinnedConfig()
        }
        .onDisappear {
            viewModel.windowDidBecomeHidden()
        }
    }
}

// MARK: - Header View

struct DebugHeaderView: View {
    @ObservedObject var viewModel: DebugViewModel
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 16) {
            // App Icon & Title
            HStack(spacing: 10) {
                Image(systemName: "ant.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("XKey Debug")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("v\(AppVersion.current) (\(AppVersion.build))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isLoggingEnabled ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                
                Text(viewModel.isLoggingEnabled ? "Recording" : "Paused")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            
            // Stats
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text("\(viewModel.logLines.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("lines")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(timeString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .onReceive(timer) { time in
                currentTime = time
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.15)),
            alignment: .bottom
        )
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
}

// MARK: - Toolbar

struct DebugToolbar: View {
    @ObservedObject var viewModel: DebugViewModel
    @Binding var searchText: String
    @Binding var filterLevel: DebugView.LogLevel
    @Binding var autoScroll: Bool

    /// Computed text for App Detector button
    private var appDetectorButtonText: String {
        if viewModel.isAppDetectorTestRunning {
            if viewModel.appDetectorTestCountdown > 0 {
                return "Stop (\(viewModel.appDetectorTestCountdown))"
            } else {
                return "Checking app..."
            }
        } else {
            return "Test App Detector"
        }
    }

    /// Computed color for App Detector button
    private var appDetectorButtonColor: Color {
        if viewModel.isAppDetectorTestRunning {
            if viewModel.appDetectorTestCountdown > 0 {
                return .orange
            } else {
                return .gray
            }
        } else {
            return .purple
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
            .frame(width: 180)
            
            // Filter Picker
            Picker("", selection: $filterLevel) {
                ForEach(DebugView.LogLevel.allCases, id: \.self) { level in
                    Label(level.rawValue, systemImage: level.icon)
                        .tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            
            Divider().frame(height: 18)
            
            // Action Buttons
            Group {
                ToolbarIconButton(icon: "gearshape", tooltip: "Log Config") {
                    viewModel.logCurrentConfig()
                }
                
                ToolbarIconButton(icon: "doc.on.doc", tooltip: "Copy All") {
                    viewModel.copyLogs()
                }
                
                ToolbarIconButton(icon: "folder", tooltip: "Open File") {
                    viewModel.openLogFile()
                }
                
                ToolbarIconButton(icon: "trash", tooltip: "Clear", color: .red) {
                    viewModel.clearLogs()
                }
            }
            
            Divider().frame(height: 18)
            
            // App Detector Test Button
            Button {
                if viewModel.isAppDetectorTestRunning && viewModel.appDetectorTestCountdown > 0 {
                    viewModel.stopAppDetectorTest()
                } else if !viewModel.isAppDetectorTestRunning {
                    viewModel.startAppDetectorTest()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isAppDetectorTestRunning ? (viewModel.appDetectorTestCountdown > 0 ? "stop.circle.fill" : "magnifyingglass") : "magnifyingglass.circle")
                        .font(.system(size: 12))
                    Text(appDetectorButtonText)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(appDetectorButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAppDetectorTestRunning && viewModel.appDetectorTestCountdown == 0)
            .help("Test App Behavior Detector (Spotlight/Raycast/Alfred/etc.)")
            
            Spacer()
            
            // Toggle Buttons
            Toggle(isOn: $viewModel.isVerboseLogging) {
                Text("Verbose")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            
            Toggle(isOn: $viewModel.isLoggingEnabled) {
                Text("Recording")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.isLoggingEnabled) { _ in
                viewModel.toggleLogging()
            }
            
            Toggle(isOn: $autoScroll) {
                Text("Auto-Scroll")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}

// MARK: - Toolbar Icon Button

struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    var color: Color = .primary
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isHovered ? color : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? color.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Log List View

struct LogListView: View {
    let lines: [String]
    let totalCount: Int
    @Binding var autoScroll: Bool
    
    @State private var lastLineCount = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Info Bar
            HStack {
                if lines.count != totalCount {
                    Text("Showing \(lines.count) of \(totalCount) entries")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(totalCount) entries")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            // Log Content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            LogLineView(line: line, lineNumber: index + 1)
                                .id(index)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: lines.count) { newCount in
                    // When logs are cleared (count decreased), reset tracking
                    if newCount < lastLineCount {
                        lastLineCount = 0
                    }

                    // Auto-scroll to bottom when new lines are added
                    if autoScroll && newCount > 0 && newCount > lastLineCount {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                    lastLineCount = newCount
                }
                .onChange(of: autoScroll) { isEnabled in
                    // When auto-scroll is toggled ON, immediately scroll to bottom
                    if isEnabled && lines.count > 0 {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lines.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Log Line View

struct LogLineView: View {
    let line: String
    let lineNumber: Int
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number
            Text("\(lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 8)
            
            // Log text
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(
            Rectangle()
                .fill(backgroundColor)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var textColor: Color {
        return .primary
    }
    
    private var backgroundColor: Color {
        if isHovered {
            return Color.blue.opacity(0.06)
        }
        return lineNumber % 2 == 0 ? Color.clear : Color.gray.opacity(0.025)
    }
}

// MARK: - Text Test Tab View

struct TextTestTabView: View {
    @ObservedObject var viewModel: DebugViewModel
    @State private var textEditorContent = ""
    
    var body: some View {
        VStack(spacing: 0) {            
            // Main Content
            HStack(spacing: 0) {
                // Left: Text Input Area (takes remaining space)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Input")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextTestEditor(text: $textEditorContent)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding()
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // Right: External App Info Panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // App Info Section
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "App Name", value: viewModel.focusedAppName)
                            InfoRow(label: "Bundle ID", value: viewModel.focusedAppBundleID)
                            InfoRow(label: "Window", value: viewModel.focusedWindowTitle)
                        }
                        
                        Divider()
                        
                        // Input Element Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Input Element")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            InfoRow(label: "AX Role", value: viewModel.focusedInputRole)
                            InfoRow(label: "AX Subrole", value: viewModel.focusedInputSubrole)
                            InfoRow(label: "AX RoleDescription", value: viewModel.focusedInputRoleDescription)
                            InfoRow(label: "AX Description", value: viewModel.focusedInputDescription)
                            InfoRow(label: "AX Placeholder", value: viewModel.focusedInputPlaceholder)
                        }
                        
                        Divider()
                        
                        // Caret Context (unified - works for any focused app)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Caret Context")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("Pos: \(viewModel.externalCaretPosition)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                            
                            // Word Before
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Word Before Caret")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.externalWordBeforeCaret.isEmpty ? "(none)" : viewModel.externalWordBeforeCaret)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(viewModel.externalWordBeforeCaret.isEmpty ? .secondary : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.green.opacity(0.08))
                                    )
                            }
                            
                            // Word After
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Word After Caret")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.externalWordAfterCaret.isEmpty ? "(none)" : viewModel.externalWordAfterCaret)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(viewModel.externalWordAfterCaret.isEmpty ? .secondary : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.orange.opacity(0.08))
                                    )
                            }
                        }                                        
                    }
                    .padding()
                }
                .frame(width: 280)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.startExternalMonitoring()
        }
        .onDisappear {
            viewModel.stopExternalMonitoring()
        }
    }
}

// MARK: - Info Row Helper

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Text(value.isEmpty ? "(empty)" : value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(value.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Text Test Editor (Simple NSTextView wrapper)

struct TextTestEditor: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = false
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextTestEditor
        
        init(_ parent: TextTestEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Preview

#Preview {
    DebugView(viewModel: DebugViewModel())
}
