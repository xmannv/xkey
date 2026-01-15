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
        case injectionTest = "Injection Test"
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
                            Image(systemName: tab == .log ? "doc.text" : (tab == .textTest ? "textformat.abc" : "play.circle"))
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
                
            case .injectionTest:
                // Injection Test Tab
                InjectionTestTabView(viewModel: viewModel)
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
                        
                        // Force Accessibility Section (for Electron/Chromium apps)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Force Accessibility")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                // Status indicator
                                if viewModel.isForceAccessibilityEnabled {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            
                            // Show target app
                            HStack(spacing: 4) {
                                Text("Target:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(viewModel.forceAccessibilityTargetApp)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            
                            Text("Enable AXManualAccessibility for Electron/Chromium apps")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Buttons
                            HStack(spacing: 8) {
                                // Toggle AXManualAccessibility
                                Button {
                                    viewModel.toggleForceAccessibility()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: viewModel.isForceAccessibilityEnabled ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 10))
                                        Text(viewModel.isForceAccessibilityEnabled ? "Enabled" : "Enable")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(viewModel.isForceAccessibilityEnabled ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                                    )
                                    .foregroundColor(viewModel.isForceAccessibilityEnabled ? .green : .blue)
                                }
                                .buttonStyle(.plain)
                                .help("Toggle AXManualAccessibility for target app")
                                
                                // Check Status Button (more useful than forcing)
                                Button {
                                    viewModel.checkAccessibilityStatus()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 10))
                                        Text("Check")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                                    .foregroundColor(.orange)
                                }
                                .buttonStyle(.plain)
                                .help("Check accessibility status of target app (see Log tab)")
                            }
                            
                            // Status message
                            if !viewModel.forceAccessibilityStatus.isEmpty {
                                Text(viewModel.forceAccessibilityStatus)
                                    .font(.system(size: 9))
                                    .foregroundColor(viewModel.forceAccessibilityStatus.hasPrefix("✅") ? .green : 
                                                    viewModel.forceAccessibilityStatus.hasPrefix("❌") ? .red : .secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                                )
                        )
                        
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
                            InfoRow(label: "AX Title", value: viewModel.focusedInputTitle)
                            InfoRow(label: "AX Identifier", value: viewModel.focusedInputIdentifier)
                        }
                        
                        // Web Content Info (shown if available)
                        if !viewModel.focusedInputDOMId.isEmpty || !viewModel.focusedInputDOMClasses.isEmpty {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Web Content")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                InfoRow(label: "DOM ID", value: viewModel.focusedInputDOMId)
                                InfoRow(label: "DOM Classes", value: viewModel.focusedInputDOMClasses)
                            }
                        }
                        
                        // Actions (shown if available)
                        if !viewModel.focusedInputActions.isEmpty {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Actions")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.focusedInputActions)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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

// MARK: - Injection Test Tab View

struct InjectionTestTabView: View {
    @ObservedObject var viewModel: DebugViewModel
    
    /// Computed button text based on state
    private var primaryButtonText: String {
        switch viewModel.injectionTestState {
        case .idle:
            return "Run Test"
        case .preparingInput:
            return "Countdown (\(viewModel.injectionTestCountdown))"
        case .typing:
            return "Typing..."
        case .preparingVerify:
            return "Verifying in \(viewModel.injectionTestCountdown)..."
        case .verifying:
            return "Verifying..."
        case .passed:
            return "Test Passed!"
        case .failed:
            return "Test Failed"
        case .completed:
            return "All Methods Tested"
        case .paused:
            return "Resume"
        }
    }
    
    /// Computed button color
    private var primaryButtonColor: Color {
        switch viewModel.injectionTestState {
        case .idle: return .blue
        case .preparingInput: return .orange
        case .typing: return .gray
        case .preparingVerify: return .purple
        case .verifying: return .gray
        case .passed: return .green
        case .failed: return .red
        case .completed: return .gray
        case .paused: return .green
        }
    }
    
    /// Whether primary button is enabled
    private var primaryButtonEnabled: Bool {
        switch viewModel.injectionTestState {
        case .idle, .preparingInput, .passed, .failed, .completed, .paused:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Panel - Input & Controls (Scrollable)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Injection Method Test")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Test if XKey injection works correctly in any app")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                
                Divider()
                
                // Input Keys Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input Keys")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., a + s + n + h", text: $viewModel.injectionTestInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(viewModel.injectionTestState != .idle && 
                                  viewModel.injectionTestState != .passed &&
                                  viewModel.injectionTestState != .failed &&
                                  viewModel.injectionTestState != .completed)
                    
                    Text("Type characters directly. Example: 'asnh', 'xin chaof'")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                // Expected Result Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expected Result")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., ánh", text: $viewModel.injectionTestExpected)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .disabled(viewModel.injectionTestState != .idle && 
                                  viewModel.injectionTestState != .passed &&
                                  viewModel.injectionTestState != .failed &&
                                  viewModel.injectionTestState != .completed)
                }
                
                Divider()
                
                // Injection Method Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Injection Method")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.injectionTestCurrentMethod) {
                        ForEach(viewModel.injectionMethodsToTest, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(viewModel.injectionTestState != .idle && 
                              viewModel.injectionTestState != .passed &&
                              viewModel.injectionTestState != .failed &&
                              viewModel.injectionTestState != .completed)
                    
                    Text(viewModel.injectionTestCurrentMethod.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Text Sending Method Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text Sending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.injectionTestTextSendingMethod) {
                        ForEach(TextSendingMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(viewModel.injectionTestState != .idle && 
                              viewModel.injectionTestState != .passed &&
                              viewModel.injectionTestState != .failed &&
                              viewModel.injectionTestState != .completed)
                }
                
                // Advanced Options (collapsible)
                DisclosureGroup(
                    isExpanded: $viewModel.injectionTestShowAdvanced
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Backspace Delay
                        HStack {
                            Text("Backspace delay:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            TextField("", value: $viewModel.injectionTestDelayBackspace, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("µs")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        // Wait Delay
                        HStack {
                            Text("Wait delay:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            TextField("", value: $viewModel.injectionTestDelayWait, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("µs")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        // Text Delay
                        HStack {
                            Text("Text delay:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            TextField("", value: $viewModel.injectionTestDelayText, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("µs")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Text("1000µs = 1ms. Increase delay if characters are lost.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Auto Clear Toggle
                        Toggle(isOn: $viewModel.injectionTestAutoClear) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto Clear Text")
                                    .font(.system(size: 10))
                                Text("Clear text after fail to test next method")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(.top, 4)
                    .disabled(viewModel.injectionTestState != .idle && 
                              viewModel.injectionTestState != .passed &&
                              viewModel.injectionTestState != .failed &&
                              viewModel.injectionTestState != .completed)
                } label: {
                    Text("Advanced Options")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Action Buttons
                VStack(spacing: 10) {
                    // Primary Button (Run/Resume/Stop)
                    Button {
                        switch viewModel.injectionTestState {
                        case .idle, .passed, .failed, .completed:
                            viewModel.startInjectionTest()
                        case .preparingInput, .preparingVerify:
                            // During countdown, primary button stops the test
                            viewModel.stopInjectionTest()
                        case .paused:
                            viewModel.resumeInjectionTest()
                        default:
                            break
                        }
                    } label: {
                        HStack {
                            if viewModel.injectionTestState == .preparingInput || viewModel.injectionTestState == .preparingVerify {
                                Image(systemName: "stop.fill")
                            } else if viewModel.injectionTestState == .typing || viewModel.injectionTestState == .verifying {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else if viewModel.injectionTestState == .passed {
                                Image(systemName: "checkmark.circle.fill")
                            } else if viewModel.injectionTestState == .failed {
                                Image(systemName: "xmark.circle.fill")
                            } else if viewModel.injectionTestState == .paused {
                                Image(systemName: "play.circle.fill")
                            } else {
                                Image(systemName: "play.fill")
                            }
                            
                            Text(viewModel.injectionTestState == .preparingInput || viewModel.injectionTestState == .preparingVerify ? "Stop" : primaryButtonText)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.injectionTestState == .preparingInput || viewModel.injectionTestState == .preparingVerify ? Color.red : primaryButtonColor)
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!primaryButtonEnabled)
                    
                    // Pause Button (only during countdown)
                    if viewModel.injectionTestState == .preparingInput || viewModel.injectionTestState == .preparingVerify {
                        Button {
                            viewModel.pauseInjectionTest()
                        } label: {
                            HStack {
                                Image(systemName: "pause.fill")
                                Text("Pause (\(viewModel.injectionTestCountdown)s)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.orange)
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Clear & Reset Button
                    if !viewModel.injectionTestLog.isEmpty {
                        Button {
                            viewModel.injectionTestLog.removeAll()
                            viewModel.injectionTestResult = ""
                            if viewModel.injectionTestState == .passed || 
                               viewModel.injectionTestState == .failed ||
                               viewModel.injectionTestState == .completed ||
                               viewModel.injectionTestState == .paused {
                                viewModel.injectionTestState = .idle
                            }
                        } label: {
                            Text("Clear & Reset")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
            }  // VStack
            }  // ScrollView
            .padding()
            .frame(width: 300)
            
            Divider()
            
            // Right Panel - Log Output
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Test Log")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Copy Log Button
                    if !viewModel.injectionTestLog.isEmpty {
                        Button {
                            let logText = viewModel.injectionTestLog.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(logText, forType: .string)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                Text("Copy")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        viewModel.injectionTestLog.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.injectionTestLog.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(lineColor(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: viewModel.injectionTestLog.count) { newCount in
                        if newCount > 0 {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(newCount - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    /// Get color for log line based on content
    private func lineColor(for line: String) -> Color {
        if line.contains("[OK]") || line.contains("PASSED") {
            return .green
        } else if line.contains("[FAIL]") || line.contains("FAILED") || line.contains("[ERROR]") {
            return .red
        } else if line.contains("===") {
            return .blue
        } else if line.starts(with: "[") && line.contains("]") && line.first != "[" {
            return .orange
        } else {
            return .primary
        }
    }
}

// MARK: - Preview

#Preview {
    DebugView(viewModel: DebugViewModel())
}
