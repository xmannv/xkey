//
//  TypingBufferTests.swift
//  XKeyTests
//
//  Comprehensive tests for the Unified Buffer System
//

import XCTest
@testable import XKey

// MARK: - TypingBuffer Core Tests

class TypingBufferTests: XCTestCase {

    var buffer: TypingBuffer!

    override func setUp() {
        super.setUp()
        buffer = TypingBuffer()
    }

    override func tearDown() {
        buffer = nil
        super.tearDown()
    }

    // MARK: - Basic Operations

    func testEmptyBuffer() {
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.totalKeystrokeCount, 0)
        XCTAssertNil(buffer.last)
    }

    func testAppendSingleCharacter() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)

        XCTAssertFalse(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.totalKeystrokeCount, 1)
        XCTAssertEqual(buffer.keyCode(at: 0), VietnameseData.KEY_A)
        XCTAssertFalse(buffer[0].isCaps)
    }

    func testAppendMultipleCharacters() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.append(keyCode: VietnameseData.KEY_B, isCaps: false)
        buffer.append(keyCode: VietnameseData.KEY_C, isCaps: false)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.keyCode(at: 0), VietnameseData.KEY_A)
        XCTAssertEqual(buffer.keyCode(at: 1), VietnameseData.KEY_B)
        XCTAssertEqual(buffer.keyCode(at: 2), VietnameseData.KEY_C)
    }

    func testAppendWithCaps() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: true)

        XCTAssertTrue(buffer[0].isCaps)
        XCTAssertTrue((buffer[0].processedData & TypingBuffer.CAPS_MASK) != 0)
    }

    func testRemoveLast() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.append(keyCode: VietnameseData.KEY_B, isCaps: false)

        let removed = buffer.removeLast()

        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(removed?.keyCode, VietnameseData.KEY_B)
        XCTAssertEqual(buffer.keyCode(at: 0), VietnameseData.KEY_A)
    }

    func testRemoveLastFromEmpty() {
        let removed = buffer.removeLast()
        XCTAssertNil(removed)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testClear() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.append(keyCode: VietnameseData.KEY_B, isCaps: false)

        buffer.clear()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.totalKeystrokeCount, 0)
    }

    // MARK: - Modifier Keystroke Tests

    func testAddModifierToLast() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))

        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.totalKeystrokeCount, 2)
        XCTAssertEqual(buffer[0].keystrokeCount, 2)
    }

    func testMultipleModifiers() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_J, isCaps: false))

        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.totalKeystrokeCount, 3)
    }

    func testRemoveLastModifier() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))

        let removed = buffer.removeLastModifierFromLast()

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.keyCode, VietnameseData.KEY_A)
        XCTAssertEqual(buffer.totalKeystrokeCount, 1)
    }

    // MARK: - Raw Keystroke Extraction

    func testGetAllRawKeystrokes() {
        buffer.append(keyCode: VietnameseData.KEY_V, isCaps: false)
        buffer.append(keyCode: VietnameseData.KEY_I, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_E, isCaps: false))
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_E, isCaps: false))
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_J, isCaps: false))
        buffer.append(keyCode: VietnameseData.KEY_T, isCaps: false)

        let rawKeystrokes = buffer.getAllRawKeystrokes()

        XCTAssertEqual(rawKeystrokes.count, 6)
        XCTAssertEqual(rawKeystrokes[0].keyCode, VietnameseData.KEY_V)
        XCTAssertEqual(rawKeystrokes[1].keyCode, VietnameseData.KEY_I)
        XCTAssertEqual(rawKeystrokes[2].keyCode, VietnameseData.KEY_E)
        XCTAssertEqual(rawKeystrokes[3].keyCode, VietnameseData.KEY_E)
        XCTAssertEqual(rawKeystrokes[4].keyCode, VietnameseData.KEY_J)
        XCTAssertEqual(rawKeystrokes[5].keyCode, VietnameseData.KEY_T)
    }

    // MARK: - Processed Data Tests

    func testProcessedDataModification() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer[0].hasTone = true

        XCTAssertTrue(buffer[0].hasTone)
        XCTAssertTrue((buffer[0].processedData & TypingBuffer.TONE_MASK) != 0)
    }

    func testToneWMask() {
        buffer.append(keyCode: VietnameseData.KEY_O, isCaps: false)
        buffer[0].hasToneW = true

        XCTAssertTrue(buffer[0].hasToneW)
        XCTAssertFalse(buffer[0].hasTone)
    }

    func testMarkMask() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer[0].mark = TypingBuffer.MARK1

        XCTAssertTrue(buffer[0].hasMark)
        XCTAssertEqual(buffer[0].mark, TypingBuffer.MARK1)
    }

    // MARK: - Snapshot & Restore Tests

    func testCreateSnapshot() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))
        buffer.append(keyCode: VietnameseData.KEY_B, isCaps: true)

        let snapshot = buffer.createSnapshot()

        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.keystrokeCount, 3)
    }

    func testRestoreFromSnapshot() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))

        let snapshot = buffer.createSnapshot()

        buffer.clear()
        buffer.append(keyCode: VietnameseData.KEY_X, isCaps: false)

        buffer.restore(from: snapshot)

        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.totalKeystrokeCount, 2)
        XCTAssertEqual(buffer.keyCode(at: 0), VietnameseData.KEY_A)
    }

    func testRestoreFromLegacy() {
        let legacyData: [UInt32] = [
            UInt32(VietnameseData.KEY_A),
            UInt32(VietnameseData.KEY_B) | TypingBuffer.CAPS_MASK
        ]

        buffer.restoreFromLegacy(legacyData)

        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.keyCode(at: 0), VietnameseData.KEY_A)
        XCTAssertEqual(buffer.keyCode(at: 1), VietnameseData.KEY_B)
        XCTAssertTrue(buffer[1].isCaps)
    }

    // MARK: - Overflow Tests

    func testBufferOverflow() {
        for i: UInt16 in 0..<UInt16(TypingBuffer.MAX_SIZE) {
            buffer.append(keyCode: i, isCaps: false)
        }

        XCTAssertEqual(buffer.count, TypingBuffer.MAX_SIZE)
        XCTAssertTrue(buffer.isFull)

        buffer.append(keyCode: 99, isCaps: false)

        XCTAssertEqual(buffer.count, TypingBuffer.MAX_SIZE)
        XCTAssertTrue(buffer.hasOverflow)
    }

    // MARK: - Overflow + getRawInputString Tests (Issue: English Detection with Overflow)

    /// Test that getRawInputString includes overflow entries
    /// This verifies the CURRENT behavior (which may cause English detection issues)
    func testGetRawInputString_IncludesOverflow() {
        // Create a simple keyCodeToChar function for testing
        let keyCodeToChar: (UInt16) -> Character? = { keyCode in
            // Map some key codes to characters for testing
            switch keyCode {
            case VietnameseData.KEY_A: return "a"
            case VietnameseData.KEY_B: return "b"
            case VietnameseData.KEY_C: return "c"
            case VietnameseData.KEY_T: return "t"
            case VietnameseData.KEY_L: return "l"
            case VietnameseData.KEY_O: return "o"
            default: return Character(UnicodeScalar(Int(keyCode) + 97)!) // a=0, b=1, etc.
            }
        }

        // Fill buffer to MAX_SIZE with 'a' characters
        for _ in 0..<TypingBuffer.MAX_SIZE {
            buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)
        }
        XCTAssertEqual(buffer.count, TypingBuffer.MAX_SIZE)
        XCTAssertFalse(buffer.hasOverflow)

        // Add one more to trigger overflow
        buffer.append(keyCode: VietnameseData.KEY_T, isCaps: false)
        XCTAssertTrue(buffer.hasOverflow, "Should have overflow after exceeding MAX_SIZE")
        XCTAssertEqual(buffer.count, TypingBuffer.MAX_SIZE, "Count should still be MAX_SIZE")

        // Add 'l' to create "tl" pattern at the boundary
        buffer.append(keyCode: VietnameseData.KEY_L, isCaps: false)

        // Get raw input string - this includes overflow
        let rawInput = buffer.getRawInputString(using: keyCodeToChar)

        // The raw input should include the overflow 'a' at the beginning
        // Total: 32 'a's initially, then 't', 'l' added (2 go to overflow when exceeding)
        // After adding 't': overflow has 1 'a', entries has 31 'a's + 't'
        // After adding 'l': overflow has 2 'a's, entries has 30 'a's + 't' + 'l'
        XCTAssertTrue(rawInput.count > buffer.count,
            "getRawInputString should include overflow, so length (\(rawInput.count)) > buffer.count (\(buffer.count))")

        // Check that overflow content is included
        XCTAssertTrue(rawInput.hasPrefix("a"), "Raw input should start with overflow 'a'")
    }

    /// Test scenario: After restore, overflow contains old word data
    /// When user types new characters, English detection uses overflow + entries
    /// This can cause false English pattern detection
    func testOverflow_AfterRestore_CausesEnglishPatternIssue() {
        let keyCodeToChar: (UInt16) -> Character? = { keyCode in
            switch keyCode {
            case VietnameseData.KEY_A: return "a"
            case VietnameseData.KEY_T: return "t"
            case VietnameseData.KEY_H: return "h"
            case VietnameseData.KEY_L: return "l"
            case VietnameseData.KEY_O: return "o"
            default: return nil
            }
        }

        // Simulate: User typed a word ending with 't', saved to history
        // Then restored, overflow contains 't'

        // Create a snapshot with overflow containing 't'
        let overflowEntry = CharacterEntry(keyCode: VietnameseData.KEY_T, isCaps: false)
        let entries = [CharacterEntry](repeating: CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false), count: 5)
        let snapshot = BufferSnapshot(entries: entries, overflow: [overflowEntry])

        // Restore from snapshot
        buffer.restore(from: snapshot)

        XCTAssertTrue(buffer.hasOverflow, "Should have overflow after restore")
        XCTAssertEqual(buffer.count, 5, "entries count should be 5")

        // Now user types 'l' - simulating typing after restore
        buffer.append(keyCode: VietnameseData.KEY_L, isCaps: false)

        // Get raw input - this includes overflow 't' + entries 'aaaaa' + new 'l'
        let rawInput = buffer.getRawInputString(using: keyCodeToChar)

        // The problem: rawInput starts with 't' from overflow
        // If entries also start with something that makes "tl" pattern...
        XCTAssertTrue(rawInput.hasPrefix("t"),
            "Raw input starts with 't' from overflow - this can cause 'tl' English pattern detection!")

        // This demonstrates the issue: overflow data affects English detection
        // even though user only typed 'l' after restore
    }

    /// Test proposed solution: getRawInputString should only use entries, not overflow
    /// for English pattern detection purposes
    func testGetRawInputStringFromEntries_ExcludesOverflow() {
        let keyCodeToChar: (UInt16) -> Character? = { keyCode in
            switch keyCode {
            case VietnameseData.KEY_A: return "a"
            case VietnameseData.KEY_T: return "t"
            case VietnameseData.KEY_L: return "l"
            default: return nil
            }
        }

        // Create snapshot with overflow
        let overflowEntry = CharacterEntry(keyCode: VietnameseData.KEY_T, isCaps: false)
        let entries = [
            CharacterEntry(keyCode: VietnameseData.KEY_L, isCaps: false),
            CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)
        ]
        let snapshot = BufferSnapshot(entries: entries, overflow: [overflowEntry])

        buffer.restore(from: snapshot)

        // Current behavior: includes overflow
        let rawInputWithOverflow = buffer.getRawInputString(using: keyCodeToChar)
        XCTAssertEqual(rawInputWithOverflow, "tla", "Current: includes overflow 't'")

        // Proposed solution: only from entries
        let rawInputEntriesOnly = buffer.getRawInputStringFromEntries(using: keyCodeToChar)
        XCTAssertEqual(rawInputEntriesOnly, "la", "Proposed: only entries, no overflow")
    }

    // MARK: - Edge Cases

    func testSubscriptOutOfBounds() {
        buffer.append(keyCode: VietnameseData.KEY_A, isCaps: false)

        XCTAssertEqual(buffer.keyCode(at: 100), 0)
    }

    func testAddModifierToEmptyBuffer() {
        buffer.addModifierToLast(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRemoveModifierFromEmptyBuffer() {
        let result = buffer.removeLastModifierFromLast()
        XCTAssertNil(result)
    }
}

// MARK: - CharacterEntry Tests

class CharacterEntryTests: XCTestCase {

    func testInitWithKeyCode() {
        let entry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)

        XCTAssertEqual(entry.keyCode, VietnameseData.KEY_A)
        XCTAssertFalse(entry.isCaps)
        XCTAssertFalse(entry.hasTone)
        XCTAssertFalse(entry.hasToneW)
        XCTAssertFalse(entry.hasMark)
        XCTAssertEqual(entry.keystrokeCount, 1)
    }

    func testInitWithCaps() {
        let entry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: true)

        XCTAssertTrue(entry.isCaps)
        XCTAssertTrue((entry.processedData & TypingBuffer.CAPS_MASK) != 0)
    }

    func testInitFromLegacy() {
        let legacyData = UInt32(VietnameseData.KEY_A) | TypingBuffer.CAPS_MASK | TypingBuffer.TONE_MASK

        let entry = CharacterEntry(fromLegacy: legacyData)

        XCTAssertEqual(entry.keyCode, VietnameseData.KEY_A)
        XCTAssertTrue(entry.isCaps)
        XCTAssertTrue(entry.hasTone)
    }

    func testAddModifier() {
        var entry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)
        entry.addModifier(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))

        XCTAssertEqual(entry.keystrokeCount, 2)
        XCTAssertEqual(entry.modifierKeystrokes.count, 1)
    }

    func testAllKeystrokes() {
        var entry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)
        entry.addModifier(RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false))
        entry.addModifier(RawKeystroke(keyCode: VietnameseData.KEY_J, isCaps: false))

        let all = entry.allKeystrokes

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].keyCode, VietnameseData.KEY_A)
        XCTAssertEqual(all[1].keyCode, VietnameseData.KEY_A)
        XCTAssertEqual(all[2].keyCode, VietnameseData.KEY_J)
    }

    func testSetKeyCode() {
        var entry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: true)
        entry.hasTone = true

        entry.setKeyCode(VietnameseData.KEY_E)

        XCTAssertEqual(entry.keyCode, VietnameseData.KEY_E)
        XCTAssertTrue(entry.isCaps)
        XCTAssertTrue(entry.hasTone)
    }
}

// MARK: - TypingHistory Tests

class TypingHistoryTests: XCTestCase {

    var history: TypingHistory!

    override func setUp() {
        super.setUp()
        history = TypingHistory()
    }

    override func tearDown() {
        history = nil
        super.tearDown()
    }

    func testEmptyHistory() {
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.count, 0)
        XCTAssertNil(history.last)
    }

    func testSaveSnapshot() {
        let entries = [CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)]
        let snapshot = BufferSnapshot(entries: entries, overflow: [])

        history.save(snapshot)

        XCTAssertEqual(history.count, 1)
        XCTAssertNotNil(history.last)
    }

    func testPopLast() {
        let entries = [CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)]
        let snapshot = BufferSnapshot(entries: entries, overflow: [])

        history.save(snapshot)
        let popped = history.popLast()

        XCTAssertNotNil(popped)
        XCTAssertTrue(history.isEmpty)
    }

    func testSaveSpaces() {
        history.saveSpaces(count: 3)

        XCTAssertEqual(history.count, 1)

        let snapshot = history.popLast()
        XCTAssertEqual(snapshot?.count, 3)
    }

    func testClear() {
        history.saveSpaces(count: 1)
        history.saveSpaces(count: 2)

        history.clear()

        XCTAssertTrue(history.isEmpty)
    }
}

// MARK: - BufferSnapshot Tests

class BufferSnapshotTests: XCTestCase {

    func testEmptySnapshot() {
        let snapshot = BufferSnapshot.empty

        XCTAssertEqual(snapshot.count, 0)
        XCTAssertEqual(snapshot.keystrokeCount, 0)
        XCTAssertNil(snapshot.firstKeyCode)
    }

    func testSnapshotWithEntries() {
        let entries = [
            CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false),
            CharacterEntry(keyCode: VietnameseData.KEY_B, isCaps: true)
        ]
        let snapshot = BufferSnapshot(entries: entries, overflow: [])

        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.firstKeyCode, VietnameseData.KEY_A)
    }

    func testIsSpace() {
        let spaceEntry = CharacterEntry(keyCode: VietnameseData.KEY_SPACE, isCaps: false)
        let spaceSnapshot = BufferSnapshot(entries: [spaceEntry], overflow: [])

        XCTAssertTrue(spaceSnapshot.isSpace)

        let normalEntry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)
        let normalSnapshot = BufferSnapshot(entries: [normalEntry], overflow: [])

        XCTAssertFalse(normalSnapshot.isSpace)
    }
}

// MARK: - RawKeystroke Tests

class RawKeystrokeTests: XCTestCase {

    func testInit() {
        let keystroke = RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: true)

        XCTAssertEqual(keystroke.keyCode, VietnameseData.KEY_A)
        XCTAssertTrue(keystroke.isCaps)
    }

    func testInitFromData() {
        let data = UInt32(VietnameseData.KEY_B) | TypingBuffer.CAPS_MASK

        let keystroke = RawKeystroke(from: data)

        XCTAssertEqual(keystroke.keyCode, VietnameseData.KEY_B)
        XCTAssertTrue(keystroke.isCaps)
    }

    func testAsUInt32() {
        let keystroke = RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: true)

        let data = keystroke.asUInt32

        XCTAssertEqual(data & TypingBuffer.CHAR_MASK, UInt32(VietnameseData.KEY_A))
        XCTAssertTrue((data & TypingBuffer.CAPS_MASK) != 0)
    }

    func testEquality() {
        let k1 = RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false)
        let k2 = RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: false)
        let k3 = RawKeystroke(keyCode: VietnameseData.KEY_A, isCaps: true)

        XCTAssertEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
    }
}
