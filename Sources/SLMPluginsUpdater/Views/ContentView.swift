import SwiftUI

struct ContentView: View {
    @Environment(UpdaterModel.self) private var model
    @State private var showLog = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                    Spacer()
                    SettingsLink { Text("Settings…") }
                }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.red.gradient)
            } else if let warning = model.warningMessage {
                HStack {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                    Spacer()
                    SettingsLink { Text("Settings…") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.2))
            }

            if let update = model.appUpdate {
                AppUpdateBanner(state: update)
            }

            if model.plugins.isEmpty {
                emptyState
            } else {
                List {
                    if model.visible.isEmpty {
                        Text("No \(model.kindFilter?.plural ?? "items") found.").foregroundStyle(.secondary)
                    }
                    section("Updates available", systemImage: "arrow.down.circle.fill", tint: .accentColor, items: model.updates,
                            actionTitle: "Update All") { model.requestInstall(model.updates) }
                    section("New — not installed on this Mac", systemImage: "sparkles", tint: .purple, items: model.newInstalls,
                            actionTitle: "Install All") { model.requestInstall(model.newInstalls) }
                    section("Up to date", systemImage: "checkmark.circle.fill", tint: .green, items: model.upToDate)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()
            footer
        }
        .toolbar {
            if model.hasApps {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $model.kindFilter) {
                        Text("All").tag(ItemKind?.none)
                        Text("Plug-ins").tag(ItemKind?.some(.plugin))
                        Text("Apps").tag(ItemKind?.some(.app))
                    }
                    .pickerStyle(.segmented)
                    .help("Show plug-ins, apps or both")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(model.isChecking || model.isInstalling)
                .help("Check GitHub for new releases")
            }
        }
        .sheet(item: Binding(
            get: { model.pendingConfirmation.map(PendingBatch.init) },
            set: { if $0 == nil { model.pendingConfirmation = nil } }
        )) { batch in
            UpdateSheet(items: batch.items)
        }
        .sheet(isPresented: $showLog) { LogView() }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, tint: Color, items: [PluginItem],
                         actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { PluginRow(item: $0) }
            } header: {
                HStack {
                    Label("\(title) (\(items.count))", systemImage: systemImage)
                        .foregroundStyle(tint)
                        .font(.headline)
                    Spacer()
                    if let actionTitle, let action, items.count > 1 {
                        Button(actionTitle, action: action)
                            .controlSize(.small)
                            .disabled(model.isInstalling)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.isChecking {
                ProgressView()
                Text("Looking for plug-ins and apps on github.com/\(model.owner)…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("No plug-ins or apps found yet").font(.title3)
                Button("Check for Updates") { Task { await model.refresh() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if model.isChecking {
                ProgressView().controlSize(.small)
                Text("Checking GitHub…")
            } else if model.isInstalling {
                ProgressView().controlSize(.small)
                Text("Installing…")
            } else if let date = model.lastChecked {
                Text("Last checked \(date.formatted(date: .omitted, time: .shortened))")
                if let summary = model.lastCheckSummary { Text("· \(summary)") }
                if model.authSource == "anonymous" {
                    Text("· anonymous GitHub access").help("Limited to 60 requests per hour per network. Add a token in Settings.")
                }
            }
            Spacer()
            Button("Activity Log") { showLog = true }
                .buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Update to this app itself.
private struct AppUpdateBanner: View {
    @Environment(UpdaterModel.self) private var model
    let state: UpdaterModel.AppUpdateState
    @State private var showNotes = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Button("What's New") { showNotes = true }.buttonStyle(.link)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12))
        .popover(isPresented: $showNotes, arrowEdge: .bottom) {
            ScrollView {
                MarkdownView(markdown: ReleaseNotes.clean(state.release.body).isEmpty ? "No release notes." : ReleaseNotes.clean(state.release.body))
                    .padding(16)
            }
            .frame(width: 420, height: 320)
        }
    }

    private var tag: String { state.release.tagName }

    private var title: String {
        switch state {
        case .available: "SLM Plugins Updater \(tag) is available"
        case .working: "Updating SLM Plugins Updater to \(tag)…"
        case .installed: "SLM Plugins Updater \(tag) is installed"
        case .failed: "Couldn't update SLM Plugins Updater to \(tag)"
        }
    }

    private var detail: String? {
        switch state {
        case .available:
            "You have \(SelfUpdater.currentVersion?.description ?? "an older version")."
                + (model.canInstallAppUpdate ? "" : " Development builds can't update themselves.")
        case let .working(_, message): message
        case .installed: "Relaunch to start using it. It's also used the next time you open the app."
        case let .failed(_, message): message
        }
    }

    private var icon: String {
        switch state {
        case .available, .working: "arrow.down.app.fill"
        case .installed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .available, .failed:
            if model.canInstallAppUpdate {
                Button(state == .available(state.release) ? "Update Now" : "Try Again") {
                    Task { await model.installAppUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isInstalling)
            } else {
                Link("Download", destination: state.release.htmlUrl)
            }
        case .working:
            ProgressView().controlSize(.small)
        case .installed:
            Button("Relaunch") { model.relaunch() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isInstalling)
        }
    }
}

private struct PendingBatch: Identifiable {
    let items: [PluginItem]
    var id: String { items.map(\.id).joined(separator: ",") }
}

struct LogView: View {
    @Environment(UpdaterModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity Log").font(.headline).padding()
            List(model.log.reversed()) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.date.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                    Text(entry.message).foregroundStyle(entry.isError ? .red : .primary).textSelection(.enabled)
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }
        .frame(width: 620, height: 380)
    }
}
