//
//  TranslationProviderTests.swift
//  XKeyTests
//
//  Unit tests for Translation Providers
//  These tests make real network calls to verify providers work correctly
//

import XCTest
@testable import XKey

final class TranslationProviderTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    // Test text samples
    let englishText = "Hello, how are you?"
    let vietnameseText = "Xin chào, bạn khỏe không?"
    let chineseText = "你好，你好吗？"
    let shortText = "Hello"
    
    // Timeout for network requests
    let networkTimeout: TimeInterval = 15.0
    
    // MARK: - Google Translate Tests
    
    func testGoogleTranslate_EnglishToVietnamese() async throws {
        let provider = GoogleTranslateProvider()
        
        let result = try await provider.translate(
            text: englishText,
            from: "en",
            to: "vi"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        XCTAssertEqual(result.providerName, "Google Translate")
        XCTAssertEqual(result.targetLanguage, "vi")
        XCTAssertEqual(result.originalText, englishText)
        
        print("✅ Google Translate: '\(englishText)' → '\(result.translatedText)'")
    }
    
    func testGoogleTranslate_AutoDetect() async throws {
        let provider = GoogleTranslateProvider()
        
        let result = try await provider.translate(
            text: vietnameseText,
            from: "auto",
            to: "en"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        XCTAssertNotNil(result.sourceLanguage, "Should detect source language")
        
        print("✅ Google Translate (auto-detect): '\(vietnameseText)' → '\(result.translatedText)' (detected: \(result.sourceLanguage ?? "unknown"))")
    }
    
    func testGoogleTranslate_EmptyText() async {
        let provider = GoogleTranslateProvider()
        
        do {
            _ = try await provider.translate(text: "", from: "en", to: "vi")
            XCTFail("Should throw error for empty text")
        } catch let error as TranslationError {
            XCTAssertEqual(error, TranslationError.emptyText)
            print("✅ Google Translate correctly rejects empty text")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Tencent TranSmart Tests
    
    func testTencentTransmart_EnglishToVietnamese() async throws {
        let provider = TencentTransmartProvider()
        
        let result = try await provider.translate(
            text: englishText,
            from: "en",
            to: "vi"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        XCTAssertEqual(result.providerName, "Tencent TranSmart")
        
        print("✅ Tencent TranSmart: '\(englishText)' → '\(result.translatedText)'")
    }
    
    func testTencentTransmart_EnglishToChinese() async throws {
        let provider = TencentTransmartProvider()
        
        let result = try await provider.translate(
            text: englishText,
            from: "en",
            to: "zh"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        
        // Check for Chinese characters
        let containsChinese = result.translatedText.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
        XCTAssertTrue(containsChinese, "Result should contain Chinese characters")
        
        print("✅ Tencent TranSmart (to Chinese): '\(englishText)' → '\(result.translatedText)'")
    }
    
    // MARK: - Volcano Engine Tests
    
    func testVolcanoEngine_EnglishToVietnamese() async throws {
        let provider = VolcanoEngineProvider()
        
        let result = try await provider.translate(
            text: englishText,
            from: "en",
            to: "vi"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        XCTAssertEqual(result.providerName, "Volcano Engine")
        
        print("✅ Volcano Engine: '\(englishText)' → '\(result.translatedText)'")
    }
    
    func testVolcanoEngine_EnglishToChinese() async throws {
        let provider = VolcanoEngineProvider()
        
        let result = try await provider.translate(
            text: englishText,
            from: "en",
            to: "zh"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        
        print("✅ Volcano Engine (to Chinese): '\(englishText)' → '\(result.translatedText)'")
    }
    
    // MARK: - Translation Service Tests
    
    func testTranslationService_Fallback() async throws {
        let service = TranslationService.shared
        
        // This tests the fallback mechanism - if first provider fails, try next
        let result = try await service.translate(
            text: shortText,
            from: "en",
            to: "vi"
        )
        
        XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
        
        print("✅ TranslationService: '\(shortText)' → '\(result.translatedText)' (via \(result.providerName))")
    }
    
    func testTranslationService_AllProvidersRegistered() {
        let service = TranslationService.shared
        
        // Check that all providers are registered
        let providers = service.sortedProviders
        
        XCTAssertGreaterThanOrEqual(providers.count, 3, "Should have at least 3 providers")
        
        let providerNames = providers.map { $0.name }
        XCTAssertTrue(providerNames.contains("Google Translate"), "Should include Google Translate")
        XCTAssertTrue(providerNames.contains("Tencent TranSmart"), "Should include Tencent TranSmart")
        XCTAssertTrue(providerNames.contains("Volcano Engine"), "Should include Volcano Engine")
        
        print("✅ All 3 providers registered: \(providerNames.joined(separator: ", "))")
    }
    
    // MARK: - Comparison Tests
    
    func testAllProviders_CompareResults() async {
        let testText = "Good morning, how are you today?"
        let providers: [TranslationProvider] = [
            GoogleTranslateProvider(),
            TencentTransmartProvider(),
            VolcanoEngineProvider()
        ]
        
        print("\n📊 Comparison Test: '\(testText)' → Vietnamese\n")
        print(String(repeating: "-", count: 80))
        
        var successCount = 0
        var failCount = 0
        
        for provider in providers {
            do {
                let startTime = Date()
                let result = try await provider.translate(
                    text: testText,
                    from: "en",
                    to: "vi"
                )
                let elapsed = Date().timeIntervalSince(startTime)
                
                print("✅ \(provider.name.padding(toLength: 20, withPad: " ", startingAt: 0)) | \(String(format: "%.2fs", elapsed)) | \(result.translatedText)")
                successCount += 1
            } catch {
                print("❌ \(provider.name.padding(toLength: 20, withPad: " ", startingAt: 0)) | FAILED | \(error.localizedDescription)")
                failCount += 1
            }
        }
        
        print(String(repeating: "-", count: 80))
        print("📈 Results: \(successCount) succeeded, \(failCount) failed\n")
        
        // All 3 providers should work
        XCTAssertGreaterThanOrEqual(successCount, 3, "All 3 providers should work")
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_GoogleTranslate() async throws {
        let provider = GoogleTranslateProvider()
        
        let startTime = Date()
        _ = try await provider.translate(text: shortText, from: "en", to: "vi")
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("⏱️ Google Translate response time: \(String(format: "%.2f", elapsed))s")
        XCTAssertLessThan(elapsed, networkTimeout, "Should complete within timeout")
    }
}

// MARK: - TranslationError Equatable

extension TranslationError: Equatable {
    public static func == (lhs: TranslationError, rhs: TranslationError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyText, .emptyText):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.providerDisabled, .providerDisabled):
            return true
        case (.unsupportedLanguage, .unsupportedLanguage):
            return true
        case (.rateLimited, .rateLimited):
            return true
        case (.networkError, .networkError):
            return true
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}
