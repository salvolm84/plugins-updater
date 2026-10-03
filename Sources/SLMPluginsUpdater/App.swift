import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SLMPluginsUpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: UpdaterModel

    init() {
        Prefs.registerDefaults()
        let model = UpdaterModel()
        _model = State(initialValue: model)
        if CommandLine.arguments.contains("--list") {
            Task { @MainActor in await model.printReport(); exit(0) }
        }
    }

    var body: some Scene {
        Window("SLM Plugins Updater", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 460)
                .task {
                    if UserDefaults.standard.bool(forKey: Prefs.checkOnLaunch) { await model.refresh() }
                }
        }
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.isChecking || model.isInstalling)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
