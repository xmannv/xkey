//
//  SettingsView.swift
//  XKey
//
//  Unified Settings View with Apple-style sidebar navigation
//  Supports macOS 26 Tahoe Liquid Glass design
//  Uses shared components from SettingsSections/
//

import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "Cơ bản"
    case quickTyping = "Gõ nhanh"
    case advanced = "Nâng cao"
    case inputSources = "Input Sources"
    case excludedApps = "Loại trừ"
    case macro = "Macro"
    case translation = "Dịch thuật"
    case convertTool = "Chuyển đổi"
    case appearance = "Giao diện"
    case backupRestore = "Sao lưu"
    case about = "Giới thiệu"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .quickTyping: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .inputSources: return "globe"
        case .excludedApps: return "app.badge.fill"
        case .macro: return "text.badge.plus"
        case .translation: return "globe.americas"
        case .convertTool: return "arrow.left.arrow.right"
        case .appearance: return "paintbrush"
        case .backupRestore: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Main Settings View

@available(macOS 13.0, *)
struct SettingsView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedSection: SettingsSection

    var onSave: ((Preferences) -> Void)?
    var onClose: (() -> Void)?

    init(selectedSection: SettingsSection = .general, onSave: ((Preferences) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self._selectedSection = State(initialValue: selectedSection)
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Content - Using shared components
            Group {
                switch selectedSection {
                case .general:
                    GeneralSection(viewModel: viewModel)
                case .quickTyping:
                    QuickTypingSection(viewModel: viewModel)
                case .advanced:
                    AdvancedSection(viewModel: viewModel)
                case .inputSources:
                    InputSourcesSection(preferencesViewModel: viewModel)
                case .excludedApps:
                    ExcludedAppsSection(viewModel: viewModel)
                case .macro:
                    MacroSection(prefsViewModel: viewModel)
                case .translation:
                    TranslationSection(viewModel: viewModel)
                case .convertTool:
                    ConvertToolSection()
                case .appearance:
                    AppearanceSection(viewModel: viewModel)
                case .backupRestore:
                    BackupRestoreSection()
                case .about:
                    AboutSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 750, height: 550)
        .onReceive(viewModel.objectWillChange) { _ in
            // Auto-save when any preference changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.save()
                onSave?(viewModel.preferences)
            }
        }
    }
}

// MARK: - Preview

@available(macOS 13.0, *)
#Preview {
    SettingsView()
}
