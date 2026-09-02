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
        
        // Common key combinations (2+ modifiers)
        HotkeyPreset(name: "⌘⌥T", hotkey: Hotkey(keyCode: 0x11, modifiers: [.command, .option], isModifierOnly: false)), // T = 0x11
        HotkeyPreset(name: "⌘⇧V", hotkey: Hotkey(keyCode: 9, modifiers: [.command, .shift], isModifierOnly: false)), // V = 9
        HotkeyPreset(name: "⌘⇧Z", hotkey: Hotkey(keyCode: 6, modifiers: [.command, .shift], isModifierOnly: false)), // Z = 6
        HotkeyPreset(name: "⌃⌥V", hotkey: Hotkey(keyCode: 9, modifiers: [.control, .option], isModifierOnly: false)),
        HotkeyPreset(name: "⌃⌥T", hotkey: Hotkey(keyCode: 0x11, modifiers: [.control, .option], isModifierOnly: false)),
        HotkeyPreset(name: "⌘⌃T", hotkey: Hotkey(keyCode: 0x11, modifiers: [.command, .control], isModifierOnly: false)),
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
    @State private var showMinimumWarning = false
    
    /// Minimum number of modifiers required (e.g., 2 for toolbar hotkey to avoid Ctrl/Option conflicts)
    var minimumModifiers: Int = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Display field - clickable to start recording
                Button(action: {
                    if !isRecording {
                        startRecording()
                    }
                }) {
                    HStack {
                        Spacer()
                        // Prompt text needs localization; recorded hotkey values are
                        // symbol-only ("⌘⇧V") so they bypass the catalog as verbatim.
                        if displayText.isEmpty {
                            Text("Nhấn để ghi phím tắt...")
                                .foregroundColor(isRecording ? .red : .primary)
                        } else {
                            Text(displayText)
                                .foregroundColor(isRecording ? .red : .primary)
                        }
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
                .help(isRecording
                      ? String(localized: "Nhấn phím tắt hoặc giữ modifier keys 0.5s...")
                      : String(localized: "Nhấn để ghi phím tắt"))
                
                // Preset menu - allows selecting common hotkeys that may be hard to record
                Menu {
                    ForEach(HotkeyPreset.presets.filter { preset in
                        // Filter presets based on minimumModifiers
                        if minimumModifiers >= 2 {
                            // Only show presets with 2+ modifiers
                            let modCount = [
                                preset.hotkey.modifiers.contains(.control),
                                preset.hotkey.modifiers.contains(.option),
                                preset.hotkey.modifiers.contains(.shift),
                                preset.hotkey.modifiers.contains(.command)
                            ].filter { $0 }.count
                            return modCount >= minimumModifiers && !preset.hotkey.isModifierOnly
                        }
                        return true
                    }) { preset in
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
            
            // Warning message when minimum modifiers not met
            if showMinimumWarning {
                Text("⚠️ Yêu cầu tối thiểu \(minimumModifiers) modifier keys (Cmd, Option, Ctrl, Shift)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
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
        showMinimumWarning = false
        updateDisplay()
    }
    
    private func startRecording() {
        isRecording = true
        displayText = String(localized: "Nhấn phím tắt...")
        currentModifiers = []
        modifierPressTime = nil
        showMinimumWarning = false
        
        // Notify that recording started (so EventTapManager can suspend hotkey processing)
        NotificationCenter.default.post(
            name: .hotkeyRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": true]
        )
        
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
            
            // Count modifiers
            let modifierCount = [
                modifiers.contains(.control),
                modifiers.contains(.option),
                modifiers.contains(.shift),
                modifiers.contains(.command)
            ].filter { $0 }.count
            
            // Check minimum modifiers requirement
            if modifierCount < minimumModifiers {
                showMinimumWarning = true
                // Don't accept, keep recording
                return nil
            }
            
            // Create new hotkey from pressed keys (regular hotkey with key)
            let newHotkey = Hotkey(
                keyCode: event.keyCode,
                modifiers: ModifierFlags(from: modifiers),
                isModifierOnly: false
            )
            
            hotkey = newHotkey
            showMinimumWarning = false
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
                    displayText = String(localized: "\(tempHotkey.displayString) (giữ 0.5s...)")
                    
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
                    displayText = String(localized: "Nhấn phím tắt...")
                }
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        currentModifiers = []
        modifierPressTime = nil
        
        // Notify that recording stopped (so EventTapManager can resume hotkey processing)
        NotificationCenter.default.post(
            name: .hotkeyRecordingStateChanged,
            object: nil,
            userInfo: ["isRecording": false]
        )
        
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
