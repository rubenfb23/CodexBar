import CodexBarCore
import Foundation

public enum LinuxRefreshFrequency: String, CaseIterable, Codable, Sendable {
    case manual
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes

    public var label: String {
        switch self {
        case .manual:
            return "Manual"
        case .oneMinute:
            return "1 min"
        case .twoMinutes:
            return "2 min"
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        }
    }
}

public struct LinuxPreferences: Codable, Sendable {
    public var refreshFrequency: LinuxRefreshFrequency
    public var costUsageEnabled: Bool
    public var statusChecksEnabled: Bool
    public var sessionQuotaNotificationsEnabled: Bool
    public var usageBarsShowUsed: Bool
    public var resetTimesShowAbsolute: Bool
    public var showOptionalCreditsAndExtraUsage: Bool
    public var hidePersonalInfo: Bool
    public var mergeIcons: Bool
    public var switcherShowsIcons: Bool
    public var menuBarShowsHighestUsage: Bool

    public init(
        refreshFrequency: LinuxRefreshFrequency = .fiveMinutes,
        costUsageEnabled: Bool = false,
        statusChecksEnabled: Bool = true,
        sessionQuotaNotificationsEnabled: Bool = true,
        usageBarsShowUsed: Bool = false,
        resetTimesShowAbsolute: Bool = false,
        showOptionalCreditsAndExtraUsage: Bool = true,
        hidePersonalInfo: Bool = false,
        mergeIcons: Bool = true,
        switcherShowsIcons: Bool = true,
        menuBarShowsHighestUsage: Bool = false)
    {
        self.refreshFrequency = refreshFrequency
        self.costUsageEnabled = costUsageEnabled
        self.statusChecksEnabled = statusChecksEnabled
        self.sessionQuotaNotificationsEnabled = sessionQuotaNotificationsEnabled
        self.usageBarsShowUsed = usageBarsShowUsed
        self.resetTimesShowAbsolute = resetTimesShowAbsolute
        self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
        self.hidePersonalInfo = hidePersonalInfo
        self.mergeIcons = mergeIcons
        self.switcherShowsIcons = switcherShowsIcons
        self.menuBarShowsHighestUsage = menuBarShowsHighestUsage
    }
}

public struct LinuxPreferencesStore: Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = Self.defaultURL(),
        fileManager: FileManager = .default)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() -> LinuxPreferences {
        guard let data = try? Data(contentsOf: self.fileURL) else { return LinuxPreferences() }
        let decoder = JSONDecoder()
        return (try? decoder.decode(LinuxPreferences.self, from: data)) ?? LinuxPreferences()
    }

    public func save(_ preferences: LinuxPreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
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
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("codexbar-linux", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }
}

public struct LinuxProviderPreferencesRow: Sendable {
    public let provider: UsageProvider
    public let displayName: String
    public let enabled: Bool
    public let source: String
    public let subtitle: String

    public init(
        provider: UsageProvider,
        displayName: String,
        enabled: Bool,
        source: String,
        subtitle: String)
    {
        self.provider = provider
        self.displayName = displayName
        self.enabled = enabled
        self.source = source
        self.subtitle = subtitle
    }
}

public enum LinuxPreferencesPresenter {
    public static func providerRows(
        config: CodexBarConfig,
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> [LinuxProviderPreferencesRow]
    {
        let normalized = config.normalized(metadata: metadata)
        return normalized.providers.map { providerConfig in
            let provider = providerConfig.id
            let providerMetadata = metadata[provider]
            let enabled = providerConfig.enabled ?? providerMetadata?.defaultEnabled ?? false
            let source = providerConfig.source?.rawValue ?? "auto"
            let subtitle = self.providerSubtitle(config: providerConfig, metadata: providerMetadata)
            return LinuxProviderPreferencesRow(
                provider: provider,
                displayName: providerMetadata?.displayName ?? provider.rawValue.capitalized,
                enabled: enabled,
                source: source,
                subtitle: subtitle)
        }
    }

    public static func aboutLines() -> [String] {
        [
            "CodexBar Linux is a native Ubuntu frontend for the CodexBar backend.",
            "It reuses CodexBarCLI JSON and the shared provider/config model from the main app.",
            "This branch is focused on bringing the macOS app structure to Ubuntu step by step.",
        ]
    }

    private static func providerSubtitle(config: ProviderConfig, metadata: ProviderMetadata?) -> String {
        var parts: [String] = []
        if let toggleTitle = metadata?.toggleTitle, !toggleTitle.isEmpty {
            parts.append(toggleTitle)
        } else {
            parts.append("Provider")
        }
        if let cookieSource = config.cookieSource {
            parts.append("Cookie source: \(cookieSource.rawValue)")
        }
        if config.extrasEnabled == true {
            parts.append("Extras enabled")
        }
        if let workspaceID = config.workspaceID, !workspaceID.isEmpty {
            parts.append("Workspace: \(workspaceID)")
        }
        return parts.joined(separator: " | ")
    }
}
