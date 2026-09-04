import Foundation

struct InputReplacement: Equatable {
    let backspaces: Int
    let characters: [VNCharacter]
    let codeTable: CodeTable

    var text: String {
        characters.map { $0.unicode(codeTable: codeTable) }.joined()
    }
}

enum InputAction: Equatable {
    case passThrough
    case consume
    case replacement(InputReplacement)
    case commit(text: String)
    case reset

    static func replace(backspaces: Int,
                        characters: [VNCharacter],
                        codeTable: CodeTable) -> InputAction {
        .replacement(InputReplacement(backspaces: backspaces,
                                      characters: characters,
                                      codeTable: codeTable))
    }

    static func replace(backspaces: Int, text: String) -> InputAction {
        replace(backspaces: backspaces,
                characters: text.map(VNCharacter.init(character:)),
                codeTable: .unicode)
    }

}
