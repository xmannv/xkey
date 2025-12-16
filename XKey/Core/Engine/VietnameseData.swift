//
//  VietnameseData.swift
//  XKey
//
//  Vietnamese language data tables - Ported from OpenKey Vietnamese.cpp
//

import Foundation

/// Contains all Vietnamese language data tables (vowels, consonants, code tables)
class VietnameseData {
    
    // MARK: - Key Codes (from platforms/mac.h)
    
    static let KEY_A: UInt16 = 0x00
    static let KEY_S: UInt16 = 0x01
    static let KEY_D: UInt16 = 0x02
    static let KEY_F: UInt16 = 0x03
    static let KEY_H: UInt16 = 0x04
    static let KEY_G: UInt16 = 0x05
    static let KEY_Z: UInt16 = 0x06
    static let KEY_X: UInt16 = 0x07
    static let KEY_C: UInt16 = 0x08
    static let KEY_V: UInt16 = 0x09
    static let KEY_B: UInt16 = 0x0B
    static let KEY_Q: UInt16 = 0x0C
    static let KEY_W: UInt16 = 0x0D
    static let KEY_E: UInt16 = 0x0E
    static let KEY_R: UInt16 = 0x0F
    static let KEY_Y: UInt16 = 0x10
    static let KEY_T: UInt16 = 0x11
    static let KEY_1: UInt16 = 0x12
    static let KEY_2: UInt16 = 0x13
    static let KEY_3: UInt16 = 0x14
    static let KEY_4: UInt16 = 0x15
    static let KEY_6: UInt16 = 0x16
    static let KEY_5: UInt16 = 0x17
    static let KEY_EQUALS: UInt16 = 0x18
    static let KEY_9: UInt16 = 0x19
    static let KEY_7: UInt16 = 0x1A
    static let KEY_MINUS: UInt16 = 0x1B
    static let KEY_8: UInt16 = 0x1C
    static let KEY_0: UInt16 = 0x1D
    static let KEY_RIGHT_BRACKET: UInt16 = 0x1E
    static let KEY_O: UInt16 = 0x1F
    static let KEY_U: UInt16 = 0x20
    static let KEY_LEFT_BRACKET: UInt16 = 0x21
    static let KEY_I: UInt16 = 0x22
    static let KEY_P: UInt16 = 0x23
    static let KEY_L: UInt16 = 0x25
    static let KEY_J: UInt16 = 0x26
    static let KEY_QUOTE: UInt16 = 0x27
    static let KEY_K: UInt16 = 0x28
    static let KEY_SEMICOLON: UInt16 = 0x29
    static let KEY_BACK_SLASH: UInt16 = 0x2A
    static let KEY_COMMA: UInt16 = 0x2B
    static let KEY_SLASH: UInt16 = 0x2C
    static let KEY_N: UInt16 = 0x2D
    static let KEY_M: UInt16 = 0x2E
    static let KEY_DOT: UInt16 = 0x2F
    static let KEY_BACKQUOTE: UInt16 = 0x32
    static let KEY_DELETE: UInt16 = 0x33
    static let KEY_ENTER: UInt16 = 0x4C
    static let KEY_SPACE: UInt16 = 0x31
    static let KEY_TAB: UInt16 = 0x30
    static let KEY_RETURN: UInt16 = 0x24
    static let KEY_ESC: UInt16 = 0x35
    static let KEY_LEFT: UInt16 = 0x7B
    static let KEY_RIGHT: UInt16 = 0x7C
    static let KEY_DOWN: UInt16 = 0x7D
    static let KEY_UP: UInt16 = 0x7E
    
    // MARK: - Processing Characters (from Engine.cpp)
    
    let processingChar: [[UInt16]] = [
        // Telex
        [KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z],
        // VNI
        [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0],
        // Simple Telex 1
        [KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z],
        // Simple Telex 2
        [KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z]
    ]
    
    // MARK: - Break Codes
    
    let breakCode: [UInt16] = [
        KEY_ESC, KEY_TAB, KEY_ENTER, KEY_RETURN, KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP,
        KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_BACK_SLASH,
        KEY_MINUS, KEY_EQUALS, KEY_BACKQUOTE, KEY_TAB
    ]
    
    let macroBreakCode: [UInt16] = [
        KEY_RETURN, KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE,
        KEY_BACK_SLASH, KEY_MINUS, KEY_EQUALS
    ]
    
    let charKeyCode: [UInt16] = [
        KEY_BACKQUOTE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
        KEY_MINUS, KEY_EQUALS, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACK_SLASH,
        KEY_SEMICOLON, KEY_QUOTE, KEY_COMMA, KEY_DOT, KEY_SLASH
    ]
    
    // MARK: - Vowel Tables (from Vietnamese.cpp)
    
    // Standalone W bad characters
    let standaloneWbad: [UInt16] = [KEY_W, KEY_E, KEY_Y, KEY_F, KEY_J, KEY_K, KEY_Z]
    
    // Double W allowed (consonant combinations)
    let doubleWAllowed: [[UInt16]] = [
        [KEY_T, KEY_R], [KEY_T, KEY_H], [KEY_C, KEY_H], [KEY_N, KEY_H],
        [KEY_N, KEY_G], [KEY_K, KEY_H], [KEY_G, KEY_I], [KEY_P, KEY_H], [KEY_G, KEY_H]
    ]
    
    // Quick Telex mappings
    let quickTelex: [UInt16: [UInt16]] = [
        KEY_C: [KEY_C, KEY_H],
        KEY_G: [KEY_G, KEY_I],
        KEY_K: [KEY_K, KEY_H],
        KEY_N: [KEY_N, KEY_G],
        KEY_Q: [KEY_Q, KEY_U],
        KEY_P: [KEY_P, KEY_H],
        KEY_T: [KEY_T, KEY_H],
        KEY_U: [KEY_U, KEY_U]
    ]
    
    // Quick Start Consonant
    let quickStartConsonant: [UInt16: [UInt16]] = [
        KEY_F: [KEY_P, KEY_H],
        KEY_J: [KEY_G, KEY_I],
        KEY_W: [KEY_Q, KEY_U]
    ]
    
    // Quick End Consonant
    let quickEndConsonant: [UInt16: [UInt16]] = [
        KEY_G: [KEY_N, KEY_G],
        KEY_H: [KEY_N, KEY_H],
        KEY_K: [KEY_C, KEY_H]
    ]
    
    // MARK: - Consonant Tables
    
    // CONSONANT_ALLOW_MASK = 0x8000 - marks consonants that are only allowed when vAllowConsonantZFWJ is enabled
    // END_CONSONANT_MASK = 0x4000 - marks consonants for quick consonant feature
    static let CONSONANT_ALLOW_MASK: UInt16 = 0x8000
    static let END_CONSONANT_MASK: UInt16 = 0x4000
    
    let consonantTable: [[UInt16]] = [
        [KEY_N, KEY_G, KEY_H],
        [KEY_P, KEY_H],
        [KEY_T, KEY_H],
        [KEY_T, KEY_R],
        [KEY_G, KEY_I],
        [KEY_C, KEY_H],
        [KEY_N, KEY_H],
        [KEY_N, KEY_G],
        [KEY_K, KEY_H],
        [KEY_G, KEY_H],
        [KEY_G],
        [KEY_C],
        [KEY_Q],
        [KEY_K],
        [KEY_T],
        [KEY_R],
        [KEY_H],
        [KEY_B],
        [KEY_M],
        [KEY_V],
        [KEY_N],
        [KEY_L],
        [KEY_X],
        [KEY_P],
        [KEY_S],
        [KEY_D],
        // Consonants allowed only when vAllowConsonantZFWJ is enabled
        [KEY_F | CONSONANT_ALLOW_MASK],
        [KEY_W | CONSONANT_ALLOW_MASK],
        [KEY_Z | CONSONANT_ALLOW_MASK],
        [KEY_J | CONSONANT_ALLOW_MASK],
        // Quick consonant entries
        [KEY_F | END_CONSONANT_MASK],
        [KEY_W | END_CONSONANT_MASK],
        [KEY_J | END_CONSONANT_MASK]
    ]
    
    let endConsonantTable: [[UInt16]] = [
        [KEY_T], [KEY_P], [KEY_C], [KEY_N], [KEY_M],
        // Quick end consonant entries (g→ng, k→ch, h→nh)
        [KEY_G | VietnameseData.END_CONSONANT_MASK],
        [KEY_K | VietnameseData.END_CONSONANT_MASK],
        [KEY_H | VietnameseData.END_CONSONANT_MASK],
        [KEY_C, KEY_H], [KEY_N, KEY_H], [KEY_N, KEY_G]
    ]
    
    // MARK: - Vowel Combine Table (from Vietnamese.cpp _vowelCombine)
    // First element: 0 = cannot have end consonant, 1 = can have end consonant
    // Remaining elements: vowel keys with optional TONE_MASK (0x20000) or TONEW_MASK (0x40000)
    
    private static let VC_TONE_MASK: UInt32 = 0x20000
    private static let VC_TONEW_MASK: UInt32 = 0x40000
    
    // Use static computed property to avoid lazy var issues with static members
    static let vowelCombineData: [UInt16: [[UInt32]]] = {
        let A = UInt32(KEY_A)
        let E = UInt32(KEY_E)
        let I = UInt32(KEY_I)
        let O = UInt32(KEY_O)
        let U = UInt32(KEY_U)
        let Y = UInt32(KEY_Y)
        let T = VC_TONE_MASK
        let W = VC_TONEW_MASK
        
        return [
            KEY_A: [
                [0, A, I],
                [0, A, O],
                [0, A, U],
                [0, A | T, U],
                [0, A, Y],
                [0, A | T, Y]
            ],
            KEY_E: [
                [0, E, O],
                [0, E | T, U]
            ],
            KEY_I: [
                [1, I, E | T, U],
                [0, I, A],
                [1, I, E | T],
                [0, I, U]
            ],
            KEY_O: [
                [0, O, A, I],
                [0, O, A, O],
                [0, O, A, Y],
                [0, O, E, O],
                [1, O, A],
                [1, O, A | W],
                [1, O, E],
                [0, O, I],
                [0, O | T, I],
                [0, O | W, I],
                [1, O, O],
                [1, O | T, O | T]
            ],
            KEY_U: [
                [0, U, Y, U],
                [1, U, Y, E | T],
                [0, U, Y, A],
                [0, U | W, O | W, U],
                [0, U | W, O | W, I],
                [0, U, O | T, I],
                [0, U, A | T, Y],
                [1, U, A, O],
                [1, U, A],
                [1, U, A | W],
                [1, U, A | T],
                [0, U | W, A],
                [1, U, E | T],
                [0, U, I],
                [0, U | W, I],
                [1, U, O],
                [1, U, O | T],
                [0, U, O | W],
                [1, U | W, O | W],
                [0, U | W, U],
                [1, U, Y]
            ],
            KEY_Y: [
                [0, Y, E | T, U],
                [1, Y, E | T]
            ]
        ]
    }()
    
    var vowelCombine: [UInt16: [[UInt32]]] {
        return VietnameseData.vowelCombineData
    }
    
    // MARK: - Vowel Tables (from Vietnamese.cpp _vowel)
    
    // Vowel combinations for each starting vowel key
    let vowelTable: [UInt16: [[UInt16]]] = [
        KEY_A: [
            [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | 0x4000],
            [KEY_A, KEY_N],
            [KEY_A, KEY_M],
            [KEY_A, KEY_U],
            [KEY_A, KEY_Y],
            [KEY_A, KEY_T],
            [KEY_A, KEY_P],
            [KEY_A],
            [KEY_A, KEY_C]
        ],
        KEY_O: [
            [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | 0x4000],
            [KEY_O, KEY_N],
            [KEY_O, KEY_M],
            [KEY_O, KEY_I],
            [KEY_O, KEY_C],
            [KEY_O, KEY_T],
            [KEY_O, KEY_P],
            [KEY_O]
        ],
        KEY_E: [
            [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | 0x4000],
            [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | 0x4000],
            [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | 0x4000],
            [KEY_E, KEY_C],
            [KEY_E, KEY_T],
            [KEY_E, KEY_Y],
            [KEY_E, KEY_U],
            [KEY_E, KEY_P],
            [KEY_E, KEY_C],
            [KEY_E, KEY_N],
            [KEY_E, KEY_M],
            [KEY_E]
        ],
        KEY_W: [
            [KEY_O, KEY_N],
            [KEY_U, KEY_O, KEY_N, KEY_G], [KEY_U, KEY_O, KEY_G | 0x4000],
            [KEY_U, KEY_O, KEY_N],
            [KEY_U, KEY_O, KEY_I],
            [KEY_U, KEY_O, KEY_C],
            [KEY_O, KEY_I],
            [KEY_O, KEY_P],
            [KEY_O, KEY_M],
            [KEY_O, KEY_A],
            [KEY_O, KEY_T],
            [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | 0x4000],
            [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | 0x4000],
            [KEY_U, KEY_N],
            [KEY_U, KEY_M],
            [KEY_U, KEY_C],
            [KEY_U, KEY_A],
            [KEY_U, KEY_I],
            [KEY_U, KEY_T],
            [KEY_U],
            [KEY_A, KEY_P],
            [KEY_A, KEY_T],
            [KEY_A, KEY_M],
            [KEY_A, KEY_N],
            [KEY_A],
            [KEY_A, KEY_C],
            [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | 0x4000],
            [KEY_O],
            [KEY_U, KEY_U]
        ]
    ]
    
    // MARK: - Vowel For Mark Table (from Vietnamese.cpp _vowelForMark)
    
    let vowelForMarkTable: [UInt16: [[UInt16]]] = [
        KEY_A: [
            [KEY_A, KEY_N, KEY_G], [KEY_A, KEY_G | 0x4000],
            [KEY_A, KEY_N],
            [KEY_A, KEY_N, KEY_H], [KEY_A, KEY_H | 0x4000],
            [KEY_A, KEY_M],
            [KEY_A, KEY_U],
            [KEY_A, KEY_Y],
            [KEY_A, KEY_T],
            [KEY_A, KEY_P],
            [KEY_A],
            [KEY_A, KEY_C],
            [KEY_A, KEY_I],
            [KEY_A, KEY_O],
            [KEY_A, KEY_C, KEY_H], [KEY_A, KEY_K | 0x4000]
        ],
        KEY_O: [
            [KEY_O, KEY_O, KEY_N, KEY_G], [KEY_O, KEY_O, KEY_G | 0x4000],
            [KEY_O, KEY_N, KEY_G], [KEY_O, KEY_G | 0x4000],
            [KEY_O, KEY_O, KEY_N],
            [KEY_O, KEY_O, KEY_C],
            [KEY_O, KEY_O],
            [KEY_O, KEY_N],
            [KEY_O, KEY_M],
            [KEY_O, KEY_I],
            [KEY_O, KEY_C],
            [KEY_O, KEY_T],
            [KEY_O, KEY_P],
            [KEY_O]
        ],
        KEY_E: [
            [KEY_E, KEY_N, KEY_H], [KEY_E, KEY_H | 0x4000],
            [KEY_E, KEY_N, KEY_G], [KEY_E, KEY_G | 0x4000],
            [KEY_E, KEY_C, KEY_H], [KEY_E, KEY_K | 0x4000],
            [KEY_E, KEY_C],
            [KEY_E, KEY_T],
            [KEY_E, KEY_Y],
            [KEY_E, KEY_U],
            [KEY_E, KEY_P],
            [KEY_E, KEY_C],
            [KEY_E, KEY_N],
            [KEY_E, KEY_M],
            [KEY_E]
        ],
        KEY_I: [
            [KEY_I, KEY_N, KEY_H], [KEY_I, KEY_H | 0x4000],
            [KEY_I, KEY_C, KEY_H], [KEY_I, KEY_K | 0x4000],
            [KEY_I, KEY_N],
            [KEY_I, KEY_T],
            [KEY_I, KEY_U],
            [KEY_I, KEY_U, KEY_P],
            [KEY_I, KEY_N],
            [KEY_I, KEY_M],
            [KEY_I, KEY_P],
            [KEY_I, KEY_A],
            [KEY_I, KEY_C],
            [KEY_I]
        ],
        KEY_U: [
            [KEY_U, KEY_N, KEY_G], [KEY_U, KEY_G | 0x4000],
            [KEY_U, KEY_I],
            [KEY_U, KEY_O],
            [KEY_U, KEY_Y],
            [KEY_U, KEY_Y, KEY_N],
            [KEY_U, KEY_Y, KEY_T],
            [KEY_U, KEY_Y, KEY_P],
            [KEY_U, KEY_Y, KEY_N, KEY_H], [KEY_U, KEY_Y, KEY_H | 0x4000],
            [KEY_U, KEY_T],
            [KEY_U, KEY_U],
            [KEY_U, KEY_A],
            [KEY_U, KEY_I],
            [KEY_U, KEY_C],
            [KEY_U, KEY_N],
            [KEY_U, KEY_M],
            [KEY_U, KEY_P],
            [KEY_U]
        ],
        KEY_Y: [
            [KEY_Y]
        ]
    ]
    
    // MARK: - Consonant D Table (from Vietnamese.cpp _consonantD)
    
    let consonantDTable: [[UInt16]] = [
        [KEY_D, KEY_E, KEY_N, KEY_H], [KEY_D, KEY_E, KEY_H | 0x4000],
        [KEY_D, KEY_E, KEY_N, KEY_G], [KEY_D, KEY_E, KEY_G | 0x4000],
        [KEY_D, KEY_E, KEY_C, KEY_H], [KEY_D, KEY_E, KEY_K | 0x4000],
        [KEY_D, KEY_E, KEY_N],
        [KEY_D, KEY_E, KEY_C],
        [KEY_D, KEY_E, KEY_M],
        [KEY_D, KEY_E],
        [KEY_D, KEY_E, KEY_T],
        [KEY_D, KEY_E, KEY_U],
        [KEY_D, KEY_E, KEY_O],
        [KEY_D, KEY_E, KEY_P],
        [KEY_D, KEY_U, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_G | 0x4000],
        [KEY_D, KEY_U, KEY_N],
        [KEY_D, KEY_U, KEY_M],
        [KEY_D, KEY_U, KEY_C],
        [KEY_D, KEY_U, KEY_O],
        [KEY_D, KEY_U, KEY_A],
        [KEY_D, KEY_U, KEY_O, KEY_I],
        [KEY_D, KEY_U, KEY_O, KEY_C],
        [KEY_D, KEY_U, KEY_O, KEY_N],
        [KEY_D, KEY_U, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_U, KEY_O, KEY_G | 0x4000],
        [KEY_D, KEY_U],
        [KEY_D, KEY_U, KEY_P],
        [KEY_D, KEY_U, KEY_T],
        [KEY_D, KEY_U, KEY_I],
        [KEY_D, KEY_I, KEY_C, KEY_H], [KEY_D, KEY_I, KEY_K | 0x4000],
        [KEY_D, KEY_I, KEY_C],
        [KEY_D, KEY_I, KEY_N, KEY_H], [KEY_D, KEY_I, KEY_H | 0x4000],
        [KEY_D, KEY_I, KEY_N],
        [KEY_D, KEY_I],
        [KEY_D, KEY_I, KEY_A],
        [KEY_D, KEY_I, KEY_E],
        [KEY_D, KEY_I, KEY_E, KEY_C],
        [KEY_D, KEY_I, KEY_E, KEY_U],
        [KEY_D, KEY_I, KEY_E, KEY_N],
        [KEY_D, KEY_I, KEY_E, KEY_M],
        [KEY_D, KEY_I, KEY_E, KEY_P],
        [KEY_D, KEY_I, KEY_T],
        [KEY_D, KEY_O],
        [KEY_D, KEY_O, KEY_A],
        [KEY_D, KEY_O, KEY_A, KEY_N],
        [KEY_D, KEY_O, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_A, KEY_G | 0x4000],
        [KEY_D, KEY_O, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_O, KEY_A, KEY_H | 0x4000],
        [KEY_D, KEY_O, KEY_A, KEY_M],
        [KEY_D, KEY_O, KEY_E],
        [KEY_D, KEY_O, KEY_I],
        [KEY_D, KEY_O, KEY_P],
        [KEY_D, KEY_O, KEY_C],
        [KEY_D, KEY_O, KEY_N],
        [KEY_D, KEY_O, KEY_N, KEY_G], [KEY_D, KEY_O, KEY_G | 0x4000],
        [KEY_D, KEY_O, KEY_M],
        [KEY_D, KEY_O, KEY_T],
        [KEY_D, KEY_A],
        [KEY_D, KEY_A, KEY_T],
        [KEY_D, KEY_A, KEY_Y],
        [KEY_D, KEY_A, KEY_U],
        [KEY_D, KEY_A, KEY_I],
        [KEY_D, KEY_A, KEY_O],
        [KEY_D, KEY_A, KEY_P],
        [KEY_D, KEY_A, KEY_C],
        [KEY_D, KEY_A, KEY_C, KEY_H], [KEY_D, KEY_A, KEY_K | 0x4000],
        [KEY_D, KEY_A, KEY_N],
        [KEY_D, KEY_A, KEY_N, KEY_H], [KEY_D, KEY_A, KEY_H | 0x4000],
        [KEY_D, KEY_A, KEY_N, KEY_G], [KEY_D, KEY_A, KEY_G | 0x4000],
        [KEY_D, KEY_A, KEY_M],
        [KEY_D]
    ]
    
    // MARK: - Code Tables (from Vietnamese.cpp _codeTable)
    
    // Code table structure: [keyCode: [CAPS_CHAR, NORMAL_CHAR, CAPS_W_CHAR, NORMAL_W_CHAR, ...marks]]
    // For marks: [Sắc_CAPS, Sắc_normal, Huyền_CAPS, Huyền_normal, Hỏi_CAPS, Hỏi_normal, Ngã_CAPS, Ngã_normal, Nặng_CAPS, Nặng_normal]
    
    // Unicode Code Table (index 0)
    let unicodeCodeTable: [UInt32: [UInt32]] = [
        // KEY_A: Â, â, Ă, ă, Á, á, À, à, Ả, ả, Ã, ã, Ạ, ạ
        0x20000 | UInt32(KEY_A): [0x00C2, 0x00E2, 0x0102, 0x0103, 0x00C1, 0x00E1, 0x00C0, 0x00E0, 0x1EA2, 0x1EA3, 0x00C3, 0x00E3, 0x1EA0, 0x1EA1],
        // KEY_O: Ô, ô, Ơ, ơ, Ó, ó, Ò, ò, Ỏ, ỏ, Õ, õ, Ọ, ọ
        0x20000 | UInt32(KEY_O): [0x00D4, 0x00F4, 0x01A0, 0x01A1, 0x00D3, 0x00F3, 0x00D2, 0x00F2, 0x1ECE, 0x1ECF, 0x00D5, 0x00F5, 0x1ECC, 0x1ECD],
        // KEY_U: (no ^), Ư, ư, Ú, ú, Ù, ù, Ủ, ủ, Ũ, ũ, Ụ, ụ
        0x40000 | UInt32(KEY_U): [0x0000, 0x0000, 0x01AF, 0x01B0, 0x00DA, 0x00FA, 0x00D9, 0x00F9, 0x1EE6, 0x1EE7, 0x0168, 0x0169, 0x1EE4, 0x1EE5],
        // KEY_E: Ê, ê, (no ˘), É, é, È, è, Ẻ, ẻ, Ẽ, ẽ, Ẹ, ẹ
        0x20000 | UInt32(KEY_E): [0x00CA, 0x00EA, 0x0000, 0x0000, 0x00C9, 0x00E9, 0x00C8, 0x00E8, 0x1EBA, 0x1EBB, 0x1EBC, 0x1EBD, 0x1EB8, 0x1EB9],
        // KEY_D: Đ, đ
        0x20000 | UInt32(KEY_D): [0x0110, 0x0111],
        // KEY_A with ^: Ấ, ấ, Ầ, ầ, Ẩ, ẩ, Ẫ, ẫ, Ậ, ậ
        (0x20000 | 0x80000) | UInt32(KEY_A): [0x1EA4, 0x1EA5, 0x1EA6, 0x1EA7, 0x1EA8, 0x1EA9, 0x1EAA, 0x1EAB, 0x1EAC, 0x1EAD],
        // KEY_A with ˘: Ắ, ắ, Ằ, ằ, Ẳ, ẳ, Ẵ, ẵ, Ặ, ặ
        (0x40000 | 0x80000) | UInt32(KEY_A): [0x1EAE, 0x1EAF, 0x1EB0, 0x1EB1, 0x1EB2, 0x1EB3, 0x1EB4, 0x1EB5, 0x1EB6, 0x1EB7],
        // KEY_O with ^: Ố, ố, Ồ, ồ, Ổ, ổ, Ỗ, ỗ, Ộ, ộ
        (0x20000 | 0x80000) | UInt32(KEY_O): [0x1ED0, 0x1ED1, 0x1ED2, 0x1ED3, 0x1ED4, 0x1ED5, 0x1ED6, 0x1ED7, 0x1ED8, 0x1ED9],
        // KEY_O with horn: Ớ, ớ, Ờ, ờ, Ở, ở, Ỡ, ỡ, Ợ, ợ
        (0x40000 | 0x80000) | UInt32(KEY_O): [0x1EDA, 0x1EDB, 0x1EDC, 0x1EDD, 0x1EDE, 0x1EDF, 0x1EE0, 0x1EE1, 0x1EE2, 0x1EE3],
        // KEY_U with horn: Ứ, ứ, Ừ, ừ, Ử, ử, Ữ, ữ, Ự, ự
        (0x40000 | 0x80000) | UInt32(KEY_U): [0x1EE8, 0x1EE9, 0x1EEA, 0x1EEB, 0x1EEC, 0x1EED, 0x1EEE, 0x1EEF, 0x1EF0, 0x1EF1],
        // KEY_E with ^: Ế, ế, Ề, ề, Ể, ể, Ễ, ễ, Ệ, ệ
        (0x20000 | 0x80000) | UInt32(KEY_E): [0x1EBE, 0x1EBF, 0x1EC0, 0x1EC1, 0x1EC2, 0x1EC3, 0x1EC4, 0x1EC5, 0x1EC6, 0x1EC7],
        // KEY_I: Í, í, Ì, ì, Ỉ, ỉ, Ĩ, ĩ, Ị, ị
        UInt32(KEY_I): [0x00CD, 0x00ED, 0x00CC, 0x00EC, 0x1EC8, 0x1EC9, 0x0128, 0x0129, 0x1ECA, 0x1ECB],
        // KEY_Y: Ý, ý, Ỳ, ỳ, Ỷ, ỷ, Ỹ, ỹ, Ỵ, ỵ
        UInt32(KEY_Y): [0x00DD, 0x00FD, 0x1EF2, 0x1EF3, 0x1EF6, 0x1EF7, 0x1EF8, 0x1EF9, 0x1EF4, 0x1EF5],
        
        // Plain vowels with marks (no circumflex/horn) - for "co" -> "có", "ca" -> "cá", etc.
        // KEY_A plain with marks: Á, á, À, à, Ả, ả, Ã, ã, Ạ, ạ
        0x80000 | UInt32(KEY_A): [0x00C1, 0x00E1, 0x00C0, 0x00E0, 0x1EA2, 0x1EA3, 0x00C3, 0x00E3, 0x1EA0, 0x1EA1],
        // KEY_O plain with marks: Ó, ó, Ò, ò, Ỏ, ỏ, Õ, õ, Ọ, ọ
        0x80000 | UInt32(KEY_O): [0x00D3, 0x00F3, 0x00D2, 0x00F2, 0x1ECE, 0x1ECF, 0x00D5, 0x00F5, 0x1ECC, 0x1ECD],
        // KEY_U plain with marks: Ú, ú, Ù, ù, Ủ, ủ, Ũ, ũ, Ụ, ụ
        0x80000 | UInt32(KEY_U): [0x00DA, 0x00FA, 0x00D9, 0x00F9, 0x1EE6, 0x1EE7, 0x0168, 0x0169, 0x1EE4, 0x1EE5],
        // KEY_E plain with marks: É, é, È, è, Ẻ, ẻ, Ẽ, ẽ, Ẹ, ẹ
        0x80000 | UInt32(KEY_E): [0x00C9, 0x00E9, 0x00C8, 0x00E8, 0x1EBA, 0x1EBB, 0x1EBC, 0x1EBD, 0x1EB8, 0x1EB9]
    ]
    
    // TCVN3 (ABC) Code Table (index 1) - 1 byte character
    let tcvn3CodeTable: [UInt32: [UInt32]] = [
        0x20000 | UInt32(KEY_A): [0xA2, 0xA9, 0xA1, 0xA8, 0xB8, 0xB8, 0xB5, 0xB5, 0xB6, 0xB6, 0xB7, 0xB7, 0xB9, 0xB9],
        0x20000 | UInt32(KEY_O): [0xA4, 0xAB, 0xA5, 0xAC, 0xE3, 0xE3, 0xDF, 0xDF, 0xE1, 0xE1, 0xE2, 0xE2, 0xE4, 0xE4],
        0x40000 | UInt32(KEY_U): [0x00, 0x00, 0xA6, 0xAD, 0xF3, 0xF3, 0xEF, 0xEF, 0xF1, 0xF1, 0xF2, 0xF2, 0xF4, 0xF4],
        0x20000 | UInt32(KEY_E): [0xA3, 0xAA, 0x00, 0x00, 0xD0, 0xD0, 0xCC, 0xCC, 0xCE, 0xCE, 0xCF, 0xCF, 0xD1, 0xD1],
        0x20000 | UInt32(KEY_D): [0xA7, 0xAE],
        (0x20000 | 0x80000) | UInt32(KEY_A): [0xCA, 0xCA, 0xC7, 0xC7, 0xC8, 0xC8, 0xC9, 0xC9, 0xCB, 0xCB],
        (0x40000 | 0x80000) | UInt32(KEY_A): [0xBE, 0xBE, 0xBB, 0xBB, 0xBC, 0xBC, 0xBD, 0xBD, 0xC6, 0xC6],
        (0x20000 | 0x80000) | UInt32(KEY_O): [0xE8, 0xE8, 0xE5, 0xE5, 0xE6, 0xE6, 0xE7, 0xE7, 0xE9, 0xE9],
        (0x40000 | 0x80000) | UInt32(KEY_O): [0xED, 0xED, 0xEA, 0xEA, 0xEB, 0xEB, 0xEC, 0xEC, 0xEE, 0xEE],
        (0x40000 | 0x80000) | UInt32(KEY_U): [0xF8, 0xF8, 0xF5, 0xF5, 0xF6, 0xF6, 0xF7, 0xF7, 0xF9, 0xF9],
        (0x20000 | 0x80000) | UInt32(KEY_E): [0xD5, 0xD5, 0xD2, 0xD2, 0xD3, 0xD3, 0xD4, 0xD4, 0xD6, 0xD6],
        UInt32(KEY_I): [0xDD, 0xDD, 0xD7, 0xD7, 0xD8, 0xD8, 0xDC, 0xDC, 0xDE, 0xDE],
        UInt32(KEY_Y): [0xFD, 0xFD, 0xFA, 0xFA, 0xFB, 0xFB, 0xFC, 0xFC, 0xFE, 0xFE],
        // Plain vowels with marks (TCVN3 uses same codes as with circumflex for plain vowels)
        0x80000 | UInt32(KEY_A): [0xB8, 0xB8, 0xB5, 0xB5, 0xB6, 0xB6, 0xB7, 0xB7, 0xB9, 0xB9],
        0x80000 | UInt32(KEY_O): [0xE3, 0xE3, 0xDF, 0xDF, 0xE1, 0xE1, 0xE2, 0xE2, 0xE4, 0xE4],
        0x80000 | UInt32(KEY_U): [0xF3, 0xF3, 0xEF, 0xEF, 0xF1, 0xF1, 0xF2, 0xF2, 0xF4, 0xF4],
        0x80000 | UInt32(KEY_E): [0xD0, 0xD0, 0xCC, 0xCC, 0xCE, 0xCE, 0xCF, 0xCF, 0xD1, 0xD1]
    ]
    
    // VNI Windows Code Table (index 2) - 2 byte character
    let vniWindowsCodeTable: [UInt32: [UInt32]] = [
        0x20000 | UInt32(KEY_A): [0xC241, 0xE261, 0xCA41, 0xEA61, 0xD941, 0xF961, 0xD841, 0xF861, 0xDB41, 0xFB61, 0xD541, 0xF561, 0xCF41, 0xEF61],
        0x20000 | UInt32(KEY_O): [0xC24F, 0xE26F, 0x00D4, 0x00F4, 0xD94F, 0xF96F, 0xD84F, 0xF86F, 0xDB4F, 0xFB6F, 0xD54F, 0xF56F, 0xCF4F, 0xEF6F],
        0x40000 | UInt32(KEY_U): [0x0000, 0x0000, 0x00D6, 0x00F6, 0xD955, 0xF975, 0xD855, 0xF875, 0xDB55, 0xFB75, 0xD555, 0xF575, 0xCF55, 0xEF75],
        0x20000 | UInt32(KEY_E): [0xC245, 0xE265, 0x0000, 0x0000, 0xD945, 0xF965, 0xD845, 0xF865, 0xDB45, 0xFB65, 0xD545, 0xF565, 0xCF45, 0xEF65],
        0x20000 | UInt32(KEY_D): [0x00D1, 0x00F1],
        (0x20000 | 0x80000) | UInt32(KEY_A): [0xC141, 0xE161, 0xC041, 0xE061, 0xC541, 0xE561, 0xC341, 0xE361, 0xC441, 0xE461],
        (0x40000 | 0x80000) | UInt32(KEY_A): [0xC941, 0xE961, 0xC841, 0xE861, 0xDA41, 0xFA61, 0xDC41, 0xFC61, 0xCB41, 0xEB61],
        (0x20000 | 0x80000) | UInt32(KEY_O): [0xC14F, 0xE16F, 0xC04F, 0xE06F, 0xC54F, 0xE56F, 0xC34F, 0xE36F, 0xC44F, 0xE46F],
        (0x40000 | 0x80000) | UInt32(KEY_O): [0xD9D4, 0xF9F4, 0xD8D4, 0xF8F4, 0xDBD4, 0xFBF4, 0xD5D4, 0xF5F4, 0xCFD4, 0xEFF4],
        (0x40000 | 0x80000) | UInt32(KEY_U): [0xD9D6, 0xF9F6, 0xD8D6, 0xF8F6, 0xDBD6, 0xFBF6, 0xD5D6, 0xF5F6, 0xCFD6, 0xEFF6],
        (0x20000 | 0x80000) | UInt32(KEY_E): [0xC145, 0xE165, 0xC045, 0xE065, 0xC545, 0xE565, 0xC345, 0xE365, 0xC445, 0xE465],
        UInt32(KEY_I): [0x00CD, 0x00ED, 0x00CC, 0x00EC, 0x00C6, 0x00E6, 0x00D3, 0x00F3, 0x00D2, 0x00F2],
        UInt32(KEY_Y): [0xD959, 0xF979, 0xD859, 0xF879, 0xDB59, 0xFB79, 0xD559, 0xF579, 0x00CE, 0x00EE],
        // Plain vowels with marks (VNI uses same codes as with circumflex for plain vowels)
        0x80000 | UInt32(KEY_A): [0xD941, 0xF961, 0xD841, 0xF861, 0xDB41, 0xFB61, 0xD541, 0xF561, 0xCF41, 0xEF61],
        0x80000 | UInt32(KEY_O): [0xD94F, 0xF96F, 0xD84F, 0xF86F, 0xDB4F, 0xFB6F, 0xD54F, 0xF56F, 0xCF4F, 0xEF6F],
        0x80000 | UInt32(KEY_U): [0xD955, 0xF975, 0xD855, 0xF875, 0xDB55, 0xFB75, 0xD555, 0xF575, 0xCF55, 0xEF75],
        0x80000 | UInt32(KEY_E): [0xD945, 0xF965, 0xD845, 0xF865, 0xDB45, 0xFB65, 0xD545, 0xF565, 0xCF45, 0xEF65]
    ]
    
    // All code tables array
    lazy var codeTables: [[UInt32: [UInt32]]] = [
        unicodeCodeTable,
        tcvn3CodeTable,
        vniWindowsCodeTable
    ]
    
    // MARK: - Helper Functions
    
    func isConsonant(_ keyCode: UInt16) -> Bool {
        return !(keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_E ||
                 keyCode == VietnameseData.KEY_U || keyCode == VietnameseData.KEY_Y ||
                 keyCode == VietnameseData.KEY_I || keyCode == VietnameseData.KEY_O)
    }
    
    func isNumberKey(_ keyCode: UInt16) -> Bool {
        return keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
               keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4 ||
               keyCode == VietnameseData.KEY_5 || keyCode == VietnameseData.KEY_6 ||
               keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8 ||
               keyCode == VietnameseData.KEY_9 || keyCode == VietnameseData.KEY_0
    }
    
    func isLetter(_ keyCode: UInt16) -> Bool {
        return keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_B ||
               keyCode == VietnameseData.KEY_C || keyCode == VietnameseData.KEY_D ||
               keyCode == VietnameseData.KEY_E || keyCode == VietnameseData.KEY_F ||
               keyCode == VietnameseData.KEY_G || keyCode == VietnameseData.KEY_H ||
               keyCode == VietnameseData.KEY_I || keyCode == VietnameseData.KEY_J ||
               keyCode == VietnameseData.KEY_K || keyCode == VietnameseData.KEY_L ||
               keyCode == VietnameseData.KEY_M || keyCode == VietnameseData.KEY_N ||
               keyCode == VietnameseData.KEY_O || keyCode == VietnameseData.KEY_P ||
               keyCode == VietnameseData.KEY_Q || keyCode == VietnameseData.KEY_R ||
               keyCode == VietnameseData.KEY_S || keyCode == VietnameseData.KEY_T ||
               keyCode == VietnameseData.KEY_U || keyCode == VietnameseData.KEY_V ||
               keyCode == VietnameseData.KEY_W || keyCode == VietnameseData.KEY_X ||
               keyCode == VietnameseData.KEY_Y || keyCode == VietnameseData.KEY_Z
    }
    
    /// Get Unicode character for a key with tone/mark
    func getUnicodeChar(keyCode: UInt16, hasTone: Bool, hasToneW: Bool, mark: UInt32, isCaps: Bool) -> UInt32 {
        // Build lookup key
        var lookupKey = UInt32(keyCode)
        if hasTone {
            lookupKey |= 0x20000  // TONE_MASK
        }
        if hasToneW {
            lookupKey |= 0x40000  // TONEW_MASK
        }
        if mark != 0 {
            lookupKey |= 0x80000  // Has mark flag
        }
        
        // Look up in code table
        if let charArray = unicodeCodeTable[lookupKey] {
            // Determine index based on mark and caps
            var charIndex = isCaps ? 0 : 1
            
            // If has mark, adjust index
            if mark != 0 {
                // Mark indices: Sắc=0, Huyền=2, Hỏi=4, Ngã=6, Nặng=8
                let markIndex: Int
                switch mark {
                case 0x80000:  // MARK1_MASK - Sắc
                    markIndex = 0
                case 0x100000: // MARK2_MASK - Huyền
                    markIndex = 2
                case 0x200000: // MARK3_MASK - Hỏi
                    markIndex = 4
                case 0x400000: // MARK4_MASK - Ngã
                    markIndex = 6
                case 0x800000: // MARK5_MASK - Nặng
                    markIndex = 8
                default:
                    markIndex = 0
                }
                charIndex = markIndex + (isCaps ? 0 : 1)
            } else if hasTone || hasToneW {
                // For tone without mark, use index 0/1 for base, 2/3 for W
                if hasToneW && !hasTone {
                    charIndex = isCaps ? 2 : 3
                }
            }
            
            if charIndex < charArray.count {
                return charArray[charIndex]
            }
        }
        
        // Fallback: return ASCII character
        if isCaps {
            // Convert to uppercase ASCII
            if keyCode >= VietnameseData.KEY_A && keyCode <= VietnameseData.KEY_Z {
                return UInt32(Character("A").asciiValue!) + UInt32(keyCode)
            }
        }
        
        // Return lowercase or original
        return UInt32(keyCode) + 0x61  // 'a' = 0x61
    }
}
