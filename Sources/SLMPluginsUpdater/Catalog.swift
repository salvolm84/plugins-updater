import Foundation

/// Maps GitHub repos to the bundles they install, so already-installed copies can be recognised.
/// Repos not listed here are still discovered from GitHub; their bundle IDs are learned on first install.
struct Catalog: Codable {
    struct Entry: Codable {
        let repo: String
        let name: String
        var bundleIDs: [String] = []
        var bundleNames: [String] = []
    }

    var ignoredRepos: [String]
    var plugins: [Entry]

    func entry(for repo: String) -> Entry? {
        plugins.first { $0.repo.caseInsensitiveCompare(repo) == .orderedSame }
    }

    func isIgnored(_ repo: String) -> Bool {
        ignoredRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Kept in the updater's repo so new plugins can be mapped without shipping a new build.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/salvolm84/plugins-updater/main/catalog.json")!

    static let builtIn = Catalog(
        ignoredRepos: ["plugins-updater", "Tracker", "xbox"],
        plugins: [
            Entry(repo: "ezplayer", name: "GroovePlayer", bundleIDs: ["com.slm.grooveplayer"]),
            Entry(repo: "keylab-drumpad-mapper", name: "Drumpad Remapper", bundleIDs: ["com.slm.drumpadremapper"]),
            Entry(repo: "MIDI-Humanizer", name: "MIDI Humanizer", bundleIDs: ["com.slmaudio.midihumanizer", "com.slmaudio.midihumanizer.inst"]),
            Entry(repo: "MIDIKeySnap", name: "MIDIKeySnap", bundleIDs: ["com.slm.midikeysnap"]),
            Entry(repo: "MidiVelocityMapper", name: "MIDI Velocity Mapper", bundleIDs: ["com.yourcompany.NewProject"], bundleNames: ["NewProject"]),
            Entry(repo: "midi_notes_mapper", name: "MIDI Notes Mapper", bundleIDs: ["com.SLM.MidiMapperEvo"]),
            Entry(repo: "vst_input_calibration", name: "Input Calibration", bundleIDs: ["com.SLM.InputCalibration"]),
        ]
    )

    static func load() async -> Catalog {
        guard let data = try? await GitHubClient.shared.fetchData(remoteURL),
              let remote = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return builtIn }
        // Remote entries win; built-in ones fill any gaps.
        var merged = remote
        for entry in builtIn.plugins where merged.entry(for: entry.repo) == nil {
            merged.plugins.append(entry)
        }
        merged.ignoredRepos = Array(Set(remote.ignoredRepos + builtIn.ignoredRepos))
        return merged
    }
}
