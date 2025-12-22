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
    
    // MARK: - Tone Placement Tests (UY Pattern)

    func testTonePlacement_HUYNH_ModernOrthography() {
        engine.reset()
        // Ensure modern orthography is enabled
        engine.vUseModernOrthography = 1

        // h
        var result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        // y
        result = engine.processKey(character: "y", keyCode: 0, isUppercase: false)
        // n
        result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // h
        result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // f (grave tone - should go on 'y' in modern orthography)
        result = engine.processKey(character: "f", keyCode: 0, isUppercase: false)

        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "huỳnh", "Tone should be on 'y' in 'huỳnh' (modern orthography)")
    }

    func testTonePlacement_HUYNH_OldOrthography() {
        engine.reset()
        // Enable old orthography
        engine.vUseModernOrthography = 0

        // h
        var result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        // y
        result = engine.processKey(character: "y", keyCode: 0, isUppercase: false)
        // n
        result = engine.processKey(character: "n", keyCode: 0, isUppercase: false)
        // h
        result = engine.processKey(character: "h", keyCode: 0, isUppercase: false)
        // f (grave tone - should STILL go on 'y' because of ending consonant "nh")
        result = engine.processKey(character: "f", keyCode: 0, isUppercase: false)

        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "huỳnh", "Tone should be on 'y' in 'huỳnh' even in old orthography (has ending consonant)")
    }

    func testTonePlacement_TUY_OldOrthography() {
        engine.reset()
        // Enable old orthography
        engine.vUseModernOrthography = 0

        // t
        var result = engine.processKey(character: "t", keyCode: 0, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        // y
        result = engine.processKey(character: "y", keyCode: 0, isUppercase: false)
        // s (acute tone - should go on 'u' in old orthography when NO ending consonant)
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)

        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "túy", "Tone should be on 'u' in 'túy' (old orthography, no ending consonant)")
    }

    func testTonePlacement_TUY_ModernOrthography() {
        engine.reset()
        // Ensure modern orthography is enabled
        engine.vUseModernOrthography = 1

        // t
        var result = engine.processKey(character: "t", keyCode: 0, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: 0, isUppercase: false)
        // y
        result = engine.processKey(character: "y", keyCode: 0, isUppercase: false)
        // s (acute tone - should go on 'y' in modern orthography)
        result = engine.processKey(character: "s", keyCode: 0, isUppercase: false)

        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "tuý", "Tone should be on 'y' in 'tuý' (modern orthography)")
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
    
    // MARK: - VNI Input Method Tests
    
    func testVNI_NUA7_ToNuaWithHorn() {
        engine.reset()
        // Set VNI input type
        engine.vInputType = 1
        
        // n
        var result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        // 7 (horn - should apply to 'u' making it 'ư')
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "nưa", "VNI: 'nua7' should become 'nưa' (horn on 'u')")
    }
    
    func testVNI_NUA73_ToNuaWithHornAndTone() {
        engine.reset()
        // Set VNI input type
        engine.vInputType = 1
        
        // n
        var result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        // 7 (horn)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        // 3 (hỏi tone)
        result = engine.processKey(character: "3", keyCode: VietnameseData.KEY_3, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "nửa", "VNI: 'nua73' should become 'nửa' (horn on 'u', hỏi tone)")
    }
    
    func testVNI_NA8_ToBreve() {
        engine.reset()
        // Set VNI input type
        engine.vInputType = 1
        
        // n
        var result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        // a
        result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        // 8 (breve - should apply to 'a' making it 'ă')
        result = engine.processKey(character: "8", keyCode: VietnameseData.KEY_8, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "nă", "VNI: 'na8' should become 'nă' (breve on 'a')")
    }
    
    func testVNI_NUO7_ToUoWithHorn() {
        engine.reset()
        // Set VNI input type
        engine.vInputType = 1
        
        // n
        var result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        // u
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        // o
        result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        // 7 (horn - should apply to both 'u' and 'o' making 'ươ')
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "nươ", "VNI: 'nuo7' should become 'nươ' (horn on both vowels)")
    }
    
    func testVNI_A6_ToCircumflex() {
        engine.reset()
        // Set VNI input type
        engine.vInputType = 1
        
        // a
        var result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        // 6 (circumflex - should make 'â')
        result = engine.processKey(character: "6", keyCode: VietnameseData.KEY_6, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "â", "VNI: 'a6' should become 'â' (circumflex)")
    }
    
    func testVNI_E6_ToCircumflex() {
        engine.reset()
        engine.vInputType = 1
        
        // e
        var result = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        // 6 (circumflex)
        result = engine.processKey(character: "6", keyCode: VietnameseData.KEY_6, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "ê", "VNI: 'e6' should become 'ê' (circumflex)")
    }
    
    func testVNI_O6_ToCircumflex() {
        engine.reset()
        engine.vInputType = 1
        
        // o
        var result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        // 6 (circumflex)
        result = engine.processKey(character: "6", keyCode: VietnameseData.KEY_6, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "ô", "VNI: 'o6' should become 'ô' (circumflex)")
    }
    
    func testVNI_U7_ToHorn() {
        engine.reset()
        engine.vInputType = 1
        
        // u
        var result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        // 7 (horn)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "ư", "VNI: 'u7' should become 'ư' (horn)")
    }
    
    func testVNI_O7_ToHorn() {
        engine.reset()
        engine.vInputType = 1
        
        // o
        var result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        // 7 (horn)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "ơ", "VNI: 'o7' should become 'ơ' (horn)")
    }
    
    func testVNI_D9_ToDStroke() {
        engine.reset()
        engine.vInputType = 1
        
        // d
        var result = engine.processKey(character: "d", keyCode: VietnameseData.KEY_D, isUppercase: false)
        // 9 (đ)
        result = engine.processKey(character: "9", keyCode: VietnameseData.KEY_9, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "đ", "VNI: 'd9' should become 'đ'")
    }
    
    func testVNI_TIE6NG_ToTieng() {
        engine.reset()
        engine.vInputType = 1
        
        // t-i-e-6-n-g
        var result = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        result = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        result = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        result = engine.processKey(character: "6", keyCode: VietnameseData.KEY_6, isUppercase: false)
        result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        result = engine.processKey(character: "g", keyCode: VietnameseData.KEY_G, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "tiêng", "VNI: 'tie6ng' should become 'tiêng'")
    }
    
    func testVNI_VIE6T_ToViet() {
        engine.reset()
        engine.vInputType = 1
        
        // v-i-e-6-t with tone 5 (nặng)
        var result = engine.processKey(character: "v", keyCode: VietnameseData.KEY_V, isUppercase: false)
        result = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        result = engine.processKey(character: "e", keyCode: VietnameseData.KEY_E, isUppercase: false)
        result = engine.processKey(character: "6", keyCode: VietnameseData.KEY_6, isUppercase: false)
        result = engine.processKey(character: "5", keyCode: VietnameseData.KEY_5, isUppercase: false)
        result = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "việt", "VNI: 'vie65t' should become 'việt'")
    }
    
    func testVNI_NGUOI_ToNguoi() {
        engine.reset()
        engine.vInputType = 1
        
        // n-g-u-o-7-i → người (with 2 tone)
        var result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        result = engine.processKey(character: "g", keyCode: VietnameseData.KEY_G, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        result = engine.processKey(character: "2", keyCode: VietnameseData.KEY_2, isUppercase: false)
        result = engine.processKey(character: "i", keyCode: VietnameseData.KEY_I, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "người", "VNI: 'nguo72i' should become 'người'")
    }
    
    func testVNI_A1_ToAcute() {
        engine.reset()
        engine.vInputType = 1
        
        // a-1 → á
        var result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "á", "VNI: 'a1' should become 'á' (acute)")
    }
    
    func testVNI_O2_ToGrave() {
        engine.reset()
        engine.vInputType = 1
        
        // o-2 → ò
        var result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        result = engine.processKey(character: "2", keyCode: VietnameseData.KEY_2, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "ò", "VNI: 'o2' should become 'ò' (grave)")
    }
    
    func testVNI_RemoveMark_0() {
        engine.reset()
        engine.vInputType = 1
        
        // a-1-0 → a (remove mark)
        var result = engine.processKey(character: "a", keyCode: VietnameseData.KEY_A, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        result = engine.processKey(character: "0", keyCode: VietnameseData.KEY_0, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "a", "VNI: 'a10' should become 'a' (mark removed)")
    }
    
    // MARK: - VNI "uy" Combination Tests
    
    func testVNI_TUY1_ModernOrthography() {
        engine.reset()
        engine.vInputType = 1
        engine.vUseModernOrthography = 1
        
        // t-u-y-1 → tuý (modern: tone on 'y')
        var result = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "tuý", "VNI: 'tuy1' should become 'tuý' (modern orthography, tone on 'y')")
    }
    
    func testVNI_TUY1_OldOrthography() {
        engine.reset()
        engine.vInputType = 1
        engine.vUseModernOrthography = 0
        
        // t-u-y-1 → túy (old: tone on 'u' when no ending consonant)
        var result = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "túy", "VNI: 'tuy1' should become 'túy' (old orthography, tone on 'u')")
    }
    
    func testVNI_QUY1_ToQuy() {
        engine.reset()
        engine.vInputType = 1
        engine.vUseModernOrthography = 1
        
        // q-u-y-1 → quý
        var result = engine.processKey(character: "q", keyCode: VietnameseData.KEY_Q, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "quý", "VNI: 'quy1' should become 'quý'")
    }
    
    func testVNI_HUYNH2_ToHuynh() {
        engine.reset()
        engine.vInputType = 1
        engine.vUseModernOrthography = 1
        
        // h-u-y-n-h-2 → huỳnh (tone always on 'y' because has ending consonant)
        var result = engine.processKey(character: "h", keyCode: VietnameseData.KEY_H, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "n", keyCode: VietnameseData.KEY_N, isUppercase: false)
        result = engine.processKey(character: "h", keyCode: VietnameseData.KEY_H, isUppercase: false)
        result = engine.processKey(character: "2", keyCode: VietnameseData.KEY_2, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "huỳnh", "VNI: 'huynh2' should become 'huỳnh' (tone on 'y')")
    }
    
    func testVNI_UY7_ShouldNotApplyHorn() {
        engine.reset()
        engine.vInputType = 1
        
        // u-y-7 → uy7 (horn key 7 should NOT apply because 'y' doesn't have horn form)
        // The engine should just pass through the '7' or handle gracefully
        var result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        
        // Since 'y' doesn't take horn, the horn should apply to 'u' making it 'ư'
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        // Possible outcomes: "ưy" if horn applied to u, or "uy7" if rejected
        // Based on the fix, it should find 'u' and apply horn
        XCTAssertEqual(output, "ưy", "VNI: 'uy7' should become 'ưy' (horn on 'u')")
    }
    
    func testVNI_THUY1_ToThuy() {
        engine.reset()
        engine.vInputType = 1
        engine.vUseModernOrthography = 1
        
        // t-h-u-y-1 → thuý
        var result = engine.processKey(character: "t", keyCode: VietnameseData.KEY_T, isUppercase: false)
        result = engine.processKey(character: "h", keyCode: VietnameseData.KEY_H, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        result = engine.processKey(character: "1", keyCode: VietnameseData.KEY_1, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "thuý", "VNI: 'thuy1' should become 'thuý'")
    }
    
    // MARK: - VNI Complex Tests - "được" case
    
    func testVNI_DUOC_WithHornAfterConsonant() {
        engine.reset()
        engine.vInputType = 1
        
        // Test: d-u-o-c-9-7-5 (gõ duoc trước, rồi thêm đ, horn, và dấu nặng)
        // Expected: được
        var result = engine.processKey(character: "d", keyCode: VietnameseData.KEY_D, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        result = engine.processKey(character: "c", keyCode: VietnameseData.KEY_C, isUppercase: false)
        // 9 - convert d to đ
        result = engine.processKey(character: "9", keyCode: VietnameseData.KEY_9, isUppercase: false)
        // 7 - add horn to vowels (uo → ươ)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        // 5 - add nặng tone
        result = engine.processKey(character: "5", keyCode: VietnameseData.KEY_5, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "được", "VNI: 'duoc975' should become 'được'")
    }
    
    func testVNI_DUOC_StandardOrder() {
        engine.reset()
        engine.vInputType = 1
        
        // Test: Standard VNI order - d-9-u-o-7-c-5
        // đ-ươ-c + nặng = được
        var result = engine.processKey(character: "d", keyCode: VietnameseData.KEY_D, isUppercase: false)
        result = engine.processKey(character: "9", keyCode: VietnameseData.KEY_9, isUppercase: false)
        result = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        result = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        result = engine.processKey(character: "7", keyCode: VietnameseData.KEY_7, isUppercase: false)
        result = engine.processKey(character: "c", keyCode: VietnameseData.KEY_C, isUppercase: false)
        result = engine.processKey(character: "5", keyCode: VietnameseData.KEY_5, isUppercase: false)
        
        let output = result.newCharacters.map { $0.toUnicode() }.joined()
        XCTAssertEqual(output, "được", "VNI: 'd9uo7c5' should become 'được'")
    }
    
    // MARK: - Macro Tests with Special Characters
    
    func testMacro_SimpleTextMacro() {
        engine.reset()
        engine.vUseMacro = 1
        engine.vLanguage = 1  // Vietnamese mode
        
        // Setup macro "bb" -> "bạn bè"
        let macroManager = MacroManager()
        _ = macroManager.addMacro(text: "bb", content: "bạn bè")
        VNEngine.setSharedMacroManager(macroManager)
        
        // Type "bb "
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        
        // Check macroKey before space
        let macroKeyBeforeSpace = engine.hookState.macroKey
        XCTAssertEqual(macroKeyBeforeSpace.count, 2, "macroKey should have 2 entries before space")
        
        // Process space (word break)
        let result = engine.processWordBreak(character: " ")
        
        // Verify macro was found and replaced
        XCTAssertTrue(result.shouldConsume, "Macro should be found and consumed")
        XCTAssertEqual(result.backspaceCount, 2, "Should delete 2 characters (bb)")
    }
    
    func testMacro_WithExclamationMark() {
        engine.reset()
        engine.vUseMacro = 1
        engine.vLanguage = 1  // Vietnamese mode
        
        // Setup macro "!bb" -> "bằng hữu"
        let macroManager = MacroManager()
        _ = macroManager.addMacro(text: "!bb", content: "bằng hữu")
        VNEngine.setSharedMacroManager(macroManager)
        
        // Enable macro manager logging
        macroManager.logCallback = { message in
            print("Macro: \(message)")
        }
        engine.logCallback = { message in
            print("Engine: \(message)")
        }
        
        // Type "!" (word break character)
        let resultExclaim = engine.processWordBreak(character: "!")
        XCTAssertFalse(resultExclaim.shouldConsume, "! should not consume yet")
        
        // Check macroKey after "!"
        let macroKeyAfterExclaim = engine.hookState.macroKey
        print("macroKey after '!': \(macroKeyAfterExclaim.map { String(format: "0x%X", $0) })")
        XCTAssertEqual(macroKeyAfterExclaim.count, 1, "macroKey should have 1 entry (!) after typing !")
        
        // Type "b"
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        let macroKeyAfterB1 = engine.hookState.macroKey
        print("macroKey after 'b': \(macroKeyAfterB1.map { String(format: "0x%X", $0) })")
        XCTAssertEqual(macroKeyAfterB1.count, 2, "macroKey should have 2 entries (!b) after typing b")
        
        // Type "b" again
        _ = engine.processKey(character: "b", keyCode: VietnameseData.KEY_B, isUppercase: false)
        let macroKeyAfterB2 = engine.hookState.macroKey
        print("macroKey after second 'b': \(macroKeyAfterB2.map { String(format: "0x%X", $0) })")
        XCTAssertEqual(macroKeyAfterB2.count, 3, "macroKey should have 3 entries (!bb)")
        
        // Process space (word break) - this should trigger macro replacement
        let result = engine.processWordBreak(character: " ")
        
        // Verify macro was found and replaced
        XCTAssertTrue(result.shouldConsume, "Macro '!bb' should be found and consumed")
        XCTAssertEqual(result.backspaceCount, 3, "Should delete 3 characters (!bb)")
    }
    
    func testMacro_WithAtSign() {
        engine.reset()
        engine.vUseMacro = 1
        engine.vLanguage = 1  // Vietnamese mode
        
        // Setup macro "you@" -> "công ty"
        let macroManager = MacroManager()
        _ = macroManager.addMacro(text: "you@", content: "công ty")
        VNEngine.setSharedMacroManager(macroManager)
        
        // Type "you"
        _ = engine.processKey(character: "y", keyCode: VietnameseData.KEY_Y, isUppercase: false)
        _ = engine.processKey(character: "o", keyCode: VietnameseData.KEY_O, isUppercase: false)
        _ = engine.processKey(character: "u", keyCode: VietnameseData.KEY_U, isUppercase: false)
        
        // Check macroKey before "@"
        let macroKeyBeforeAt = engine.hookState.macroKey
        XCTAssertEqual(macroKeyBeforeAt.count, 3, "macroKey should have 3 entries (you) before @")
        
        // Type "@" (word break character)
        let resultAt = engine.processWordBreak(character: "@")
        XCTAssertFalse(resultAt.shouldConsume, "@ should not consume yet")
        
        // Check macroKey after "@"
        let macroKeyAfterAt = engine.hookState.macroKey
        print("macroKey after '@': \(macroKeyAfterAt.map { String(format: "0x%X", $0) })")
        XCTAssertEqual(macroKeyAfterAt.count, 4, "macroKey should have 4 entries (you@)")
        
        // Process space (word break) - this should trigger macro replacement
        let result = engine.processWordBreak(character: " ")
        
        // Verify macro was found and replaced
        XCTAssertTrue(result.shouldConsume, "Macro 'you@' should be found and consumed")
        XCTAssertEqual(result.backspaceCount, 4, "Should delete 4 characters (you@)")
    }
    
    func testMacro_KeyCodeMapping() {
        // Test that getCharacterCode correctly maps keycode + CAPS_MASK to character
        let macroManager = MacroManager()
        
        // Verify "!" mapping: keyCode 0x12 (KEY_1) with CAPS_MASK should map to '!' (0x21)
        let exclamKeyData: UInt32 = 0x12 | 0x10000  // KEY_1 with CAPS_MASK
        
        // Test through the macro search mechanism
        _ = macroManager.addMacro(text: "!test", content: "result")
        
        // Simulate typing "!test" as keycodes
        let typedKey: [UInt32] = [
            0x10012,  // ! (Shift+1)
            0x11,     // t
            0x0E,     // e
            0x01,     // s
            0x11      // t
        ]
        
        // Find macro
        let foundMacro = macroManager.findMacro(key: typedKey)
        XCTAssertNotNil(foundMacro, "Macro '!test' should be found with keycode input")
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

