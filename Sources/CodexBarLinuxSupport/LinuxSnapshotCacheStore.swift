import Foundation

public struct LinuxCachedProviderSnapshot: Codable, Sendable {
    public let payload: LinuxProviderPayload
    public let cachedAt: Date

    public init(payload: LinuxProviderPayload, cachedAt: Date) {
        self.payload = payload
        self.cachedAt = cachedAt
    }
}

public struct LinuxSnapshotCacheStore: Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = Self.defaultURL(),
        fileManager: FileManager = .default)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() -> [String: LinuxCachedProviderSnapshot] {
        guard let data = try? Data(contentsOf: self.fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: LinuxCachedProviderSnapshot].self, from: data)) ?? [:]
    }

    public func save(_ snapshots: [String: LinuxCachedProviderSnapshot]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshots)
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: self.fileURL, options: [.atomic])
        try self.fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: self.fileURL.path)
    }

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("codexbar-linux", isDirectory: true)
            .appendingPathComponent("provider-cache.json")
    }
}
