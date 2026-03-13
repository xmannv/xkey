//
//  TranslationLoadingOverlay.swift
//  XKey
//
//  A minimal floating overlay showing translation status.
//  Dark, compact, clean design. Supports loading spinner and brief messages.
//

import Cocoa
import SwiftUI

class TranslationLoadingOverlay {
    
    static let shared = TranslationLoadingOverlay()
    
    private var window: NSWindow?
    private var isShowing = false
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Show loading overlay (spinning indicator) near the current mouse position
    func show() {
        showOverlay(content: AnyView(LoadingOverlayView()))
    }
    
    /// Show a brief message overlay (e.g., "Copied ✓") that auto-hides
    func showBrief(message: String, duration: TimeInterval = 1.2) {
        showOverlay(
            content: AnyView(BriefOverlayView(message: message)),
            autoHideAfter: duration
        )
    }
    
    /// Hide the overlay
    func hide() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isShowing else { return }
        isShowing = false
        
        onMainThread { [weak self] in
            self?.dismissWindow()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Unified method to show any SwiftUI view as a floating overlay
    private func showOverlay(content: AnyView, autoHideAfter: TimeInterval? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        // Dismiss any existing overlay first
        if isShowing {
            isShowing = false
            dismissWindow()
        }
        
        isShowing = true
        
        onMainThread { [weak self] in
            guard let self = self else { return }
            
            let hostingView = NSHostingView(rootView: content)
            hostingView.setFrameSize(hostingView.fittingSize)
            
            let contentSize = hostingView.fittingSize
            let mouseLocation = NSEvent.mouseLocation
            let windowOrigin = NSPoint(
                x: mouseLocation.x - contentSize.width / 2,
                y: mouseLocation.y - contentSize.height - 15
            )
            
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
            
            newWindow.orderFront(nil)
            self.window = newWindow
            
            // Schedule auto-hide if specified
            if let duration = autoHideAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    self?.hide()
                }
            }
        }
    }
    
    /// Dismiss the current window
    private func dismissWindow() {
        window?.orderOut(nil)
        window = nil
    }
    
    /// Execute block on main thread, dispatch if needed
    private func onMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - SwiftUI Views

/// Shared capsule background modifier for overlay views
private struct OverlayCapsuleStyle: ViewModifier {
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

struct LoadingOverlayView: View {
    var body: some View {
        HStack(spacing: 8) {
            SpinningCircle()
                .frame(width: 10, height: 10)
            
            Text("Translating...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .modifier(OverlayCapsuleStyle())
    }
}

struct BriefOverlayView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.green)
            
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .modifier(OverlayCapsuleStyle())
    }
}

// MARK: - Spinner Animation

private struct SpinningCircle: View {
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

#Preview {
    VStack(spacing: 20) {
        LoadingOverlayView()
        BriefOverlayView(message: "Copied")
    }
    .padding(20)
    .background(Color.gray)
}
