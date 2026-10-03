import SwiftUI

struct SettingsView: View {
    @Environment(UpdaterModel.self) private var model
    @AppStorage(Prefs.owner) private var owner = "salvolm84"
    @AppStorage(Prefs.includePrereleases) private var includePrereleases = false
    @AppStorage(Prefs.removeQuarantine) private var removeQuarantine = true
    @AppStorage(Prefs.checkOnLaunch) private var checkOnLaunch = true

    var body: some View {
        Form {
            Section("Formats to install") {
                ForEach(PluginFormat.allCases) { FormatToggle(format: $0) }
                Text("Plug-ins go to ~/Library/Audio/Plug-Ins, apps to /Applications. Existing copies are replaced where they are, and old versions go to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Security") {
                Toggle("Remove quarantine flag after install (sudo xattr)", isOn: $removeQuarantine)
                Text("Runs `xattr -rd com.apple.quarantine` as administrator on every installed bundle so macOS doesn't block the unsigned plug-ins.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for updates at launch", isOn: $checkOnLaunch)
                Toggle("Include pre-releases", isOn: $includePrereleases)
                TextField("GitHub owner", text: $owner)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FormatToggle: View {
    let format: PluginFormat
    @AppStorage private var enabled: Bool

    init(format: PluginFormat) {
        self.format = format
        _enabled = AppStorage(wrappedValue: format != .app, Prefs.format(format))
    }

    var body: some View {
        Toggle(format.displayName, isOn: $enabled)
    }
}
