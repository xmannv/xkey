//
//  ExcludedAppsView.swift
//  XKey
//
//  View for managing excluded apps (apps where Vietnamese input is disabled)
//

import SwiftUI
import AppKit

// MARK: - Excluded Apps Settings Section

struct ExcludedAppsSettingsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @StateObject private var excludedAppsVM = ExcludedAppsViewModel()
    @State private var showAppPicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroup(title: "Loại trừ ứng dụng") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Các ứng dụng trong danh sách này sẽ không hỗ trợ gõ tiếng Việt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Master toggle for exclusion rules
                        Toggle("Bật tính năng loại trừ ứng dụng", isOn: $viewModel.preferences.exclusionRulesEnabled)
                        
                        // Hotkey to toggle exclusion rules
                        HStack {
                            Text("Phím tắt bật/tắt:")
                                .font(.caption)
                            Spacer()
                            HotkeyRecorderView(hotkey: $viewModel.preferences.toggleExclusionHotkey, minimumModifiers: 2)
                                .frame(width: 150)
                        }
                        
                        Text("Nhấn phím tắt để nhanh chóng bật/tắt tính năng loại trừ ứng dụng")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        HStack(spacing: 12) {
                            Button(action: { showAppPicker = true }) {
                                Label("Thêm ứng dụng", systemImage: "plus.app")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.preferences.exclusionRulesEnabled)
                            
                            Spacer()
                            
                            if !viewModel.preferences.excludedApps.isEmpty {
                                Button(role: .destructive) {
                                    viewModel.preferences.excludedApps.removeAll()
                                } label: {
                                    Label("Xóa tất cả", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!viewModel.preferences.exclusionRulesEnabled)
                            }
                        }
                    }
                }
                
                // Excluded apps list
                SettingsGroup(title: "Danh sách ứng dụng loại trừ (\(viewModel.preferences.excludedApps.count))") {
                    if viewModel.preferences.excludedApps.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Chưa có ứng dụng nào")
                                .foregroundColor(.secondary)
                            Text("Thêm ứng dụng để tắt gõ tiếng Việt khi sử dụng")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.preferences.excludedApps) { app in
                                ExcludedAppRow(app: app) {
                                    removeApp(app)
                                }
                            }
                        }
                    }
                }
                .disabled(!viewModel.preferences.exclusionRulesEnabled)
                .opacity(viewModel.preferences.exclusionRulesEnabled ? 1.0 : 0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView { selectedApp in
                addApp(selectedApp)
            }
        }
    }
    
    private func addApp(_ app: ExcludedApp) {
        // Check if already exists
        guard !viewModel.preferences.excludedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else {
            return
        }
        viewModel.preferences.excludedApps.append(app)
    }
    
    private func removeApp(_ app: ExcludedApp) {
        viewModel.preferences.excludedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
    }
}

// MARK: - Excluded App Row

struct ExcludedAppRow: View {
    let app: ExcludedApp
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var appIcon: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            
            // App info
            VStack(alignment: .leading, spacing: 2) {
                Text(app.appName)
                    .fontWeight(.medium)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.gray.opacity(0.03))
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            loadAppIcon()
        }
    }
    
    private func loadAppIcon() {
        if let path = app.appPath {
            appIcon = NSWorkspace.shared.icon(forFile: path)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - App Picker View

struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AppPickerViewModel()
    @State private var searchText = ""
    let onSelect: (ExcludedApp) -> Void
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return viewModel.apps
        }
        return viewModel.apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chọn ứng dụng")
                    .font(.headline)
                Spacer()
                Button("Đóng") {
                    dismiss()
                }
            }
            .padding()
            
            // Search
            TextField("Tìm kiếm...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            // Tabs
            Picker("", selection: $viewModel.selectedTab) {
                Text("Tất cả").tag(AppPickerTab.all)
                Text("Đang chạy").tag(AppPickerTab.running)                
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // App list
            if viewModel.isLoading {
                ProgressView("Đang tải...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Không tìm thấy ứng dụng")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    AppPickerRow(app: app) {
                        let excludedApp = ExcludedApp(
                            bundleIdentifier: app.bundleIdentifier,
                            appName: app.name,
                            appPath: app.path
                        )
                        onSelect(excludedApp)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            viewModel.loadApps()
        }
    }
}

// MARK: - App Picker Row

struct AppPickerRow: View {
    let app: AppInfo
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Thêm") {
                onSelect()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - View Models

class ExcludedAppsViewModel: ObservableObject {
    // Placeholder for future functionality
}

enum AppPickerTab {
    case running
    case all
}

struct AppInfo: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let path: String?
    let icon: NSImage?
    
    init(name: String, bundleIdentifier: String, path: String?, icon: NSImage?) {
        self.id = bundleIdentifier
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.icon = icon
    }
}

class AppPickerViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isLoading = false
    @Published var selectedTab: AppPickerTab = .all {
        didSet {
            loadApps()
        }
    }
    
    func loadApps() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loadedApps: [AppInfo]
            
            switch self?.selectedTab {
            case .running:
                loadedApps = self?.loadRunningApps() ?? []
            case .all:
                loadedApps = self?.loadAllApps() ?? []
            case .none:
                loadedApps = []
            }
            
            DispatchQueue.main.async {
                self?.apps = loadedApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self?.isLoading = false
            }
        }
    }
    
    private func loadRunningApps() -> [AppInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var apps: [AppInfo] = []
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  let name = app.localizedName,
                  app.activationPolicy == .regular else {
                continue
            }
            
            let icon = app.icon
            let path = app.bundleURL?.path
            
            apps.append(AppInfo(
                name: name,
                bundleIdentifier: bundleId,
                path: path,
                icon: icon
            ))
        }
        
        return apps
    }
    
    private func loadAllApps() -> [AppInfo] {
        var apps: [AppInfo] = []
        let fileManager = FileManager.default
        
        // Search in /Applications and ~/Applications
        let appDirs = [
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        
        for dir in appDirs {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else {
                continue
            }
            
            for item in contents where item.hasSuffix(".app") {
                let appPath = (dir as NSString).appendingPathComponent(item)
                
                if let bundle = Bundle(path: appPath),
                   let bundleId = bundle.bundleIdentifier {
                    let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String) ??
                               (bundle.infoDictionary?["CFBundleName"] as? String) ??
                               (item as NSString).deletingPathExtension
                    
                    let icon = NSWorkspace.shared.icon(forFile: appPath)
                    
                    apps.append(AppInfo(
                        name: name,
                        bundleIdentifier: bundleId,
                        path: appPath,
                        icon: icon
                    ))
                }
            }
        }
        
        return apps
    }
}
