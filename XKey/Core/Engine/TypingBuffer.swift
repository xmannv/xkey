//
//  TypingBuffer.swift
//  XKey
//
//  Unified Buffer System - Single source of truth for typing state
//  Replaces the dual typingWord/keyStates architecture
//

import Foundation

// MARK: - Raw Keystroke

/// Represents a single raw keystroke from the user
struct RawKeystroke: Equatable {
    let keyCode: UInt16
    let isCaps: Bool

    var asUInt32: UInt32 {
        UInt32(keyCode) | (isCaps ? TypingBuffer.CAPS_MASK : 0)
    }

    init(keyCode: UInt16, isCaps: Bool = false) {
        self.keyCode = keyCode
        self.isCaps = isCaps
    }

    init(from data: UInt32) {
        self.keyCode = UInt16(data & TypingBuffer.CHAR_MASK)
        self.isCaps = (data & TypingBuffer.CAPS_MASK) != 0
    }
}

// MARK: - Character Entry

/// A single character in the typing buffer
/// Contains both raw input (for restore) and processed output (for display)
struct CharacterEntry: Equatable {
    // MARK: - Raw Input (for restore/undo)

    /// The primary keystroke that created this entry
    var primaryKeystroke: RawKeystroke

    /// Additional keystrokes that modified this entry (e.g., 'a' for aa→â, 'j' for tone mark)
    /// When restoring, we replay: primaryKeystroke + modifierKeystrokes
    var modifierKeystrokes: [RawKeystroke] = []

    // MARK: - Processed Output (for display)

    /// The processed character data with all Vietnamese modifications
    /// Contains: keyCode | CAPS_MASK | TONE_MASK | TONEW_MASK | MARK_MASK | STANDALONE_MASK
    var processedData: UInt32

    // MARK: - Computed Properties

    /// The base key code (without any masks)
    var keyCode: UInt16 {
        UInt16(processedData & TypingBuffer.CHAR_MASK)
    }

    /// Whether the character is uppercase
    var isCaps: Bool {
        get { (processedData & TypingBuffer.CAPS_MASK) != 0 }
        set {
            if newValue {
                processedData |= TypingBuffer.CAPS_MASK
            } else {
                processedData &= ~TypingBuffer.CAPS_MASK
            }
        }
    }

    /// Whether the character has circumflex (â, ê, ô)
    var hasTone: Bool {
        get { (processedData & TypingBuffer.TONE_MASK) != 0 }
        set {
            if newValue {
                processedData |= TypingBuffer.TONE_MASK
            } else {
                processedData &= ~TypingBuffer.TONE_MASK
            }
        }
    }

    /// Whether the character has horn (ư, ơ)
    var hasToneW: Bool {
        get { (processedData & TypingBuffer.TONEW_MASK) != 0 }
        set {
            if newValue {
                processedData |= TypingBuffer.TONEW_MASK
            } else {
                processedData &= ~TypingBuffer.TONEW_MASK
            }
        }
    }

    /// Whether the character has a tone mark (sắc, huyền, hỏi, ngã, nặng)
    var hasMark: Bool {
        (processedData & TypingBuffer.MARK_MASK) != 0
    }

    /// The tone mark value (0 = no mark, or one of MARK1-MARK5)
    var mark: UInt32 {
        get { processedData & TypingBuffer.MARK_MASK }
        set {
            processedData &= ~TypingBuffer.MARK_MASK
            processedData |= (newValue & TypingBuffer.MARK_MASK)
        }
    }

    /// Whether this is a standalone character (ơ from [, ư from ])
    var isStandalone: Bool {
        get { (processedData & TypingBuffer.STANDALONE_MASK) != 0 }
        set {
            if newValue {
                processedData |= TypingBuffer.STANDALONE_MASK
            } else {
                processedData &= ~TypingBuffer.STANDALONE_MASK
            }
        }
    }

    /// Total number of keystrokes that created this entry
    var keystrokeCount: Int {
        1 + modifierKeystrokes.count
    }

    /// All keystrokes in order (for restore)
    var allKeystrokes: [RawKeystroke] {
        [primaryKeystroke] + modifierKeystrokes
    }

    // MARK: - Initialization

    init(keyCode: UInt16, isCaps: Bool) {
        self.primaryKeystroke = RawKeystroke(keyCode: keyCode, isCaps: isCaps)
        self.processedData = UInt32(keyCode) | (isCaps ? TypingBuffer.CAPS_MASK : 0)
    }

    init(primaryKeystroke: RawKeystroke, processedData: UInt32) {
        self.primaryKeystroke = primaryKeystroke
        self.processedData = processedData
    }

    /// Create from legacy typingWord data (for migration)
    init(fromLegacy processedData: UInt32) {
        let keyCode = UInt16(processedData & TypingBuffer.CHAR_MASK)
        let isCaps = (processedData & TypingBuffer.CAPS_MASK) != 0
        self.primaryKeystroke = RawKeystroke(keyCode: keyCode, isCaps: isCaps)
        self.processedData = processedData
    }

    // MARK: - Mutation Methods

    /// Add a modifier keystroke (e.g., second 'a' for â, 'j' for tone mark)
    mutating func addModifier(_ keystroke: RawKeystroke) {
        modifierKeystrokes.append(keystroke)
    }

    /// Remove the last modifier keystroke (for undo)
    @discardableResult
    mutating func removeLastModifier() -> RawKeystroke? {
        modifierKeystrokes.popLast()
    }

    /// Clear all modifiers
    mutating func clearModifiers() {
        modifierKeystrokes.removeAll()
    }

    /// Update the processed data with a mask
    mutating func addMask(_ mask: UInt32) {
        processedData |= mask
    }

    /// Remove a mask from processed data
    mutating func removeMask(_ mask: UInt32) {
        processedData &= ~mask
    }

    /// Set the base key code (preserving other masks)
    mutating func setKeyCode(_ keyCode: UInt16) {
        processedData = (processedData & ~TypingBuffer.CHAR_MASK) | UInt32(keyCode)
    }
}

// MARK: - Typing Buffer

/// Unified buffer for Vietnamese typing
/// Single source of truth - no more sync issues between typingWord and keyStates
final class TypingBuffer {

    // MARK: - Constants (same as VNEngine for compatibility)

    static let MAX_SIZE = 32

    static let CHAR_MASK: UInt32    = 0xFFFF      // Bits 0-15: key code
    static let CAPS_MASK: UInt32    = 0x10000     // Bit 16: uppercase
    static let TONE_MASK: UInt32    = 0x20000     // Bit 17: circumflex (^)
    static let TONEW_MASK: UInt32   = 0x40000     // Bit 18: horn (ư, ơ)
    static let MARK_MASK: UInt32    = 0xF80000    // Bits 19-23: tone marks
    static let STANDALONE_MASK: UInt32 = 0x1000000 // Bit 24: standalone char

    // Tone marks
    static let MARK1: UInt32 = 0x080000  // Sắc (´)
    static let MARK2: UInt32 = 0x100000  // Huyền (`)
    static let MARK3: UInt32 = 0x180000  // Hỏi (?)
    static let MARK4: UInt32 = 0x200000  // Ngã (~)
    static let MARK5: UInt32 = 0x280000  // Nặng (.)

    // MARK: - Storage

    private var entries: [CharacterEntry] = []

    /// Characters that overflowed the buffer (for very long words)
    private var overflow: [CharacterEntry] = []

    // MARK: - Properties

    /// Number of characters in the buffer (displayed characters)
    var count: Int { entries.count }

    /// Whether the buffer is empty
    var isEmpty: Bool { entries.isEmpty }

    /// Whether the buffer is full
    var isFull: Bool { entries.count >= TypingBuffer.MAX_SIZE }

    /// Total number of raw keystrokes (for restore)
    var totalKeystrokeCount: Int {
        entries.reduce(0) { $0 + $1.keystrokeCount } +
        overflow.reduce(0) { $0 + $1.keystrokeCount }
    }

    /// Check if there are overflow characters
    var hasOverflow: Bool { !overflow.isEmpty }

    // MARK: - Subscript Access

    subscript(index: Int) -> CharacterEntry {
        get {
            guard index >= 0 && index < entries.count else {
                fatalError("TypingBuffer index out of bounds: \(index), count: \(entries.count)")
            }
            return entries[index]
        }
        set {
            guard index >= 0 && index < entries.count else {
                fatalError("TypingBuffer index out of bounds: \(index), count: \(entries.count)")
            }
            entries[index] = newValue
        }
    }

    // MARK: - Insert Operations

    /// Insert a new character at the end
    /// Returns: the index where the character was inserted
    @discardableResult
    func append(keyCode: UInt16, isCaps: Bool) -> Int {
        if entries.count >= TypingBuffer.MAX_SIZE {
            // Move first entry to overflow
            overflow.append(entries.removeFirst())
        }

        let entry = CharacterEntry(keyCode: keyCode, isCaps: isCaps)
        entries.append(entry)
        return entries.count - 1
    }

    /// Insert a new character entry at the end
    @discardableResult
    func append(_ entry: CharacterEntry) -> Int {
        if entries.count >= TypingBuffer.MAX_SIZE {
            overflow.append(entries.removeFirst())
        }
        entries.append(entry)
        return entries.count - 1
    }

    // MARK: - Remove Operations

    /// Remove and return the last character
    @discardableResult
    func removeLast() -> CharacterEntry? {
        guard !entries.isEmpty else { return nil }

        let removed = entries.removeLast()

        // If we have overflow, bring one back
        if !overflow.isEmpty {
            entries.insert(overflow.removeLast(), at: 0)
        }

        return removed
    }

    /// Remove character at specific index
    @discardableResult
    func remove(at index: Int) -> CharacterEntry? {
        guard index >= 0 && index < entries.count else { return nil }

        let removed = entries.remove(at: index)

        // If we have overflow, bring one back
        if !overflow.isEmpty {
            entries.insert(overflow.removeLast(), at: 0)
        }

        return removed
    }

    /// Clear the entire buffer
    func clear() {
        entries.removeAll()
        overflow.removeAll()
    }

    // MARK: - Modifier Operations

    /// Add a modifier keystroke to the last entry
    /// Used for Telex double keys (aa→â) and tone marks
    func addModifierToLast(_ keystroke: RawKeystroke) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].addModifier(keystroke)
    }

    /// Add a modifier keystroke to entry at specific index
    func addModifier(at index: Int, keystroke: RawKeystroke) {
        guard index >= 0 && index < entries.count else { return }
        entries[index].addModifier(keystroke)
    }

    /// Remove the last modifier from the last entry
    @discardableResult
    func removeLastModifierFromLast() -> RawKeystroke? {
        guard !entries.isEmpty else { return nil }
        return entries[entries.count - 1].removeLastModifier()
    }

    // MARK: - Query Operations

    /// Get the last entry (or nil if empty)
    var last: CharacterEntry? {
        entries.last
    }

    /// Get entry at index from the end (0 = last, 1 = second to last, etc.)
    func fromEnd(_ offset: Int) -> CharacterEntry? {
        let index = entries.count - 1 - offset
        guard index >= 0 && index < entries.count else { return nil }
        return entries[index]
    }

    /// Get the key code at index
    func keyCode(at index: Int) -> UInt16 {
        guard index >= 0 && index < entries.count else { return 0 }
        return entries[index].keyCode
    }

    /// Get raw keystroke at flat index (across all entries and modifiers)
    /// This provides O(1) amortized access for sequential iteration
    func getRawKeystroke(at flatIndex: Int) -> RawKeystroke? {
        var currentIndex = 0

        // Check overflow first
        for entry in overflow {
            let entryKeystrokeCount = entry.keystrokeCount
            if flatIndex < currentIndex + entryKeystrokeCount {
                let localIndex = flatIndex - currentIndex
                if localIndex == 0 {
                    return entry.primaryKeystroke
                } else {
                    return entry.modifierKeystrokes[localIndex - 1]
                }
            }
            currentIndex += entryKeystrokeCount
        }

        // Then check entries
        for entry in entries {
            let entryKeystrokeCount = entry.keystrokeCount
            if flatIndex < currentIndex + entryKeystrokeCount {
                let localIndex = flatIndex - currentIndex
                if localIndex == 0 {
                    return entry.primaryKeystroke
                } else {
                    return entry.modifierKeystrokes[localIndex - 1]
                }
            }
            currentIndex += entryKeystrokeCount
        }

        return nil
    }

    /// Get the processed data at index (compatible with legacy typingWord)
    func processedData(at index: Int) -> UInt32 {
        guard index >= 0 && index < entries.count else { return 0 }
        return entries[index].processedData
    }

    /// Set the processed data at index
    func setProcessedData(at index: Int, _ data: UInt32) {
        guard index >= 0 && index < entries.count else { return }
        entries[index].processedData = data
    }

    // MARK: - Raw Keystroke Extraction

    /// Get all raw keystrokes in order (for restore/undo)
    func getAllRawKeystrokes() -> [RawKeystroke] {
        var result: [RawKeystroke] = []

        // Add overflow keystrokes first
        for entry in overflow {
            result.append(contentsOf: entry.allKeystrokes)
        }

        // Add current entries
        for entry in entries {
            result.append(contentsOf: entry.allKeystrokes)
        }

        return result
    }

    /// Get raw keystrokes as UInt32 array (compatible with legacy keyStates)
    func getRawKeystrokesAsUInt32() -> [UInt32] {
        getAllRawKeystrokes().map { $0.asUInt32 }
    }

    /// Get raw input as string (ASCII without Vietnamese transforms)
    func getRawInputString(using keyCodeToChar: (UInt16) -> Character?) -> String {
        var result = ""
        for keystroke in getAllRawKeystrokes() {
            if let char = keyCodeToChar(keystroke.keyCode) {
                let finalChar = keystroke.isCaps ? Character(String(char).uppercased()) : char
                result.append(finalChar)
            }
        }
        return result
    }

    // MARK: - Processed Output

    /// Get all processed data as UInt32 array (compatible with legacy typingWord)
    func getAllProcessedData() -> [UInt32] {
        entries.map { $0.processedData }
    }

    /// Get all entries
    func getAllEntries() -> [CharacterEntry] {
        entries
    }

    // MARK: - Snapshot & Restore

    /// Create a snapshot of the current state
    func createSnapshot() -> BufferSnapshot {
        BufferSnapshot(
            entries: entries,
            overflow: overflow
        )
    }

    /// Restore from a snapshot
    func restore(from snapshot: BufferSnapshot) {
        entries = snapshot.entries
        overflow = snapshot.overflow
    }

    /// Restore from legacy typingWord data
    /// Note: This loses raw keystroke information
    func restoreFromLegacy(_ legacyData: [UInt32]) {
        clear()
        for data in legacyData {
            let entry = CharacterEntry(fromLegacy: data)
            entries.append(entry)
        }
    }

    // MARK: - Iteration

    /// Iterate over entries from start to end
    func forEach(_ body: (Int, CharacterEntry) -> Void) {
        for (index, entry) in entries.enumerated() {
            body(index, entry)
        }
    }

    /// Iterate over entries from end to start
    func forEachReversed(_ body: (Int, CharacterEntry) -> Void) {
        for index in stride(from: entries.count - 1, through: 0, by: -1) {
            body(index, entries[index])
        }
    }

    /// Find index of first entry matching predicate
    func firstIndex(where predicate: (CharacterEntry) -> Bool) -> Int? {
        entries.firstIndex(where: predicate)
    }

    /// Find index of last entry matching predicate
    func lastIndex(where predicate: (CharacterEntry) -> Bool) -> Int? {
        entries.lastIndex(where: predicate)
    }

    // MARK: - Debug

    func debugDescription() -> String {
        var result = "TypingBuffer(count=\(count), keystrokes=\(totalKeystrokeCount))\n"
        for (i, entry) in entries.enumerated() {
            result += "  [\(i)] keyCode=\(entry.keyCode) processed=\(String(format: "0x%X", entry.processedData)) "
            result += "modifiers=\(entry.modifierKeystrokes.count)\n"
        }
        return result
    }
}

// MARK: - Buffer Snapshot

/// Immutable snapshot of buffer state for save/restore
struct BufferSnapshot: Equatable {
    let entries: [CharacterEntry]
    let overflow: [CharacterEntry]

    /// Number of displayed characters
    var count: Int { entries.count }

    /// Total keystrokes
    var keystrokeCount: Int {
        entries.reduce(0) { $0 + $1.keystrokeCount } +
        overflow.reduce(0) { $0 + $1.keystrokeCount }
    }

    /// Check if this is a space (KEY_SPACE = 0x31)
    var isSpace: Bool {
        entries.count == 1 && entries[0].keyCode == 0x31
    }

    /// Get all processed data (for legacy compatibility)
    var allProcessedData: [UInt32] {
        entries.map { $0.processedData }
    }

    /// Get first key code
    var firstKeyCode: UInt16? {
        entries.first?.keyCode
    }

    /// Empty snapshot
    static let empty = BufferSnapshot(entries: [], overflow: [])
}

// MARK: - Typing History

/// Manages the history of typed words for restore functionality
final class TypingHistory {

    private var snapshots: [BufferSnapshot] = []

    /// Number of saved words
    var count: Int { snapshots.count }

    /// Whether history is empty
    var isEmpty: Bool { snapshots.isEmpty }

    /// Save current buffer state
    func save(_ snapshot: BufferSnapshot) {
        guard !snapshot.entries.isEmpty else { return }
        snapshots.append(snapshot)
    }

    /// Save a space word
    func saveSpaces(count: Int, keyCode: UInt16 = 0x31) {
        var entries: [CharacterEntry] = []
        for _ in 0..<count {
            entries.append(CharacterEntry(keyCode: keyCode, isCaps: false))
        }
        snapshots.append(BufferSnapshot(entries: entries, overflow: []))
    }

    /// Pop and return the last saved snapshot
    @discardableResult
    func popLast() -> BufferSnapshot? {
        snapshots.popLast()
    }

    /// Peek at the last snapshot without removing
    var last: BufferSnapshot? {
        snapshots.last
    }

    /// Clear all history
    func clear() {
        snapshots.removeAll()
    }
}
