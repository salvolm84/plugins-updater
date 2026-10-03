import Foundation

enum GitHubError: LocalizedError {
    case http(Int, String)
    case rateLimited(reset: Date?)

    var errorDescription: String? {
        switch self {
        case let .http(code, path): "GitHub returned HTTP \(code) for \(path)."
        case let .rateLimited(reset):
            if let reset { "GitHub API rate limit reached. Try again after \(reset.formatted(date: .omitted, time: .shortened))." }
            else { "GitHub API rate limit reached. Try again later." }
        }
    }
}

struct GitHubClient {
    static let shared = GitHubClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        // A disk cache lets URLSession revalidate with ETags; 304 responses don't count against the rate limit.
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    func repos(owner: String) async throws -> [GitHubRepo] {
        try await get("users/\(owner)/repos?per_page=100&type=owner&sort=pushed")
    }

    func releases(fullName: String) async throws -> [GitHubRelease] {
        try await get("repos/\(fullName)/releases?per_page=30")
    }

    func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubError.http(http.statusCode, url.absoluteString)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SLM-Plugins-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 429,
               http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                throw GitHubError.rateLimited(reset: reset)
            }
            throw GitHubError.http(http.statusCode, path)
        }
        return try decoder.decode(T.self, from: data)
    }
}
