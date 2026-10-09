import AppKit
import Observation

/// In-app sign-in for the "Claude (Subscription)" provider. Drives Anthropic's own Claude Code
/// login (`claude auth login --claudeai`) so the user never touches a terminal, and Clippy
/// never handles subscription tokens itself.
@Observable
final class ClaudeCodeAccount {
    enum State: Equatable {
        case checking
        case notInstalled
        case installing
        case signedOut
        case signingIn
        case signedIn(account: String?)
        case failed(String)
    }

    private(set) var state: State = .checking
    /// Sign-in page URL printed by the CLI, as a fallback if the browser didn't open by itself.
    private(set) var signInURL: URL?
    /// True when the CLI asks for a code to be pasted back (manual OAuth flow).
    private(set) var needsCode = false
    @ObservationIgnored private var loginProcess: Process?
    @ObservationIgnored private var loginInput: FileHandle?

    static let installerCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    // MARK: Status

    func refresh() async {
        guard let cli = ClaudeCodeCLIClient.executableURL else {
            state = .notInstalled
            return
        }
        if state != .signingIn && state != .installing { state = .checking }
        let result = await CLIRunner.run(cli, ["auth", "status"])
        state = Self.parseStatus(result.output) ?? .failed("Couldn't read the Claude sign-in status.")
    }

    nonisolated static func parseStatus(_ output: String) -> State? {
        // `claude auth status` prints JSON; tolerate log lines around it.
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
              let data = String(output[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard json["loggedIn"] as? Bool == true else { return .signedOut }
        let account = ["email", "emailAddress", "account", "organizationName"]
            .lazy.compactMap { json[$0] as? String }.first
        return .signedIn(account: account)
    }

    // MARK: Sign in / out

    func signIn() {
        guard let cli = ClaudeCodeCLIClient.executableURL else {
            state = .notInstalled
            return
        }
        cancelSignIn()
        state = .signingIn
        signInURL = nil
        needsCode = false

        let process = Process()
        process.executableURL = cli
        process.arguments = ["auth", "login", "--claudeai"]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = input
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.loginProcess = nil
                self?.loginInput = nil
                self?.needsCode = false
                await self?.refresh()
                if self?.isSignedIn == true { NSApp.activate() }
            }
        }
        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        loginProcess = process
        loginInput = input.fileHandleForWriting

        let reader = output.fileHandleForReading
        Task { [weak self] in
            do {
                for try await line in reader.bytes.lines {
                    self?.handleLoginOutput(line)
                }
            } catch {}
        }
    }

    private func handleLoginOutput(_ line: String) {
        if signInURL == nil, let url = Self.firstURL(in: line) {
            signInURL = url
        }
        let lower = line.lowercased()
        if lower.contains("paste") && lower.contains("code") {
            needsCode = true
        }
    }

    nonisolated static func firstURL(in line: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        return detector.firstMatch(in: line, range: range)?.url.flatMap { $0.scheme == "https" ? $0 : nil }
    }

    func submitCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let loginInput else { return }
        loginInput.write(Data((trimmed + "\n").utf8))
    }

    func cancelSignIn() {
        if loginProcess?.isRunning == true { loginProcess?.terminate() }
        loginProcess = nil
        loginInput = nil
    }

    func signOut() async {
        guard let cli = ClaudeCodeCLIClient.executableURL else { return }
        _ = await CLIRunner.run(cli, ["auth", "logout"])
        await refresh()
    }

    // MARK: Install

    /// Runs Anthropic's official Claude Code installer (installs to ~/.local/bin, no admin rights).
    func install() async {
        state = .installing
        let result = await CLIRunner.run(URL(fileURLWithPath: "/bin/bash"), ["-c", Self.installerCommand])
        if result.status != 0 || ClaudeCodeCLIClient.executableURL == nil {
            let tail = result.output.split(separator: "\n").suffix(2).joined(separator: " ")
            state = .failed("Installation failed. \(tail)")
            return
        }
        await refresh()
    }
}

/// Runs a command off the main thread and returns its exit status and combined output.
nonisolated enum CLIRunner {
    struct Result: Sendable {
        var status: Int32
        var output: String
    }

    static func run(_ executable: URL, _ arguments: [String], timeout: Duration = .seconds(300)) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let collector = OutputCollector()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                collector.append(handle.availableData)
            }
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: Result(status: process.terminationStatus, output: collector.string))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
                return
            }
            let box = ProcessBox.wrap(process)
            Task {
                try? await Task.sleep(for: timeout)
                box.terminate()
            }
        }
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
        var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }
}
