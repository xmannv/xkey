//
//  HotkeyRecorderView.swift
//  XKey
//
//  SwiftUI Hotkey Recorder
//

import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var displayText = ""
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?
    @State private var currentModifiers: NSEvent.ModifierFlags = []
    @State private var modifierPressTime: Date?
    
    var body: some View {
        HStack(spacing: 8) {
            // Display field - clickable to start recording
            Button(action: {
                if !isRecording {
                    startRecording()
                }
            }) {
                HStack {
                    Spacer()
                    Text(displayText.isEmpty ? "Nhấn để ghi phím tắt..." : displayText)
                        .foregroundColor(isRecording ? .red : .primary)
                    Spacer()
                }
                .frame(height: 30)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red : Color.gray.opacity(0.3), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Nhấn phím tắt hoặc giữ modifier keys 0.5s..." : "Nhấn để ghi phím tắt")
            
            // Clear button
            Button(action: clearHotkey) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Xóa phím tắt")
        }
        .onAppear {
            updateDisplay()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        displayText = "Nhấn phím tắt..."
        currentModifiers = []
        modifierPressTime = nil
        
        // Monitor key down events (for regular hotkeys like Cmd+Shift+V)
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard isRecording else { return event }
            
            // Ignore if no modifiers
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if modifiers.isEmpty {
                // Allow Escape to cancel
                if event.keyCode == 53 { // Escape key
                    stopRecording()
                }
                return nil
            }
            
            // Create new hotkey from pressed keys (regular hotkey with key)
            let newHotkey = Hotkey(
                keyCode: event.keyCode,
                modifiers: ModifierFlags(from: modifiers),
                isModifierOnly: false
            )
            
            hotkey = newHotkey
            stopRecording()
            updateDisplay()
            
            return nil
        }
        
        // Monitor flags changed events (for modifier-only hotkeys like Ctrl+Shift)
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            guard isRecording else { return event }
            
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            
            // Check if we have at least 2 modifiers pressed
            let modifierCount = [
                modifiers.contains(.control),
                modifiers.contains(.option),
                modifiers.contains(.shift),
                modifiers.contains(.command)
            ].filter { $0 }.count
            
            if modifierCount >= 2 {
                // Started pressing multiple modifiers
                if currentModifiers != modifiers {
                    currentModifiers = modifiers
                    modifierPressTime = Date()
                    
                    // Update display to show current modifiers
                    let tempHotkey = Hotkey(keyCode: 0, modifiers: ModifierFlags(from: modifiers), isModifierOnly: true)
                    displayText = tempHotkey.displayString + " (giữ 0.5s...)"
                    
                    // Schedule check after 0.5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard isRecording else { return }
                        
                        // Check if same modifiers are still held
                        if let pressTime = modifierPressTime,
                           Date().timeIntervalSince(pressTime) >= 0.5,
                           currentModifiers == modifiers {
                            // Create modifier-only hotkey
                            let newHotkey = Hotkey(
                                keyCode: 0,
                                modifiers: ModifierFlags(from: modifiers),
                                isModifierOnly: true
                            )
                            hotkey = newHotkey
                            stopRecording()
                            updateDisplay()
                        }
                    }
                }
            } else {
                // Modifiers released or only one modifier
                currentModifiers = []
                modifierPressTime = nil
                if isRecording {
                    displayText = "Nhấn phím tắt..."
                }
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        currentModifiers = []
        modifierPressTime = nil
        
        // Remove event monitors
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        
        updateDisplay()
    }
    
    private func clearHotkey() {
        // Stop recording first if active
        if isRecording {
            stopRecording()
        }
        hotkey = Hotkey(keyCode: 0, modifiers: [], isModifierOnly: false)
        updateDisplay()
    }
    
    private func updateDisplay() {
        if hotkey.isModifierOnly && !hotkey.modifiers.isEmpty {
            displayText = hotkey.displayString
        } else if hotkey.keyCode != 0 {
            displayText = hotkey.displayString
        } else {
            displayText = ""
        }
    }
}

// MARK: - Preview

#Preview {
    HotkeyRecorderView(hotkey: .constant(Hotkey(keyCode: 9, modifiers: [.command, .shift], isModifierOnly: false)))
        .padding()
}
