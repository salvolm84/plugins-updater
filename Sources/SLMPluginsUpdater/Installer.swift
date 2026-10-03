import Foundation

enum InstallError: LocalizedError {
    case noAssets
    case noBundles

    var errorDescription: String? {
        switch self {
        case .noAssets: "The release has no macOS downloads for the enabled formats."
        case .noBundles: "The download contains no plug-in bundles for the enabled formats."
        }
    }
}

/// One bundle ready to be copied into place.
struct PlannedCopy {
    let source: URL
    let destination: URL
    /// An existing copy (possibly with a different file name) that the new one replaces.
    let replacing: URL?
    let needsAdmin: Bool
    let bundleID: String?
    let bundleVersion: String?
}

struct StagedInstall {
    let item: PluginItem
    let stagingDir: URL
    let copies: [PlannedCopy]
}

enum Installer {
    /// Downloads and unzips the release, and works out where every bundle goes.
    static func stage(_ item: PluginItem, formats: Set<PluginFormat>, progress: @escaping @MainActor (String) -> Void) async throws -> StagedInstall {
        let assets = item.latest.assets.filter { asset in
            guard AssetFilter.isMacAsset(asset) else { return false }
            guard let hint = AssetFilter.formatHint(asset) else { return true }
            return formats.contains(hint)
        }
        guard !assets.isEmpty else { throw InstallError.noAssets }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "SLMPluginsUpdater-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            var bundles: [URL] = []
            for asset in assets {
                await progress("Downloading \(asset.name)…")
                let (tmp, response) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw GitHubError.http(http.statusCode, asset.name)
                }
                let zip = staging.appending(path: asset.name)
                try fm.moveItem(at: tmp, to: zip)

                await progress("Unpacking \(asset.name)…")
                let unpackDir = staging.appending(path: "unpacked-\(asset.id)", directoryHint: .isDirectory)
                try await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpackDir.path])
                bundles += findBundles(in: unpackDir)
            }

            let wanted = bundles.filter { url in PluginFormat(fileExtension: url.pathExtension).map(formats.contains) ?? false }
            guard !wanted.isEmpty else { throw InstallError.noBundles }
            let copies = wanted.compactMap { plan(source: $0, item: item) }
            return StagedInstall(item: item, stagingDir: staging, copies: copies)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Copies the bundles that don't need root. Returns the shell commands for the ones that do.
    static func copyUserBundles(_ staged: StagedInstall) async throws -> [String] {
        let fm = FileManager.default
        var adminCommands: [String] = []
        for copy in staged.copies {
            if copy.needsAdmin {
                if let old = copy.replacing { adminCommands.append("rm -rf \(Shell.quote(old.path))") }
                adminCommands.append("rm -rf \(Shell.quote(copy.destination.path))")
                adminCommands.append("/usr/bin/ditto \(Shell.quote(copy.source.path)) \(Shell.quote(copy.destination.path))")
                continue
            }
            try fm.createDirectory(at: copy.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Old versions go to the Trash rather than being deleted outright.
            for old in [copy.replacing, copy.destination].compactMap({ $0 }) where fm.fileExists(atPath: old.path) {
                if (try? fm.trashItem(at: old, resultingItemURL: nil)) == nil {
                    try fm.removeItem(at: old)
                }
            }
            try await Shell.run("/usr/bin/ditto", [copy.source.path, copy.destination.path])
        }
        return adminCommands
    }

    static func quarantineCommand(for paths: [URL]) -> String {
        paths.map { "/usr/bin/xattr -rd com.apple.quarantine \(Shell.quote($0.path)) 2>/dev/null" }.joined(separator: "; ") + "; true"
    }

    static func cleanUp(_ staged: StagedInstall) {
        try? FileManager.default.removeItem(at: staged.stagingDir)
    }

    // MARK: - Helpers

    private static func findBundles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var found: [URL] = []
        for url in entries where url.lastPathComponent != "__MACOSX" && !url.lastPathComponent.hasPrefix("._") {
            if PluginFormat(fileExtension: url.pathExtension) != nil {
                found.append(url) // don't descend into bundles
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                found += findBundles(in: url)
            }
        }
        return found
    }

    private static func plan(source: URL, item: PluginItem) -> PlannedCopy? {
        guard let format = PluginFormat(fileExtension: source.pathExtension) else { return nil }
        let new = InstalledBundle(url: source)
        let sameFormat = item.installed.filter { $0.format == format }
        // Replace the copy with the same file name first, then one with the same bundle ID.
        let existing = sameFormat.first { $0.url.lastPathComponent == source.lastPathComponent }
            ?? sameFormat.first { b in
                guard let id = b.bundleID, let newID = new?.bundleID else { return false }
                return id.caseInsensitiveCompare(newID) == .orderedSame
            }
        let directory = existing?.url.deletingLastPathComponent() ?? format.defaultInstallDirectory
        let destination = directory.appending(path: source.lastPathComponent)
        let fm = FileManager.default
        let writableDir = fm.fileExists(atPath: directory.path) ? fm.isWritableFile(atPath: directory.path)
            : directory.path.hasPrefix(fm.homeDirectoryForCurrentUser.path)
        let replacing = existing.map(\.url).flatMap { $0.path == destination.path ? nil : $0 }
        return PlannedCopy(
            source: source,
            destination: destination,
            replacing: replacing,
            needsAdmin: !writableDir,
            bundleID: new?.bundleID,
            bundleVersion: new?.version
        )
    }
}
