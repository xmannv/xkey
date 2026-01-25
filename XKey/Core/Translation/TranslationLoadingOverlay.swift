//
//  TranslationLoadingOverlay.swift
//  XKey
//
//  A minimal floating overlay showing translation in progress.
//  Dark, compact, clean design.
//

import Cocoa
import SwiftUI

class TranslationLoadingOverlay {
    
    static let shared = TranslationLoadingOverlay()
    
    private var window: NSWindow?
    private var isShowing = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Show loading overlay near the current mouse position
    func show() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isShowing else { return }
        isShowing = true
        
        if Thread.isMainThread {
            createAndShowWindow()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.createAndShowWindow()
            }
        }
    }
    
    /// Hide the loading overlay
    func hide() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isShowing else { return }
        isShowing = false
        
        if Thread.isMainThread {
            dismissWindow()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.dismissWindow()
            }
        }
    }
    
    private func dismissWindow() {
        window?.orderOut(nil)
        window = nil
    }
    
    private func createAndShowWindow() {
        let mouseLocation = NSEvent.mouseLocation
        
        // Create hosting view first to measure content size
        let hostingView = NSHostingView(rootView: LoadingOverlayView())
        hostingView.setFrameSize(hostingView.fittingSize)
        
        let contentSize = hostingView.fittingSize
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
    }
}

// MARK: - SwiftUI View

struct LoadingOverlayView: View {
    var body: some View {
        HStack(spacing: 8) {
            // Custom spinning circle
            SpinningCircle()
                .frame(width: 10, height: 10)
            
            Text("Translating...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.9))
        )
        .fixedSize()
    }
}

// Custom spinning circle animation
struct SpinningCircle: View {
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
    LoadingOverlayView()
        .padding(20)
        .background(Color.gray)
}
