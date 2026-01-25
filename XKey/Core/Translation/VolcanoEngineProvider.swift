//
//  VolcanoEngineProvider.swift
//  XKey
//
//  Volcano Engine (ByteDance) Translation Provider
//  Uses the free browser extension endpoint
//

import Foundation

class VolcanoEngineProvider: TranslationProvider {
    
    // MARK: - Protocol Properties
    
    let id = "volcano_engine"
    let name = "Volcano Engine"
    let description = "Dịch bằng Volcano Engine - ByteDance (miễn phí, hỗ trợ tốt tiếng Trung)"
    
    var isEnabled: Bool = true
    
    var supportedSourceLanguages: [String]? {
        return nil  // Supports many languages including "auto"
    }
    
    var supportedTargetLanguages: [String]? {
        return nil  // Supports many languages
    }
    
    // MARK: - Private Properties
    
    /// Use shared session to reduce memory footprint
    private var session: URLSession { TranslationNetworkManager.shared.session }
    private let baseURL = "https://translate.volcengine.com/crx/translate/v1/"
    
    // Language code mapping (ISO 639-1 to Volcano format)
    private let languageMapping: [String: String] = [
        "auto": "detect",
        "zh": "zh",
        "zh-cn": "zh",
        "zh-tw": "zh-Hant",
        "en": "en",
        "ja": "ja",
        "ko": "ko",
        "vi": "vi",
        "th": "th",
        "id": "id",
        "ms": "ms",
        "fr": "fr",
        "de": "de",
        "es": "es",
        "pt": "pt",
        "it": "it",
        "ru": "ru",
        "ar": "ar",
        "hi": "hi",
        "tr": "tr",
        "pl": "pl",
        "nl": "nl"
    ]
    
    // MARK: - Language Mapping
    
    private func mapLanguageCode(_ code: String) -> String {
        return languageMapping[code.lowercased()] ?? code
    }
    
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
        
        let sourceLang = mapLanguageCode(sourceLanguageCode)
        let targetLang = mapLanguageCode(targetLanguageCode)
        
        // Build request body
        let requestBody: [String: Any] = [
            "source_language": sourceLang,
            "target_language": targetLang,
            "text": text
        ]
        
        guard let url = URL(string: baseURL) else {
            throw TranslationError.invalidResponse
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("https://translate.volcengine.com", forHTTPHeaderField: "Origin")
        request.addValue("https://translate.volcengine.com/", forHTTPHeaderField: "Referer")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
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
            // Response format varies, try multiple formats
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TranslationError.invalidResponse
            }
            
            // Check for error
            if let code = json["code"] as? Int, code != 0 {
                if let message = json["message"] as? String {
                    throw TranslationError.unknown(message)
                }
                throw TranslationError.unknown("Volcano API error: \(code)")
            }
            
            // Try to extract translated text from different response formats
            var translatedText: String?
            
            // Format 1: {"translation": "text"}
            if let translation = json["translation"] as? String {
                translatedText = translation
            }
            
            // Format 2: {"data": {"translation": "text"}}
            if translatedText == nil,
               let dataObj = json["data"] as? [String: Any],
               let translation = dataObj["translation"] as? String {
                translatedText = translation
            }
            
            // Format 3: {"translations": [{"text": "..."}]}
            if translatedText == nil,
               let translations = json["translations"] as? [[String: Any]],
               let first = translations.first,
               let text = first["text"] as? String {
                translatedText = text
            }
            
            // Format 4: {"TranslationList": [{"Translation": "..."}]}
            if translatedText == nil,
               let translationList = json["TranslationList"] as? [[String: Any]],
               let first = translationList.first,
               let translation = first["Translation"] as? String {
                translatedText = translation
            }
            
            guard let result = translatedText, !result.isEmpty else {
                throw TranslationError.invalidResponse
            }
            
            // Extract detected source language
            var detectedSource: String? = nil
            if let detected = json["detected_language"] as? String {
                detectedSource = detected
            } else if let detected = json["DetectedSourceLanguage"] as? String {
                detectedSource = detected
            }
            
            return TranslationResult(
                originalText: text,
                translatedText: result,
                sourceLanguage: detectedSource,
                targetLanguage: targetLang,
                providerName: name
            )
            
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error)
        }
    }
}
