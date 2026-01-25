//
//  TranslationLanguage.swift
//  XKey
//
//  Shared Translation Language Enum
//  Used by both XKey and XKeyIM for Preferences serialization
//

import Foundation

// MARK: - Supported Languages

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case auto = "auto"
    case vietnamese = "vi"
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"
    case thai = "th"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "Tự động nhận diện"
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .thai: return "ไทย"
        }
    }
    
    var flag: String {
        switch self {
        case .auto: return "🌐"
        case .vietnamese: return "🇻🇳"
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .spanish: return "🇪🇸"
        case .russian: return "🇷🇺"
        case .thai: return "🇹🇭"
        }
    }
}
