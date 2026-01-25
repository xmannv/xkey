//
//  GoogleTranslateProvider.swift
//  XKey
//
//  Google Translate Provider Implementation
//  Uses translate.googleapis.com free API
//

import Foundation

class GoogleTranslateProvider: TranslationProvider {
    
    // MARK: - Protocol Properties
    
    let id = "google_translate"
    let name = "Google Translate"
    let description = "Dịch bằng Google Translate (miễn phí, có giới hạn)"
    
    var isEnabled: Bool = true
    
    var supportedSourceLanguages: [String]? {
        return nil  // Supports all ISO 639-1 language codes including "auto"
    }
    
    var supportedTargetLanguages: [String]? {
        return nil  // Supports all ISO 639-1 language codes (except "auto")
    }
    
    // MARK: - Private Properties
    
    /// Use shared session to reduce memory footprint
    private var session: URLSession { TranslationNetworkManager.shared.session }
    private let baseURL = "https://translate.googleapis.com/translate_a/single"
    
    // MARK: - Translation
    
    func translate(
        text: String,
        from sourceLanguageCode: String,
        to targetLanguageCode: String
    ) async throws -> TranslationResult {
        
        guard isEnabled else {
            throw TranslationError.providerDisabled
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyText
        }
        
        // Build URL with query parameters
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLanguageCode),
            URLQueryItem(name: "tl", value: targetLanguageCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        
        guard let url = components.url else {
            throw TranslationError.invalidResponse
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }
            
            if httpResponse.statusCode == 429 {
                throw TranslationError.rateLimited
            }
            
            guard httpResponse.statusCode == 200 else {
                throw TranslationError.unknown("HTTP \(httpResponse.statusCode)")
            }
            
            // Parse response
            // Google Translate returns a nested array structure:
            // [[[translated_text, original_text, null, null, confidence]], null, source_language]
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let translations = json.first as? [Any] else {
                throw TranslationError.invalidResponse
            }
            
            // Extract translated text from all translation segments
            var translatedParts: [String] = []
            for translation in translations {
                if let translationArray = translation as? [Any],
                   let translatedText = translationArray.first as? String {
                    translatedParts.append(translatedText)
                }
            }
            
            let translatedText = translatedParts.joined()
            
            // Try to get detected source language
            var detectedSourceLanguage: String? = nil
            if json.count > 2, let sourceLang = json[2] as? String {
                detectedSourceLanguage = sourceLang
            }
            
            return TranslationResult(
                originalText: text,
                translatedText: translatedText,
                sourceLanguage: detectedSourceLanguage,
                targetLanguage: targetLanguageCode,
                providerName: name
            )
            
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error)
        }
    }
}
