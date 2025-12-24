//
//  HotkeyRecorderView.swift
//  XKey
//
//  SwiftUI Hotkey Recorder
//

import SwiftUI

// MARK: - Preset Hotkeys

/// Common hotkey presets that users can quickly select
private struct HotkeyPreset: Identifiable {
    let id = UUID()
    let name: String
    let hotkey: Hotkey
    
    static let presets: [HotkeyPreset] = [
        // Modifier-only presets
        HotkeyPreset(name: "⌃Space (Ctrl+Space)", hotkey: Hotkey(keyCode: 49, modifiers: [.control], isModifierOnly: false)), // Space = 49
        HotkeyPreset(name: "Fn", hotkey: Hotkey(keyCode: 0, modifiers: [.function], isModifierOnly: true)),
        HotkeyPreset(name: "⌥Z (Alt+Z)", hotkey: Hotkey(keyCode: 6, modifiers: [.option], isModifierOnly: false)), // Z = 6
        HotkeyPreset(name: "⌃⇧ (Ctrl+Shift)", hotkey: Hotkey(keyCode: 0, modifiers: [.control, .shift], isModifierOnly: true)),
        HotkeyPreset(name: "⌥⇧ (Option+Shift)", hotkey: Hotkey(keyCode: 0, modifiers: [.option, .shift], isModifierOnly: true)),
        HotkeyPreset(name: "⌘⇧ (Cmd+Shift)", hotkey: Hotkey(keyCode: 0, modifiers: [.command, .shift], isModifierOnly: true)),
        
        // Common key combinations
        HotkeyPreset(name: "⌘⇧V", hotkey: Hotkey(keyCode: 9, modifiers: [.command, .shift], isModifierOnly: false)), // V = 9
        HotkeyPreset(name: "⌘⇧Z", hotkey: Hotkey(keyCode: 6, modifiers: [.command, .shift], isModifierOnly: false)), // Z = 6
        HotkeyPreset(name: "⌃⌥V", hotkey: Hotkey(keyCode: 9, modifiers: [.control, .option], isModifierOnly: false)),
    ]
}

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
            
            // Preset menu - allows selecting common hotkeys that may be hard to record
            Menu {
                ForEach(HotkeyPreset.presets) { preset in
                    Button(preset.name) {
                        selectPreset(preset)
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("Chọn phím tắt có sẵn (hữu ích cho Ctrl+Space, Fn...)")
            
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
    
    private func selectPreset(_ preset: HotkeyPreset) {
        // Stop recording if active
        if isRecording {
            stopRecording()
        }
        hotkey = preset.hotkey
        updateDisplay()
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
        
        // Monitor flags changed events (for modifier-only hotkeys like Ctrl+Shift or Fn)
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            guard isRecording else { return event }
            
            // Include .function for Fn key support
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
            
            // Check modifier conditions:
            // - If Fn is pressed (alone or with others), allow it
            // - Otherwise require at least 2 modifiers
            let hasFn = modifiers.contains(.function)
            let otherModifierCount = [
                modifiers.contains(.control),
                modifiers.contains(.option),
                modifiers.contains(.shift),
                modifiers.contains(.command)
            ].filter { $0 }.count
            
            // Allow: Fn alone, Fn + others, or 2+ other modifiers
            let isValidModifierCombo = hasFn || otherModifierCount >= 2
            
            if isValidModifierCombo {
                // Started pressing valid modifier combination
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
                // Modifiers released or insufficient modifiers
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
