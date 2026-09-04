import Foundation

struct DictionaryFileSignature: Equatable {
    let modificationTime: TimeInterval
    let fileSize: UInt64
    let fileIdentifier: UInt64?
}

/// Manager for Vietnamese dictionary files for spell checking
/// Stores dictionaries in App Group container for sharing between XKey and XKeyIM
class VNDictionaryManager: DictionaryLoading {
    static let shared = VNDictionaryManager()

    typealias AvailabilityProvider = (URL) -> Bool
    typealias SignatureProvider = (URL) throws -> DictionaryFileSignature?
    typealias ContentReader = (URL) throws -> String

    // Dictionary URLs from hunspell-vi repository
    private let dictionaryURLs = [
        "DauMoi": "https://raw.githubusercontent.com/xmannv/hunspell-vi/master/dictionaries/vi-DauMoi.dic",
        "DauCu": "https://raw.githubusercontent.com/xmannv/hunspell-vi/master/dictionaries/vi-DauCu.dic"
    ]

    // In-memory dictionary cache
    private var wordSets: [String: Set<String>] = [:]
    private var loadedSignatures: [String: DictionaryFileSignature] = [:]
    private let cacheLock = NSLock()
    private let dictionaryDirectoryOverride: URL?
    private let availabilityProvider: AvailabilityProvider
    private let signatureProvider: SignatureProvider
    private let contentReader: ContentReader

    // App Group identifier (same as SharedSettings)
    private let appGroupIdentifier = "7E6Z9B4F2H.com.codetay.inputmethod.XKey"

    // Local storage path in App Group (shared between XKey and XKeyIM)
    private var dictionaryDirectory: URL {
        if let dictionaryDirectoryOverride {
            return dictionaryDirectoryOverride
        }

        // Use the same App Group as SharedSettings for cross-app dictionary sharing
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            // Fallback to Application Support if App Group is not available
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dictDir = appSupport.appendingPathComponent("XKey/Dictionaries")
            try? FileManager.default.createDirectory(at: dictDir, withIntermediateDirectories: true)
            return dictDir
        }

        let dictDir = containerURL.appendingPathComponent("Dictionaries")
        try? FileManager.default.createDirectory(at: dictDir, withIntermediateDirectories: true)
        return dictDir
    }

    init(dictionaryDirectory: URL? = nil,
         availabilityProvider: @escaping AvailabilityProvider = { FileManager.default.fileExists(atPath: $0.path) },
         signatureProvider: @escaping SignatureProvider = VNDictionaryManager.fileSignature,
         contentReader: @escaping ContentReader = VNDictionaryManager.readDictionary) {
        dictionaryDirectoryOverride = dictionaryDirectory
        self.availabilityProvider = availabilityProvider
        self.signatureProvider = signatureProvider
        self.contentReader = contentReader
    }

    // MARK: - Public API

    /// Check if a word exists in the dictionary (either user dictionary or hunspell dictionary)
    func isValidWord(_ word: String, style: DictionaryStyle = .dauMoi) -> Bool {
        // Normalize the word (lowercase and remove tones for checking)
        let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
        
        // First, check user dictionary (custom words defined by user)
        if SharedSettings.shared.isWordInUserDictionary(normalized) {
            return true // Word is in user dictionary, skip spell check
        }
        
        // Then check hunspell dictionary
        cacheLock.lock()
        let wordSet = wordSets[style.rawValue]
        cacheLock.unlock()
        guard let wordSet else {
            return false // Dictionary not loaded
        }

        return wordSet.contains(normalized)
    }

    /// Check if dictionaries are available locally
    func isDictionaryAvailable(style: DictionaryStyle = .dauMoi) -> Bool {
        let localPath = dictionaryDirectory.appendingPathComponent("vi-\(style.rawValue).dic")
        return availabilityProvider(localPath)
    }

    /// Check if dictionary is loaded in memory
    func isDictionaryLoaded(style: DictionaryStyle = .dauMoi) -> Bool {
        let localPath = dictionaryDirectory.appendingPathComponent("vi-\(style.rawValue).dic")
        guard let currentSignature = try? signatureProvider(localPath) else { return false }

        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = style.rawValue
        return wordSets[key] != nil && loadedSignatures[key] == currentSignature
    }

    /// Get the directory where dictionaries are stored
    func getDictionaryDirectoryURL() -> URL {
        return dictionaryDirectory
    }

    /// Download dictionary from repository
    func downloadDictionary(style: DictionaryStyle = .dauMoi, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let urlString = dictionaryURLs[style.rawValue],
              let url = URL(string: urlString) else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        DebugLogger.shared.log("[VNDict] Starting download from: \(urlString)")
        DebugLogger.shared.log("[VNDict] Target directory: \(dictionaryDirectory.path)")

        // Use URLRequest with cache policy to always fetch fresh data from server
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DebugLogger.shared.log("[VNDict] Download error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                DebugLogger.shared.log("[VNDict] HTTP status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    completion(.failure(DictionaryError.noData))
                    return
                }
            }

            guard let data = data, !data.isEmpty else {
                DebugLogger.shared.log("[VNDict] No data received")
                completion(.failure(DictionaryError.noData))
                return
            }

            DebugLogger.shared.log("[VNDict] Received \(data.count) bytes")

            // Save to local storage
            let localPath = self.dictionaryDirectory.appendingPathComponent("vi-\(style.rawValue).dic")
            DebugLogger.shared.log("[VNDict] Saving to: \(localPath.path)")

            do {
                try data.write(to: localPath, options: .atomic)
                // Verify file was written
                let exists = FileManager.default.fileExists(atPath: localPath.path)
                DebugLogger.shared.log("[VNDict] File saved, exists: \(exists)")
                completion(.success(()))
            } catch {
                DebugLogger.shared.log("[VNDict] Write error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Load dictionary from local storage into memory
    func loadDictionary(style: DictionaryStyle = .dauMoi) throws {
        let localPath = dictionaryDirectory.appendingPathComponent("vi-\(style.rawValue).dic")
        DebugLogger.shared.log("[VNDict] Loading from: \(localPath.path)")

        for _ in 0..<3 {
            guard let signatureBeforeRead = try signatureProvider(localPath) else {
                DebugLogger.shared.log("[VNDict] File not found at: \(localPath.path)")
                throw DictionaryError.fileNotFound
            }
            let words = parseDictionary(content: try contentReader(localPath))
            guard let signatureAfterRead = try signatureProvider(localPath),
                  signatureBeforeRead == signatureAfterRead else {
                continue
            }

            guard try signatureProvider(localPath) == signatureAfterRead else {
                continue
            }

            cacheLock.lock()
            wordSets[style.rawValue] = words
            loadedSignatures[style.rawValue] = signatureAfterRead
            cacheLock.unlock()

            DebugLogger.shared.log("Loaded \(words.count) words from \(style.rawValue) dictionary")
            return
        }

        throw DictionaryError.fileChangedDuringLoad
    }

    /// Download and load dictionary in one go
    func downloadAndLoad(style: DictionaryStyle = .dauMoi, completion: @escaping (Result<Void, Error>) -> Void) {
        downloadDictionary(style: style) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let preferences = SharedSettings.shared.loadPreferences()
                let selectedStyle: DictionaryStyle = preferences.modernStyle ? .dauMoi : .dauCu
                if Self.shouldLoadDownloadedDictionary(
                    style: style,
                    spellCheckEnabled: preferences.spellCheckEnabled,
                    selectedStyle: selectedStyle
                ) {
                    let refreshResult = DictionaryRuntime.shared.refresh(enabled: true, style: style)
                    guard self.isDictionaryLoaded(style: style) else {
                        completion(.failure(DictionaryError.loadFailed(
                            refreshResult.diagnostic ?? "Current dictionary file was not loaded"
                        )))
                        return
                    }
                }
                DistributedNotificationCenter.default().postNotificationName(
                    .xkeySettingsDidChange,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Load dictionary if available locally, otherwise do nothing
    func loadIfAvailable(style: DictionaryStyle = .dauMoi) {
        _ = DictionaryRuntime.shared.refresh(enabled: true, style: style)
    }

    /// Get dictionary statistics
    func getDictionaryStats() -> [String: Int] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return wordSets.mapValues(\.count)
    }
    
    /// Estimate memory usage of loaded dictionaries in bytes
    /// Each Vietnamese word averages ~10 characters × 2 bytes (UTF-16) + Set overhead
    func getEstimatedMemoryUsage() -> Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return estimatedMemoryUsage(for: wordSets)
    }
    
    /// Human-readable memory usage string
    func getMemoryUsageString() -> String {
        let bytes = getEstimatedMemoryUsage()
        if bytes == 0 {
            return "0 KB"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    /// Clear loaded dictionaries from memory
    func clearCache() {
        cacheLock.lock()
        let wordCount = wordSets.values.reduce(0) { $0 + $1.count }
        let memoryBefore = estimatedMemoryUsage(for: wordSets)
        wordSets.removeAll()
        loadedSignatures.removeAll()
        cacheLock.unlock()

        guard wordCount > 0 else { return }
        DebugLogger.shared.log("[VNDict] Cleared dictionary cache: \(wordCount) words, freed ~\(formatMemoryUsage(memoryBefore))")
    }

    /// Delete local dictionary files
    func deleteLocalDictionaries() throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: dictionaryDirectory, includingPropertiesForKeys: nil)
        for url in contents where url.pathExtension == "dic" {
            try fileManager.removeItem(at: url)
        }
        clearCache()
    }

    private func parseDictionary(content: String) -> Set<String> {
        var words = Set<String>()
        for (index, line) in content.components(separatedBy: .newlines).enumerated() {
            guard index > 0, !line.isEmpty else { continue }
            let word = line.components(separatedBy: "/").first ?? line
            words.insert(word.lowercased().trimmingCharacters(in: .whitespaces))
        }
        return words
    }

    private func estimatedMemoryUsage(for dictionaries: [String: Set<String>]) -> Int {
        let avgWordLength = 10
        let bytesPerWord = avgWordLength * 2 + 24
        return dictionaries.values.reduce(0) { $0 + $1.count * bytesPerWord }
    }

    private func formatMemoryUsage(_ bytes: Int) -> String {
        if bytes == 0 {
            return "0 KB"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    nonisolated static func fileSignature(at url: URL) throws -> DictionaryFileSignature? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            throw error
        }
        guard let modificationDate = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? NSNumber else {
            throw DictionaryError.fileAttributesUnavailable
        }
        return DictionaryFileSignature(
            modificationTime: modificationDate.timeIntervalSinceReferenceDate,
            fileSize: fileSize.uint64Value,
            fileIdentifier: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }

    nonisolated static func readDictionary(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func shouldLoadDownloadedDictionary(style: DictionaryStyle,
                                               spellCheckEnabled: Bool,
                                               selectedStyle: DictionaryStyle) -> Bool {
        spellCheckEnabled && style == selectedStyle
    }
}

// MARK: - Supporting Types

extension VNDictionaryManager {
    enum DictionaryStyle: String {
        case dauMoi = "DauMoi"  // Reformed style (common in Vietnam)
        case dauCu = "DauCu"    // Traditional style (common abroad)
    }

    enum DictionaryError: LocalizedError {
        case invalidURL
        case noData
        case fileNotFound
        case parseError
        case loadFailed(String)
        case fileChangedDuringLoad
        case fileAttributesUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid dictionary URL"
            case .noData:
                return "No data received from server"
            case .fileNotFound:
                return "Dictionary file not found locally"
            case .parseError:
                return "Failed to parse dictionary file"
            case .loadFailed(let message):
                return message
            case .fileChangedDuringLoad:
                return "Dictionary file kept changing while loading"
            case .fileAttributesUnavailable:
                return "Dictionary file attributes are unavailable"
            }
        }
    }
}
