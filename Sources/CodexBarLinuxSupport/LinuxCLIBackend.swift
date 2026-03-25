import CodexBarCore
import Dispatch
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct LinuxDashboardLoadResult: Sendable {
    public let cliBinaryPath: String
    public let payloads: [LinuxProviderPayload]
    public let cachedProviderIDs: [String]
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(
        cliBinaryPath: String,
        payloads: [LinuxProviderPayload],
        cachedProviderIDs: [String],
        stdout: String,
        stderr: String,
        exitCode: Int32)
    {
        self.cliBinaryPath = cliBinaryPath
        self.payloads = payloads
        self.cachedProviderIDs = cachedProviderIDs
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
    private static let defaultProcessTimeoutSeconds: TimeInterval = 25

    public let environment: [String: String]
    public let configStore: CodexBarConfigStore
    public let preferencesStore: LinuxPreferencesStore
    public let snapshotCacheStore: LinuxSnapshotCacheStore

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        preferencesStore: LinuxPreferencesStore = LinuxPreferencesStore(),
        snapshotCacheStore: LinuxSnapshotCacheStore = LinuxSnapshotCacheStore())
    {
        self.environment = environment
        self.configStore = configStore
        self.preferencesStore = preferencesStore
        self.snapshotCacheStore = snapshotCacheStore
    }

    public func fetchUsagePayloads() throws -> LinuxDashboardLoadResult {
        let config = try self.loadConfig()
        let enabledProviders = config.enabledProviders()
        let cliBinaryPath = try self.resolveCLIBinaryPath()
        var cachedSnapshots = self.snapshotCacheStore.load()

        guard !enabledProviders.isEmpty else {
            return LinuxDashboardLoadResult(
                cliBinaryPath: cliBinaryPath,
                payloads: [],
                cachedProviderIDs: [],
                stdout: "",
                stderr: "",
                exitCode: 0)
        }

        var payloads: [LinuxProviderPayload] = []
        var cachedProviderIDs: [String] = []
        var stdoutParts: [String] = []
        var stderrParts: [String] = []
        var lastExitCode: Int32 = 0
        var cacheDidChange = false

        for provider in enabledProviders {
            let configuredSource = config.providerConfig(for: provider)?.source ?? .auto
            let sourceAttempts = Self.linuxSourceAttempts(for: provider, configuredSource: configuredSource)

            var chosenPayloads: [LinuxProviderPayload] = []
            var chosenStdout = ""
            var chosenStderr = ""
            var chosenExitCode: Int32 = 0

            for sourceMode in sourceAttempts {
                let command = try self.runProcess(
                    executablePath: cliBinaryPath,
                    arguments: Self.usageArguments(for: provider, sourceMode: sourceMode),
                    label: "CodexBar Linux refresh (\(provider.rawValue), \(sourceMode.rawValue))",
                    timeout: self.processTimeoutSeconds())
                let trimmed = command.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let decodedPayloads = trimmed.isEmpty ? [] : try self.decodePayloads(from: command.stdout)

                if chosenPayloads.isEmpty {
                    chosenPayloads = decodedPayloads
                    chosenStdout = command.stdout
                    chosenStderr = command.stderr
                    chosenExitCode = command.exitCode
                }

                if Self.containsSuccessfulPayload(decodedPayloads, for: provider) {
                    chosenPayloads = decodedPayloads
                    chosenStdout = command.stdout
                    chosenStderr = command.stderr
                    chosenExitCode = command.exitCode
                    break
                }
            }

            if Self.containsSuccessfulPayload(chosenPayloads, for: provider) {
                payloads.append(contentsOf: chosenPayloads)
                if let successfulPayload = chosenPayloads.first(where: { $0.provider == provider.rawValue && $0.error == nil }) {
                    cachedSnapshots[provider.rawValue] = LinuxCachedProviderSnapshot(payload: successfulPayload, cachedAt: Date())
                    cacheDidChange = true
                }
            } else if let cachedPayload = cachedSnapshots[provider.rawValue]?.payload {
                payloads.append(cachedPayload)
                cachedProviderIDs.append(provider.rawValue)
            } else {
                payloads.append(contentsOf: chosenPayloads)
            }

            if !chosenStdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stdoutParts.append(chosenStdout)
            }
            if !chosenStderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stderrParts.append(chosenStderr)
            }
            if chosenExitCode != 0 {
                lastExitCode = chosenExitCode
            }
        }

        if cacheDidChange {
            try self.snapshotCacheStore.save(cachedSnapshots)
        }

        if payloads.isEmpty, lastExitCode != 0 {
            throw LinuxCLIBackendError.commandFailed(
                label: "CodexBarCLI usage",
                code: lastExitCode,
                stderr: stderrParts.joined(separator: "\n"),
                stdout: stdoutParts.joined(separator: "\n"))
        }

        return LinuxDashboardLoadResult(
            cliBinaryPath: cliBinaryPath,
            payloads: payloads,
            cachedProviderIDs: cachedProviderIDs,
            stdout: stdoutParts.joined(separator: "\n"),
            stderr: stderrParts.joined(separator: "\n"),
            exitCode: lastExitCode)
    }

    @discardableResult
    public func openConfigInDefaultApp() throws -> URL {
        let fileURL = try self.ensureConfigFile()
        let opener = try self.resolveExecutablePath(named: "xdg-open")
        let command = try self.runProcess(
            executablePath: opener,
            arguments: [fileURL.path],
            label: "Open CodexBar config",
            timeout: 5)
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
        _ = try self.configStore.loadOrCreateDefault()
        return self.configStore.fileURL
    }

    public func loadConfig() throws -> CodexBarConfig {
        try self.configStore.loadOrCreateDefault()
    }

    public func setProviderEnabled(_ provider: UsageProvider, enabled: Bool) throws {
        var config = try self.loadConfig()
        var providerConfig = config.providerConfig(for: provider) ?? ProviderConfig(id: provider)
        providerConfig.enabled = enabled
        config.setProviderConfig(providerConfig)
        try self.configStore.save(config.normalized())
    }

    public func loadPreferences() -> LinuxPreferences {
        self.preferencesStore.load()
    }

    public func savePreferences(_ preferences: LinuxPreferences) throws {
        try self.preferencesStore.save(preferences)
    }

    static func decodePayloadsFromCLIStdout(_ stdout: String) throws -> [LinuxProviderPayload] {
        let segments = self.extractJSONArraySegments(from: stdout)
        guard !segments.isEmpty else {
            throw LinuxCLIBackendError.decodeFailed("No JSON array payload found in CLI stdout.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var payloads: [LinuxProviderPayload] = []
        for segment in segments {
            do {
                let decoded = try decoder.decode([LinuxProviderPayload].self, from: Data(segment.utf8))
                payloads.append(contentsOf: decoded)
            } catch {
                throw LinuxCLIBackendError.decodeFailed(error.localizedDescription)
            }
        }

        let providerPayloads = payloads.filter { $0.provider != "cli" }
        if !providerPayloads.isEmpty {
            return providerPayloads
        }
        return payloads
    }

    private func decodePayloads(from stdout: String) throws -> [LinuxProviderPayload] {
        try Self.decodePayloadsFromCLIStdout(stdout)
    }

    static func usageArguments(for provider: UsageProvider, sourceMode: ProviderSourceMode) -> [String] {
        let cliName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.cliName
        return [
            "usage",
            "--format", "json",
            "--json-only",
            "--pretty",
            "--status",
            "--provider", cliName,
            "--source", sourceMode.rawValue,
            "--web-timeout", "20",
        ]
    }

    static func linuxSourceAttempts(for provider: UsageProvider, configuredSource: ProviderSourceMode) -> [ProviderSourceMode] {
        guard configuredSource == .auto else {
            return [configuredSource]
        }

        let supportedSources = ProviderDescriptorRegistry.descriptor(for: provider).fetchPlan.sourceModes
        guard supportedSources.contains(.web) else {
            return [.auto]
        }

        let orderedFallbacks: [ProviderSourceMode] = [.oauth, .api, .cli]
        let candidates = orderedFallbacks.filter { supportedSources.contains($0) }
        return candidates.isEmpty ? [.auto] : candidates
    }

    static func containsSuccessfulPayload(_ payloads: [LinuxProviderPayload], for provider: UsageProvider) -> Bool {
        payloads.contains { payload in
            payload.provider == provider.rawValue && payload.error == nil
        }
    }

    static func extractJSONArraySegments(from text: String) -> [String] {
        var segments: [String] = []
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaping = false

        for index in text.indices {
            let character = text[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "[" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
                continue
            }

            if character == "]", depth > 0 {
                depth -= 1
                if depth == 0, let segmentStartIndex = startIndex {
                    let nextIndex = text.index(after: index)
                    segments.append(String(text[segmentStartIndex..<nextIndex]))
                    startIndex = nil
                    isInsideString = false
                    isEscaping = false
                }
            }
        }

        return segments
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

    private func processTimeoutSeconds() -> TimeInterval {
        guard let raw = self.environment["CODEXBAR_LINUX_PROCESS_TIMEOUT"],
              let value = TimeInterval(raw),
              value > 0
        else {
            return Self.defaultProcessTimeoutSeconds
        }
        return value
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        label: String,
        timeout: TimeInterval) throws -> (stdout: String, stderr: String, exitCode: Int32)
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
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            throw LinuxCLIBackendError.launchFailed("\(label): \(error.localizedDescription)")
        }

        let didExit = exitSemaphore.wait(timeout: .now() + timeout) == .success
        if !didExit, !Self.forceExit(process, exitSemaphore: exitSemaphore) {
            return ("", "\(label) timed out after \(Int(timeout.rounded()))s.", 4)
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        var stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if !didExit {
            let timeoutMessage = "\(label) timed out after \(Int(timeout.rounded()))s."
            stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? timeoutMessage
                : "\(stderr)\n\(timeoutMessage)"
        }
        return (stdout, stderr, process.terminationStatus)
    }

    private static func forceExit(_ process: Process, exitSemaphore: DispatchSemaphore) -> Bool {
        guard process.isRunning else { return true }

        process.terminate()
        if exitSemaphore.wait(timeout: .now() + 0.5) == .success {
            return true
        }

        guard process.isRunning else { return true }
        kill(process.processIdentifier, SIGKILL)
        return exitSemaphore.wait(timeout: .now() + 1.0) == .success
    }
}
