import SwiftUI

struct PluginRow: View {
    @Environment(UpdaterModel.self) private var model
    let item: PluginItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.body.weight(.semibold))
                    ForEach(item.installed.isEmpty ? item.offeredFormats : item.installedFormats) { f in
                        Text(f.shortName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(versionLine).font(.callout).foregroundStyle(.secondary)
                if let state = model.installStates[item.id] {
                    stateLine(state)
                } else if let description = item.repo.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer()

            Link(destination: item.latest.htmlUrl) { Image(systemName: "arrow.up.right.square") }
                .help("Open release on GitHub")

            switch item.status {
            case .updateAvailable:
                Button("Update") { model.requestInstall([item]) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isInstalling)
            case .notInstalled:
                Button("Install") { model.requestInstall([item]) }
                    .disabled(model.isInstalling)
            case .upToDate, .unknownVersion:
                Button("Reinstall") { model.requestInstall([item]) }
                    .buttonStyle(.borderless)
                    .disabled(model.isInstalling)
            }
        }
        .padding(.vertical, 4)
    }

    private var versionLine: String {
        let latest = item.latest.tagName
        switch item.status {
        case .notInstalled: return "Latest \(latest) · not installed"
        case .updateAvailable: return "\(item.installedVersion?.description ?? "?") → \(latest)"
        case .upToDate: return "\(item.installedVersion?.description ?? latest) · latest \(latest)"
        case .unknownVersion: return "Installed (unknown version) · latest \(latest)"
        }
    }

    private var icon: String {
        switch item.status {
        case .updateAvailable: "arrow.down.circle.fill"
        case .notInstalled: "plus.circle"
        case .upToDate, .unknownVersion: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch item.status {
        case .updateAvailable: .accentColor
        case .notInstalled: .purple
        case .upToDate, .unknownVersion: .green
        }
    }

    @ViewBuilder
    private func stateLine(_ state: UpdaterModel.InstallState) -> some View {
        switch state {
        case let .working(message):
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(message) }.font(.caption)
        case .done:
            Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }
}
