//
//  SessionMonitoringTests.swift
//  XKeyTests
//
//  Unit tests for multi-user session monitoring (Fast User Switching)
//  Tests the notification-driven session state management in EventTapManager
//  and the delegate callback in KeyboardEventHandler.
//

import XCTest
@testable import XKey

// MARK: - Mock Delegate for Testing

/// Mock delegate that records sessionDidBecomeActive() calls
class MockEventTapDelegate: EventTapManager.EventTapDelegate {
    var sessionDidBecomeActiveCalled = false
    var sessionDidBecomeActiveCallCount = 0
    
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        return true
    }
    
    func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent? {
        return event
    }
    
    func sessionDidBecomeActive() {
        sessionDidBecomeActiveCalled = true
        sessionDidBecomeActiveCallCount += 1
    }
}

// MARK: - Session Monitoring Tests

class SessionMonitoringTests: XCTestCase {
    
    var eventTapManager: EventTapManager!
    
    override func setUp() {
        super.setUp()
        eventTapManager = EventTapManager()
    }
    
    override func tearDown() {
        eventTapManager = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    /// Verify that EventTapManager starts with isSessionOnConsole = true
    /// when running in the current (active) session
    func testInitialState_OnConsole() {
        // When running tests, we ARE on the console
        XCTAssertTrue(eventTapManager.isSessionOnConsole,
            "Should default to on-console when running in active session")
    }
    
    /// Verify that session observers are set up during init
    func testInitialState_ObserversRegistered() {
        XCTAssertFalse(eventTapManager.sessionObservers.isEmpty,
            "Session observers should be registered during init")
        XCTAssertEqual(eventTapManager.sessionObservers.count, 2,
            "Should have exactly 2 observers (resign + become active)")
    }
    
    // MARK: - Notification Response Tests
    
    /// Simulate user switching AWAY from this session
    func testSessionResignActive_SetsOffConsole() {
        // Precondition: on console
        XCTAssertTrue(eventTapManager.isSessionOnConsole)
        
        // Post resign notification (simulates Fast User Switch away)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Should now be off-console
        XCTAssertFalse(eventTapManager.isSessionOnConsole,
            "isSessionOnConsole should be false after resignActive notification")
    }
    
    /// Simulate user switching BACK to this session
    func testSessionBecomeActive_SetsOnConsole() {
        // Force off-console first
        eventTapManager.isSessionOnConsole = false
        XCTAssertFalse(eventTapManager.isSessionOnConsole)
        
        // Post becomeActive notification (simulates Fast User Switch back)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Should now be on-console
        XCTAssertTrue(eventTapManager.isSessionOnConsole,
            "isSessionOnConsole should be true after becomeActive notification")
    }
    
    /// Test full round-trip: on → off → on
    func testSessionRoundTrip() {
        // Start on-console
        XCTAssertTrue(eventTapManager.isSessionOnConsole)
        
        // Switch away
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        XCTAssertFalse(eventTapManager.isSessionOnConsole,
            "Should be off-console after resign")
        
        // Switch back
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: NSWorkspace.shared
        )
        XCTAssertTrue(eventTapManager.isSessionOnConsole,
            "Should be on-console after become active")
    }
    
    /// Verify multiple resign notifications don't cause issues
    func testMultipleResignNotifications() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Should still be off-console (idempotent)
        XCTAssertFalse(eventTapManager.isSessionOnConsole,
            "Multiple resign notifications should keep off-console state")
    }
    
    // MARK: - Delegate Callback Tests
    
    /// Verify delegate.sessionDidBecomeActive() is called on becomeActive
    func testDelegateCalled_OnBecomeActive() {
        let mockDelegate = MockEventTapDelegate()
        eventTapManager.delegate = mockDelegate
        
        // Force off-console, then switch back
        eventTapManager.isSessionOnConsole = false
        
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Delegate call is dispatched async on main queue — drain the run loop
        let expectation = expectation(description: "Delegate called")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(mockDelegate.sessionDidBecomeActiveCalled,
            "Delegate should receive sessionDidBecomeActive() callback")
        XCTAssertEqual(mockDelegate.sessionDidBecomeActiveCallCount, 1,
            "Delegate should be called exactly once per becomeActive notification")
    }
    
    /// Verify delegate is NOT called on resign (only on become active)
    func testDelegateNotCalled_OnResign() {
        let mockDelegate = MockEventTapDelegate()
        eventTapManager.delegate = mockDelegate
        
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Drain run loop
        let expectation = expectation(description: "Run loop drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertFalse(mockDelegate.sessionDidBecomeActiveCalled,
            "Delegate should NOT receive callback on resignActive")
    }
    
    /// Verify no crash when delegate is nil during becomeActive
    func testNilDelegate_NoCrash() {
        eventTapManager.delegate = nil
        eventTapManager.isSessionOnConsole = false
        
        // Should not crash
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: NSWorkspace.shared
        )
        
        // Drain run loop
        let expectation = expectation(description: "Run loop drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(eventTapManager.isSessionOnConsole,
            "State should update even with nil delegate")
    }
    
    // MARK: - Observer Cleanup Tests
    
    /// Verify observers are removed when EventTapManager is deallocated
    func testObserverCleanup_OnDeinit() {
        // Create and immediately release
        var manager: EventTapManager? = EventTapManager()
        let observerCount = manager!.sessionObservers.count
        XCTAssertEqual(observerCount, 2, "Should have 2 observers before deinit")
        
        manager = nil
        // After deinit, observers should be removed from notification center
        // We can't directly verify removal, but we verify no crash/leak
        // by forcing a notification after deinit
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        // No crash = success
    }
    
    // MARK: - Debug Callback Tests
    
    /// Verify debug log messages are emitted for session state changes
    func testDebugLog_SessionResign() {
        var logMessages: [String] = []
        eventTapManager.debugLogCallback = { message in
            logMessages.append(message)
        }
        
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: NSWorkspace.shared
        )
        
        let hasResignLog = logMessages.contains { $0.contains("resigned active") }
        XCTAssertTrue(hasResignLog,
            "Should log session resign event. Logs: \(logMessages)")
    }
    
    func testDebugLog_SessionBecomeActive() {
        var logMessages: [String] = []
        eventTapManager.debugLogCallback = { message in
            logMessages.append(message)
        }
        
        eventTapManager.isSessionOnConsole = false
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: NSWorkspace.shared
        )
        
        let hasBecomeActiveLog = logMessages.contains { $0.contains("became active") }
        XCTAssertTrue(hasBecomeActiveLog,
            "Should log session become active event. Logs: \(logMessages)")
    }
}

// MARK: - KeyboardEventHandler Session Tests

class KeyboardEventHandlerSessionTests: XCTestCase {
    
    var handler: KeyboardEventHandler!
    
    override func setUp() {
        super.setUp()
        handler = KeyboardEventHandler()
    }
    
    override func tearDown() {
        handler = nil
        super.tearDown()
    }
    
    /// Verify sessionDidBecomeActive() resets engine state
    func testSessionDidBecomeActive_ResetsEngine() {
        // Type some characters to build up engine buffer
        _ = handler.engine.processKey(
            character: "v", keyCode: VietnameseData.KEY_V, isUppercase: false
        )
        _ = handler.engine.processKey(
            character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false
        )
        _ = handler.engine.processKey(
            character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false
        )
        
        // Verify buffer has content
        XCTAssertGreaterThan(handler.engine.index, 0,
            "Engine should have buffered characters")
        
        // Call sessionDidBecomeActive
        handler.sessionDidBecomeActive()
        
        // Verify engine was reset
        XCTAssertEqual(handler.engine.index, 0,
            "Engine buffer should be cleared after sessionDidBecomeActive()")
    }
    
    /// Verify debug log is emitted during session reset
    func testSessionDidBecomeActive_LogsMessage() {
        var logMessages: [String] = []
        handler.debugLogCallback = { message in
            logMessages.append(message)
        }
        
        handler.sessionDidBecomeActive()
        
        let hasSessionLog = logMessages.contains { $0.contains("Session active") }
        XCTAssertTrue(hasSessionLog,
            "Should log session active message. Logs: \(logMessages)")
    }
}

// MARK: - Default Protocol Extension Tests

class EventTapDelegateDefaultTests: XCTestCase {
    
    /// Verify that a conformer that doesn't override sessionDidBecomeActive
    /// compiles and runs without issues (tests the default no-op extension)
    func testDefaultImplementation_NoOp() {
        // MinimalDelegate only implements required methods, doesn't override sessionDidBecomeActive
        // The fact that this compiles proves the default extension works
        let delegate = MinimalDelegate()
        
        // Should not crash — calls the default no-op implementation
        delegate.sessionDidBecomeActive()
    }
}

/// Minimal conformer that relies on default sessionDidBecomeActive() implementation
private class MinimalDelegate: EventTapManager.EventTapDelegate {
    func shouldProcessEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        return true
    }
    
    func processKeyEvent(_ event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) -> CGEvent? {
        return event
    }
    // sessionDidBecomeActive() intentionally NOT implemented — uses default extension
}
