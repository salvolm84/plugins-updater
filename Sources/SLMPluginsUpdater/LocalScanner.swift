import Foundation

enum LocalScanner {
    /// Every plug-in / app bundle in the standard user and system locations.
    static func scan() -> [InstalledBundle] {
        let fm = FileManager.default
        var result: [InstalledBundle] = []
        for format in PluginFormat.allCases {
            for dir in format.searchDirectories {
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { continue }
                for url in entries {
                    if url.pathExtension.lowercased() == format.fileExtension {
                        if let bundle = InstalledBundle(url: url) { result.append(bundle) }
                    } else if format != .app, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        // Some installers use vendor sub-folders inside the plug-in directories.
                        let nested = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                        result += nested.filter { $0.pathExtension.lowercased() == format.fileExtension }.compactMap(InstalledBundle.init(url:))
                    }
                }
            }
        }
        return result
    }
}
