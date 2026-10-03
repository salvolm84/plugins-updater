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

            if model.plugins.isEmpty {
                emptyState
            } else {
                List {
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
                Text("Looking for plug-ins on github.com/\(model.owner)…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("No plug-ins found yet").font(.title3)
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
