import CodexBarCore
import Foundation

public enum LinuxStatusLevel: Sendable, Equatable {
    case operational   // green
    case degraded      // yellow
    case incident      // red
}

public struct LinuxDashboardSnapshot: Sendable {
    public let refreshedAt: Date
    public let cliBinaryPath: String
    public let cards: [LinuxProviderCard]

    public init(refreshedAt: Date, cliBinaryPath: String, cards: [LinuxProviderCard]) {
        self.refreshedAt = refreshedAt
        self.cliBinaryPath = cliBinaryPath
        self.cards = cards
    }
}

public struct LinuxDashboardRenderOptions: Sendable {
    public let hidePersonalInfo: Bool
    public let usageBarsShowUsed: Bool
    public let resetTimeDisplayStyle: ResetTimeDisplayStyle
    public let showOptionalCreditsAndExtraUsage: Bool

    public init(
        hidePersonalInfo: Bool = false,
        usageBarsShowUsed: Bool = false,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = .countdown,
        showOptionalCreditsAndExtraUsage: Bool = true)
    {
        self.hidePersonalInfo = hidePersonalInfo
        self.usageBarsShowUsed = usageBarsShowUsed
        self.resetTimeDisplayStyle = resetTimeDisplayStyle
        self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
    }
}

public struct LinuxProviderCard: Sendable {
    public let providerID: String
    public let title: String
    public let subtitle: String
    public let statusLine: String
    public let metadataLine: String?
    public let footerLine: String?
    public let errorMessage: String?
    public let statusLevel: LinuxStatusLevel?
    public let usageBars: [LinuxUsageBar]

    public init(
        providerID: String,
        title: String,
        subtitle: String,
        statusLine: String,
        metadataLine: String?,
        footerLine: String?,
        errorMessage: String?,
        statusLevel: LinuxStatusLevel?,
        usageBars: [LinuxUsageBar])
    {
        self.providerID = providerID
        self.title = title
        self.subtitle = subtitle
        self.statusLine = statusLine
        self.metadataLine = metadataLine
        self.footerLine = footerLine
        self.errorMessage = errorMessage
        self.statusLevel = statusLevel
        self.usageBars = usageBars
    }
}

public struct LinuxUsageBar: Sendable {
    public let title: String
    public let fractionFilled: Double
    public let detail: String

    public init(title: String, fractionFilled: Double, detail: String) {
        self.title = title
        self.fractionFilled = fractionFilled
        self.detail = detail
    }
}

public enum LinuxDashboardPresenter {
    public static func makeSnapshot(
        from payloads: [LinuxProviderPayload],
        cliBinaryPath: String,
        refreshedAt: Date = Date(),
        hidePersonalInfo: Bool = false,
        options: LinuxDashboardRenderOptions? = nil) -> LinuxDashboardSnapshot
    {
        let resolvedOptions = options ?? LinuxDashboardRenderOptions(hidePersonalInfo: hidePersonalInfo)
        let cards = payloads
            .map { Self.makeCard(from: $0, options: resolvedOptions) }
            .sorted { lhs, rhs in
                if lhs.title == rhs.title {
                    return lhs.providerID < rhs.providerID
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        return LinuxDashboardSnapshot(refreshedAt: refreshedAt, cliBinaryPath: cliBinaryPath, cards: cards)
    }

    public static func refreshSubtitle(for snapshot: LinuxDashboardSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let count = snapshot.cards.count
        let noun = count == 1 ? "provider" : "providers"
        return "Refreshed \(formatter.string(from: snapshot.refreshedAt)) with \(count) \(noun) from \(snapshot.cliBinaryPath)"
    }

    private static func makeCard(from payload: LinuxProviderPayload, options: LinuxDashboardRenderOptions) -> LinuxProviderCard {
        let title = self.friendlyProviderName(for: payload.provider)
        let account = self.accountLabel(for: payload, hidePersonalInfo: options.hidePersonalInfo)
        let plan = self.planLabel(for: payload)
        let subtitle = [account, plan].compactMap { $0 }.joined(separator: " | ").nilIfEmpty
            ?? self.fallbackSubtitle(for: payload)
        let usageBars = self.usageBars(for: payload, options: options)
        let metadataLine = self.metadataLine(for: payload)
        let footerLine = self.footerLine(for: payload, options: options)
        let errorMessage = payload.error?.message
        let statusLine = self.statusLine(for: payload)
        return LinuxProviderCard(
            providerID: payload.provider,
            title: title,
            subtitle: subtitle,
            statusLine: statusLine,
            metadataLine: metadataLine,
            footerLine: footerLine,
            errorMessage: errorMessage,
            statusLevel: self.statusLevel(for: payload),
            usageBars: usageBars)
    }

    private static func usageBars(for payload: LinuxProviderPayload, options: LinuxDashboardRenderOptions) -> [LinuxUsageBar] {
        var bars: [LinuxUsageBar] = []
        if let usage = payload.usage {
            if let primary = usage.primary {
                bars.append(self.makeBar(
                    title: self.windowTitle(for: primary, fallback: "Primary window"),
                    window: primary,
                    options: options))
            }
            if let secondary = usage.secondary {
                bars.append(self.makeBar(
                    title: self.windowTitle(for: secondary, fallback: "Secondary window"),
                    window: secondary,
                    options: options))
            }
            if let tertiary = usage.tertiary {
                bars.append(self.makeBar(
                    title: self.windowTitle(for: tertiary, fallback: "Tertiary window"),
                    window: tertiary,
                    options: options))
            }
        }
        if let codeReview = payload.openaiDashboard?.codeReviewLimit {
            bars.append(self.makeBar(title: "Code review", window: codeReview, options: options))
        }
        return bars
    }

    private static func windowTitle(for window: RateWindow, fallback: String) -> String {
        switch window.windowMinutes {
        case 60:
            return "1h"
        case 300:
            return "5h"
        case 1_440:
            return "Day"
        case 10_080:
            return "Week"
        case 43_200:
            return "Month"
        default:
            return fallback
        }
    }

    private static func makeBar(title: String, window: RateWindow, options: LinuxDashboardRenderOptions) -> LinuxUsageBar {
        let used = max(0, min(window.usedPercent, 100))
        let remaining = max(0, min(window.remainingPercent, 100))
        let fillPercent = options.usageBarsShowUsed ? used : remaining
        let usageText = UsageFormatter.usageLine(remaining: remaining, used: used, showUsed: options.usageBarsShowUsed)
        let resetText = UsageFormatter.resetLine(for: window, style: options.resetTimeDisplayStyle) ?? "Reset unavailable"
        let detail = "\(usageText) | \(resetText)"
        return LinuxUsageBar(title: title, fractionFilled: fillPercent / 100, detail: detail)
    }

    private static func statusLevel(for payload: LinuxProviderPayload) -> LinuxStatusLevel? {
        if payload.error != nil { return .incident }
        guard let indicator = payload.status?.indicator else { return nil }
        switch indicator {
        // .maintenance and .unknown are treated as operational — the provider is
        // not reporting an active incident, so the UI shows green rather than yellow.
        case .none, .maintenance, .unknown:
            return .operational
        case .minor:
            return .degraded
        case .major, .critical:
            return .incident
        }
    }

    private static func statusLine(for payload: LinuxProviderPayload) -> String {
        if let error = payload.error {
            return "Error (\(error.kind?.rawValue ?? "runtime")): \(error.message)"
        }
        guard let status = payload.status else {
            return "No provider status feed configured"
        }
        if let description = status.description, !description.isEmpty {
            return "\(status.indicator.label) | \(description)"
        }
        return status.indicator.label
    }

    private static func metadataLine(for payload: LinuxProviderPayload) -> String? {
        var parts = ["Source: \(payload.source)"]
        if let version = payload.version, !version.isEmpty {
            parts.append("Version: \(version)")
        }
        if let statusURL = payload.status?.url, !statusURL.isEmpty {
            parts.append(statusURL)
        }
        return parts.joined(separator: " | ").nilIfEmpty
    }

    private static func footerLine(for payload: LinuxProviderPayload, options: LinuxDashboardRenderOptions) -> String? {
        var parts: [String] = []
        if options.showOptionalCreditsAndExtraUsage, let credits = payload.credits?.remaining {
            parts.append("Credits: \(self.decimalString(credits))")
        } else if options.showOptionalCreditsAndExtraUsage, let credits = payload.openaiDashboard?.creditsRemaining {
            parts.append("Credits: \(self.decimalString(credits))")
        }
        if let updatedAt = payload.usage?.updatedAt ?? payload.credits?.updatedAt ?? payload.openaiDashboard?.updatedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Snapshot: \(formatter.string(from: updatedAt))")
        }
        return parts.joined(separator: " | ").nilIfEmpty
    }

    private static func accountLabel(for payload: LinuxProviderPayload, hidePersonalInfo: Bool) -> String? {
        let value = payload.usage?.identity?.accountEmail
            ?? payload.openaiDashboard?.signedInEmail
            ?? payload.account
        guard hidePersonalInfo else { return value }
        return self.redactEmail(value)
    }

    private static func planLabel(for payload: LinuxProviderPayload) -> String? {
        payload.usage?.identity?.loginMethod
            ?? payload.openaiDashboard?.accountPlan
    }

    private static func fallbackSubtitle(for payload: LinuxProviderPayload) -> String {
        if payload.error == nil {
            return "Connected via \(self.sourceDisplayName(payload.source))"
        }
        return "No account metadata"
    }

    private static func sourceDisplayName(_ source: String) -> String {
        switch source.lowercased() {
        case "oauth":
            return "OAuth"
        case "cli":
            return "CLI"
        case "codex-cli":
            return "Codex CLI"
        case "api":
            return "API"
        case "web":
            return "Web"
        case "auto":
            return "Auto"
        default:
            return source
                .split(separator: "-")
                .map { part in
                    part.prefix(1).uppercased() + String(part.dropFirst())
                }
                .joined(separator: " ")
        }
    }

    private static func friendlyProviderName(for providerID: String) -> String {
        switch providerID {
        case "codex":
            return "Codex"
        case "claude":
            return "Claude"
        case "cursor":
            return "Cursor"
        case "copilot":
            return "GitHub Copilot"
        case "openrouter":
            return "OpenRouter"
        case "jetbrains":
            return "JetBrains"
        case "opencode":
            return "OpenCode"
        default:
            return providerID
                .split(separator: "-")
                .map { part in
                    part.prefix(1).uppercased() + String(part.dropFirst())
                }
                .joined(separator: " ")
        }
    }

    private static func percentString(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func decimalString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func redactEmail(_ value: String?) -> String? {
        guard let value, let atIndex = value.firstIndex(of: "@") else { return value }
        let prefix = value[..<atIndex]
        let suffix = value[atIndex...]
        guard prefix.count > 2 else { return "***\(suffix)" }
        let visible = prefix.prefix(2)
        return "\(visible)***\(suffix)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
