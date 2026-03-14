import SwiftUI

// MARK: - Glass Design Menu Bar Popover (macOS 12+)

struct StatusBarPopoverView: View {
    @ObservedObject var viewModel: StatusBarViewModel
    var onCheckForUpdates: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isInputMethodExpanded = true
    @State private var isCodeTableExpanded = false

    // Filtered code tables (exclude experimental)
    private var supportedCodeTables: [CodeTable] {
        CodeTable.allCases.filter { $0 != .unicodeCompound && $0 != .vietnameseLocaleCP1258 }
    }

    var body: some View {
        VStack(spacing: 4) {
            // MARK: - Toggle Vietnamese
            toggleSection

            // MARK: - Input Method
            inputMethodSection

            // MARK: - Code Table
            codeTableSection

            // MARK: - Divider
            sectionDivider

            // MARK: - Tools
            toolsSection

            // MARK: - Divider
            sectionDivider

            // MARK: - Footer
            footerSection
        }
        .padding(.vertical, 6)
        .frame(width: 300)
    }

    // MARK: - Toggle Section
    private var toggleSection: some View {
        HStack {
            Text("Gõ Tiếng Việt")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.isVietnameseEnabled },
                set: { _ in viewModel.toggleVietnamese() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .menuCardStyle()
    }

    // MARK: - Input Method Section
    private var inputMethodSection: some View {
        VStack(spacing: 0) {
            // Section header - clickable to expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInputMethodExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Kiểu gõ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(viewModel.currentInputMethod.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Image(systemName: isInputMethodExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            if isInputMethodExpanded {
                VStack(spacing: 1) {
                    ForEach(InputMethod.allCases, id: \.self) { method in
                        MenuRow(
                            title: method.displayName,
                            isSelected: method == viewModel.currentInputMethod
                        ) {
                            viewModel.selectInputMethod(method)
                        }
                    }
                }
                .menuCardStyle()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Code Table Section
    private var codeTableSection: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCodeTableExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Bảng mã")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(viewModel.currentCodeTable.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Image(systemName: isCodeTableExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)

            if isCodeTableExpanded {
                VStack(spacing: 1) {
                    ForEach(supportedCodeTables, id: \.self) { table in
                        MenuRow(
                            title: table.displayName,
                            isSelected: table == viewModel.currentCodeTable
                        ) {
                            viewModel.selectCodeTable(table)
                        }
                    }
                }
                .menuCardStyle()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Tools Section
    private var toolsSection: some View {
        VStack(spacing: 1) {
            ActionRow(title: "Quản lý Macro...", icon: "text.badge.plus") {
                onDismiss?()
                viewModel.openMacroManagement()
            }
            ActionRow(title: "Công cụ chuyển đổi...", icon: "arrow.left.arrow.right") {
                onDismiss?()
                viewModel.openConvertTool()
            }
            if viewModel.debugModeEnabled {
                ActionRow(title: "Tắt Debug Window", icon: "ant") {
                    viewModel.onToggleDebugWindow?()
                }
            } else {
                ActionRow(title: "Mở Debug Window...", icon: "ant") {
                    viewModel.onToggleDebugWindow?()
                }
            }
        }
        .menuCardStyle()
    }

    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 1) {
            ActionRow(title: "Kiểm tra cập nhật...", icon: "arrow.triangle.2.circlepath") {
                onDismiss?()
                onCheckForUpdates?()
            }
            ActionRow(title: "Bảng điều khiển...", icon: "gearshape", shortcut: "⌘,") {
                onDismiss?()
                viewModel.openPreferences()
            }

            Divider()
                .padding(.horizontal, 8)

            ActionRow(title: "Thoát XKey", icon: "power", shortcut: "⌘Q") {
                viewModel.quit()
            }
        }
        .menuCardStyle()
    }

    // MARK: - Section Divider
    private var sectionDivider: some View {
        Color.clear.frame(height: 0)
    }
}

// MARK: - macOS Card Style Modifier

private struct MenuCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 8)
    }
}

private extension View {
    func menuCardStyle() -> some View {
        self.modifier(MenuCardModifier())
    }
}

// MARK: - Menu Row (selectable with checkmark, macOS style)

private struct MenuRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Action Row (clickable row with icon, macOS style)

private struct ActionRow: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? .white.opacity(0.9) : .secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .white : .primary)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? .white.opacity(0.7) : .secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - NSVisualEffectView Hosting (Glass Background)

/// NSViewRepresentable wrapping NSVisualEffectView for glass/vibrancy effect
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
