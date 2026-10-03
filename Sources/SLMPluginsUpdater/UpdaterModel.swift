import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdaterModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let message: String
        let isError: Bool
    }

    enum InstallState: Equatable {
        case working(String)
        case done
        case failed(String)
    }

    private(set) var plugins: [PluginItem] = []
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var lastChecked: Date?
    private(set) var lastCheckSummary: String?
    var errorMessage: String?
    private(set) var installStates: [String: InstallState] = [:]
    private(set) var log: [LogEntry] = []

    /// Plugins waiting for the user to confirm in the changelog sheet.
    var pendingConfirmation: [PluginItem]?

    var updates: [PluginItem] { plugins.filter { $0.status == .updateAvailable } }
    var newInstalls: [PluginItem] { plugins.filter { $0.status == .notInstalled } }
    var upToDate: [PluginItem] { plugins.filter { $0.status == .upToDate || $0.status == .unknownVersion } }

    var owner: String { UserDefaults.standard.string(forKey: Prefs.owner) ?? "salvolm84" }
    var includePrereleases: Bool { UserDefaults.standard.bool(forKey: Prefs.includePrereleases) }

    private var records = StateStore.shared.load()

    // MARK: - Checking

    func refresh() async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let owner = owner
            let includePre = includePrereleases
            async let catalogTask = Catalog.load()
            let repos = try await GitHubClient.shared.repos(owner: owner)
            let catalog = await catalogTask
            let candidates = repos.filter { !$0.fork && !$0.archived && !catalog.isIgnored($0.name) }

            let withReleases = try await withThrowingTaskGroup(of: (GitHubRepo, [GitHubRelease]).self) { group in
                for repo in candidates {
                    group.addTask { (repo, try await GitHubClient.shared.releases(fullName: repo.fullName)) }
                }
                var out: [(GitHubRepo, [GitHubRelease])] = []
                for try await pair in group { out.append(pair) }
                return out
            }

            let local = await Task.detached { LocalScanner.scan() }.value
            plugins = withReleases.compactMap { repo, releases in
                makeItem(repo: repo, releases: releases, catalog: catalog, local: local, includePrereleases: includePre)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            lastChecked = Date()
            lastCheckSummary = "\(updates.count) update(s), \(newInstalls.count) new, \(upToDate.count) up to date"
            append("Checked \(plugins.count) plugins from github.com/\(owner): \(lastCheckSummary!).")
        } catch {
            errorMessage = error.localizedDescription
            append("Check failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func makeItem(repo: GitHubRepo, releases: [GitHubRelease], catalog: Catalog, local: [InstalledBundle], includePrereleases: Bool) -> PluginItem? {
        let usable = releases.filter { !$0.draft && (includePrereleases || !$0.prerelease) && $0.assets.contains(where: AssetFilter.isMacAsset) }
        guard let latest = usable.max(by: { a, b in
            switch (a.version, b.version) {
            case let (va?, vb?) where va != vb: va < vb
            default: (a.publishedAt ?? .distantPast) < (b.publishedAt ?? .distantPast)
            }
        }) else { return nil }

        let entry = catalog.entry(for: repo.name)
        // Repos outside the catalog must look like audio plug-ins, so unrelated macOS apps aren't offered.
        if entry == nil, !repo.hasPluginTopic, !AssetFilter.looksLikePlugin(latest) { return nil }
        let record = records[repo.fullName]
        let knownIDs = Set(((entry?.bundleIDs ?? []) + (record?.bundles.compactMap(\.bundleID) ?? [])).map { $0.lowercased() })
        let knownNames = Set(entry?.bundleNames ?? [])
        let recordedPaths = Set(record?.bundles.map(\.path) ?? [])

        let installed = local.filter { b in
            recordedPaths.contains(b.url.path)
                || b.bundleID.map { knownIDs.contains($0.lowercased()) } == true
                || knownNames.contains(b.name)
        }

        return PluginItem(
            repo: repo,
            displayName: entry?.name ?? repo.name,
            latest: latest,
            releases: releases,
            installed: installed,
            installedVersion: installedVersion(installed: installed, record: record)
        )
    }

    /// Prefers the tag this app installed (bundle versions aren't always bumped), unless the bundle changed since.
    private func installedVersion(installed: [InstalledBundle], record: InstallRecord?) -> Version? {
        if let record {
            let recorded = Dictionary(record.bundles.map { ($0.path, $0.bundleVersion) }, uniquingKeysWith: { a, _ in a })
            let tracked = installed.filter { recorded[$0.url.path] != nil }
            if !tracked.isEmpty, tracked.allSatisfy({ recorded[$0.url.path] == $0.version }) {
                return Version(record.tag)
            }
        }
        // Lowest version across formats, so a stale format still shows as needing an update.
        return installed.compactMap { $0.version.flatMap(Version.init) }.min()
    }

    // MARK: - Installing

    func requestInstall(_ items: [PluginItem]) {
        guard !items.isEmpty, !isInstalling else { return }
        pendingConfirmation = items
    }

    func confirmPending() async {
        guard let items = pendingConfirmation else { return }
        pendingConfirmation = nil
        await install(items)
    }

    private func install(_ items: [PluginItem]) async {
        isInstalling = true
        defer { isInstalling = false }
        let formats = Prefs.enabledFormats
        var staged: [StagedInstall] = []
        var adminCommands: [String: [String]] = [:]

        for item in items {
            let id = item.id
            installStates[id] = .working("Preparing…")
            do {
                let s = try await Installer.stage(item, formats: formats) { [weak self] message in
                    self?.installStates[id] = .working(message)
                }
                installStates[id] = .working("Installing…")
                adminCommands[id] = try await Installer.copyUserBundles(s)
                staged.append(s)
            } catch {
                installStates[id] = .failed(error.localizedDescription)
                append("\(item.displayName): \(error.localizedDescription)", isError: true)
            }
        }
        guard !staged.isEmpty else { return }

        // One password prompt for every system-domain copy plus the quarantine removal.
        let allPaths = staged.flatMap { $0.copies.map(\.destination) }
        var script = staged.flatMap { adminCommands[$0.item.id] ?? [] }
        let removeQuarantine = UserDefaults.standard.bool(forKey: Prefs.removeQuarantine)
        if removeQuarantine { script.append(Installer.quarantineCommand(for: allPaths)) }

        var adminFailed: Error?
        if !script.isEmpty {
            for s in staged { installStates[s.item.id] = .working("Waiting for administrator password…") }
            do {
                try await Shell.runAsAdmin(
                    script.joined(separator: " && "),
                    prompt: "SLM Plugins Updater wants to clear the macOS quarantine flag (xattr) on the plug-ins it just installed."
                )
                if removeQuarantine { append("Removed quarantine attribute from \(allPaths.count) bundle(s).") }
            } catch {
                adminFailed = error
                append("Administrator step failed: \(error.localizedDescription)", isError: true)
            }
        }

        for s in staged {
            let id = s.item.id
            let neededAdmin = !(adminCommands[id] ?? []).isEmpty
            if let adminFailed, neededAdmin {
                installStates[id] = .failed(adminFailed.localizedDescription)
            } else {
                records[s.item.repo.fullName] = InstallRecord(
                    tag: s.item.latest.tagName,
                    installedAt: Date(),
                    bundles: s.copies.map { .init(path: $0.destination.path, bundleID: $0.bundleID, bundleVersion: $0.bundleVersion) }
                )
                installStates[id] = .done
                let where_ = s.copies.map { $0.destination.deletingLastPathComponent().path }.uniqued().joined(separator: ", ")
                append("Installed \(s.item.displayName) \(s.item.latest.tagName) → \(where_)"
                       + (adminFailed != nil && removeQuarantine ? " (quarantine flag NOT removed)" : ""))
            }
            Installer.cleanUp(s)
        }
        StateStore.shared.save(records)

        // Make hosts pick up new Audio Units without a reboot.
        if staged.contains(where: { $0.copies.contains { $0.destination.pathExtension == "component" } }) {
            _ = try? await Shell.run("/usr/bin/killall", ["-9", "AudioComponentRegistrar"])
        }

        isInstalling = false
        await refresh()
    }

    // MARK: - Misc

    var runningDAWs: [String] {
        let prefixes = ["com.steinberg.cubase", "com.steinberg.nuendo", "com.cockos.reaper", "com.apple.logic", "com.apple.garageband",
                        "com.ableton.live", "com.bitwig", "com.presonus.studioone", "com.image-line.flstudio", "com.motu.digitalperformer",
                        "com.avid.protools", "com.renoise", "com.apple.mainstage"]
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier?.lowercased(), prefixes.contains(where: id.hasPrefix) else { return nil }
            return app.localizedName
        }
    }

    private func append(_ message: String, isError: Bool = false) {
        log.append(LogEntry(message: message, isError: isError))
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension UpdaterModel {
    /// `--list`: prints what the app would offer, without installing anything.
    func printReport() async {
        // The window's launch check may already be running; wait for it instead of skipping.
        try? await Task.sleep(for: .milliseconds(200))
        while isChecking { try? await Task.sleep(for: .milliseconds(100)) }
        if lastChecked == nil { await refresh() }
        if let errorMessage { print("error: \(errorMessage)") }
        for item in plugins {
            let status: String = switch item.status {
            case .updateAvailable: "UPDATE"
            case .notInstalled: "NEW"
            case .upToDate: "OK"
            case .unknownVersion: "UNKNOWN"
            }
            print("[\(status)] \(item.displayName) (\(item.repo.name)) installed=\(item.installedVersion?.description ?? "-") latest=\(item.latest.tagName)")
            for b in item.installed { print("    \(b.url.path) v\(b.version ?? "?")") }
            for r in ReleaseNotes.releases(in: item, includePrereleases: includePrereleases) {
                print("    changelog \(r.tagName): \(ReleaseNotes.clean(r.body).prefix(120).replacingOccurrences(of: "\n", with: " ⏎ "))")
            }
        }
    }
}
