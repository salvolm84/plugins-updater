import Foundation

enum Prefs {
    static let owner = "owner"
    static let includePrereleases = "includePrereleases"
    static let removeQuarantine = "removeQuarantine"
    static let checkOnLaunch = "checkOnLaunch"
    static func format(_ f: PluginFormat) -> String { "format.\(f.rawValue)" }

    static func registerDefaults() {
        var defaults: [String: Any] = [
            owner: "salvolm84",
            includePrereleases: false,
            removeQuarantine: true,
            checkOnLaunch: true,
        ]
        for f in PluginFormat.allCases { defaults[format(f)] = f != .app }
        UserDefaults.standard.register(defaults: defaults)
    }

    static var enabledFormats: Set<PluginFormat> {
        Set(PluginFormat.allCases.filter { UserDefaults.standard.bool(forKey: format($0)) })
    }
}
