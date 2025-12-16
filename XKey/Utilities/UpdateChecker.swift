//
//  UpdateChecker.swift
//  XKey
//
//  Service to check for updates from GitHub releases
//

import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let htmlUrl: String
    let publishedAt: String
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case body
    }
}

enum UpdateStatus: Equatable {
    case checking
    case upToDate
    case updateAvailable(version: String, url: String, releaseNotes: String)
    case error(String)
}

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateStatus: UpdateStatus = .upToDate
    
    private let currentVersion: String
    private let repoURL = "https://api.github.com/repos/xmannv/xkey/releases/latest"
    
    init(currentVersion: String = AppVersion.current) {
        self.currentVersion = currentVersion
    }
    
    func checkForUpdates() async {
        updateStatus = .checking
        
        guard let url = URL(string: repoURL) else {
            updateStatus = .error("URL không hợp lệ")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                updateStatus = .error("Phản hồi không hợp lệ")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                updateStatus = .error("Lỗi HTTP: \(httpResponse.statusCode)")
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            
            if compareVersions(latestVersion, currentVersion) > 0 {
                updateStatus = .updateAvailable(
                    version: latestVersion,
                    url: release.htmlUrl,
                    releaseNotes: release.body ?? ""
                )
            } else {
                updateStatus = .upToDate
            }
            
        } catch {
            updateStatus = .error("Không thể kiểm tra cập nhật: \(error.localizedDescription)")
        }
    }
    
    /// Compare two semantic versions
    /// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let v1Parts = v1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Parts.count, v2Parts.count)
        
        for i in 0..<maxLength {
            let v1Part = i < v1Parts.count ? v1Parts[i] : 0
            let v2Part = i < v2Parts.count ? v2Parts[i] : 0
            
            if v1Part > v2Part {
                return 1
            } else if v1Part < v2Part {
                return -1
            }
        }
        
        return 0
    }
}
