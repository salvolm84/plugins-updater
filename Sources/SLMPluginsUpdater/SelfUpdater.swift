import AppKit
import Foundation

enum SelfUpdateError: LocalizedError {
    case noAsset
    case noApp
    case wrongVersion(String?)
    case notInAppBundle

    var errorDescription: String? {
        switch self {
        case .noAsset: "The release has no macOS download."
        case .noApp: "The download doesn't contain SLM Plugins Updater."
        case let .wrongVersion(v): "The downloaded app reports version \(v ?? "?"), not the release version."
        case .notInAppBundle: "This copy isn't running from an .app bundle (development build), so it can't replace itself."
        }
    }
}

/// Keeps this app current from its own GitHub releases.
enum SelfUpdater {
    static let repo = "salvolm84/plugins-updater"

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.slm.pluginsupdater" }

    /// `nil` for `swift build` binaries, which have no Info.plist.
    static var currentVersion: Version? {
        if let fake = ProcessInfo.processInfo.environment["SLM_UPDATER_FAKE_VERSION"] { return Version(fake) }
        return (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Version.init)
    }

    static var appURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// Replacing the bundle needs a password when its folder isn't writable (e.g. /Applications for a standard user).
    static var needsAdmin: Bool {
        guard let appURL else { return false }
        let fm = FileManager.default
        return !fm.isWritableFile(atPath: appURL.deletingLastPathComponent().path) || !fm.isWritableFile(atPath: appURL.path)
    }

    static func asset(in release: GitHubRelease) -> GitHubAsset? {
        let zips = release.assets.filter(AssetFilter.isMacAsset)
        return zips.first { $0.name.lowercased().contains("arm64") || $0.name.lowercased().contains("universal") } ?? zips.first
    }

    /// The newest usable release if it's newer than this build.
    static func newerRelease(in releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        guard let current = currentVersion else { return nil }
        return releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) && asset(in: $0) != nil }
            .compactMap { r in r.version.map { (r, $0) } }
            .filter { $0.1 > current }
            .max { $0.1 < $1.1 }?.0
    }

    /// Downloads, verifies and swaps in the new bundle. The running process keeps using the old binary until it relaunches.
    static func install(_ release: GitHubRelease, progress: @escaping @MainActor (String) -> Void) async throws {
        guard let appURL else { throw SelfUpdateError.notInAppBundle }
        guard let asset = asset(in: release) else { throw SelfUpdateError.noAsset }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "SLMPluginsUpdater-self-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        await progress("Downloading \(release.tagName)…")
        let (tmp, response) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubError.http(http.statusCode, asset.name)
        }
        let zip = staging.appending(path: asset.name)
        try fm.moveItem(at: tmp, to: zip)

        await progress("Unpacking…")
        let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
        try await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        guard let newApp = findApp(in: unpacked) else { throw SelfUpdateError.noApp }
        let newVersion = InstalledBundle(url: newApp)?.version
        guard let expected = release.version, newVersion.flatMap(Version.init) == expected else {
            throw SelfUpdateError.wrongVersion(newVersion)
        }

        await progress("Verifying…")
        _ = try? await Shell.run("/usr/bin/xattr", ["-rd", "com.apple.quarantine", newApp.path])
        try await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

        await progress("Installing…")
        if needsAdmin {
            try await Shell.runAsAdmin(
                "rm -rf \(Shell.quote(appURL.path)) && /usr/bin/ditto \(Shell.quote(newApp.path)) \(Shell.quote(appURL.path))"
                    + " && /usr/bin/xattr -rd com.apple.quarantine \(Shell.quote(appURL.path)) 2>/dev/null; true",
                prompt: "SLM Plugins Updater wants to update itself to \(newVersion ?? "the latest version")."
            )
        } else {
            // Move the old copy aside first so a failed copy can be rolled back.
            let backup = staging.appending(path: "previous.app")
            try fm.moveItem(at: appURL, to: backup)
            do {
                try await Shell.run("/usr/bin/ditto", [newApp.path, appURL.path])
            } catch {
                try? fm.removeItem(at: appURL)
                try? fm.moveItem(at: backup, to: appURL)
                throw error
            }
            // The old version goes to the Trash rather than being deleted outright.
            _ = try? fm.trashItem(at: backup, resultingItemURL: nil)
        }
    }

    /// Waits for this process to exit, then opens the (new) bundle.
    static func relaunch() {
        guard let appURL else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(Shell.quote(appURL.path))"]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "app" {
            enumerator.skipDescendants()
            if InstalledBundle(url: url)?.bundleID == bundleID { return url }
        }
        return nil
    }
}
