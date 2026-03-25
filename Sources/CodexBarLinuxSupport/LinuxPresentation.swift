import CodexBarCore
import Foundation

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

public struct LinuxProviderCard: Sendable {
    public let providerID: String
    public let title: String
    public let subtitle: String
    public let statusLine: String
    public let metadataLine: String?
    public let footerLine: String?
    public let errorMessage: String?
    public let usageBars: [LinuxUsageBar]

    public init(
        providerID: String,
        title: String,
        subtitle: String,
        statusLine: String,
        metadataLine: String?,
        footerLine: String?,
        errorMessage: String?,
        usageBars: [LinuxUsageBar])
    {
        self.providerID = providerID
        self.title = title
        self.subtitle = subtitle
        self.statusLine = statusLine
        self.metadataLine = metadataLine
        self.footerLine = footerLine
        self.errorMessage = errorMessage
        self.usageBars = usageBars
    }
}

public struct LinuxUsageBar: Sendable {
    public let title: String
    public let fractionUsed: Double
    public let detail: String

    public init(title: String, fractionUsed: Double, detail: String) {
        self.title = title
        self.fractionUsed = fractionUsed
        self.detail = detail
    }
}

public enum LinuxDashboardPresenter {
    public static func makeSnapshot(
        from payloads: [LinuxProviderPayload],
        cliBinaryPath: String,
        refreshedAt: Date = Date(),
        hidePersonalInfo: Bool = false) -> LinuxDashboardSnapshot
    {
        let cards = payloads
            .map { Self.makeCard(from: $0, hidePersonalInfo: hidePersonalInfo) }
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

    private static func makeCard(from payload: LinuxProviderPayload, hidePersonalInfo: Bool) -> LinuxProviderCard {
        let title = self.friendlyProviderName(for: payload.provider)
        let account = self.accountLabel(for: payload, hidePersonalInfo: hidePersonalInfo)
        let plan = self.planLabel(for: payload)
        let subtitle = [account, plan].compactMap { $0 }.joined(separator: " | ").nilIfEmpty ?? "No account metadata"
        let usageBars = self.usageBars(for: payload)
        let metadataLine = self.metadataLine(for: payload)
        let footerLine = self.footerLine(for: payload)
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
            usageBars: usageBars)
    }

    private static func usageBars(for payload: LinuxProviderPayload) -> [LinuxUsageBar] {
        var bars: [LinuxUsageBar] = []
        if let usage = payload.usage {
            if let primary = usage.primary {
                bars.append(self.makeBar(title: "Primary window", window: primary))
            }
            if let secondary = usage.secondary {
                bars.append(self.makeBar(title: "Secondary window", window: secondary))
            }
            if let tertiary = usage.tertiary {
                bars.append(self.makeBar(title: "Tertiary window", window: tertiary))
            }
        }
        if let codeReview = payload.openaiDashboard?.codeReviewLimit {
            bars.append(self.makeBar(title: "Code review", window: codeReview))
        }
        return bars
    }

    private static func makeBar(title: String, window: RateWindow) -> LinuxUsageBar {
        let percent = max(0, min(window.usedPercent, 100))
        let usedText = Self.percentString(percent)
        let resetText: String
        if let resetDescription = window.resetDescription, !resetDescription.isEmpty {
            resetText = resetDescription
        } else if let resetsAt = window.resetsAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            resetText = "resets \(formatter.string(from: resetsAt))"
        } else {
            resetText = "reset unavailable"
        }
        let detail = "\(usedText) used | \(resetText)"
        return LinuxUsageBar(title: title, fractionUsed: percent / 100, detail: detail)
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

    private static func footerLine(for payload: LinuxProviderPayload) -> String? {
        var parts: [String] = []
        if let credits = payload.credits?.remaining {
            parts.append("Credits: \(self.decimalString(credits))")
        } else if let credits = payload.openaiDashboard?.creditsRemaining {
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
