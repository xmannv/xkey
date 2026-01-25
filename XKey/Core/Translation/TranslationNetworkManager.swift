//
//  TranslationNetworkManager.swift
//  XKey
//
//  Shared network manager for all translation providers
//  Reduces memory usage by reusing a single URLSession
//

import Foundation

/// Shared network manager for translation providers
/// Using a single URLSession instead of one per provider saves ~20-30MB of memory
final class TranslationNetworkManager {
    
    // MARK: - Singleton
    
    static let shared = TranslationNetworkManager()
    
    // MARK: - Properties
    
    /// Shared URLSession for all translation requests
    let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        
        // Limit connection pool to reduce memory footprint
        config.httpMaximumConnectionsPerHost = 2
        
        // Disable caching to reduce memory usage
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: config)
    }
}
