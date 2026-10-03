import Foundation
import Security

/// GitHub token: the one saved in Settings (Keychain), else the GitHub CLI login if `gh` is installed.
enum Credentials {
    private static let service = "com.slm.pluginsupdater"
    private static let account = "github-token"

    static var savedToken: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func save(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func ghCLIToken() async -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            if let out = try? await Shell.run(path, ["auth", "token", "--hostname", "github.com"]) {
                let token = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty, !token.contains(" ") { return token }
            }
        }
        return nil
    }

    static func resolve() async -> (token: String?, source: String) {
        // Lets you test what users without a token see.
        if ProcessInfo.processInfo.environment["SLM_UPDATER_ANONYMOUS"] == "1" { return (nil, "anonymous") }
        if let saved = savedToken { return (saved, "Settings token") }
        if let gh = await ghCLIToken() { return (gh, "GitHub CLI login") }
        return (nil, "anonymous")
    }
}
