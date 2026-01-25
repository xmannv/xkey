//
//  TranslationProvider.swift
//  XKey
//
//  Strategy Pattern Protocol for Translation Providers
//

import Foundation

// MARK: - Translation Result

struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String?
    let targetLanguage: String
    let providerName: String
}

// MARK: - Translation Error

enum TranslationError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case emptyText
    case providerDisabled
    case unsupportedLanguage
    case rateLimited
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from translation service"
        case .emptyText:
            return "No text to translate"
        case .providerDisabled:
            return "Translation provider is disabled"
        case .unsupportedLanguage:
            return "Unsupported language"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Translation Provider Protocol (Strategy Pattern)

protocol TranslationProvider {
    /// Unique identifier for the provider
    var id: String { get }
    
    /// Display name for the provider
    var name: String { get }
    
    /// Provider description
    var description: String { get }
    
    /// Whether the provider is currently enabled
    var isEnabled: Bool { get set }
    
    /// Supported source languages (nil means all)
    var supportedSourceLanguages: [TranslationLanguage]? { get }
    
    /// Supported target languages
    var supportedTargetLanguages: [TranslationLanguage] { get }
    
    /// Translate text asynchronously
    func translate(
        text: String,
        from sourceLanguage: TranslationLanguage,
        to targetLanguage: TranslationLanguage
    ) async throws -> TranslationResult
}

// MARK: - Provider Configuration

struct TranslationProviderConfig: Codable, Identifiable, Equatable {
    var id: String
    var isEnabled: Bool
    var priority: Int  // Lower number = higher priority
    
    init(id: String, isEnabled: Bool = true, priority: Int = 0) {
        self.id = id
        self.isEnabled = isEnabled
        self.priority = priority
    }
}
