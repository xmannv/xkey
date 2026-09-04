import XCTest
@testable import XKey

final class InputSessionParityContractTests: XCTestCase {
    func testStandaloneHostSupportsTypingParityCapabilities() {
        let capabilities = HostCapabilities.xkeyIM
        XCTAssertTrue(capabilities.supports(.secureInputFeedback))
        XCTAssertTrue(capabilities.supports(.spellCheck))
        XCTAssertTrue(capabilities.supports(.macroExpansion))
        XCTAssertTrue(capabilities.supports(.smartSwitch))
        XCTAssertTrue(capabilities.supports(.appRules))
        XCTAssertTrue(capabilities.supports(.toggleVietnamese))
        XCTAssertTrue(capabilities.supports(.undoTyping))
    }

    func testStandaloneHostDeclaresMainAppUICommandsUnsupported() {
        let capabilities = HostCapabilities.xkeyIM
        XCTAssertFalse(capabilities.supports(.translationUI))
        XCTAssertFalse(capabilities.supports(.convertToolUI))
        XCTAssertFalse(capabilities.supports(.settingsUI))
        XCTAssertFalse(capabilities.supports(.debugWindowUI))
        XCTAssertFalse(capabilities.supports(.toolbarUI))
        XCTAssertFalse(capabilities.unsupportedReason(for: .translationUI)?.isEmpty ?? true)
        XCTAssertFalse(capabilities.unsupportedReason(for: .convertToolUI)?.isEmpty ?? true)
        XCTAssertFalse(capabilities.unsupportedReason(for: .settingsUI)?.isEmpty ?? true)
        XCTAssertFalse(capabilities.unsupportedReason(for: .debugWindowUI)?.isEmpty ?? true)
        XCTAssertFalse(capabilities.unsupportedReason(for: .toolbarUI)?.isEmpty ?? true)
    }
}
