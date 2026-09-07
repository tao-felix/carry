import Foundation

/// What one `carry …` run produced.
struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval

    var ok: Bool { exitCode == 0 }

    /// The last non-empty line of stderr, else of stdout. For status lines and logs.
    var tail: String {
        for text in [stderr, stdout] {
            if let line = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
                .last(where: { !$0.isEmpty }) {
                return line
            }
        }
        return ""
    }

    /// The last `n` lines of stdout and stderr together, for the log file.
    func lastLines(_ n: Int = 20) -> [String] {
        let lines = (stdout + "\n" + stderr).split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Array(lines.suffix(n))
    }
}

/// Finds and runs the `carry` executable. The CLI is the engine; this app only drives it.
enum CarryCLI {
    static let installCommand = "uv tool install carry-context"
    static let upgradeCommand = "uv tool install --upgrade carry-context"

    /// The PATH every child gets, so `carry` finds `uv`-installed tools and Homebrew.
    static var searchPath: String {
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(NSHomeDirectory())/.local/bin"
    }

    /// `~/.local/bin/carry`, `/opt/homebrew/bin/carry`, `/usr/local/bin/carry`, then PATH.
    static func locate() -> String? {
        let home = NSHomeDirectory()
        var candidates = ["\(home)/.local/bin/carry", "/opt/homebrew/bin/carry", "/usr/local/bin/carry"]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += path.split(separator: ":").map { "\($0)/carry" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `executable arguments…` with no shell, capturing stdout and stderr.
    /// `timeout` terminates a stuck process; `carry sync` gets none (Pro processing can take minutes).
    static func run(_ executable: String, _ arguments: [String], extraEnvironment: [String: String] = [:],
                    timeout: TimeInterval? = nil) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, arguments, extraEnvironment: extraEnvironment,
                                                           timeout: timeout))
            }
        }
    }

    /// `carry --version` → `0.1.0`.
    static func version(_ executable: String) async -> String? {
        let result = await run(executable, ["--version"], timeout: 20)
        guard result.ok else { return nil }
        let words = result.stdout.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return words.last.map(String.init)
    }

    private final class DataBox {
        var data = Data()
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], extraEnvironment: [String: String],
                                    timeout: TimeInterval?) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        environment["HOME"] = NSHomeDirectory()
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONUTF8"] = "1"
        for (key, value) in extraEnvironment { environment[key] = value }
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let started = Date()
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: "could not start \(executable): \(error.localizedDescription)",
                                 duration: 0)
        }

        var timedOut = false
        var watchdog: DispatchWorkItem?
        if let timeout {
            let item = DispatchWorkItem {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
            watchdog = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }

        // Drain both pipes at once so a chatty stderr can never block a chatty stdout.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog?.cancel()

        var stderr = String(decoding: errBox.data, as: UTF8.self)
        if timedOut { stderr += "\ntimed out after \(Int(timeout ?? 0)) s" }
        return CommandResult(exitCode: process.terminationStatus, stdout: String(decoding: outData, as: UTF8.self),
                             stderr: stderr, duration: Date().timeIntervalSince(started))
    }
}
