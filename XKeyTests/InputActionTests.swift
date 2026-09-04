import XCTest
@testable import XKey

final class InputActionTests: XCTestCase {
    func testReplacementEqualityIncludesCodeTableWhenRenderedTextMatches() {
        let characters = [VNCharacter(character: "a")]
        let unicode = InputAction.replace(backspaces: 1,
                                          characters: characters,
                                          codeTable: .unicode)
        let vniWindows = InputAction.replace(backspaces: 1,
                                             characters: characters,
                                             codeTable: .vniWindows)

        XCTAssertNotEqual(unicode, vniWindows)
    }

    func testReplacementEqualityIncludesRawCharactersWhenRenderedTextMatches() {
        let plain = InputAction.replace(backspaces: 1,
                                        characters: [VNCharacter(character: "a")],
                                        codeTable: .unicode)
        let vowel = InputAction.replace(backspaces: 1,
                                        characters: [VNCharacter(vowel: .a)],
                                        codeTable: .unicode)

        XCTAssertNotEqual(plain, vowel)
    }
}
