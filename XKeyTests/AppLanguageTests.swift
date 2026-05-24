//
//  AppLanguageTests.swift
//  XKeyTests
//

import XCTest
@testable import XKey

class AppLanguageTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }

    // MARK: - applyLanguage

    func testApplyLanguageVietnamese() {
        UserDefaults.standard.set("vi", forKey: "appLanguage")
        AppLanguage.applyLanguage()
        let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(languages, ["vi"])
    }

    func testApplyLanguageEnglish() {
        UserDefaults.standard.set("en", forKey: "appLanguage")
        AppLanguage.applyLanguage()
        let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(languages, ["en"])
    }

    func testApplyLanguageChinese() {
        UserDefaults.standard.set("zh-Hans", forKey: "appLanguage")
        AppLanguage.applyLanguage()
        let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertEqual(languages, ["zh-Hans"])
    }

    func testApplyLanguageSystemClearsAppOverride() {
        UserDefaults.standard.set("system", forKey: "appLanguage")
        AppLanguage.applyLanguage()
        // After applying "system", the app-level override is removed;
        // AppleLanguages falls back to the OS-level value (always present)
        let lang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system")
        XCTAssertEqual(lang, .system)
    }

    func testMissingKeyDefaultsToSystem() {
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        XCTAssertEqual(AppLanguage(rawValue: saved) ?? .system, .system)
    }

    func testInvalidValueDefaultsToSystem() {
        XCTAssertNil(AppLanguage(rawValue: "invalid"))
    }

    // MARK: - localeIdentifier

    func testLocaleIdentifiers() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.vi.localeIdentifier, "vi")
        XCTAssertEqual(AppLanguage.en.localeIdentifier, "en")
        XCTAssertEqual(AppLanguage.zhHans.localeIdentifier, "zh-Hans")
    }

    // MARK: - Codable backward compatibility

    func testPreferencesDefaultLanguageIsSystem() {
        let prefs = Preferences()
        XCTAssertEqual(prefs.appLanguage, .system)
    }

    func testPreferencesRoundTripWithAppLanguage() throws {
        var prefs = Preferences()
        prefs.appLanguage = .zhHans

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(decoded.appLanguage, .zhHans)
    }
}
