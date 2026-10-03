import Foundation

enum ReleaseNotes {
    /// Sections that repeat in every release and say nothing about what changed.
    private static let droppedSections = ["install", "installation", "requirements", "build", "building", "download"]
    private static let droppedLinePrefixes = ["the plugin is unsigned", "requires macos", "**full changelog**", "full changelog"]

    /// Releases newer than `installed`, up to and including `latest`, newest first.
    static func releases(in item: PluginItem, includePrereleases: Bool) -> [GitHubRelease] {
        guard let latestVersion = item.latest.version else { return [item.latest] }
        let range = item.releases.filter { release in
            guard !release.draft, includePrereleases || !release.prerelease, let v = release.version else { return false }
            if v > latestVersion { return false }
            if let installed = item.installedVersion, item.status != .notInstalled { return v > installed }
            return v == latestVersion
        }
        let sorted = range.sorted { ($0.version!, $0.publishedAt ?? .distantPast) > ($1.version!, $1.publishedAt ?? .distantPast) }
        return sorted.isEmpty ? [item.latest] : sorted
    }

    static func clean(_ body: String?) -> String {
        guard let body else { return "" }
        var out: [String] = []
        var skipLevel: Int?
        var inFence = false
        for line in body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
            } else if !inFence, let (level, title) = heading(trimmed) {
                if let skip = skipLevel, level > skip { continue }
                skipLevel = nil
                if droppedSections.contains(where: title.lowercased().hasPrefix) {
                    skipLevel = level
                    continue
                }
            }
            if skipLevel != nil { continue }
            if !inFence, droppedLinePrefixes.contains(where: trimmed.lowercased().hasPrefix) { continue }
            out.append(line)
        }
        // Collapse blank runs and trim.
        var collapsed: [String] = []
        for line in out where !(line.trimmingCharacters(in: .whitespaces).isEmpty && (collapsed.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)) {
            collapsed.append(line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }
}
