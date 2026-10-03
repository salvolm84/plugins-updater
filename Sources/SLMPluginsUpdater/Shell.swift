import Foundation

enum ShellError: LocalizedError {
    case failed(String, Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .failed(cmd, code, output): "\(cmd) failed (\(code)): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .cancelled: "The administrator password prompt was cancelled."
        }
    }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw ShellError.failed((executable as NSString).lastPathComponent, process.terminationStatus, output)
            }
            return output
        }.value
    }

    /// Runs a shell script as root through the standard macOS administrator password prompt.
    static func runAsAdmin(_ script: String, prompt: String) async throws {
        let appleScript = "do shell script \"\(appleScriptEscape(script))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
        do {
            try await run("/usr/bin/osascript", ["-e", appleScript])
        } catch ShellError.failed(_, _, let output) where output.contains("-128") {
            throw ShellError.cancelled
        }
    }

    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
