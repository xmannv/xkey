import XCTest
@testable import XKey

final class VNDictionaryManagerTests: XCTestCase {
    private enum SignatureError: LocalizedError {
        case denied

        var errorDescription: String? { "Dictionary attributes unavailable" }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "1\nplaceholder\n".write(
            to: dictionaryURL,
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testExternalFileSignatureChangeInvalidatesLoadedDictionary() throws {
        var signature = DictionaryFileSignature(
            modificationTime: 1,
            fileSize: 10,
            fileIdentifier: 100
        )
        let manager = VNDictionaryManager(
            dictionaryDirectory: directory,
            signatureProvider: { _ in signature },
            contentReader: { _ in "1\nfirst-version\n" }
        )

        try manager.loadDictionary(style: .dauMoi)
        XCTAssertTrue(manager.isDictionaryLoaded(style: .dauMoi))

        signature = DictionaryFileSignature(
            modificationTime: 2,
            fileSize: 11,
            fileIdentifier: 101
        )

        XCTAssertFalse(manager.isDictionaryLoaded(style: .dauMoi))
    }

    func testAtomicReplacementIsDetectedByProductionFileSignature() throws {
        let manager = VNDictionaryManager(dictionaryDirectory: directory)
        try manager.loadDictionary(style: .dauMoi)
        XCTAssertTrue(manager.isDictionaryLoaded(style: .dauMoi))
        let originalSignature = try VNDictionaryManager.fileSignature(at: dictionaryURL)

        try "1\nreplacement\n".write(
            to: dictionaryURL,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNotEqual(try VNDictionaryManager.fileSignature(at: dictionaryURL), originalSignature)
        XCTAssertFalse(manager.isDictionaryLoaded(style: .dauMoi))
    }

    func testReplacementDuringParseRetriesAndPublishesStableFileOnly() throws {
        let oldSignature = DictionaryFileSignature(
            modificationTime: 1,
            fileSize: 10,
            fileIdentifier: 100
        )
        let newSignature = DictionaryFileSignature(
            modificationTime: 2,
            fileSize: 20,
            fileIdentifier: 101
        )
        var signatures = [oldSignature, newSignature, newSignature, newSignature, newSignature, newSignature]
        var readCount = 0
        let manager = VNDictionaryManager(
            dictionaryDirectory: directory,
            signatureProvider: { _ in signatures.removeFirst() },
            contentReader: { _ in
                readCount += 1
                return readCount == 1 ? "1\nstale-entry\n" : "1\ncurrent-entry\n"
            }
        )

        try manager.loadDictionary(style: .dauMoi)

        XCTAssertEqual(readCount, 2)
        XCTAssertFalse(manager.isValidWord("stale-entry", style: .dauMoi))
        XCTAssertTrue(manager.isValidWord("current-entry", style: .dauMoi))
        XCTAssertTrue(manager.isDictionaryLoaded(style: .dauMoi))
    }

    func testUnstableFinalVerificationNeverPublishesCandidateContent() throws {
        func signature(_ value: UInt64) -> DictionaryFileSignature {
            DictionaryFileSignature(
                modificationTime: TimeInterval(value),
                fileSize: value + 1,
                fileIdentifier: value + 100
            )
        }
        let signatures = (0..<7).map { signature(UInt64($0)) }
        var signatureSequence = [
            signatures[0], signatures[0], signatures[0],
            signatures[1], signatures[1], signatures[2],
            signatures[3], signatures[3], signatures[4],
            signatures[5], signatures[5], signatures[6]
        ]
        var readCount = 0
        let manager = VNDictionaryManager(
            dictionaryDirectory: directory,
            signatureProvider: { _ in
                signatureSequence.isEmpty ? signatures[6] : signatureSequence.removeFirst()
            },
            contentReader: { _ in
                readCount += 1
                return readCount == 1 ? "1\nknown-good\n" : "1\nunstable-candidate\n"
            }
        )
        try manager.loadDictionary(style: .dauMoi)

        XCTAssertThrowsError(try manager.loadDictionary(style: .dauMoi))
        XCTAssertTrue(manager.isValidWord("known-good", style: .dauMoi))
        XCTAssertFalse(manager.isValidWord("unstable-candidate", style: .dauMoi))
    }

    func testExistingFileSignatureFailureReportsFailedInsteadOfUnavailable() {
        let manager = VNDictionaryManager(
            dictionaryDirectory: directory,
            availabilityProvider: { _ in true },
            signatureProvider: { _ in throw SignatureError.denied }
        )
        let runtime = DictionaryRuntime(loader: manager)

        let result = runtime.refresh(enabled: true, style: .dauMoi)

        XCTAssertEqual(result.newState, .failed(.dauMoi))
        XCTAssertEqual(result.diagnostic, SignatureError.denied.localizedDescription)
    }

    func testDownloadedDictionaryDoesNotLoadWhenSpellCheckIsDisabled() {
        XCTAssertFalse(VNDictionaryManager.shouldLoadDownloadedDictionary(
            style: .dauMoi,
            spellCheckEnabled: false,
            selectedStyle: .dauMoi
        ))
    }

    private var dictionaryURL: URL {
        directory.appendingPathComponent("vi-DauMoi.dic")
    }
}
