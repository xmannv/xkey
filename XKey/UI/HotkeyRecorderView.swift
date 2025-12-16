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
    @State private var eventMonitor: Any?
    
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
            .help(isRecording ? "Nhấn phím tắt của bạn..." : "Nhấn để ghi phím tắt")
            
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
        
        // Store current hotkey to compare
        let currentHotkey = hotkey
        
        // Start monitoring key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
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
            
            // Create new hotkey from pressed keys
            let newHotkey = Hotkey(
                keyCode: event.keyCode,
                modifiers: ModifierFlags(from: modifiers)
            )
            
            // Update hotkey (even if it's the same as current)
            hotkey = newHotkey
            stopRecording()
            updateDisplay()
            
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        
        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        updateDisplay()
    }
    
    private func clearHotkey() {
        hotkey = Hotkey(keyCode: 0, modifiers: [])
        updateDisplay()
    }
    
    private func updateDisplay() {
        if hotkey.keyCode != 0 {
            displayText = hotkey.displayString
        } else {
            displayText = ""
        }
    }
}

// MARK: - Preview

#Preview {
    HotkeyRecorderView(hotkey: .constant(Hotkey(keyCode: 9, modifiers: [.command, .shift])))
        .padding()
}
