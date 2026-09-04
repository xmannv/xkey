import XCTest
@testable import XKey

final class DictionaryRuntimeTests: XCTestCase {
    private final class FakeLoader: DictionaryLoading {
        var availableStyles: Set<VNDictionaryManager.DictionaryStyle> = []
        var loadedStyles: Set<VNDictionaryManager.DictionaryStyle> = []
        var loadError: Error?
        private(set) var loadCalls: [VNDictionaryManager.DictionaryStyle] = []

        func isDictionaryAvailable(style: VNDictionaryManager.DictionaryStyle) -> Bool {
            availableStyles.contains(style)
        }

        func isDictionaryLoaded(style: VNDictionaryManager.DictionaryStyle) -> Bool {
            loadedStyles.contains(style)
        }

        func loadDictionary(style: VNDictionaryManager.DictionaryStyle) throws {
            loadCalls.append(style)
            if let loadError { throw loadError }
            loadedStyles.insert(style)
        }
    }

    private enum TestError: Error {
        case loadFailed
    }

    func testDisabledDoesNotLoad() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi]
        let runtime = DictionaryRuntime(loader: loader)

        XCTAssertEqual(runtime.refresh(enabled: false, style: .dauMoi).newState, .disabled)
        XCTAssertEqual(runtime.state, .disabled)
        XCTAssertTrue(loader.loadCalls.isEmpty)
    }

    func testFirstEnabledRefreshLoadsAvailableDictionary() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi]
        let runtime = DictionaryRuntime(loader: loader)

        let result = runtime.refresh(enabled: true, style: .dauMoi)

        XCTAssertEqual(result.previousState, .disabled)
        XCTAssertEqual(result.newState, .loaded(.dauMoi))
        XCTAssertTrue(result.didChange)
        XCTAssertEqual(loader.loadCalls, [.dauMoi])
    }

    func testRepeatedRefreshDoesNotReloadLoadedStyle() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi]
        let runtime = DictionaryRuntime(loader: loader)

        runtime.refresh(enabled: true, style: .dauMoi)
        runtime.refresh(enabled: true, style: .dauMoi)

        XCTAssertEqual(loader.loadCalls, [.dauMoi])
    }

    func testStyleChangeLoadsNewStyle() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi, .dauCu]
        let runtime = DictionaryRuntime(loader: loader)

        runtime.refresh(enabled: true, style: .dauMoi)
        XCTAssertEqual(runtime.refresh(enabled: true, style: .dauCu).newState, .loaded(.dauCu))
        XCTAssertEqual(loader.loadCalls, [.dauMoi, .dauCu])
    }

    func testUnavailableDictionaryReportsUnavailableWithoutLoading() {
        let loader = FakeLoader()
        let runtime = DictionaryRuntime(loader: loader)

        XCTAssertEqual(runtime.refresh(enabled: true, style: .dauCu).newState, .unavailable(.dauCu))
        XCTAssertTrue(loader.loadCalls.isEmpty)
    }

    func testUnavailableDictionaryRetriesWhenItBecomesAvailable() {
        let loader = FakeLoader()
        let runtime = DictionaryRuntime(loader: loader)
        XCTAssertEqual(runtime.refresh(enabled: true, style: .dauCu).newState, .unavailable(.dauCu))

        loader.availableStyles.insert(.dauCu)

        XCTAssertEqual(runtime.refresh(enabled: true, style: .dauCu).newState, .loaded(.dauCu))
        XCTAssertEqual(loader.loadCalls, [.dauCu])
    }

    func testFailedLoadCanRetry() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi]
        loader.loadError = TestError.loadFailed
        let runtime = DictionaryRuntime(loader: loader)

        let failure = runtime.refresh(enabled: true, style: .dauMoi)
        XCTAssertEqual(failure.newState, .failed(.dauMoi))
        XCTAssertNotNil(failure.diagnostic)
        loader.loadError = nil

        XCTAssertEqual(runtime.refresh(enabled: true, style: .dauMoi).newState, .loaded(.dauMoi))
        XCTAssertEqual(loader.loadCalls, [.dauMoi, .dauMoi])
    }

    func testRepeatedRefreshReportsNoTransition() {
        let loader = FakeLoader()
        loader.availableStyles = [.dauMoi]
        let runtime = DictionaryRuntime(loader: loader)
        _ = runtime.refresh(enabled: true, style: .dauMoi)

        let result = runtime.refresh(enabled: true, style: .dauMoi)

        XCTAssertEqual(result.previousState, .loaded(.dauMoi))
        XCTAssertEqual(result.newState, .loaded(.dauMoi))
        XCTAssertFalse(result.didChange)
    }

    func testLoaderCanReadRuntimeStateDuringLoad() {
        final class ReentrantLoader: DictionaryLoading {
            var readState: (() -> DictionaryRuntimeState)?

            func isDictionaryAvailable(style: VNDictionaryManager.DictionaryStyle) -> Bool { true }
            func isDictionaryLoaded(style: VNDictionaryManager.DictionaryStyle) -> Bool { false }
            func loadDictionary(style: VNDictionaryManager.DictionaryStyle) throws {
                _ = readState?()
            }
        }

        let loader = ReentrantLoader()
        let runtime = DictionaryRuntime(loader: loader)
        loader.readState = { runtime.state }
        let completed = expectation(description: "refresh completed")

        DispatchQueue.global().async {
            _ = runtime.refresh(enabled: true, style: .dauMoi)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testConcurrentSameStyleRefreshLoadsOnce() {
        final class BlockingLoader: DictionaryLoading {
            let loadStarted = DispatchSemaphore(value: 0)
            let allowLoad = DispatchSemaphore(value: 0)
            private let lock = NSLock()
            private var _loadCount = 0
            private var loaded = false

            var loadCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return _loadCount
            }

            func isDictionaryAvailable(style: VNDictionaryManager.DictionaryStyle) -> Bool { true }
            func isDictionaryLoaded(style: VNDictionaryManager.DictionaryStyle) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return loaded
            }
            func loadDictionary(style: VNDictionaryManager.DictionaryStyle) throws {
                lock.lock()
                _loadCount += 1
                lock.unlock()
                loadStarted.signal()
                allowLoad.wait()
                lock.lock()
                loaded = true
                lock.unlock()
            }
        }

        let loader = BlockingLoader()
        let secondWaiting = DispatchSemaphore(value: 0)
        let runtime = DictionaryRuntime(loader: loader) {
            secondWaiting.signal()
        }
        let completed = expectation(description: "both refreshes completed")
        completed.expectedFulfillmentCount = 2
        let secondCompleted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = runtime.refresh(enabled: true, style: .dauMoi)
            completed.fulfill()
        }
        XCTAssertEqual(loader.loadStarted.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async {
            _ = runtime.refresh(enabled: true, style: .dauMoi)
            secondCompleted.signal()
            completed.fulfill()
        }
        XCTAssertEqual(secondWaiting.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(loader.loadCount, 1)
        loader.allowLoad.signal()

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(secondCompleted.wait(timeout: .now()), .success)
        XCTAssertEqual(loader.loadCount, 1)
    }

    func testOlderStyleCompletionDoesNotOverwriteLatestRequest() {
        final class StyleBlockingLoader: DictionaryLoading {
            let modernStarted = DispatchSemaphore(value: 0)
            let legacyStarted = DispatchSemaphore(value: 0)
            let allowModern = DispatchSemaphore(value: 0)
            let allowLegacy = DispatchSemaphore(value: 0)
            private let lock = NSLock()
            private var loadedStyles: Set<VNDictionaryManager.DictionaryStyle> = []

            func isDictionaryAvailable(style: VNDictionaryManager.DictionaryStyle) -> Bool { true }
            func isDictionaryLoaded(style: VNDictionaryManager.DictionaryStyle) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return loadedStyles.contains(style)
            }
            func loadDictionary(style: VNDictionaryManager.DictionaryStyle) throws {
                let started = style == .dauMoi ? modernStarted : legacyStarted
                let allow = style == .dauMoi ? allowModern : allowLegacy
                started.signal()
                allow.wait()
                lock.lock()
                loadedStyles.insert(style)
                lock.unlock()
            }
        }

        let loader = StyleBlockingLoader()
        let runtime = DictionaryRuntime(loader: loader)
        let modernCompleted = expectation(description: "modern refresh completed")
        let legacyCompleted = expectation(description: "legacy refresh completed")

        DispatchQueue.global().async {
            _ = runtime.refresh(enabled: true, style: .dauMoi)
            modernCompleted.fulfill()
        }
        XCTAssertEqual(loader.modernStarted.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async {
            _ = runtime.refresh(enabled: true, style: .dauCu)
            legacyCompleted.fulfill()
        }
        XCTAssertEqual(loader.legacyStarted.wait(timeout: .now() + 1), .success)

        loader.allowLegacy.signal()
        wait(for: [legacyCompleted], timeout: 1)
        loader.allowModern.signal()
        wait(for: [modernCompleted], timeout: 1)

        XCTAssertEqual(runtime.state, .loaded(.dauCu))
    }
}
