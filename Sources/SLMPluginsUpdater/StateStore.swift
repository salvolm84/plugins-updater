import Foundation

/// What this app installed, so versions stay correct even when a bundle's Info.plist isn't bumped.
struct InstallRecord: Codable {
    struct Bundle: Codable {
        let path: String
        let bundleID: String?
        let bundleVersion: String?
    }

    let tag: String
    let installedAt: Date
    let bundles: [Bundle]
}

struct StateStore {
    static let shared = StateStore()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SLM Plugins Updater", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "installed.json")
    }()

    func load() -> [String: InstallRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: InstallRecord].self, from: data)) ?? [:]
    }

    func save(_ records: [String: InstallRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}
