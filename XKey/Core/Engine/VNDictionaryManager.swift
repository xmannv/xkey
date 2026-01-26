import Foundation

/// Manager for Vietnamese dictionary files for spell checking
/// Stores dictionaries in App Group container for sharing between XKey and XKeyIM
class VNDictionaryManager {
    static let shared = VNDictionaryManager()

    // Dictionary URLs from hunspell-vi repository
    private let dictionaryURLs = [
        "DauMoi": "https://raw.githubusercontent.com/xmannv/hunspell-vi/master/dictionaries/vi-DauMoi.dic",
        "DauCu": "https://raw.githubusercontent.com/xmannv/hunspell-vi/master/dictionaries/vi-DauCu.dic"
    ]

    // In-memory dictionary cache
    private var wordSets: [String: Set<String>] = [:]
    private var isLoading = false

    // App Group identifier (same as SharedSettings)
    private let appGroupIdentifier = "7E6Z9B4F2H.com.codetay.inputmethod.XKey"

    // Local storage path in App Group (shared between XKey and XKeyIM)
    private var dictionaryDirectory: URL {
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

    private init() {}

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
        guard let wordSet = wordSets[style.rawValue] else {
            return false // Dictionary not loaded
        }

        return wordSet.contains(normalized)
    }

    /// Check if dictionaries are available locally
    func isDictionaryAvailable(style: DictionaryStyle = .dauMoi) -> Bool {
        let localPath = dictionaryDirectory.appendingPathComponent("vi-\(style.rawValue).dic")
        return FileManager.default.fileExists(atPath: localPath.path)
    }

    /// Check if dictionary is loaded in memory
    func isDictionaryLoaded(style: DictionaryStyle = .dauMoi) -> Bool {
        return wordSets[style.rawValue] != nil
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
                try data.write(to: localPath)
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

        guard FileManager.default.fileExists(atPath: localPath.path) else {
            DebugLogger.shared.log("[VNDict] File not found at: \(localPath.path)")
            throw DictionaryError.fileNotFound
        }

        let content = try String(contentsOf: localPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // First line is word count, skip it
        var words = Set<String>()
        for (index, line) in lines.enumerated() {
            guard index > 0, !line.isEmpty else { continue }

            // Some entries may have flags (e.g., "word/flags"), we only need the word part
            let word = line.components(separatedBy: "/").first ?? line
            words.insert(word.lowercased().trimmingCharacters(in: .whitespaces))
        }

        wordSets[style.rawValue] = words
        DebugLogger.shared.log("Loaded \(words.count) words from \(style.rawValue) dictionary")
    }

    /// Download and load dictionary in one go
    func downloadAndLoad(style: DictionaryStyle = .dauMoi, completion: @escaping (Result<Void, Error>) -> Void) {
        downloadDictionary(style: style) { [weak self] result in
            switch result {
            case .success:
                do {
                    try self?.loadDictionary(style: style)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Load dictionary if available locally, otherwise do nothing
    func loadIfAvailable(style: DictionaryStyle = .dauMoi) {
        guard isDictionaryAvailable(style: style), !isDictionaryLoaded(style: style) else {
            return
        }

        try? loadDictionary(style: style)
    }

    /// Get dictionary statistics
    func getDictionaryStats() -> [String: Int] {
        var stats: [String: Int] = [:]
        for (key, wordSet) in wordSets {
            stats[key] = wordSet.count
        }
        return stats
    }
    
    /// Estimate memory usage of loaded dictionaries in bytes
    /// Each Vietnamese word averages ~10 characters × 2 bytes (UTF-16) + Set overhead
    func getEstimatedMemoryUsage() -> Int {
        var totalBytes = 0
        for (_, wordSet) in wordSets {
            // Estimate: average word length × 2 bytes (UTF-16) + 24 bytes overhead per word
            let avgWordLength = 10
            let bytesPerWord = avgWordLength * 2 + 24  // UTF-16 + String/Set overhead
            totalBytes += wordSet.count * bytesPerWord
        }
        return totalBytes
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
        if !wordSets.isEmpty {
            let memoryBefore = getMemoryUsageString()
            let wordCount = wordSets.values.reduce(0) { $0 + $1.count }
            wordSets.removeAll()
            DebugLogger.shared.log("[VNDict] Cleared dictionary cache: \(wordCount) words, freed ~\(memoryBefore)")
        }
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
            }
        }
    }
}
