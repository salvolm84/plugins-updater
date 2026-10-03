import Foundation

// MARK: - GitHub API

struct GitHubRepo: Decodable, Hashable {
    let name: String
    let fullName: String
    let description: String?
    let fork: Bool
    let archived: Bool
    let htmlUrl: URL
    var topics: [String]? = nil

    static let pluginTopics: Set<String> = ["audio-plugin", "audio-plugins", "vst", "vst3", "audio-unit", "audiounit", "au", "clap", "juce", "daw"]
    var hasPluginTopic: Bool { !(topics ?? []).filter { Self.pluginTopics.contains($0.lowercased()) }.isEmpty }
}

struct GitHubRelease: Decodable, Hashable, Identifiable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let htmlUrl: URL
    let assets: [GitHubAsset]

    var version: Version? { Version(tagName) }
    var title: String { (name?.isEmpty == false ? name! : tagName) }
}

struct GitHubAsset: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let size: Int
    let browserDownloadUrl: URL
}

// MARK: - Plugin formats

enum PluginFormat: String, Codable, CaseIterable, Identifiable {
    case vst3, au, clap, app

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .vst3: "vst3"
        case .au: "component"
        case .clap: "clap"
        case .app: "app"
        }
    }

    var displayName: String {
        switch self {
        case .vst3: "VST3"
        case .au: "Audio Unit"
        case .clap: "CLAP"
        case .app: "Standalone app"
        }
    }

    var shortName: String {
        switch self {
        case .vst3: "VST3"
        case .au: "AU"
        case .clap: "CLAP"
        case .app: "App"
        }
    }

    init?(fileExtension ext: String) {
        guard let match = PluginFormat.allCases.first(where: { $0.fileExtension == ext.lowercased() }) else { return nil }
        self = match
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Where new installs go when nothing is installed yet.
    var defaultInstallDirectory: URL {
        switch self {
        case .vst3: Self.home.appending(path: "Library/Audio/Plug-Ins/VST3")
        case .au: Self.home.appending(path: "Library/Audio/Plug-Ins/Components")
        case .clap: Self.home.appending(path: "Library/Audio/Plug-Ins/CLAP")
        case .app: URL(filePath: "/Applications")
        }
    }

    /// Every place an existing copy may live (user and system domains).
    var searchDirectories: [URL] {
        switch self {
        case .vst3: [defaultInstallDirectory, URL(filePath: "/Library/Audio/Plug-Ins/VST3")]
        case .au: [defaultInstallDirectory, URL(filePath: "/Library/Audio/Plug-Ins/Components")]
        case .clap: [defaultInstallDirectory, URL(filePath: "/Library/Audio/Plug-Ins/CLAP")]
        case .app: [defaultInstallDirectory, Self.home.appending(path: "Applications")]
        }
    }
}

// MARK: - Local bundles

struct InstalledBundle: Hashable, Identifiable {
    let url: URL
    let bundleID: String?
    let version: String?
    let format: PluginFormat

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    init?(url: URL) {
        guard let format = PluginFormat(fileExtension: url.pathExtension) else { return nil }
        let plist = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
        self.url = url
        self.format = format
        self.bundleID = plist?["CFBundleIdentifier"] as? String
        self.version = (plist?["CFBundleShortVersionString"] as? String) ?? (plist?["CFBundleVersion"] as? String)
    }
}

// MARK: - Plugin item shown in the UI

enum PluginStatus: Comparable {
    case updateAvailable
    case notInstalled
    case unknownVersion
    case upToDate
}

struct PluginItem: Identifiable, Hashable {
    let repo: GitHubRepo
    let displayName: String
    let latest: GitHubRelease
    let releases: [GitHubRelease]
    let installed: [InstalledBundle]
    let installedVersion: Version?

    var id: String { repo.fullName }

    var status: PluginStatus {
        if installed.isEmpty { return .notInstalled }
        guard let installedVersion, let latestVersion = latest.version else { return .unknownVersion }
        return latestVersion > installedVersion ? .updateAvailable : .upToDate
    }

    var installedFormats: [PluginFormat] {
        PluginFormat.allCases.filter { f in installed.contains { $0.format == f } }
    }

    /// Formats this release ships, guessed from asset names (refined after unzip).
    var offeredFormats: [PluginFormat] {
        let hints = latest.assets.filter(AssetFilter.isMacAsset).compactMap(AssetFilter.formatHint)
        return PluginFormat.allCases.filter(hints.contains)
    }
}

// MARK: - Asset filtering

enum AssetFilter {
    static func isMacAsset(_ asset: GitHubAsset) -> Bool {
        let n = asset.name.lowercased()
        guard n.hasSuffix(".zip") else { return false }
        if ["windows", "win64", "win32", "linux", "ubuntu"].contains(where: n.contains) { return false }
        if (n.contains("x86_64") || n.contains("intel")) && !n.contains("universal") { return false }
        return ["mac", "osx", "darwin", "vst3", "component", "-au", "_au", "clap"].contains(where: n.contains)
    }

    /// For repos not in the catalog: only an explicit plug-in format in an asset name counts.
    static func looksLikePlugin(_ release: GitHubRelease) -> Bool {
        release.assets.filter(isMacAsset).contains { formatHint($0) != nil || $0.name.lowercased().contains("plugin") }
    }

    /// Best-effort guess of the format inside a zip, `nil` when it may contain several.
    static func formatHint(_ asset: GitHubAsset) -> PluginFormat? {
        let n = asset.name.lowercased()
        let hasAU = n.contains("-au.") || n.contains("-au-") || n.contains("_au.") || n.contains("_au_") || n.contains("component")
        let hasVST3 = n.contains("vst3")
        let hasCLAP = n.contains("clap")
        switch (hasAU, hasVST3, hasCLAP) {
        case (true, false, false): return .au
        case (false, true, false): return .vst3
        case (false, false, true): return .clap
        default: return nil
        }
    }
}
