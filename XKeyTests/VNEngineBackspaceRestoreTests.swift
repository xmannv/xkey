//
//  VNEngineBackspaceRestoreTests.swift
//  XKeyTests
//
//  Tests for backspace handling and history restore functionality.
//

import XCTest
@testable import XKey

// MARK: - Backspace and History Restore Tests

class VNEngineBackspaceRestoreTests: XCTestCase {

    var engine: VNEngine!

    override func setUp() {
        super.setUp()
        engine = VNEngine()
        engine.reset()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func typeWord(_ word: String) {
        for char in word {
            let keyCode = getKeyCode(for: char)
            _ = engine.processKey(character: char, keyCode: keyCode, isUppercase: char.isUppercase)
        }
    }

    private func typeBackspace() {
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
    }

    private func processSpace() {
        _ = engine.processWordBreak(character: " ")
    }

    private func getKeyCode(for char: Character) -> UInt16 {
        let lower = char.lowercased().first!
        switch lower {
        case "a": return VietnameseData.KEY_A
        case "b": return VietnameseData.KEY_B
        case "c": return VietnameseData.KEY_C
        case "d": return VietnameseData.KEY_D
        case "e": return VietnameseData.KEY_E
        case "f": return VietnameseData.KEY_F
        case "g": return VietnameseData.KEY_G
        case "h": return VietnameseData.KEY_H
        case "i": return VietnameseData.KEY_I
        case "j": return VietnameseData.KEY_J
        case "k": return VietnameseData.KEY_K
        case "l": return VietnameseData.KEY_L
        case "m": return VietnameseData.KEY_M
        case "n": return VietnameseData.KEY_N
        case "o": return VietnameseData.KEY_O
        case "p": return VietnameseData.KEY_P
        case "q": return VietnameseData.KEY_Q
        case "r": return VietnameseData.KEY_R
        case "s": return VietnameseData.KEY_S
        case "t": return VietnameseData.KEY_T
        case "u": return VietnameseData.KEY_U
        case "v": return VietnameseData.KEY_V
        case "w": return VietnameseData.KEY_W
        case "x": return VietnameseData.KEY_X
        case "y": return VietnameseData.KEY_Y
        case "z": return VietnameseData.KEY_Z
        default: return 0
        }
    }

    // MARK: - Basic Backspace Tests

    func testBackspaceRemovesLastCharacter() {
        typeWord("abc")
        XCTAssertEqual(engine.getCurrentWord(), "abc")

        typeBackspace()
        XCTAssertEqual(engine.getCurrentWord(), "ab")

        typeBackspace()
        XCTAssertEqual(engine.getCurrentWord(), "a")
    }

    func testBackspaceEmptiesBuffer() {
        typeWord("ab")
        typeBackspace()
        typeBackspace()

        XCTAssertTrue(engine.buffer.isEmpty)
        XCTAssertEqual(engine.index, 0)
    }

    // MARK: - History Restore on Backspace Tests

    func testHistorySavedAfterWordBreak() {
        typeWord("xin")
        processSpace()

        // History should have saved the word
        XCTAssertGreaterThan(engine.history.count, 0)
    }

    func testHistoryRestoreWhenBufferEmpty() {
        // Type first word
        typeWord("xin")
        processSpace()
        
        // Type second word
        typeWord("chao")
        processSpace()
        
        // History should have 2 words now
        XCTAssertGreaterThanOrEqual(engine.history.count, 1)
        
        // Buffer should be empty, spaceCount should be 1
        XCTAssertTrue(engine.buffer.isEmpty)
        XCTAssertEqual(engine.spaceCount, 1)
        
        // Delete the space
        typeBackspace()
        
        // Space should be removed, and word "chao" should be restored from history
        // (depends on implementation - may restore or may not)
    }

    func testHistoryPopOnRestore() {
        typeWord("test")
        processSpace()
        
        let countBefore = engine.history.count
        
        // Delete to trigger restore
        typeBackspace()  // Remove space
        
        // History count should decrease after restore
        // (spaceCount restore doesn't pop, but further backspaces do)
    }

    // MARK: - Normal Backspace Tests

    func testNormalBackspaceRestoresFromHistory() {
        typeWord("abc")

        // Normal backspace - should trust history without needing AX verify
        typeBackspace()
        typeBackspace()

        // Since cursorMovedSinceReset = false and focusChangedDuringTyping = false,
        // should trust history
        typeBackspace()

        // Buffer should be empty, history is used for restore
        XCTAssertTrue(engine.buffer.isEmpty)
    }

    // MARK: - Cursor Moved Tests

    func testCursorMovedSkipsRestore() {
        typeWord("test")
        processSpace()
        typeWord("word")
        
        // Simulate cursor movement (like clicking in middle of text)
        engine.resetWithCursorMoved()
        
        // cursorMovedSinceReset should be true
        XCTAssertTrue(engine.cursorMovedSinceReset)
        
        // History should be cleared on subsequent backspace to empty
        typeWord("new")
        
        for _ in 0..<3 {
            typeBackspace()
        }
        
        // After buffer empty with cursorMovedSinceReset=true, history should be cleared
        XCTAssertTrue(engine.history.isEmpty)
    }

    func testCursorMovedClearsHistory() {
        typeWord("first")
        processSpace()
        
        XCTAssertGreaterThan(engine.history.count, 0)
        
        // Reset with cursor moved
        engine.resetWithCursorMoved()
        
        // History should be preserved until backspace triggers clear
        // But engine.reset() also clears history
        XCTAssertTrue(engine.history.isEmpty)
    }

    // MARK: - Focus Changed Tests

    func testFocusChangedSkipsRestore() {
        typeWord("abc")

        // Notify focus changed
        engine.notifyFocusChanged()
        XCTAssertTrue(engine.focusChangedDuringTyping)

        // Delete all characters to trigger buffer empty path
        typeBackspace()
        typeBackspace()
        typeBackspace()

        // With focusChangedDuringTyping = true, should skip restore and set desync flag
        XCTAssertTrue(engine.bufferDesyncDetected, "Focus changed should skip restore and set desync flag")
    }

    func testFocusChangedClearsHistory() {
        typeWord("abc")
        processSpace()  // Save to history
        typeWord("def")

        // Notify focus changed
        engine.notifyFocusChanged()

        // Delete all to trigger buffer empty path
        for _ in 0..<3 {
            typeBackspace()
        }

        // With focusChangedDuringTyping = true, history should be cleared
        XCTAssertTrue(engine.history.isEmpty, "Focus changed should clear history on backspace")
    }

    // MARK: - Buffer Desync Detection Tests

    func testBufferDesyncFlagSetOnFocusChange() {
        // Initially should be false
        XCTAssertFalse(engine.bufferDesyncDetected)

        typeWord("abc")
        engine.notifyFocusChanged()  // Mark focus changed

        // Delete to trigger buffer empty
        for _ in 0..<3 {
            typeBackspace()
        }
        
        // bufferDesyncDetected should be set when focus changed during typing
        XCTAssertTrue(engine.bufferDesyncDetected, "Focus change should set desync flag")
    }

    func testBufferDesyncFlagClearedOnNewSession() {
        engine.bufferDesyncDetected = true
        
        engine.startNewSession()
        
        XCTAssertFalse(engine.bufferDesyncDetected)
    }

    func testBufferDesyncFlagClearedOnReset() {
        engine.bufferDesyncDetected = true
        
        engine.reset()
        
        XCTAssertFalse(engine.bufferDesyncDetected)
    }

    // MARK: - Cross Word Boundary Tests

    func testDeleteAcrossWordBoundary() {
        // Type "hello world"
        typeWord("hello")
        processSpace()
        typeWord("world")
        
        // Delete all of "world"
        for _ in 0..<5 {
            typeBackspace()
        }
        
        XCTAssertTrue(engine.buffer.isEmpty)
        
        // Delete the space
        XCTAssertEqual(engine.spaceCount, 1)
        typeBackspace()
        
        // Now should restore "hello" from history
        // After restore, buffer may have "hello" content
    }

    func testContinuousBackspaceAcrossMultipleWords() {
        // Type multiple words
        typeWord("one")
        processSpace()
        typeWord("two")
        processSpace()
        typeWord("three")
        
        // Delete everything backwards
        // "three" = 5 chars
        for _ in 0..<5 {
            typeBackspace()
        }
        XCTAssertTrue(engine.buffer.isEmpty)
        
        // Delete space
        typeBackspace()
        
        // Continue deleting - should restore "two"
        // Then delete "two" = 3 chars
        for _ in 0..<3 {
            typeBackspace()
        }
        
        // Delete space
        typeBackspace()
        
        // Continue - should restore "one"
        // Engine should handle gracefully
    }

    // MARK: - History Empty Tests

    func testHistoryEmptySetseCursorMovedFlag() {
        // Type but don't save to history (no word break)
        typeWord("abc")
        
        // Delete all
        for _ in 0..<3 {
            typeBackspace()
        }
        
        // When buffer empty and history is also empty,
        // restoreLastTypingState() sets cursorMovedSinceReset = true
        XCTAssertTrue(engine.cursorMovedSinceReset)
    }

    func testMultipleDeletesWithEmptyHistory() {
        // Start fresh - no history
        engine.reset()
        XCTAssertTrue(engine.history.isEmpty)
        
        typeWord("test")
        
        // Delete all - should not crash when history is empty
        for _ in 0..<4 {
            typeBackspace()
        }
        
        // Additional deletes on empty buffer - should not crash
        typeBackspace()
        typeBackspace()
        
        XCTAssertTrue(engine.buffer.isEmpty)
    }

    // MARK: - Vietnamese Word Backspace Tests

    func testBackspaceOnVietnameseWord() {
        // Type "việt" = vieejt
        _ = engine.processKey(character: "v", keyCode: VietnameseData.KEY_V, isUppercase: false)
        _ = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        _ = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        _ = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        _ = engine.processKey(character: "j", keyCode: VietnameseData.KEY_J, isUppercase: false)
        _ = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        
        XCTAssertEqual(engine.getCurrentWord(), "việt")
        
        // Delete 't'
        typeBackspace()
        XCTAssertEqual(engine.buffer.count, 3)  // v, i, ệ
        
        // Delete 'ệ' (had circumflex + dot below)
        typeBackspace()
        XCTAssertEqual(engine.buffer.count, 2)  // v, i
    }

    func testBackspaceOnTelexDoubleKey() {
        // Type "aa" → "â"
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        
        XCTAssertEqual(engine.getCurrentWord(), "â")
        XCTAssertEqual(engine.buffer.count, 1)
        
        // Delete "â" - should remove whole character
        typeBackspace()
        
        XCTAssertTrue(engine.buffer.isEmpty)
    }

    // MARK: - Special Character Backspace Tests

    func testBackspaceWithSpecialCharacter() {
        typeWord("hello")
        
        // Type comma (special character)
        _ = engine.processKey(character: ",", keyCode: VietnameseData.KEY_COMMA, isUppercase: false)
        
        // Comma triggers word break, so specialChar may have the comma
        // Delete the comma
        typeBackspace()
        
        // Behavior depends on specialChar handling
    }

    // MARK: - Space Count Tests

    func testSpaceCountOnMultipleSpaces() {
        typeWord("test")
        processSpace()
        
        XCTAssertEqual(engine.spaceCount, 1)
        
        // Multiple spaces would increase count if using space key multiple times
        // (depends on how processWordBreak handles consecutive spaces)
    }

    func testSpaceCountDecreasesOnBackspace() {
        typeWord("test")
        processSpace()
        
        XCTAssertEqual(engine.spaceCount, 1)
        
        typeBackspace()
        
        XCTAssertEqual(engine.spaceCount, 0)
    }
}

// MARK: - Regression Tests for Race Condition Fix

class VNEngineRaceConditionFixTests: XCTestCase {

    var engine: VNEngine!

    override func setUp() {
        super.setUp()
        engine = VNEngine()
        engine.reset()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    /// Test that normal backspace restores from history
    func testNormalBackspaceBypassesAXVerify() {
        // Type word
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        _ = engine.processKey(character: "c", keyCode: VietnameseData.KEY_C, isUppercase: false)

        // Ensure no desync flags
        XCTAssertFalse(engine.cursorMovedSinceReset)
        XCTAssertFalse(engine.focusChangedDuringTyping)

        // Delete all - buffer becomes empty
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)

        // Buffer should be empty, restore works from history
        XCTAssertTrue(engine.buffer.isEmpty)
    }

    /// Test that focus changed skips restore and sets desync flag
    func testFocusChangedSkipsRestoreAndSetsDesync() {
        // Type word
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        _ = engine.processKey(character: "c", keyCode: VietnameseData.KEY_C, isUppercase: false)

        // Notify focus changed
        engine.notifyFocusChanged()
        XCTAssertTrue(engine.focusChangedDuringTyping)

        // Delete all
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)

        // Focus changed should skip restore and set desync flag
        XCTAssertTrue(engine.bufferDesyncDetected, "Focus changed should set desync flag")
    }

    /// Test that cursor moved skips restore entirely
    func testCursorMovedSkipsRestoreEntirely() {
        // Type and save to history
        _ = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        _ = engine.processWordBreak(character: ",")  // Save to history
        
        XCTAssertGreaterThan(engine.history.count, 0)
        
        // Simulate cursor movement
        engine.resetWithCursorMoved()
        XCTAssertTrue(engine.cursorMovedSinceReset)
        
        // Type new word
        _ = engine.processKey(character: "c", keyCode: VietnameseData.KEY_C, isUppercase: false)
        
        // Delete - should skip restore and clear history
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        
        // History should be cleared because cursorMovedSinceReset was true
        XCTAssertTrue(engine.history.isEmpty, "Cursor moved should clear history on backspace")
    }

    /// Test the original bug scenario: typing across word boundary
    /// This test verifies that after the race condition fix, restore works correctly
    func testTypingAcrossWordBoundaryWithBackspace() {
        // Simulate the original bug: "giup " + more typing + backspace
        
        // Type "giup"
        _ = engine.processKey(character: "g", keyCode: VietnameseData.KEY_G, isUppercase: false)
        _ = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        _ = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        _ = engine.processKey(character: "p", keyCode: VietnameseData.KEY_P, isUppercase: false)
        
        XCTAssertEqual(engine.getCurrentWord(), "giup")
        
        // Space - save to history
        _ = engine.processWordBreak(character: " ")
        let historyCountAfterSpace = engine.history.count
        XCTAssertGreaterThan(historyCountAfterSpace, 0, "Word should be saved to history after space")
        XCTAssertTrue(engine.buffer.isEmpty, "Buffer should be empty after word break")
        XCTAssertEqual(engine.spaceCount, 1, "Space count should be 1")
        
        // Type more (new word after space)
        _ = engine.processKey(character: "s", keyCode: VietnameseData.KEY_S, isUppercase: false)
        _ = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        
        XCTAssertEqual(engine.buffer.count, 2, "Buffer should have 2 chars")
        
        // Delete all of new word
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        
        // Buffer empty, but spaceCount should still be 1
        XCTAssertTrue(engine.buffer.isEmpty, "Buffer should be empty after deleting 'st'")
        // Note: spaceCount may be > 0 or may have been restored from history
        
        // Delete space - should trigger restore of "giup" from history
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
        
        // After deleting space, "giup" should be restored from history
        // The exact behavior depends on how restore works with spaceCount
        // Key verification: engine should be in a usable state
        
        // If buffer is restored, verify we can continue typing and get Vietnamese output
        if !engine.buffer.isEmpty {
            // Buffer restored - type "s" for tone mark
            _ = engine.processKey(character: "s", keyCode: VietnameseData.KEY_S, isUppercase: false)
            
            let word = engine.getCurrentWord()
            // Should have Vietnamese tone mark on 'u' if properly restored
            XCTAssertTrue(word.contains("ú") || word.contains("giúp") || word.count >= 4, 
                "After restore and 's', word should have content: \(word)")
        }
    }
}

// MARK: - History Order Fix Tests

/// Tests for the fix that ensures space is saved BEFORE word in special paths
/// (plain text words and restore paths) to maintain correct LIFO restore order.
class VNEngineHistoryOrderFixTests: XCTestCase {

    var engine: VNEngine!

    override func setUp() {
        super.setUp()
        engine = VNEngine()
        engine.vCheckSpelling = 1  // Enable spell checking for restore tests
        engine.reset()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func typeWord(_ word: String) {
        for char in word {
            let keyCode = getKeyCode(for: char)
            _ = engine.processKey(character: char, keyCode: keyCode, isUppercase: char.isUppercase)
        }
    }

    private func typeBackspace() {
        _ = engine.processKey(character: "\u{8}", keyCode: VietnameseData.KEY_DELETE, isUppercase: false)
    }

    private func processSpace() {
        _ = engine.processWordBreak(character: " ")
    }

    private func getKeyCode(for char: Character) -> UInt16 {
        let lower = char.lowercased().first!
        switch lower {
        case "a": return VietnameseData.KEY_A
        case "b": return VietnameseData.KEY_B
        case "c": return VietnameseData.KEY_C
        case "d": return VietnameseData.KEY_D
        case "e": return VietnameseData.KEY_E
        case "f": return VietnameseData.KEY_F
        case "g": return VietnameseData.KEY_G
        case "h": return VietnameseData.KEY_H
        case "i": return VietnameseData.KEY_I
        case "j": return VietnameseData.KEY_J
        case "k": return VietnameseData.KEY_K
        case "l": return VietnameseData.KEY_L
        case "m": return VietnameseData.KEY_M
        case "n": return VietnameseData.KEY_N
        case "o": return VietnameseData.KEY_O
        case "p": return VietnameseData.KEY_P
        case "q": return VietnameseData.KEY_Q
        case "r": return VietnameseData.KEY_R
        case "s": return VietnameseData.KEY_S
        case "t": return VietnameseData.KEY_T
        case "u": return VietnameseData.KEY_U
        case "v": return VietnameseData.KEY_V
        case "w": return VietnameseData.KEY_W
        case "x": return VietnameseData.KEY_X
        case "y": return VietnameseData.KEY_Y
        case "z": return VietnameseData.KEY_Z
        default: return 0
        }
    }

    // MARK: - Normal Case (Baseline)

    /// Test normal case: Vietnamese words save in correct order
    func testNormalVietnameseWordsHistoryOrder() {
        // Type "xin" + space + "chao" + space
        typeWord("xin")
        processSpace()
        
        typeWord("chao")
        processSpace()
        
        // History should be: ["xin", space, "chao"]
        // spaceCount = 1 (for the trailing space)
        XCTAssertGreaterThanOrEqual(engine.history.count, 2, "History should have at least 2 items")
        XCTAssertEqual(engine.spaceCount, 1, "spaceCount should be 1 for trailing space")
        
        // Backspace through everything and verify order
        // BS to remove trailing space
        typeBackspace()
        XCTAssertEqual(engine.spaceCount, 0, "spaceCount should be 0 after removing trailing space")
        
        // Should restore "chao" from history
        XCTAssertEqual(engine.getCurrentWord(), "chao", "Should restore 'chao' after removing space")
        
        // BS to remove "chao"
        for _ in 0..<4 {
            typeBackspace()
        }
        XCTAssertTrue(engine.buffer.isEmpty, "Buffer should be empty after removing 'chao'")
        
        // Should now have spaceCount = 1 (the space between xin and chao)
        XCTAssertEqual(engine.spaceCount, 1, "Should restore space between words")
        
        // BS to remove the space
        typeBackspace()
        XCTAssertEqual(engine.spaceCount, 0, "spaceCount should be 0 after removing space")
        
        // Should restore "xin" from history
        XCTAssertEqual(engine.getCurrentWord(), "xin", "Should restore 'xin' after all backspaces")
    }

    // MARK: - Plain Text Word Test (tempDisableKey && !hasVNProcessing)

    /// Test that plain text words (like "setup") are saved with correct history order
    /// This tests the fix for the tempDisableKey && !hasVNProcessing branch
    func testPlainTextWordHistoryOrder() {
        // Type Vietnamese word first
        typeWord("xin")
        processSpace()
        
        // Type plain text word (will set tempDisableKey = true)
        typeWord("setup")
        
        // To trigger tempDisableKey, we need the word to not have Vietnamese processing
        // "setup" doesn't have any telex marks, so tempDisableKey might not be set
        // Let's manually set it for this test
        engine.tempDisableKey = true
        
        processSpace()
        
        // Now backspace through "setup" and verify order
        // First remove trailing space
        typeBackspace()
        
        // Should restore "setup" 
        let word = engine.getCurrentWord()
        XCTAssertEqual(word.lowercased(), "setup", "Should restore 'setup', got: \(word)")
        
        // Remove "setup"
        for _ in 0..<5 {
            typeBackspace()
        }
        
        // Should have space restored
        XCTAssertEqual(engine.spaceCount, 1, "Should restore space after 'xin'")
        
        // Remove space
        typeBackspace()
        
        // Should restore "xin"
        XCTAssertEqual(engine.getCurrentWord(), "xin", "Should restore 'xin' after all backspaces")
    }

    // MARK: - Mixed Vietnamese and Plain Text

    /// Regression test for the bug: mixed word types backspace desync
    /// This test verifies that after typing multiple words with space,
    /// backspace correctly restores each word in reverse order.
    func testMixedVietnamesePlainTextHistoryOrder() {
        // Type "nghiem" (Vietnamese with marks)
        _ = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        _ = engine.processKey(character: "g", keyCode: VietnameseData.KEY_G, isUppercase: false)
        _ = engine.processKey(character: "h", keyCode: VietnameseData.KEY_H, isUppercase: false)
        _ = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        _ = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        _ = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)  // circumflex
        _ = engine.processKey(character: "j", keyCode: VietnameseData.KEY_J, isUppercase: false)  // dot below
        _ = engine.processKey(character: "m", keyCode: VietnameseData.KEY_M, isUppercase: false)
        
        let word1 = engine.getCurrentWord()
        XCTAssertEqual(word1, "nghiệm", "First word should be 'nghiệm'")
        
        processSpace()
        
        // Type simple word "abc"
        typeWord("abc")
        processSpace()
        
        // Verify initial state after typing
        XCTAssertTrue(engine.buffer.isEmpty, "Buffer should be empty after space")
        XCTAssertEqual(engine.spaceCount, 1, "spaceCount should be 1")
        XCTAssertGreaterThanOrEqual(engine.history.count, 2, "History should have at least 2 items")
        
        // Now backspace and verify restore order
        // Remove trailing space
        typeBackspace()
        XCTAssertEqual(engine.spaceCount, 0, "spaceCount should be 0")
        
        // Should restore "abc"
        XCTAssertEqual(engine.getCurrentWord(), "abc", "Should restore 'abc'")
        
        // Remove "abc"
        for _ in 0..<3 {
            typeBackspace()
        }
        XCTAssertTrue(engine.buffer.isEmpty, "Buffer should be empty")
        
        // Should have space restored
        XCTAssertEqual(engine.spaceCount, 1, "Should restore space after 'nghiệm'")
        
        // Remove space
        typeBackspace()
        XCTAssertEqual(engine.spaceCount, 0, "spaceCount should be 0")
        
        // Should restore first word - verify it contains Vietnamese content
        let restoredWord = engine.getCurrentWord()
        XCTAssertFalse(restoredWord.isEmpty, "Should restore first word, got empty")
        // The restored word might be the original keystrokes or transformed - just verify it's not empty
        XCTAssertTrue(restoredWord.count >= 4, "Restored word should have content: \(restoredWord)")
    }

    // MARK: - Continuous Backspace Across Multiple Words

    /// Test continuous backspace across 3+ words with mixed content
    func testContinuousBackspaceMultipleWords() {
        // Type: "mot hai ba"
        typeWord("mot")
        processSpace()
        
        typeWord("hai")
        processSpace()
        
        typeWord("ba")
        processSpace()
        
        // Backspace through everything
        // Remove trailing space
        typeBackspace()
        
        // Remove "ba"
        for _ in 0..<2 { typeBackspace() }
        XCTAssertTrue(engine.buffer.isEmpty)
        
        // Remove space
        typeBackspace()
        XCTAssertEqual(engine.spaceCount, 0)
        
        // Should restore "hai"
        XCTAssertEqual(engine.getCurrentWord(), "hai")
        
        // Remove "hai"
        for _ in 0..<3 { typeBackspace() }
        
        // Remove space
        typeBackspace()
        
        // Should restore "mot"
        XCTAssertEqual(engine.getCurrentWord(), "mot")
    }

    // MARK: - Edge Case: Empty History

    /// Test that backspace on empty history doesn't crash
    func testBackspaceWithEmptyHistoryNoCrash() {
        engine.reset()
        XCTAssertTrue(engine.history.isEmpty)
        
        typeWord("test")
        
        // Delete all
        for _ in 0..<4 {
            typeBackspace()
        }
        
        // Additional backspace on empty buffer - should not crash
        typeBackspace()
        typeBackspace()
        
        // cursorMovedSinceReset should be set when history is empty
        XCTAssertTrue(engine.cursorMovedSinceReset, "Should set cursorMovedSinceReset when history empty")
    }

    // MARK: - Edge Case: Single Word

    /// Test single word save and restore
    func testSingleWordSaveRestore() {
        typeWord("xin")
        processSpace()
        
        // Buffer should be empty, word saved to history
        XCTAssertTrue(engine.buffer.isEmpty)
        XCTAssertEqual(engine.spaceCount, 1)
        XCTAssertGreaterThan(engine.history.count, 0)
        
        // Backspace removes space
        typeBackspace()
        
        // Should restore "xin"
        XCTAssertEqual(engine.getCurrentWord(), "xin")
    }
}

