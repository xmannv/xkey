//
//  ToggleHUDWindow.swift
//  XKey
//
//  Lightweight HUD overlay for showing toggle state feedback
//  Uses the same FloatingToolbarStyle as TranslationToolbar/TempOffToolbar
//

import AppKit
import SwiftUI

class ToggleHUDWindow {
    
    // MARK: - Singleton
    
    static let shared = ToggleHUDWindow()
    
    // MARK: - Properties
    
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var hostingController: NSHostingController<ToggleHUDView>?
    private let viewModel = ToggleHUDViewModel()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Show a toggle HUD with icon and label
    /// - Parameters:
    ///   - title: Feature name (e.g. "Loại trừ ứng dụng")
    ///   - isEnabled: Whether the feature is now enabled
    ///   - duration: How long to show the HUD (seconds)
    func show(title: String, isEnabled: Bool, duration: TimeInterval = 1.5) {
        // Cancel any existing timer
        hideTimer?.invalidate()
        
        // Update content
        viewModel.title = title
        viewModel.isEnabled = isEnabled
        
        // Create panel if needed
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        // Update size to fit content
        if let hostingController = hostingController {
            let fittingSize = hostingController.view.fittingSize
            panel.setContentSize(fittingSize)
        }
        
        // Center on main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2 - 80 // Slightly below center
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Show with fade-in
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        
        // Schedule hide
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hideWithAnimation()
        }
    }
    
    // MARK: - Private
    
    private func createPanel() {
        let hudView = ToggleHUDView(viewModel: viewModel)
        let controller = NSHostingController(rootView: hudView)
        
        let fittingSize = controller.view.fittingSize
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newPanel.contentViewController = controller
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false // SwiftUI handles shadow
        newPanel.ignoresMouseEvents = true
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        hostingController = controller
        panel = newPanel
    }
    
    private func hideWithAnimation() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }
}

// MARK: - ViewModel

private class ToggleHUDViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var isEnabled: Bool = true
}

// MARK: - SwiftUI HUD View

private struct ToggleHUDView: View {
    @ObservedObject var viewModel: ToggleHUDViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            // Icon
            Image(systemName: viewModel.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(viewModel.isEnabled ? .green : .orange)
            
            // Title
            Text(viewModel.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            // State
            Text(viewModel.isEnabled ? "BẬT" : "TẮT")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(viewModel.isEnabled ? .green : .orange)
        }
        .fixedSize()
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}
