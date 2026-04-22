//
//  FloatingOverlay.swift
//  XKey
//
//  Shared floating overlay component for displaying brief status messages.
//  Supports multiple positioning modes, auto-dismiss, and fade animations.
//  Used by: Translation, Secure Input warning, and any future overlay needs.
//

import Cocoa
import SwiftUI

// MARK: - Overlay Position

/// Where the overlay should appear on screen
enum OverlayPosition {
    /// Near the current mouse cursor
    case nearMouse
    /// Top-center of the main screen
    case topCenter
    /// Bottom-center of the main screen
    case bottomCenter
}

// MARK: - FloatingOverlay

/// A reusable floating overlay that displays any SwiftUI view in a borderless window.
///
/// Usage:
/// ```
/// FloatingOverlay.shared.show(content: AnyView(MyView()), position: .nearMouse)
/// FloatingOverlay.shared.show(content: AnyView(MyView()), position: .topCenter, autoHideAfter: 3.0)
/// FloatingOverlay.shared.hide()
/// ```
class FloatingOverlay {
    
    static let shared = FloatingOverlay()
    
    private var window: NSWindow?
    private var isShowing = false
    private let lock = NSLock()
    private var autoHideWorkItem: DispatchWorkItem?
    
    /// Create a new independent overlay instance.
    /// Use separate instances when multiple overlays must coexist
    /// (e.g., translation loading + secure input warning).
    init() {}
    
    // MARK: - Public API
    
    /// Show a SwiftUI view as a floating overlay
    /// - Parameters:
    ///   - content: Any SwiftUI view wrapped in AnyView
    ///   - position: Where to display the overlay (default: nearMouse)
    ///   - autoHideAfter: Auto-dismiss after this duration (nil = manual dismiss)
    ///   - animated: Whether to use fade in/out animation (default: true)
    func show(
        content: AnyView,
        position: OverlayPosition = .nearMouse,
        autoHideAfter: TimeInterval? = nil,
        animated: Bool = true
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel any pending auto-hide
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        
        // Dismiss existing overlay first
        if isShowing {
            isShowing = false
            let oldWindow = window
            window = nil
            oldWindow?.orderOut(nil)
        }
        
        isShowing = true
        
        onMainThread { [weak self] in
            guard let self = self else { return }
            
            let hostingView = NSHostingView(rootView: content)
            let contentSize = hostingView.fittingSize
            let windowOrigin = self.calculateOrigin(for: position, contentSize: contentSize)
            
            let newWindow = NSWindow(
                contentRect: NSRect(origin: windowOrigin, size: contentSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = true
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
            newWindow.ignoresMouseEvents = true
            newWindow.contentView = hostingView
            
            if animated {
                newWindow.alphaValue = 0
            }
            
            newWindow.orderFront(nil)
            self.window = newWindow
            
            // Fade in
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    newWindow.animator().alphaValue = 1
                }
            }
            
            // Schedule auto-hide if specified
            if let duration = autoHideAfter {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.hide()
                }
                self.autoHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
            }
        }
    }
    
    /// Hide the overlay with optional fade-out animation
    func hide(animated: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel any pending auto-hide
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        
        guard isShowing else { return }
        isShowing = false
        
        // Capture the window reference to dismiss — prevents racing with a
        // subsequent show() that may create a new window during the fade-out.
        let windowToDismiss = window
        window = nil
        
        onMainThread {
            guard let windowToDismiss = windowToDismiss else { return }
            
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    windowToDismiss.animator().alphaValue = 0
                }, completionHandler: {
                    windowToDismiss.orderOut(nil)
                })
            } else {
                windowToDismiss.orderOut(nil)
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Show a loading spinner with text
    func showLoading(_ text: String = "Translating...") {
        show(
            content: AnyView(OverlayLoadingView(text: text)),
            position: .nearMouse
        )
    }
    
    /// Show a brief success/info message that auto-dismisses
    func showBrief(_ message: String, icon: String = "checkmark.circle.fill", iconColor: Color = .green, duration: TimeInterval = 1.2) {
        show(
            content: AnyView(OverlayBriefView(message: message, icon: icon, iconColor: iconColor)),
            position: .nearMouse,
            autoHideAfter: duration
        )
    }
    
    /// Show a warning message at the top of the screen
    func showWarning(title: String, subtitle: String, duration: TimeInterval = 5.0) {
        show(
            content: AnyView(OverlayWarningView(title: title, subtitle: subtitle)),
            position: .topCenter,
            autoHideAfter: duration
        )
    }
    
    // MARK: - Private Helpers
    
    /// Calculate window origin based on position mode
    private func calculateOrigin(for position: OverlayPosition, contentSize: NSSize) -> NSPoint {
        switch position {
        case .nearMouse:
            let mouseLocation = NSEvent.mouseLocation
            return NSPoint(
                x: mouseLocation.x - contentSize.width / 2,
                y: mouseLocation.y - contentSize.height - 15
            )
            
        case .topCenter:
            guard let screen = NSScreen.main else {
                return NSPoint(x: 100, y: 100)
            }
            let screenFrame = screen.visibleFrame
            return NSPoint(
                x: screenFrame.midX - contentSize.width / 2,
                y: screenFrame.maxY - contentSize.height - 10
            )
            
        case .bottomCenter:
            guard let screen = NSScreen.main else {
                return NSPoint(x: 100, y: 100)
            }
            let screenFrame = screen.visibleFrame
            return NSPoint(
                x: screenFrame.midX - contentSize.width / 2,
                y: screenFrame.minY + 10
            )
        }
    }
    
    private func onMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - Shared SwiftUI Overlay Views

/// Dark capsule background modifier
struct OverlayCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.9))
            )
            .fixedSize()
    }
}

/// Loading spinner with text
struct OverlayLoadingView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            OverlaySpinner()
                .frame(width: 10, height: 10)
            
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .modifier(OverlayCapsuleStyle())
    }
}

/// Brief message with icon (e.g., "Copied ✓")
struct OverlayBriefView: View {
    let message: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(iconColor)
            
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .modifier(OverlayCapsuleStyle())
    }
}

/// Warning with title + subtitle and accent border
struct OverlayWarningView: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .fixedSize()
    }
}

/// Spinning circle animation
struct OverlaySpinner: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.white, lineWidth: 2)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 0.8).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        OverlayLoadingView(text: "Translating...")
        OverlayBriefView(message: "Copied", icon: "checkmark.circle.fill", iconColor: .green)
        OverlayWarningView(title: "Secure Input đang bật", subtitle: "Bởi 1Password — XKey không thể nhận phím")
    }
    .padding(20)
    .background(Color.gray)
}
