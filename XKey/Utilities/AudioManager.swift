//
//  AudioManager.swift
//  XKey
//
//  Manages audio playback with wake-from-sleep handling
//  to fix audio routing issues after Mac wakes up
//

import AppKit
import CoreAudio

/// Manages audio playback with proper handling for system sleep/wake events
/// 
/// Problem: When Mac wakes from sleep with wired headphones plugged in,
/// macOS sometimes doesn't properly reconnect audio routing, causing
/// NSSound.beep() to fail silently.
///
/// Solution: Listen for wake notifications and "warm up" the audio system
/// by playing a silent sound to reinitialize audio routing.
final class AudioManager {
    
    // MARK: - Singleton
    static let shared = AudioManager()
    
    // MARK: - Properties
    
    /// Thread-safe flag indicating if audio system is ready
    /// Uses atomic operations for thread safety
    private let audioReadyLock = NSLock()
    private var _isAudioReady = true
    private var isAudioReady: Bool {
        get {
            audioReadyLock.lock()
            defer { audioReadyLock.unlock() }
            return _isAudioReady
        }
        set {
            audioReadyLock.lock()
            _isAudioReady = newValue
            audioReadyLock.unlock()
        }
    }
    
    /// Dedicated queue for audio operations
    private let audioQueue = DispatchQueue(label: "com.xkey.audio", qos: .userInteractive)
    
    /// Listener for CoreAudio device changes
    private var audioDeviceListener: AudioObjectPropertyListenerProc?
    
    // MARK: - Initialization
    
    private init() {
        setupWakeNotifications()
        setupAudioDeviceListener()
    }
    
    deinit {
        removeAudioDeviceListener()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Wake Notification Handling
    
    /// Setup observers for system sleep/wake notifications
    private func setupWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // Listen for wake from sleep
        notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Listen for sleep (to prepare for wake)
        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }
    
    /// Setup listener for audio device changes (plug/unplug headphones)
    private func setupAudioDeviceListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Add listener for default output device changes
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioQueue
        ) { [weak self] _, _ in
            self?.handleAudioDeviceChange()
        }
        
        if status != noErr {
            NSLog("[AudioManager] Failed to add audio device listener: \(status)")
        }
    }
    
    private func removeAudioDeviceListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioQueue,
            { _, _ in }
        )
    }
    
    // MARK: - Event Handlers
    
    @objc private func handleSystemWillSleep(_ notification: Notification) {
        isAudioReady = false
        NSLog("[AudioManager] System going to sleep")
    }
    
    @objc private func handleWakeFromSleep(_ notification: Notification) {
        NSLog("[AudioManager] System woke up - scheduling audio refresh")
        
        // Delay to let audio system fully initialize
        audioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAudioSystem()
        }
    }
    
    private func handleAudioDeviceChange() {
        NSLog("[AudioManager] Audio device changed")
        refreshAudioSystem()
    }
    
    // MARK: - Audio System Management
    
    /// Refresh the audio system to re-establish audio routing
    /// Plays a silent sound to "warm up" the audio subsystem
    private func refreshAudioSystem() {
        DispatchQueue.main.async { [weak self] in
            // Play a silent system sound to wake up audio routing
            // "Blow" is a standard macOS system sound
            if let silentSound = NSSound(named: NSSound.Name("Blow")) {
                silentSound.volume = 0.0
                silentSound.play()
                
                // Stop after brief warmup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    silentSound.stop()
                }
            }
            
            // Mark audio as ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.isAudioReady = true
                NSLog("[AudioManager] Audio system ready")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Play the system beep sound
    /// Handles wake-from-sleep audio routing issues automatically
    func playBeep() {
        // Fast path: audio is ready, play immediately on main thread
        if isAudioReady {
            DispatchQueue.main.async {
                NSSound.beep()
            }
            return
        }
        
        // Slow path: need to refresh audio first
        NSLog("[AudioManager] Audio not ready, refreshing before beep")
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Refresh and wait for completion
            let semaphore = DispatchSemaphore(value: 0)
            
            DispatchQueue.main.async {
                self.refreshAudioSystem()
            }
            
            // Wait up to 300ms for refresh
            _ = semaphore.wait(timeout: .now() + 0.3)
            
            // Play beep on main thread
            DispatchQueue.main.async {
                NSSound.beep()
            }
        }
    }
    
    /// Force refresh the audio system
    /// Call this if you know audio might be in a bad state
    func forceRefresh() {
        isAudioReady = false
        audioQueue.async { [weak self] in
            self?.refreshAudioSystem()
        }
    }
}
