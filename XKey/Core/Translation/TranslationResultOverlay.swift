//
//  TranslationResultOverlay.swift
//  XKey
//
//  A floating overlay showing translation result.
//  Glassmorphism design with copy button, fade animation,
//  optional auto-hide countdown bar, and click-outside-to-dismiss.
//

import Cocoa
import SwiftUI

class TranslationResultOverlay {
    
    static let shared = TranslationResultOverlay()
    
    private var panel: NSPanel?
    private var isShowing = false
    private let lock = NSLock()
    private var autoHideTimer: DispatchWorkItem?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    
    private init() {}
    
    /// Show translation result overlay near the current mouse position
    /// - Parameters:
    ///   - text: The translated text to display
    ///   - autoHideSeconds: Auto-hide after N seconds. 0 = don't auto-hide, click outside to dismiss.
    func show(text: String, autoHideSeconds: Int = 4) {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel any existing timer
        autoHideTimer?.cancel()
        autoHideTimer = nil
        
        // Remove existing monitors
        removeMonitors()
        
        isShowing = true
        
        if Thread.isMainThread {
            createAndShowWindow(text: text, autoHideSeconds: autoHideSeconds)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.createAndShowWindow(text: text, autoHideSeconds: autoHideSeconds)
            }
        }
    }
    
    /// Hide the result overlay
    func hide() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isShowing else { return }
        isShowing = false
        
        // Cancel timer
        autoHideTimer?.cancel()
        autoHideTimer = nil
        
        if Thread.isMainThread {
            dismissWindow()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.dismissWindow()
            }
        }
    }
    
    private func removeMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }
    
    private func dismissWindow() {
        removeMonitors()
        
        // Fade out animation
        if let p = panel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                p.orderOut(nil)
                self?.panel = nil
            })
        }
    }
    
    private func createAndShowWindow(text: String, autoHideSeconds: Int) {
        // Dismiss any existing window immediately
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        
        let mouseLocation = NSEvent.mouseLocation
        
        // Create hosting view first to measure content size
        let resultView = TranslationResultView(
            text: text,
            autoHideSeconds: autoHideSeconds,
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                // Brief visual feedback then dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.hide()
                }
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        )
        
        let hostingView = NSHostingView(rootView: resultView)
        hostingView.setFrameSize(hostingView.fittingSize)
        
        let contentSize = hostingView.fittingSize
        
        // Position: centered horizontally, above cursor
        // Ensure window stays within screen bounds
        var originX = mouseLocation.x - contentSize.width / 2
        var originY = mouseLocation.y - contentSize.height - 12
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Clamp horizontal
            originX = max(screenFrame.minX + 4, min(originX, screenFrame.maxX - contentSize.width - 4))
            // If would go below screen, show above cursor instead
            if originY < screenFrame.minY {
                originY = mouseLocation.y + 20
            }
        }
        
        // Use NSPanel with .nonactivatingPanel to prevent stealing focus from the active app
        let newPanel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: originX, y: originY), size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        newPanel.ignoresMouseEvents = false
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.minSize = NSSize(width: 200, height: 80)
        newPanel.maxSize = NSSize(width: 600, height: 500)
        newPanel.contentView = hostingView
        
        // Fade in — use orderFrontRegardless to show without activating
        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            newPanel.animator().alphaValue = 1
        }
        
        self.panel = newPanel
        self.isShowing = true
        
        // Setup click-outside-to-dismiss monitor
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        
        // Setup auto-hide timer if > 0
        if autoHideSeconds > 0 {
            let workItem = DispatchWorkItem { [weak self] in
                self?.hide()
            }
            autoHideTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(autoHideSeconds), execute: workItem)
        }
    }
}

// MARK: - SwiftUI Views

struct TranslationResultView: View {
    let text: String
    let autoHideSeconds: Int
    let onCopy: () -> Void
    let onDismiss: () -> Void
    
    @State private var isCopied = false
    @State private var fontSize: CGFloat = 13
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Text("Bản dịch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Font size buttons
                Button(action: { if fontSize > 10 { fontSize -= 1 } }) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(fontSize > 10 ? .secondary : .quaternary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(fontSize <= 10)
                .help("Giảm cỡ chữ")
                
                Button(action: { if fontSize < 24 { fontSize += 1 } }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(fontSize < 24 ? .secondary : .quaternary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(fontSize >= 24)
                .help("Tăng cỡ chữ")
                
                // Copy button
                Button(action: {
                    isCopied = true
                    onCopy()
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isCopied ? .green : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sao chép bản dịch")
                
                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Đóng")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            Divider()
                .padding(.horizontal, 8)
            
            // Translation text with scroll for long content
            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: 200)
            
            // Auto-hide countdown bar
            if autoHideSeconds > 0 {
                AutoHideProgressBar(duration: Double(autoHideSeconds))
                    .frame(height: 2)
            }
        }
        .frame(minWidth: 200, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Auto-hide Progress Bar

struct AutoHideProgressBar: View {
    let duration: Double
    
    @State private var progress: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                
                // Fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .cyan.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 0
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TranslationResultView(
            text: "Hello World",
            autoHideSeconds: 5,
            onCopy: {},
            onDismiss: {}
        )
        TranslationResultView(
            text: "Đây là một bản dịch dài hơn để kiểm tra khả năng hiển thị nhiều dòng text và xem giao diện có đẹp không.",
            autoHideSeconds: 0,
            onCopy: {},
            onDismiss: {}
        )
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
