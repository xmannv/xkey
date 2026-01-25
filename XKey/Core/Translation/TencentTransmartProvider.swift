//
//  TencentTransmartProvider.swift
//  XKey
//
//  Tencent TranSmart Translation Provider
//  Uses the free transmart.qq.com API
//

import Foundation

class TencentTransmartProvider: TranslationProvider {
    
    // MARK: - Protocol Properties
    
    let id = "tencent_transmart"
    let name = "Tencent TranSmart"
    let description = "Dịch bằng Tencent TranSmart (miễn phí, hỗ trợ tốt tiếng Trung)"
    
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
    private let baseURL = "https://transmart.qq.com/api/imt"
    
    // Language code mapping (ISO 639-1 to Tencent format)
    private let languageMapping: [String: String] = [
        "auto": "auto",
        "zh": "zh",
        "zh-cn": "zh",
        "zh-tw": "zh-TW",
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
            "header": [
                "fn": "auto_translation",
                "client_key": "browser-firefox-\(Int(Date().timeIntervalSince1970 * 1000))"
            ],
            "source": [
                "lang": sourceLang,
                "text_list": [text]
            ],
            "target": [
                "lang": targetLang
            ]
        ]
        
        guard let url = URL(string: baseURL) else {
            throw TranslationError.invalidResponse
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("https://transmart.qq.com", forHTTPHeaderField: "Origin")
        request.addValue("https://transmart.qq.com/", forHTTPHeaderField: "Referer")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
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
            // Response format: {"header":{"ret_code":"succ"},"auto_translation":["translated text"]}
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TranslationError.invalidResponse
            }
            
            // Check for error in header
            if let header = json["header"] as? [String: Any],
               let retCode = header["ret_code"] as? String,
               retCode != "succ" {
                throw TranslationError.unknown("Tencent API error: \(retCode)")
            }
            
            // Extract translated text
            guard let translations = json["auto_translation"] as? [String],
                  let translatedText = translations.first else {
                throw TranslationError.invalidResponse
            }
            
            return TranslationResult(
                originalText: text,
                translatedText: translatedText,
                sourceLanguage: sourceLang == "auto" ? nil : sourceLang,
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
