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

    // MARK: - Constants (referencing VNEngine as canonical source)

    static let MAX_SIZE = 32

    // Masks - delegate to VNEngine to avoid duplication
    static var CHAR_MASK: UInt32       { VNEngine.CHAR_MASK }
    static var CAPS_MASK: UInt32       { VNEngine.CAPS_MASK }
    static var TONE_MASK: UInt32       { VNEngine.TONE_MASK }
    static var TONEW_MASK: UInt32      { VNEngine.TONEW_MASK }
    static var MARK_MASK: UInt32       { VNEngine.MARK_MASK }
    static var STANDALONE_MASK: UInt32 { VNEngine.STANDALONE_MASK }

    // Tone mark values - delegate to VNEngine to avoid duplication
    static var MARK1: UInt32 { VNEngine.MARK1_MASK }  // Sắc (´)
    static var MARK2: UInt32 { VNEngine.MARK2_MASK }  // Huyền (`)
    static var MARK3: UInt32 { VNEngine.MARK3_MASK }  // Hỏi (?)
    static var MARK4: UInt32 { VNEngine.MARK4_MASK }  // Ngã (~)
    static var MARK5: UInt32 { VNEngine.MARK5_MASK }  // Nặng (.)

    // MARK: - Storage

    private var entries: [CharacterEntry] = []

    /// Characters that overflowed the buffer (for very long words)
    private var overflow: [CharacterEntry] = []

    /// Keystroke sequence in actual typing order (for restore at word break)
    /// This tracks the EXACT order user typed keys, separate from per-entry modifiers
    /// Example: "thưef" → sequence = [t, h, u, w, e, f] in this exact order
    /// Note: getAllRawKeystrokes() returns [t, h, u, w, f, e] because f modifies ư (entry[2])
    /// For word break restore, we need keystrokeSequence to restore correct order
    private var keystrokeSequence: [RawKeystroke] = []

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
    /// Also removes the corresponding keystrokes from keystrokeSequence
    @discardableResult
    func removeLast() -> CharacterEntry? {
        guard !entries.isEmpty else { return nil }

        let removed = entries.removeLast()
        
        // Remove corresponding keystrokes from sequence
        // The entry had (1 primary + N modifiers) keystrokes
        let keystrokesToRemove = removed.keystrokeCount
        for _ in 0..<keystrokesToRemove {
            _ = keystrokeSequence.popLast()
        }

        // If we have overflow, bring one back
        if !overflow.isEmpty {
            entries.insert(overflow.removeLast(), at: 0)
        }

        return removed
    }

    /// Remove character at specific index
    /// Note: This is more complex - we need to find and remove the right keystrokes
    /// For now, we only remove from sequence if removing the LAST entry
    /// Other cases are rare and the sequence may become inconsistent
    @discardableResult
    func remove(at index: Int) -> CharacterEntry? {
        guard index >= 0 && index < entries.count else { return nil }

        let removed = entries.remove(at: index)
        
        // If removing the last entry, also remove from sequence
        // For middle entries, sequence becomes inconsistent but this is rare
        if index == entries.count {
            let keystrokesToRemove = removed.keystrokeCount
            for _ in 0..<keystrokesToRemove {
                _ = keystrokeSequence.popLast()
            }
        }

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
        keystrokeSequence.removeAll()
    }

    // MARK: - Keystroke Sequence Tracking
    
    /// Record a keystroke in the actual typing order
    /// Call this for EVERY keystroke (primary keys and modifiers)
    /// This maintains the exact order user typed for restore at word break
    func recordKeystroke(_ keystroke: RawKeystroke) {
        keystrokeSequence.append(keystroke)
    }
    
    /// Get keystroke sequence in actual typing order (for restore at word break)
    /// This returns keystrokes in the EXACT order user typed them
    /// Unlike getAllRawKeystrokes() which groups modifiers with their entries
    func getKeystrokeSequence() -> [RawKeystroke] {
        return keystrokeSequence
    }
    
    /// Get keystroke sequence as UInt32 array (for compatibility)
    func getKeystrokeSequenceAsUInt32() -> [UInt32] {
        keystrokeSequence.map { $0.asUInt32 }
    }
    
    /// Remove last keystroke from sequence (for backspace handling)
    @discardableResult
    func removeLastFromSequence() -> RawKeystroke? {
        keystrokeSequence.popLast()
    }
    
    /// Get count of keystrokes in sequence
    var keystrokeSequenceCount: Int {
        keystrokeSequence.count
    }

    // MARK: - Modifier Operations

    /// Add a modifier keystroke to the last entry
    /// Used for Telex double keys (aa→â) and tone marks
    /// NOTE: This does NOT record to keystrokeSequence - caller must call recordKeystroke separately
    func addModifierToLast(_ keystroke: RawKeystroke) {
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].addModifier(keystroke)
    }

    /// Add a modifier keystroke to entry at specific index
    /// NOTE: This does NOT record to keystrokeSequence - caller must call recordKeystroke separately
    func addModifier(at index: Int, keystroke: RawKeystroke) {
        guard index >= 0 && index < entries.count else { return }
        entries[index].addModifier(keystroke)
    }

    /// Remove the last modifier from the last entry
    /// Also removes the last keystroke from keystrokeSequence (assuming it was the modifier)
    @discardableResult
    func removeLastModifierFromLast() -> RawKeystroke? {
        guard !entries.isEmpty else { return nil }
        let removed = entries[entries.count - 1].removeLastModifier()
        if removed != nil {
            _ = keystrokeSequence.popLast()
        }
        return removed
    }
    
    /// Remove the last modifier from entry at specific index
    /// Also removes from keystrokeSequence if the modifier was recently added
    /// Note: This may not perfectly track sequence if modifier was added long ago
    @discardableResult
    func removeLastModifier(at index: Int) -> RawKeystroke? {
        guard index >= 0 && index < entries.count else { return nil }
        let removed = entries[index].removeLastModifier()
        if removed != nil {
            // Remove from sequence - this assumes the modifier is still near the end
            // This is a best-effort approach; in complex undo scenarios, sequence may be imperfect
            _ = keystrokeSequence.popLast()
        }
        return removed
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
    /// NOTE: This includes overflow entries - use getRawInputStringFromEntries() for English detection
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

    /// Get raw input as string from ENTRIES ONLY (excludes overflow)
    /// Use this for English pattern detection to avoid false positives from restored overflow data
    ///
    /// Problem: After restore, overflow may contain old word data. When user types new characters,
    /// getRawInputString() returns overflow + entries, which can cause false English pattern detection.
    /// Example: overflow=['t'], entries=['l','o'] → getRawInputString()="tlo" → "tl" detected as English!
    ///
    /// Solution: For English detection, only check entries (what user is currently typing),
    /// not overflow (old data from previous words).
    func getRawInputStringFromEntries(using keyCodeToChar: (UInt16) -> Character?) -> String {
        var result = ""
        for entry in entries {
            for keystroke in entry.allKeystrokes {
                if let char = keyCodeToChar(keystroke.keyCode) {
                    let finalChar = keystroke.isCaps ? Character(String(char).uppercased()) : char
                    result.append(finalChar)
                }
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
            overflow: overflow,
            keystrokeSequence: keystrokeSequence
        )
    }

    /// Restore from a snapshot
    /// Note: keystrokeSequence is rebuilt from entries (per-entry order) instead of
    /// restoring from snapshot. This ensures consistency after restore + edit operations.
    /// The original typing order is lost, but per-entry order produces correct restore output.
    func restore(from snapshot: BufferSnapshot) {
        entries = snapshot.entries
        overflow = snapshot.overflow
        // Rebuild keystrokeSequence from entries to ensure consistency
        // This allows proper handling of delete operations after restore
        keystrokeSequence = getAllRawKeystrokes()
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
    /// Keystroke sequence preserving actual typing order (for restore)
    let keystrokeSequence: [RawKeystroke]

    /// Number of displayed characters
    var count: Int { entries.count }

    /// Total keystrokes
    var keystrokeCount: Int {
        entries.reduce(0) { $0 + $1.keystrokeCount } +
        overflow.reduce(0) { $0 + $1.keystrokeCount }
    }

    /// Check if this is a space
    var isSpace: Bool {
        entries.count == 1 && entries[0].keyCode == VietnameseData.KEY_SPACE
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
    static let empty = BufferSnapshot(entries: [], overflow: [], keystrokeSequence: [])
}


// MARK: - Typing History

/// Manages the history of typed words for restore functionality
final class TypingHistory {

    // MARK: - Configuration
    
    /// Maximum number of snapshots to keep in history
    /// This prevents unbounded memory growth for long typing sessions
    /// Default: 10 words (typical Vietnamese words)
    private let maxSnapshots: Int
    
    // MARK: - Storage
    
    private var snapshots: [BufferSnapshot] = []

    // MARK: - Initialization
    
    init(maxSnapshots: Int = 10) {
        self.maxSnapshots = maxSnapshots
    }
    
    // MARK: - Properties
    
    /// Number of saved words
    var count: Int { snapshots.count }

    /// Whether history is empty
    var isEmpty: Bool { snapshots.isEmpty }
    
    /// Current capacity limit
    var capacity: Int { maxSnapshots }

    // MARK: - Save Operations
    
    /// Save current buffer state
    func save(_ snapshot: BufferSnapshot) {
        guard !snapshot.entries.isEmpty else { return }
        snapshots.append(snapshot)
        
        // Auto-trim if exceeds limit
        trimIfNeeded()
    }

    /// Save a space word
    func saveSpaces(count: Int, keyCode: UInt16 = VietnameseData.KEY_SPACE) {
        var entries: [CharacterEntry] = []
        for _ in 0..<count {
            entries.append(CharacterEntry(keyCode: keyCode, isCaps: false))
        }
        snapshots.append(BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: []))
        
        // Auto-trim if exceeds limit
        trimIfNeeded()
    }
    
    // MARK: - Retrieve Operations

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
    
    // MARK: - Memory Management
    
    /// Trim history to stay within limit
    /// Called automatically on save, but can be called manually
    func trimIfNeeded() {
        if snapshots.count > maxSnapshots {
            let excess = snapshots.count - maxSnapshots
            snapshots.removeFirst(excess)
        }
    }
    
    /// Manually trim to a specific count
    func trimTo(count targetCount: Int) {
        guard targetCount >= 0 && targetCount < snapshots.count else { return }
        let excess = snapshots.count - targetCount
        snapshots.removeFirst(excess)
    }
    
    /// Get estimated memory usage in bytes
    /// Each snapshot: ~(entries.count * 48) bytes for CharacterEntry structs
    func estimatedMemoryUsage() -> Int {
        var totalBytes = 0
        for snapshot in snapshots {
            // CharacterEntry: ~48 bytes (RawKeystroke + array + UInt32 + overhead)
            let entryBytes = snapshot.entries.count * 48
            let overflowBytes = snapshot.overflow.count * 48
            totalBytes += entryBytes + overflowBytes + 16  // 16 bytes for BufferSnapshot overhead
        }
        return totalBytes
    }
}

