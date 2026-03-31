//
//  PreferencesView.swift
//  XKey
//
//  SwiftUI Preferences View with Vertical Sidebar Layout
//  Uses shared components from SettingsSections/
//  Compatible with macOS 12+
//

import SwiftUI

// MARK: - Section Enum

/// Sections for the legacy preferences view (macOS 12 compatible)
enum PreferencesSection: String, CaseIterable, Identifiable {
    case about = "Giới thiệu"
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .about: return "info.circle"
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
        }
    }

    /// Whether this section is available on the current macOS version
    var isAvailable: Bool {
        switch self {
        case .translation:
            if #available(macOS 13.0, *) { return true }
            return false
        default:
            return true
        }
    }

    /// Map from legacy integer tab index to section
    static func from(tabIndex: Int) -> PreferencesSection {
        switch tabIndex {
        case 0: return .about
        case 1: return .general
        case 2: return .quickTyping
        case 3: return .advanced
        case 4: return .inputSources
        case 5: return .excludedApps
        case 6: return .macro
        case 7: return .convertTool
        case 8: return .appearance
        case 9: return .backupRestore
        default: return .general
        }
    }
}

// MARK: - Preferences View

struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedSection: PreferencesSection

    var onSave: ((Preferences) -> Void)?

    init(selectedTab: Int = 0, onSave: ((Preferences) -> Void)? = nil) {
        self._selectedSection = State(initialValue: PreferencesSection.from(tabIndex: selectedTab))
        self.onSave = onSave
    }

    var body: some View {
        // Sidebar + Content layout
        HStack(spacing: 0) {
            // Vertical sidebar
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(PreferencesSection.allCases.filter { $0.isAvailable }) { section in
                        SidebarButton(
                            title: section.rawValue,
                            icon: section.icon,
                            isSelected: selectedSection == section
                        ) {
                            selectedSection = section
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .frame(width: 160)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // Content area
            Group {
                switch selectedSection {
                case .about:
                    AboutSection()
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
                    if #available(macOS 13.0, *) {
                        TranslationSection(viewModel: viewModel)
                    }
                case .convertTool:
                    ConvertToolSection()
                case .appearance:
                    AppearanceSection(viewModel: viewModel)
                case .backupRestore:
                    BackupRestoreSection()
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

// MARK: - Sidebar Button

/// Custom sidebar button compatible with macOS 12+
private struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .white : .secondary)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}
