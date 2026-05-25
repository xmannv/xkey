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
        let snapshot = BufferSnapshot(entries: entries, overflow: [overflowEntry], keystrokeSequence: [])

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
        let snapshot = BufferSnapshot(entries: entries, overflow: [overflowEntry], keystrokeSequence: [])

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
        let snapshot = BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: [])

        history.save(snapshot)

        XCTAssertEqual(history.count, 1)
        XCTAssertNotNil(history.last)
    }

    func testPopLast() {
        let entries = [CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)]
        let snapshot = BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: [])

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
        let snapshot = BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: [])

        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.firstKeyCode, VietnameseData.KEY_A)
    }

    func testIsSpace() {
        let spaceEntry = CharacterEntry(keyCode: VietnameseData.KEY_SPACE, isCaps: false)
        let spaceSnapshot = BufferSnapshot(entries: [spaceEntry], overflow: [], keystrokeSequence: [])

        XCTAssertTrue(spaceSnapshot.isSpace)

        let normalEntry = CharacterEntry(keyCode: VietnameseData.KEY_A, isCaps: false)
        let normalSnapshot = BufferSnapshot(entries: [normalEntry], overflow: [], keystrokeSequence: [])

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

// MARK: - Keystroke Sequence Tests

/// Tests for keystroke sequence tracking in TypingBuffer
/// Ensures correct order is maintained for restore functionality
class KeystrokeSequenceTests: XCTestCase {
    
    var buffer: TypingBuffer!
    
    override func setUp() {
        super.setUp()
        buffer = TypingBuffer()
    }
    
    override func tearDown() {
        buffer = nil
        super.tearDown()
    }
    
    // MARK: - Basic Append Tests
    
    /// Test that recording keystroke adds to sequence
    func testRecordKeystrokeAddsToSequence() {
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))  // t
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))  // h
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))  // u
        
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 3)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
    }
    
    /// Test keystrokeSequenceCount property
    func testKeystrokeSequenceCount() {
        XCTAssertEqual(buffer.keystrokeSequenceCount, 0)
        
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        XCTAssertEqual(buffer.keystrokeSequenceCount, 1)
        
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))
        XCTAssertEqual(buffer.keystrokeSequenceCount, 2)
    }
    
    // MARK: - Modifier Order Tests
    
    /// Test critical case: "thưef" where f modifies ư but typed after e
    /// keystrokeSequence should maintain typing order: t, h, u, w, e, f
    /// Even though f is a modifier for ư (entry at index 2). Uses the stamped pattern
    /// for non-last-entry modifiers so each keystroke's entryId points to its real
    /// owning entry — required for `removeLast` filtering to behave correctly.
    func testModifierAtOldEntryMaintainsTypingOrder() {
        // Simulate typing "thưef" where f modifies ư

        // t
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))

        // h
        buffer.append(keyCode: 0x04, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))

        // u
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))

        // w (modifier to u → ư) — entries.last is still u, so auto-stamping happens
        // to land on the right entry; using the stamped result is harmless here.
        let stampedW = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(stampedW)

        // e (new entry)
        buffer.append(keyCode: 0x0E, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0E, isCaps: false))

        // f (modifier to ư at index 2, typed AFTER e). Now entries.last is e, so
        // recordKeystroke's auto-stamping would wrongly tag f with e's id; pass the
        // stamped value from `addModifier(at:)` instead so f stays correlated with u.
        let stampedF = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x03, isCaps: false))
        buffer.recordKeystroke(stampedF)
        
        // Verify keystrokeSequence maintains typing order
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x0E)  // e - BEFORE f ✓
        XCTAssertEqual(sequence[5].keyCode, 0x03)  // f - AFTER e ✓
        
        // Compare with getAllRawKeystrokes (per-entry order)
        let allKeystrokes = buffer.getAllRawKeystrokes()
        // getAllRawKeystrokes groups by entry, so f comes before e
        // Entry[2] = ư with modifiers [w, f]
        // Entry[3] = e with no modifiers
        // Result: t, h, u, w, f, e (WRONG order for restore!)
        XCTAssertEqual(allKeystrokes[4].keyCode, 0x03)  // f before e
        XCTAssertEqual(allKeystrokes[5].keyCode, 0x0E)  // e after f
        
        // This demonstrates why we need keystrokeSequence for restore!
    }
    
    // MARK: - Remove Tests
    
    /// Test that removeLast removes keystrokes from sequence
    func testRemoveLastUpdatesSequence() {
        // Append t, h, u
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        
        buffer.append(keyCode: 0x04, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))
        
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        
        // Remove last (u)
        buffer.removeLast()
        
        // Sequence should be: t, h
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
    }
    
    /// Test that removeLast with modifiers removes all keystrokes from that entry
    func testRemoveLastWithModifiersUpdatesSequence() {
        // Append t, h
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        
        buffer.append(keyCode: 0x04, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))
        
        // Append u with w modifier (ư)
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0D, isCaps: false))
        
        // Remove last (ư which has u + w = 2 keystrokes)
        buffer.removeLast()
        
        // Sequence should be: t, h (u and w removed)
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
    }
    
    /// Test that removeLastModifier updates sequence
    func testRemoveLastModifierUpdatesSequence() {
        // Append u with w modifier
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0D, isCaps: false))
        
        XCTAssertEqual(buffer.keystrokeSequenceCount, 2)
        
        // Remove modifier (w)
        buffer.removeLastModifierFromLast()
        
        // Sequence should be: u only
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 1)
        XCTAssertEqual(sequence[0].keyCode, 0x20)  // u
    }
    
    // MARK: - Clear Tests
    
    /// Test that clear clears keystrokeSequence
    func testClearClearsSequence() {
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))
        
        XCTAssertEqual(buffer.keystrokeSequenceCount, 2)
        
        buffer.clear()
        
        XCTAssertEqual(buffer.keystrokeSequenceCount, 0)
        XCTAssertTrue(buffer.getKeystrokeSequence().isEmpty)
    }
    
    // MARK: - UInt32 Conversion Tests
    
    /// Test getKeystrokeSequenceAsUInt32
    func testKeystrokeSequenceAsUInt32() {
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))  // t
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: true))   // H (caps)
        
        let sequence = buffer.getKeystrokeSequenceAsUInt32()
        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence[0], 0x11)  // t without caps
        XCTAssertEqual(sequence[1], 0x04 | TypingBuffer.CAPS_MASK)  // H with caps
    }
    
    // MARK: - Complex Scenario Tests
    
    /// Test "quás" scenario: q, u, a, a (modifier), s (modifier)
    func testQuasScenario() {
        // q
        buffer.append(keyCode: 0x0C, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0C, isCaps: false))
        
        // u
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        
        // a
        buffer.append(keyCode: 0x00, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x00, isCaps: false))
        
        // second a (modifier to make â)
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x00, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x00, isCaps: false))
        
        // s (mark on â)
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x01, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x01, isCaps: false))
        
        // Sequence should be: q, u, a, a, s
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 5)
        XCTAssertEqual(sequence[0].keyCode, 0x0C)  // q
        XCTAssertEqual(sequence[1].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[2].keyCode, 0x00)  // a
        XCTAssertEqual(sequence[3].keyCode, 0x00)  // a (modifier)
        XCTAssertEqual(sequence[4].keyCode, 0x01)  // s
    }
    
    /// Test caps preserved in sequence
    func testCapsPreservedInSequence() {
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: true))   // T
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))  // h
        
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertTrue(sequence[0].isCaps)   // T is caps
        XCTAssertFalse(sequence[1].isCaps)  // h is not caps
    }
    
    /// Test removeLastFromSequence
    func testRemoveLastFromSequence() {
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        
        let removed = buffer.removeLastFromSequence()
        
        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.keyCode, 0x20)
        XCTAssertEqual(buffer.keystrokeSequenceCount, 2)
    }
}

// MARK: - Restore + Edit Tests

/// Tests for restore from history followed by edit operations
/// These tests ensure keystrokeSequence remains consistent after restore + delete + type
class RestoreEditTests: XCTestCase {
    
    var buffer: TypingBuffer!
    
    override func setUp() {
        super.setUp()
        buffer = TypingBuffer()
    }
    
    override func tearDown() {
        buffer = nil
        super.tearDown()
    }
    
    // MARK: - Snapshot and Restore
    
    /// Test that createSnapshot includes keystrokeSequence
    func testCreateSnapshotIncludesKeystrokeSequence() {
        // Simulate typing "ua" with w modifier on u (ưa). w is a modifier on a
        // non-last entry, so pass the stamped result of `addModifier(at:)` to
        // `recordKeystroke` to keep entryIds correct.
        buffer.append(keyCode: 0x20, isCaps: false)  // u
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))

        buffer.append(keyCode: 0x00, isCaps: false)  // a
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x00, isCaps: false))

        let stampedW = buffer.addModifier(at: 0, keystroke: RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(stampedW)
        
        let snapshot = buffer.createSnapshot()
        
        // Snapshot should have keystrokeSequence
        XCTAssertEqual(snapshot.keystrokeSequence.count, 3)
        XCTAssertEqual(snapshot.keystrokeSequence[0].keyCode, 0x20)  // u
        XCTAssertEqual(snapshot.keystrokeSequence[1].keyCode, 0x00)  // a
        XCTAssertEqual(snapshot.keystrokeSequence[2].keyCode, 0x0D)  // w
    }
    
    /// Restore must preserve the snapshot's `keystrokeSequence` verbatim (typing order).
    /// Stable entry IDs let subsequent mutations stay consistent without needing the
    /// per-entry rebuild that previously discarded typing order.
    func testRestorePreservesSnapshotTypingOrder() {
        // Build entry "ư" (u with w modifier) — w was actually typed AFTER a in user's
        // real sequence, so typing order is u, a, w.
        let entryU = CharacterEntry(keyCode: 0x20, isCaps: false)  // u
        var entryUWithMod = entryU
        entryUWithMod.addModifier(RawKeystroke(keyCode: 0x0D, isCaps: false))  // w stamped with u's id

        let entryA = CharacterEntry(keyCode: 0x00, isCaps: false)  // a

        // Build sequence in typing order with proper entryIds so restore + later edits
        // can still correlate keystrokes back to entries.
        let originalSequence = [
            entryUWithMod.primaryKeystroke,        // u
            entryA.primaryKeystroke,               // a
            entryUWithMod.modifierKeystrokes[0]    // w (stamped with u's id)
        ]

        let snapshot = BufferSnapshot(
            entries: [entryUWithMod, entryA],
            overflow: [],
            keystrokeSequence: originalSequence
        )

        buffer.restore(from: snapshot)

        // After restore, sequence stays in typing order: u, a, w (not per-entry [u, w, a]).
        let restoredSequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(restoredSequence.count, 3)
        XCTAssertEqual(restoredSequence[0].keyCode, 0x20)  // u
        XCTAssertEqual(restoredSequence[1].keyCode, 0x00)  // a (typed before the w modifier)
        XCTAssertEqual(restoredSequence[2].keyCode, 0x0D)  // w (modifier on u, typed last)
    }
    
    /// Critical test: "thừa" → restore → delete 'a' → type 'e'. With stable entry IDs,
    /// restore preserves typing order (not per-entry order). Subsequent `removeLast`
    /// filters the sequence by the removed entry's id so the deleted entry's keystroke
    /// is pulled from its true position in typing order, not blindly from the tail.
    func testRestoreDeleteTypeProducesCorrectSequence() {
        // Build "thừa" entries. Modifiers are stamped with the owning entry's id by
        // CharacterEntry.addModifier — capture the resulting keystrokes so the snapshot
        // sequence holds the same entryIds.
        let entryT = CharacterEntry(keyCode: 0x11, isCaps: false)  // t
        let entryH = CharacterEntry(keyCode: 0x04, isCaps: false)  // h
        var entryU = CharacterEntry(keyCode: 0x20, isCaps: false)  // u → ư → ừ
        let wMod = entryU.addModifier(RawKeystroke(keyCode: 0x0D, isCaps: false))
        let fMod = entryU.addModifier(RawKeystroke(keyCode: 0x03, isCaps: false))
        let entryA = CharacterEntry(keyCode: 0x00, isCaps: false)  // a

        // Typing order: t, h, u, a, w, f. Both w and f were typed after a, but they
        // belong to u (they're modifiers on it). The snapshot sequence records the
        // true typing order while each keystroke's entryId still points back to its
        // owning entry.
        let originalSequence = [
            entryT.primaryKeystroke,
            entryH.primaryKeystroke,
            entryU.primaryKeystroke,
            entryA.primaryKeystroke,
            wMod,
            fMod
        ]

        let snapshot = BufferSnapshot(
            entries: [entryT, entryH, entryU, entryA],
            overflow: [],
            keystrokeSequence: originalSequence
        )

        // Step 1: Restore from snapshot — sequence preserved in typing order.
        buffer.restore(from: snapshot)

        var sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x00)  // a — typed before the w/f modifiers
        XCTAssertEqual(sequence[4].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[5].keyCode, 0x03)  // f

        // Step 2: Delete 'a' — `removeLast` filters sequence by entryA.id, removing
        // the 'a' keystroke from its true position (index 3) without disturbing the
        // w/f modifiers that belong to u.
        buffer.removeLast()

        sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 5)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x03)  // f

        // Step 3: Type 'e'.
        buffer.append(keyCode: 0x0E, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0E, isCaps: false))

        sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x03)  // f
        XCTAssertEqual(sequence[5].keyCode, 0x0E)  // e

        // Replaying this sequence produces: "thuwfe" ✓
    }
    
    /// Test delete entry with modifiers removes all keystrokes correctly
    func testDeleteEntryWithModifiersRemovesAllKeystrokes() {
        // Build "ừ" = u + w + f
        buffer.append(keyCode: 0x20, isCaps: false)  // u
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))
        
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x0D, isCaps: false))  // w
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0D, isCaps: false))
        
        buffer.addModifierToLast(RawKeystroke(keyCode: 0x03, isCaps: false))  // f
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x03, isCaps: false))
        
        XCTAssertEqual(buffer.keystrokeSequenceCount, 3)  // u, w, f
        
        // Delete the entry (ừ)
        buffer.removeLast()
        
        // All keystrokes should be removed
        XCTAssertEqual(buffer.keystrokeSequenceCount, 0)
    }
    
    /// Test restore empty snapshot
    func testRestoreEmptySnapshot() {
        // Add some content first
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))
        
        // Restore empty
        buffer.restore(from: BufferSnapshot.empty)
        
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.keystrokeSequenceCount, 0)
    }
    
    /// Test multiple restore operations
    func testMultipleRestoreOperations() {
        // Build snapshots with proper sequences so the buffer's invariant
        // (sequence count == totalKeystrokeCount, every keystroke carries its entry's
        // id) is satisfied after each restore.
        let entriesAB: [CharacterEntry] = [
            CharacterEntry(keyCode: 0x00, isCaps: false),  // a
            CharacterEntry(keyCode: 0x0B, isCaps: false)   // b
        ]
        let snapshot1 = BufferSnapshot(
            entries: entriesAB,
            overflow: [],
            keystrokeSequence: entriesAB.map { $0.primaryKeystroke }
        )

        let entriesXY: [CharacterEntry] = [
            CharacterEntry(keyCode: 0x07, isCaps: false),  // x
            CharacterEntry(keyCode: 0x10, isCaps: false)   // y
        ]
        let snapshot2 = BufferSnapshot(
            entries: entriesXY,
            overflow: [],
            keystrokeSequence: entriesXY.map { $0.primaryKeystroke }
        )
        
        // Restore first
        buffer.restore(from: snapshot1)
        XCTAssertEqual(buffer.count, 2)
        
        // Restore second
        buffer.restore(from: snapshot2)
        XCTAssertEqual(buffer.count, 2)
        
        // keystrokeSequence should match second snapshot's entries
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 2)
        XCTAssertEqual(sequence[0].keyCode, 0x07)  // x
        XCTAssertEqual(sequence[1].keyCode, 0x10)  // y
    }
    
    /// Test that getAllRawKeystrokes matches keystrokeSequence after restore
    func testGetAllRawKeystrokesMatchesSequenceAfterRestore() {
        // Create snapshot with entry that has modifiers
        var entryU = CharacterEntry(keyCode: 0x20, isCaps: false)
        entryU.addModifier(RawKeystroke(keyCode: 0x0D, isCaps: false))  // w
        
        let snapshot = BufferSnapshot(
            entries: [entryU],
            overflow: [],
            keystrokeSequence: [
                RawKeystroke(keyCode: 0x20, isCaps: false),
                RawKeystroke(keyCode: 0x0D, isCaps: false)
            ]
        )
        
        buffer.restore(from: snapshot)
        
        // After restore, keystrokeSequence should equal getAllRawKeystrokes
        let allRaw = buffer.getAllRawKeystrokes()
        let sequence = buffer.getKeystrokeSequence()
        
        XCTAssertEqual(allRaw.count, sequence.count)
        for i in 0..<allRaw.count {
            XCTAssertEqual(allRaw[i].keyCode, sequence[i].keyCode)
            XCTAssertEqual(allRaw[i].isCaps, sequence[i].isCaps)
        }
    }
}

// MARK: - Integration Tests for Restore Wrong Spelling

/// Tests that simulate the full restore wrong spelling flow
class RestoreWrongSpellingIntegrationTests: XCTestCase {
    
    var buffer: TypingBuffer!
    
    override func setUp() {
        super.setUp()
        buffer = TypingBuffer()
    }
    
    override func tearDown() {
        buffer = nil
        super.tearDown()
    }
    
    /// Simulate typing "thưef" where f is modifier for ư typed AFTER e
    /// Original bug: restore produced "thuwfe" instead of "thuwef".
    /// Uses the stamped pattern for non-last-entry modifiers so f's entryId points
    /// at u, not e (would otherwise corrupt sequence if removeLast were called).
    func testTypingWithLateModifierProducesCorrectRestoreOrder() {
        // Simulate typing: t, h, u, w, e, f. f is modifier for ư but typed after e.

        // t
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))

        // h
        buffer.append(keyCode: 0x04, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))

        // u
        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))

        // w (modifier to u → ư)
        let stampedW = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(stampedW)

        // e (new entry, typed BEFORE f)
        buffer.append(keyCode: 0x0E, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0E, isCaps: false))

        // f (modifier to ư at index 2, typed AFTER e)
        let stampedF = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x03, isCaps: false))
        buffer.recordKeystroke(stampedF)
        
        // keystrokeSequence should maintain typing order: t, h, u, w, e, f
        let sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x0E)  // e - BEFORE f ✓
        XCTAssertEqual(sequence[5].keyCode, 0x03)  // f - AFTER e ✓
        
        // Restore using keystrokeSequence produces: "thuwef" ✓
    }
    
    /// Simulate the problematic scenario from log:
    /// Type "thừa" → save → restore → delete 'a' → type 'e' → restore should produce
    /// "thuwfe". With stable entry IDs, restore preserves typing order and removeLast
    /// filters by entryId, so both the immediate restore state and the post-edit state
    /// reflect what the user actually typed.
    func testHistoryRestoreThenEditProducesCorrectRestore() {
        // Step 1: Type "thừa" — typing order is t, h, u, a, w, f. Use the stamped
        // keystroke returned by `addModifier(at:)` so non-last-entry modifiers get the
        // right entryId in the sequence (auto-stamping inside `recordKeystroke` uses
        // entries.last.id, which would mis-label these).
        buffer.append(keyCode: 0x11, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x11, isCaps: false))

        buffer.append(keyCode: 0x04, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x04, isCaps: false))

        buffer.append(keyCode: 0x20, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x20, isCaps: false))

        buffer.append(keyCode: 0x00, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x00, isCaps: false))

        // w (modifier on u at index 2) — pass the stamped result to recordKeystroke.
        let stampedW = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x0D, isCaps: false))
        buffer.recordKeystroke(stampedW)

        // f (modifier on u at index 2)
        let stampedF = buffer.addModifier(at: 2, keystroke: RawKeystroke(keyCode: 0x03, isCaps: false))
        buffer.recordKeystroke(stampedF)

        // Step 2: Save snapshot.
        let snapshot = buffer.createSnapshot()

        // Step 3: Clear (simulate word break).
        buffer.clear()

        // Step 4: Restore from snapshot. Sequence stays in typing order.
        buffer.restore(from: snapshot)

        var sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[3].keyCode, 0x00, "After restore, 'a' sits at typing-order position 3 (typed before w and f)")
        XCTAssertEqual(sequence[5].keyCode, 0x03, "Tail keystroke is 'f' — last key the user pressed")

        // Step 5: Delete 'a'. removeLast filters by entryId so the 'a' keystroke is
        // removed from its true position (index 3), leaving the w/f modifiers intact.
        buffer.removeLast()

        sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 5)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x03)  // f

        // Step 6: Type 'e'.
        buffer.append(keyCode: 0x0E, isCaps: false)
        buffer.recordKeystroke(RawKeystroke(keyCode: 0x0E, isCaps: false))

        sequence = buffer.getKeystrokeSequence()
        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence[0].keyCode, 0x11)  // t
        XCTAssertEqual(sequence[1].keyCode, 0x04)  // h
        XCTAssertEqual(sequence[2].keyCode, 0x20)  // u
        XCTAssertEqual(sequence[3].keyCode, 0x0D)  // w
        XCTAssertEqual(sequence[4].keyCode, 0x03)  // f
        XCTAssertEqual(sequence[5].keyCode, 0x0E)  // e

        // Replaying this sequence produces: "thuwfe" ✓
    }
}
