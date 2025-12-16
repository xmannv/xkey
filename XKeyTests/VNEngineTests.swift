//
//  VNEngineTests.swift
//  XKeyTests
//
//  Unit tests for Vietnamese typing engine
//

import XCTest
@testable import XKey

class VNEngineTests: XCTestCase {
    
    var engine: VNEngine!
    
    override func setUp() {
        super.setUp()
        engine = VNEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Basic Vowel Tests
    
    func testBasicVowel_A() {
        let result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        XCTAssertTrue(result.shouldConsume, "Should consume 'a'")
        XCTAssertEqual(result.newCharacters.count, 1, "Should output 1 character")
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "a", "Should output 'a'")
    }
    
    func testBasicVowel_E() {
        let result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        XCTAssertTrue(result.shouldConsume)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "e")
    }
    
    // MARK: - Telex Transformation Tests
    
    func testTelex_AA_ToCircumflex() {
        // Type 'a'
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "a")
        
        // Type 'a' again -> should become 'â'
        result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.backspaceCount, 1, "Should delete previous 'a'")
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "â", "Should output 'â'")
    }
    
    func testTelex_AW_ToBreve() {
        // Type 'a'
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "a")
        
        // Type 'w' -> should become 'ă'
        result = engine.processKey(character: "w", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.backspaceCount, 1, "Should delete previous 'a'")
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ă", "Should output 'ă'")
    }
    
    func testTelex_EE_ToCircumflex() {
        // Type 'e'
        var result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        
        // Type 'e' again -> should become 'ê'
        result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ê")
    }
    
    func testTelex_OO_ToCircumflex() {
        // Type 'o'
        var result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        
        // Type 'o' again -> should become 'ô'
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ô")
    }
    
    func testTelex_OW_ToHorn() {
        // Type 'o'
        var result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        
        // Type 'w' -> should become 'ơ'
        result = engine.processKey(character: "w", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ơ")
    }
    
    func testTelex_UW_ToHorn() {
        // Type 'u'
        var result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        
        // Type 'w' -> should become 'ư'
        result = engine.processKey(character: "w", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ư")
    }
    
    func testTelex_DD_ToDStroke() {
        // Type 'd'
        var result = engine.processKey(character: "d", keyCode: 0, isUppercase: false)
        
        // Type 'd' again -> should become 'đ'
        result = engine.processKey(character: "d", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "đ")
    }
    
    // MARK: - Tone Tests
    
    func testTone_AS_ToAcute() {
        // Type 'a'
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        
        // Type 's' (acute tone) -> should become 'á'
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "á", "Should output 'á'")
    }
    
    func testTone_AF_ToGrave() {
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        result = engine.processKey(character: "f", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "à")
    }
    
    func testTone_AR_ToHookAbove() {
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        result = engine.processKey(character: "r", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ả")
    }
    
    func testTone_AX_ToTilde() {
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        result = engine.processKey(character: "x", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ã")
    }
    
    func testTone_AJ_ToDotBelow() {
        var result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        result = engine.processKey(character: "j", keyCode: 0, isUppercase: false)
        XCTAssertEqual(result.newCharacters.first?.toUnicode(), "ạ")
    }
    
    // MARK: - Complete Word Tests
    
    func testWord_Viet() {
        engine.reset()
        
        // v
        var result = engine.processKey(character: "v", keyCode: 0, isUppercase: false)
        // i
        result = engine.processKey(character: "i", keyCode: 0, isUppercase: false)
        // e
        result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        // e (transform to ê)
        result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        // t
        result = engine.processKey(character: "t", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "việt", "Should output 'việt'")
    }
    
    func testWord_Nam() {
        engine.reset()
        
        // n
        var result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        // m
        result = engine.processKey(character: "m", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "nam", "Should output 'nam'")
    }
    
    func testWord_Toi() {
        engine.reset()
        
        // t
        var result = engine.processKey(character: "t", keyCode: 0, isUppercase: false)
        // o
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        // o (transform to ô)
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        // i
        result = engine.processKey(character: "i", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "tôi", "Should output 'tôi'")
    }
    
    // MARK: - Tone Placement Tests (2 Vowels)
    
    func testTonePlacement_HOA_NoEndingConsonant() {
        engine.reset()
        
        // h
        var result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // o
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        // s (tone should go on 'a' - second vowel, following OpenKey modern orthography)
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "hoá", "Tone should be on second vowel (OpenKey modern orthography)")
    }
    
    func testTonePlacement_HOAN_WithEndingConsonant() {
        engine.reset()
        
        // h
        var result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // o
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        // n (ending consonant)
        result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // s (tone should STILL go on 'a' - OpenKey modern orthography always puts tone on 'a' in "oa")
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "hoán", "Tone should be on 'a' even with ending consonant (OpenKey modern orthography)")
    }
    
    func testTonePlacement_KHOANG_MarkBeforeEndConsonant() {
        engine.reset()
        
        // k
        var result = engine.processKey(character: "k", keyCode: 0, isUppercase: false)
        // h
        result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // o
        result = engine.processKey(character: "o", keyCode: 0, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: 0, isUppercase: false)
        // r (hook above tone - should go on 'a')
        result = engine.processKey(character: "r", keyCode: 0, isUppercase: false)
        // n
        result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // g
        result = engine.processKey(character: "g", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "khoảng", "Tone should be on 'a' in 'khoảng' (OpenKey modern orthography)")
    }
    
    // MARK: - Tone Placement Tests (3 Vowels)
    
    func testTonePlacement_UYEN_ThreeVowels() {
        engine.reset()
        
        // u
        var result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        // y
        result = engine.processKey(character: "y", keyCode: 0, isUppercase: false)
        // e
        result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        // e (transform to ê)
        result = engine.processKey(character: "e", keyCode: 0, isUppercase: false)
        // n
        result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // s (tone should go on middle vowel 'ê')
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "uyến", "Tone should be on middle vowel for 3-vowel sequence")
    }
}

// MARK: - Helper Extension

extension VNCharacter {
    func toUnicode() -> String {
        // This is a simplified version - actual implementation would use VNCharacterMap
        // For testing purposes, we'll return the raw value
        
        if let vowel = self.vowel {
            let base = vowel.rawValue
            if let tone = self.tone, tone != .none {
                return applyTone(to: base, tone: tone)
            }
            return base
        }
        
        if let consonant = self.consonant {
            return consonant.rawValue
        }
        
        return ""
    }
    
    private func applyTone(to base: String, tone: VNTone) -> String {
        // Simplified tone application for testing
        let toneMap: [String: [VNTone: String]] = [
            "a": [
                .acute: "á", .grave: "à", .hookAbove: "ả",
                .tilde: "ã", .dotBelow: "ạ"
            ],
            "e": [
                .acute: "é", .grave: "è", .hookAbove: "ẻ",
                .tilde: "ẽ", .dotBelow: "ẹ"
            ],
            "ê": [
                .acute: "ế", .grave: "ề", .hookAbove: "ể",
                .tilde: "ễ", .dotBelow: "ệ"
            ],
            // Add more as needed
        ]
        
        return toneMap[base]?[tone] ?? base
    }
}

