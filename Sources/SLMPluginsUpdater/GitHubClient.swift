import CryptoKit
import Foundation

enum GitHubError: LocalizedError {
    case http(Int, String)
    case rateLimited(reset: Date?)

    var errorDescription: String? {
        switch self {
        case let .http(code, path): "GitHub returned HTTP \(code) for \(path)."
        case let .rateLimited(reset):
            "GitHub API rate limit reached"
                + (reset.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
                + ". Add a GitHub token in Settings to raise the limit."
        }
    }
}

/// GitHub REST client with a persistent ETag cache.
/// Revalidations answered with 304 don't count against the rate limit, and cached
/// responses are served (marked stale) when the limit is hit.
final class GitHubClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let token: String?
    private let cacheDir: URL
    private let lock = NSLock()
    private var _staleCount = 0
    private var _rateLimitReset: Date?

    /// Number of responses served from cache because GitHub refused the request.
    var staleCount: Int { lock.withLock { _staleCount } }
    var rateLimitReset: Date? { lock.withLock { _rateLimitReset } }
    var isAuthenticated: Bool { token != nil }

    init(token: String?) {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData // we do our own ETag caching
        config.urlCache = nil
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.token = token
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.slm.pluginsupdater/github", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func repos(owner: String) async throws -> [GitHubRepo] {
        try await get("users/\(owner)/repos?per_page=100&type=owner&sort=pushed")
    }

    func releases(fullName: String) async throws -> [GitHubRelease] {
        try await get("repos/\(fullName)/releases?per_page=30")
    }

    /// Plain download (raw.githubusercontent.com isn't API rate-limited).
    func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubError.http(http.statusCode, url.absoluteString)
        }
        return data
    }

    // MARK: - Private

    private struct CachedResponse: Codable {
        let etag: String
        let body: Data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decoder.decode(T.self, from: try await getData(path))
    }

    private func getData(_ path: String) async throws -> Data {
        let cacheFile = cacheDir.appending(path: cacheKey(path))
        let cached = (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode(CachedResponse.self, from: $0) }

        var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SLM-Plugins-Updater", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let cached { markStale(); return cached.body } // offline: use what we have
            throw error
        }
        guard let http = response as? HTTPURLResponse else { return data }

        switch http.statusCode {
        case 304:
            if let cached { return cached.body }
            throw GitHubError.http(304, path)
        case 200..<300:
            if let etag = http.value(forHTTPHeaderField: "ETag"),
               let encoded = try? JSONEncoder().encode(CachedResponse(etag: etag, body: data)) {
                try? encoded.write(to: cacheFile, options: .atomic)
            }
            return data
        case _ where Self.isRateLimited(http):
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            lock.withLock { _rateLimitReset = reset }
            if let cached { markStale(); return cached.body }
            throw GitHubError.rateLimited(reset: reset)
        default:
            throw GitHubError.http(http.statusCode, path)
        }
    }

    private static func isRateLimited(_ http: HTTPURLResponse) -> Bool {
        http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0")
    }

    private func markStale() {
        lock.withLock { _staleCount += 1 }
    }

    /// Separate cache entries per auth state, since private data may differ.
    private func cacheKey(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(((token == nil ? "anon:" : "auth:") + path).utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}
