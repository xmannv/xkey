import XCTest
@testable import XKey

/// Tests for KeyCodeToCharacter mapping to ensure QWERTZ/AZERTY support
class KeyCodeToCharacterTests: XCTestCase {
    
    // MARK: - Basic Letter Mapping Tests
    
    func testBasicLetterMapping() {
        // Test lowercase letters (without Shift)
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x00, withShift: false), "a")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x06, withShift: false), "z")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x10, withShift: false), "y")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x01, withShift: false), "s")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x0E, withShift: false), "e")
        
        // Test uppercase letters (with Shift)
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x00, withShift: true), "A")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x06, withShift: true), "Z")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x10, withShift: true), "Y")
    }
    
    // MARK: - QWERTZ Critical Test Cases
    
    func testQWERTZLayout() {
        // On QWERTZ keyboard:
        // - Physical position 0x06 (Z on QWERTY) displays 'Y'
        // - Physical position 0x10 (Y on QWERTY) displays 'Z'
        
        // But KeyCodeToCharacter should ALWAYS return QWERTY characters:
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x06, withShift: false), "z",
                       "Physical key at Z position (0x06) should map to 'z' on QWERTY, not 'y'")
        
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x10, withShift: false), "y",
                       "Physical key at Y position (0x10) should map to 'y' on QWERTY, not 'z'")
    }
    
    func testTypingVietnameseWithQWERTZ() {
        // Test case: Typing "lý" (Telex: l-y-s) on QWERTZ
        // User presses: l, y (physical Y position), s
        
        let lKey = KeyCodeToCharacter.qwertyCharacter(keyCode: 0x25, withShift: false) // L
        let yKey = KeyCodeToCharacter.qwertyCharacter(keyCode: 0x10, withShift: false) // Y
        let sKey = KeyCodeToCharacter.qwertyCharacter(keyCode: 0x01, withShift: false) // S
        
        XCTAssertEqual(lKey, "l")
        XCTAssertEqual(yKey, "y", "Should get 'y' from keyCode 0x10 (Y position)")
        XCTAssertEqual(sKey, "s")
    }
    
    // MARK: - Special Characters
    
    func testSpecialCharactersWithoutShift() {
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x31, withShift: false), " ")  // Space
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2B, withShift: false), ",")  // Comma
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2F, withShift: false), ".")  // Period
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2C, withShift: false), "/")  // Slash
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x21, withShift: false), "[")  // [
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x1E, withShift: false), "]")  // ]
    }
    
    func testSpecialCharactersWithShift() {
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2B, withShift: true), "<")  // Shift+,
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2F, withShift: true), ">")  // Shift+.
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x2C, withShift: true), "?")  // Shift+/
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x21, withShift: true), "{")  // Shift+[
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x1E, withShift: true), "}")  // Shift+]
    }
    
    func testNumbersWithoutShift() {
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x12, withShift: false), "1")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x13, withShift: false), "2")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x14, withShift: false), "3")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x15, withShift: false), "4")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x17, withShift: false), "5")  // 0x17 = kVK_ANSI_5
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x16, withShift: false), "6")  // 0x16 = kVK_ANSI_6
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x1A, withShift: false), "7")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x1C, withShift: false), "8")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x19, withShift: false), "9")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x1D, withShift: false), "0")
    }
    
    func testNumbersWithShift() {
        // Shifted numbers produce special characters
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x12, withShift: true), "!")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x13, withShift: true), "@")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x14, withShift: true), "#")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x15, withShift: true), "$")
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x17, withShift: true), "%")  // 0x17 = kVK_ANSI_5
        XCTAssertEqual(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x16, withShift: true), "^")  // 0x16 = kVK_ANSI_6
    }
    
    // MARK: - QWERTY Letter Helper
    
    func testQWERTYLetterHelper() {
        XCTAssertEqual(KeyCodeToCharacter.qwertyLetter(keyCode: 0x00), "a")
        XCTAssertEqual(KeyCodeToCharacter.qwertyLetter(keyCode: 0x06), "z")
        XCTAssertEqual(KeyCodeToCharacter.qwertyLetter(keyCode: 0x10), "y")
        
        // Non-letters should return nil
        XCTAssertNil(KeyCodeToCharacter.qwertyLetter(keyCode: 0x31)) // Space
        XCTAssertNil(KeyCodeToCharacter.qwertyLetter(keyCode: 0x2B)) // Comma
    }
    
    // MARK: - Unknown Keys
    
    func testUnknownKeyCode() {
        // Test an unmapped key code
        XCTAssertNil(KeyCodeToCharacter.qwertyCharacter(keyCode: 0xFF, withShift: false))
        XCTAssertNil(KeyCodeToCharacter.qwertyCharacter(keyCode: 0x100, withShift: true))
    }
    
    // MARK: - Complete Alphabet Test
    
    func testCompleteAlphabet() {
        let expectedLowercase: [(UInt16, Character)] = [
            (0x00, "a"), (0x0B, "b"), (0x08, "c"), (0x02, "d"), (0x0E, "e"),
            (0x03, "f"), (0x05, "g"), (0x04, "h"), (0x22, "i"), (0x26, "j"),
            (0x28, "k"), (0x25, "l"), (0x2E, "m"), (0x2D, "n"), (0x1F, "o"),
            (0x23, "p"), (0x0C, "q"), (0x0F, "r"), (0x01, "s"), (0x11, "t"),
            (0x20, "u"), (0x09, "v"), (0x0D, "w"), (0x07, "x"), (0x10, "y"),
            (0x06, "z")
        ]
        
        for (keyCode, expectedChar) in expectedLowercase {
            XCTAssertEqual(
                KeyCodeToCharacter.qwertyCharacter(keyCode: keyCode, withShift: false),
                expectedChar,
                "Key code 0x\(String(format: "%02X", keyCode)) should map to '\(expectedChar)'"
            )
        }
    }
}
