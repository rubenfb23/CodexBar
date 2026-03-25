import CodexBarCore
import Foundation

public struct LinuxProviderPayload: Decodable, Sendable {
    public let provider: String
    public let account: String?
    public let version: String?
    public let source: String
    public let status: LinuxProviderStatusPayload?
    public let usage: UsageSnapshot?
    public let credits: CreditsSnapshot?
    public let openaiDashboard: OpenAIDashboardSnapshot?
    public let error: LinuxProviderErrorPayload?

    public init(
        provider: String,
        account: String?,
        version: String?,
        source: String,
        status: LinuxProviderStatusPayload?,
        usage: UsageSnapshot?,
        credits: CreditsSnapshot?,
        openaiDashboard: OpenAIDashboardSnapshot?,
        error: LinuxProviderErrorPayload?)
    {
        self.provider = provider
        self.account = account
        self.version = version
        self.source = source
        self.status = status
        self.usage = usage
        self.credits = credits
        self.openaiDashboard = openaiDashboard
        self.error = error
    }
}

public struct LinuxProviderStatusPayload: Decodable, Sendable {
    public let indicator: Indicator
    public let description: String?
    public let updatedAt: Date?
    public let url: String

    public init(indicator: Indicator, description: String?, updatedAt: Date?, url: String) {
        self.indicator = indicator
        self.description = description
        self.updatedAt = updatedAt
        self.url = url
    }

    public enum Indicator: String, Decodable, Sendable {
        case none
        case minor
        case major
        case critical
        case maintenance
        case unknown

        public var label: String {
            switch self {
            case .none:
                return "Operational"
            case .minor:
                return "Partial outage"
            case .major:
                return "Major outage"
            case .critical:
                return "Critical issue"
            case .maintenance:
                return "Maintenance"
            case .unknown:
                return "Status unknown"
            }
        }
    }
}

public struct LinuxProviderErrorPayload: Decodable, Sendable {
    public let code: Int32
    public let message: String
    public let kind: Kind?

    public init(code: Int32, message: String, kind: Kind?) {
        self.code = code
        self.message = message
        self.kind = kind
    }

    public enum Kind: String, Decodable, Sendable {
        case args
        case config
        case provider
        case runtime
    }
}
