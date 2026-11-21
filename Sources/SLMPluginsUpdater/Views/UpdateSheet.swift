import SwiftUI

/// Confirmation step: shows what changed since the installed version before anything is downloaded.
struct UpdateSheet: View {
    @Environment(UpdaterModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let items: [PluginItem]
    @State private var showFullNotes = false

    private var updateCount: Int { items.filter { $0.status != .notInstalled }.count }
    private var newCount: Int { items.filter { $0.status == .notInstalled }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text("Review the changes below, then confirm.").foregroundStyle(.secondary)
            }
            .padding(20)

            let daws = items.contains { $0.kind == .plugin } ? model.runningDAWs : []
            if !daws.isEmpty {
                warning("\(daws.joined(separator: ", ")) is running. Quit it before installing so the new plug-in version is loaded.")
            }
            let runningApps = items.flatMap(\.runningAppNames).uniqued()
            if !runningApps.isEmpty {
                warning("\(runningApps.joined(separator: ", ")) is running. Quit it before updating; the open copy keeps running the old version.")
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(items) { item in
                        PluginChangelog(item: item, showFullNotes: showFullNotes, includePrereleases: model.includePrereleases)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Toggle("Show full release notes", isOn: $showFullNotes).toggleStyle(.checkbox)
                Spacer()
                if UserDefaults.standard.bool(forKey: Prefs.removeQuarantine) {
                    Label("Your admin password will be asked to run xattr", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    let items = items
                    dismiss()
                    Task { await model.confirm(items) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 560)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
    }

    private var title: String {
        switch (updateCount, newCount) {
        case (_, 0): updateCount == 1 ? "Update \(items[0].displayName)?" : "Update \(updateCount) \(items.noun)?"
        case (0, _): newCount == 1 ? "Install \(items[0].displayName)?" : "Install \(newCount) new \(items.noun)?"
        default: "Update \(updateCount) and install \(newCount) \(items.noun)?"
        }
    }

    private var confirmTitle: String {
        newCount > 0 && updateCount == 0 ? "Install" : "Update"
    }
}

private struct PluginChangelog: View {
    let item: PluginItem
    let showFullNotes: Bool
    let includePrereleases: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayName).font(.title3.weight(.semibold))
                Spacer()
                Text(header).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }

            ForEach(ReleaseNotes.releases(in: item, includePrereleases: includePrereleases)) { release in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(release.tagName).font(.headline)
                        if release.prerelease {
                            Text("pre-release").font(.caption2).padding(.horizontal, 5).background(.orange.opacity(0.25), in: Capsule())
                        }
                        if let date = release.publishedAt {
                            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    let notes = showFullNotes ? (release.body ?? "") : ReleaseNotes.clean(release.body)
                    if notes.isEmpty {
                        Text("No release notes.").foregroundStyle(.secondary).italic()
                    } else {
                        MarkdownView(markdown: notes)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var header: String {
        if item.status == .notInstalled { return "new install · \(item.latest.tagName)" }
        return "\(item.installedVersion?.description ?? "?") → \(item.latest.tagName)"
    }
}
