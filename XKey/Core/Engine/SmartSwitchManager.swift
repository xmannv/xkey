//
//  SmartSwitchManager.swift
//  XKey
//
//  Smart switch key - Remember language per app
//  Ported from OpenKey SmartSwitchKey.cpp
//

import Foundation

/// Manages per-app language settings
class SmartSwitchManager {
    
    // MARK: - Properties
    
    private var appLanguageMap: [String: Int] = [:]  // bundleId -> language (0: English, 1: Vietnamese)
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - App Language Management
    
    /// Get language for app, or set default if not found
    /// - Parameters:
    ///   - bundleId: App bundle identifier
    ///   - currentLanguage: Current language to set if not found
    /// - Returns: Language for this app (-1 if not found, 0: English, 1: Vietnamese)
    func getAppLanguage(bundleId: String, currentLanguage: Int) -> Int {
        if let language = appLanguageMap[bundleId] {
            return language
        }
        
        // Not found - set current language as default
        setAppLanguage(bundleId: bundleId, language: currentLanguage)
        return -1
    }
    
    /// Set language for app
    func setAppLanguage(bundleId: String, language: Int) {
        appLanguageMap[bundleId] = language
    }
    
    /// Remove app from map
    func removeApp(bundleId: String) {
        appLanguageMap.removeValue(forKey: bundleId)
    }
    
    /// Clear all app settings
    func clearAll() {
        appLanguageMap.removeAll()
    }
    
    /// Get all app settings
    func getAllApps() -> [(bundleId: String, language: Int)] {
        return appLanguageMap.map { (bundleId: $0.key, language: $0.value) }
    }
    
    // MARK: - File I/O
    
    /// Save to file
    func saveToFile(path: String) -> Bool {
        do {
            let data = try JSONEncoder().encode(appLanguageMap)
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            print("Error saving smart switch data: \(error)")
            return false
        }
    }
    
    /// Load from file
    func loadFromFile(path: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            appLanguageMap = try JSONDecoder().decode([String: Int].self, from: data)
            return true
        } catch {
            print("Error loading smart switch data: \(error)")
            return false
        }
    }
    
    // MARK: - Binary Format (OpenKey compatible)
    
    /// Initialize from binary data (OpenKey format)
    func initFromBinaryData(_ data: Data) {
        guard data.count >= 2 else { return }
        
        var cursor = 0
        
        // Read app count (2 bytes)
        let appCount = data.withUnsafeBytes { $0.load(fromByteOffset: cursor, as: UInt16.self) }
        cursor += 2
        
        appLanguageMap.removeAll()
        
        for _ in 0..<appCount {
            guard cursor < data.count else { break }
            
            // Read bundle ID length (1 byte)
            let bundleIdLength = Int(data[cursor])
            cursor += 1
            
            guard cursor + bundleIdLength <= data.count else { break }
            
            // Read bundle ID
            let bundleIdData = data.subdata(in: cursor..<(cursor + bundleIdLength))
            guard let bundleId = String(data: bundleIdData, encoding: .utf8) else { continue }
            cursor += bundleIdLength
            
            guard cursor < data.count else { break }
            
            // Read language (1 byte)
            let language = Int(data[cursor])
            cursor += 1
            
            appLanguageMap[bundleId] = language
        }
    }
    
    /// Convert to binary data (OpenKey format)
    func toBinaryData() -> Data {
        var data = Data()
        
        // Write app count (2 bytes)
        var appCount = UInt16(appLanguageMap.count)
        data.append(contentsOf: withUnsafeBytes(of: &appCount) { Array($0) })
        
        // Write each app
        for (bundleId, language) in appLanguageMap {
            // Write bundle ID length (1 byte)
            let bundleIdData = bundleId.data(using: .utf8) ?? Data()
            data.append(UInt8(bundleIdData.count))
            
            // Write bundle ID
            data.append(bundleIdData)
            
            // Write language (1 byte)
            data.append(UInt8(language))
        }
        
        return data
    }
}
