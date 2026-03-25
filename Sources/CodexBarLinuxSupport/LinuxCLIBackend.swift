import CodexBarCore
import Foundation

public struct LinuxDashboardLoadResult: Sendable {
    public let cliBinaryPath: String
    public let payloads: [LinuxProviderPayload]
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(
        cliBinaryPath: String,
        payloads: [LinuxProviderPayload],
        stdout: String,
        stderr: String,
        exitCode: Int32)
    {
        self.cliBinaryPath = cliBinaryPath
        self.payloads = payloads
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum LinuxCLIBackendError: LocalizedError {
    case cliBinaryNotFound
    case configOpenToolMissing
    case launchFailed(String)
    case commandFailed(label: String, code: Int32, stderr: String, stdout: String)
    case emptyOutput(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliBinaryNotFound:
            return """
            Could not find CodexBarCLI or codexbar. Build the package first or set CODEXBAR_LINUX_CLI_BINARY.
            """
        case .configOpenToolMissing:
            return "Could not find xdg-open. Install xdg-utils to open the config file from the Ubuntu app."
        case let .launchFailed(details):
            return "Failed to launch subprocess: \(details)"
        case let .commandFailed(label, code, stderr, stdout):
            let output = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "\(label) failed with exit code \(code)."
            }
            return "\(label) failed with exit code \(code): \(output)"
        case let .emptyOutput(label):
            return "\(label) returned no JSON output."
        case let .decodeFailed(details):
            return "Failed to decode CodexBar CLI JSON: \(details)"
        }
    }
}

public struct LinuxCLIBackend: Sendable {
    public let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func fetchUsagePayloads() throws -> LinuxDashboardLoadResult {
        let cliBinaryPath = try self.resolveCLIBinaryPath()
        let command = try self.runProcess(
            executablePath: cliBinaryPath,
            arguments: [
                "usage",
                "--format", "json",
                "--pretty",
                "--status",
                "--provider", "all",
                "--web-timeout", "20",
            ],
            label: "CodexBar Linux refresh")
        let trimmed = command.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LinuxCLIBackendError.emptyOutput("CodexBarCLI usage")
        }
        let payloads = try self.decodePayloads(from: command.stdout)
        if command.exitCode != 0, payloads.isEmpty {
            throw LinuxCLIBackendError.commandFailed(
                label: "CodexBarCLI usage",
                code: command.exitCode,
                stderr: command.stderr,
                stdout: command.stdout)
        }
        return LinuxDashboardLoadResult(
            cliBinaryPath: cliBinaryPath,
            payloads: payloads,
            stdout: command.stdout,
            stderr: command.stderr,
            exitCode: command.exitCode)
    }

    @discardableResult
    public func openConfigInDefaultApp() throws -> URL {
        let fileURL = try self.ensureConfigFile()
        let opener = try self.resolveExecutablePath(named: "xdg-open")
        let command = try self.runProcess(
            executablePath: opener,
            arguments: [fileURL.path],
            label: "Open CodexBar config")
        if command.exitCode != 0 {
            throw LinuxCLIBackendError.commandFailed(
                label: "Open CodexBar config",
                code: command.exitCode,
                stderr: command.stderr,
                stdout: command.stdout)
        }
        return fileURL
    }

    public func ensureConfigFile() throws -> URL {
        let store = CodexBarConfigStore()
        _ = try store.loadOrCreateDefault()
        return store.fileURL
    }

    private func decodePayloads(from stdout: String) throws -> [LinuxProviderPayload] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([LinuxProviderPayload].self, from: Data(stdout.utf8))
        } catch {
            throw LinuxCLIBackendError.decodeFailed(error.localizedDescription)
        }
    }

    private func resolveCLIBinaryPath() throws -> String {
        if let override = self.environment["CODEXBAR_LINUX_CLI_BINARY"],
           self.isExecutable(path: override)
        {
            return override
        }

        let executableNames = ["CodexBarCLI", "codexbar"]
        if let currentExecutablePath = self.currentExecutablePath() {
            let executableDirectory = URL(fileURLWithPath: currentExecutablePath).deletingLastPathComponent()
            for name in executableNames {
                let candidate = executableDirectory.appendingPathComponent(name).path
                if self.isExecutable(path: candidate) {
                    return candidate
                }
            }
        }

        for name in executableNames {
            if let resolved = try? self.resolveExecutablePath(named: name) {
                return resolved
            }
        }

        throw LinuxCLIBackendError.cliBinaryNotFound
    }

    private func resolveExecutablePath(named name: String) throws -> String {
        let pathEntries = (self.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry, isDirectory: true).appendingPathComponent(name).path
            if self.isExecutable(path: candidate) {
                return candidate
            }
        }
        if self.isExecutable(path: name) {
            return name
        }
        switch name {
        case "xdg-open":
            throw LinuxCLIBackendError.configOpenToolMissing
        default:
            throw LinuxCLIBackendError.cliBinaryNotFound
        }
    }

    private func currentExecutablePath() -> String? {
        guard let argv0 = CommandLine.arguments.first, !argv0.isEmpty else { return nil }
        if argv0.hasPrefix("/") {
            return URL(fileURLWithPath: argv0).standardizedFileURL.path
        }
        if let resolved = try? self.resolveExecutablePath(named: argv0) {
            return resolved
        }
        let currentDirectory = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .appendingPathComponent(argv0)
            .standardizedFileURL
            .path
    }

    private func isExecutable(path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        label: String) throws -> (stdout: String, stderr: String, exitCode: Int32)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = self.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = nil

        do {
            try process.run()
        } catch {
            throw LinuxCLIBackendError.launchFailed("\(label): \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}
