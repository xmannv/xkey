//
//  DebugWindowController.swift
//  XKey
//
//  Window controller for SwiftUI Debug Window
//

import Cocoa
import SwiftUI

class DebugWindowController: NSWindowController, DebugWindowControllerProtocol, NSWindowDelegate {
    
    private let viewModel: DebugViewModel
    private var pinManager: WindowPinManager?
    
    /// Callback when window is closed (via Close button on title bar)
    var onWindowClose: (() -> Void)?
    
    /// Callback when window is closed - used to nil out reference in AppDelegate
    var onWindowClosed: (() -> Void)?
    
    init() {
        self.viewModel = DebugViewModel()
        
        // Create SwiftUI view with shared view model
        let debugView = DebugView(viewModel: viewModel)
        
        // Wrap in hosting controller
        let hostingController = NSHostingController(rootView: debugView)
        
        // Create window with modern styling
        let window = NSWindow(contentViewController: hostingController)
        window.title = "XKey Debug Console"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        // Allow window to be released when closed to free memory
        window.isReleasedWhenClosed = true
        window.setContentSize(NSSize(width: 900, height: 700))
        window.minSize = NSSize(width: 700, height: 500)
        window.level = .floating  // Always on top by default
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        
        super.init(window: window)
        
        // Set window delegate to catch close event
        window.delegate = self
        
        // Setup pin button using shared WindowPinManager
        let pm = WindowPinManager(window: window, initiallyPinned: viewModel.isAlwaysOnTop)
        pm.onToggle = { [weak self] isEnabled in
            self?.viewModel.isAlwaysOnTop = isEnabled
        }
        pm.setupPinButton()
        self.pinManager = pm
        
        // Setup always on top callback (ViewModel → window level + pin button)
        viewModel.alwaysOnTopCallback = { [weak self] isEnabled in
            self?.window?.level = isEnabled ? .floating : .normal
            self?.pinManager?.updatePinButton(isEnabled)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // User clicked the Close button on title bar
        // Notify AppDelegate to disable debug mode
        onWindowClose?()
        
        // Stop ViewModel timers when window closes
        viewModel.stopAllTimers()
        
        // Clear content to release SwiftUI views immediately
        window?.contentViewController = nil
        
        // Notify delegate to nil out the reference
        onWindowClosed?()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    var isLoggingEnabled: Bool {
        return viewModel.isLoggingEnabled
    }
    
    var isVerboseLogging: Bool {
        return viewModel.isVerboseLogging
    }
    
    func setupReadWordCallback(_ callback: @escaping () -> Void) {
        viewModel.readWordCallback = callback
    }
    
    func setupVerboseLoggingCallback(_ callback: @escaping (Bool) -> Void) {
        viewModel.verboseLoggingCallback = callback
    }
    
    func updateStatus(_ status: String) {
        viewModel.updateStatus(status)
    }
    
    func logEvent(_ event: String) {
        viewModel.logEvent(event)
    }
    
    func logKeyEvent(character: Character, keyCode: UInt16, result: String) {
        viewModel.logKeyEvent(character: character, keyCode: keyCode, result: result)
    }
    
    func logEngineResult(input: String, output: String, backspaces: Int) {
        viewModel.logEngineResult(input: input, output: output, backspaces: backspaces)
    }
}
