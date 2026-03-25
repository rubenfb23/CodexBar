import CodexBarCore
@testable import CodexBarLinuxSupport
import Foundation
import Testing

@Suite
struct CodexBarLinuxSupportTests {
    @Test
    func presenterBuildsCardsFromCLIJSONShape() {
        let payloads = [
            LinuxProviderPayload(
                provider: "codex",
                account: nil,
                version: "1.2.3",
                source: "cli",
                status: LinuxProviderStatusPayload(
                    indicator: .none,
                    description: "All systems operational",
                    updatedAt: nil,
                    url: "https://status.openai.com"),
                usage: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 28,
                        windowMinutes: 300,
                        resetsAt: Date(timeIntervalSince1970: 1_750_000_000),
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                    identity: ProviderIdentitySnapshot(
                        providerID: .codex,
                        accountEmail: "ruben@example.com",
                        accountOrganization: nil,
                        loginMethod: "Pro")),
                credits: CreditsSnapshot(
                    remaining: 41.5,
                    events: [],
                    updatedAt: Date(timeIntervalSince1970: 1_750_000_000)),
                openaiDashboard: nil,
                error: nil),
            LinuxProviderPayload(
                provider: "claude",
                account: nil,
                version: nil,
                source: "api",
                status: nil,
                usage: nil,
                credits: nil,
                openaiDashboard: nil,
                error: LinuxProviderErrorPayload(code: 1, message: "Missing token", kind: .provider)),
        ]

        let snapshot = LinuxDashboardPresenter.makeSnapshot(
            from: payloads,
            cliBinaryPath: "/tmp/CodexBarCLI",
            refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(snapshot.cards.count == 2)
        #expect(snapshot.cards[0].title == "Claude")
        #expect(snapshot.cards[0].errorMessage == "Missing token")
        #expect(snapshot.cards[1].title == "Codex")
        #expect(snapshot.cards[1].subtitle.contains("ruben@example.com"))
        #expect(snapshot.cards[1].subtitle.contains("Pro"))
        #expect(snapshot.cards[1].usageBars.count == 1)
        #expect(snapshot.cards[1].usageBars[0].title == "5h")
        #expect(snapshot.cards[1].footerLine?.contains("41.5") == true)
        #expect(LinuxDashboardPresenter.refreshSubtitle(for: snapshot).contains("/tmp/CodexBarCLI"))
    }

    @Test
    func presenterAddsCodeReviewWindowWhenDashboardDataExists() {
        let payload = LinuxProviderPayload(
            provider: "codex",
            account: nil,
            version: nil,
            source: "web",
            status: nil,
            usage: nil,
            credits: nil,
            openaiDashboard: OpenAIDashboardSnapshot(
                signedInEmail: "ruben@example.com",
                codeReviewRemainingPercent: 72,
                codeReviewLimit: RateWindow(
                    usedPercent: 28,
                    windowMinutes: 1_440,
                    resetsAt: Date(timeIntervalSince1970: 1_750_000_000),
                    resetDescription: nil),
                creditEvents: [],
                dailyBreakdown: [],
                usageBreakdown: [],
                creditsPurchaseURL: nil,
                primaryLimit: nil,
                secondaryLimit: nil,
                creditsRemaining: 10,
                accountPlan: "Plus",
                updatedAt: Date(timeIntervalSince1970: 1_750_000_000)),
            error: nil)

        let snapshot = LinuxDashboardPresenter.makeSnapshot(
            from: [payload],
            cliBinaryPath: "/tmp/CodexBarCLI",
            refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(snapshot.cards.count == 1)
        #expect(snapshot.cards[0].usageBars.count == 1)
        #expect(snapshot.cards[0].usageBars[0].title == "Code review")
        #expect(snapshot.cards[0].footerLine?.contains("10") == true)
    }

    @Test
    func presenterRedactsEmailWhenPrivacyEnabled() {
        let payload = LinuxProviderPayload(
            provider: "codex",
            account: "ruben@example.com",
            version: nil,
            source: "cli",
            status: nil,
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "ruben@example.com",
                    accountOrganization: nil,
                    loginMethod: "Pro")),
            credits: nil,
            openaiDashboard: nil,
            error: nil)

        let snapshot = LinuxDashboardPresenter.makeSnapshot(
            from: [payload],
            cliBinaryPath: "/tmp/CodexBarCLI",
            refreshedAt: Date(timeIntervalSince1970: 1_750_000_000),
            hidePersonalInfo: true)

        #expect(snapshot.cards.count == 1)
        #expect(snapshot.cards[0].subtitle.contains("ru***@example.com"))
    }

    @Test
    func presenterUsesConnectedViaFallbackWhenIdentityIsMissing() {
        let payload = LinuxProviderPayload(
            provider: "claude",
            account: nil,
            version: nil,
            source: "oauth",
            status: nil,
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: nil)),
            credits: nil,
            openaiDashboard: nil,
            error: nil)

        let snapshot = LinuxDashboardPresenter.makeSnapshot(
            from: [payload],
            cliBinaryPath: "/tmp/CodexBarCLI",
            refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(snapshot.cards.count == 1)
        #expect(snapshot.cards[0].subtitle == "Connected via OAuth")
    }

    @Test
    func presenterUsesDurationLabelsForPrimaryAndWeeklyWindows() {
        let payload = LinuxProviderPayload(
            provider: "codex",
            account: nil,
            version: nil,
            source: "oauth",
            status: nil,
            usage: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 50,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_750_000_000),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 10_080,
                    resetsAt: Date(timeIntervalSince1970: 1_750_000_000),
                    resetDescription: nil),
                updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
                identity: nil),
            credits: nil,
            openaiDashboard: nil,
            error: nil)

        let snapshot = LinuxDashboardPresenter.makeSnapshot(
            from: [payload],
            cliBinaryPath: "/tmp/CodexBarCLI",
            refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(snapshot.cards.count == 1)
        #expect(snapshot.cards[0].usageBars.map(\.title) == ["5h", "Week"])
    }

    @Test
    func preferencesPresenterReflectsConfigOrderAndState() {
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(id: .claude, enabled: true, source: .api),
                ProviderConfig(id: .codex, enabled: false, source: .cli),
            ])

        let rows = LinuxPreferencesPresenter.providerRows(config: config)

        #expect(rows.count >= 2)
        #expect(rows[0].provider == .claude)
        #expect(rows[0].enabled == true)
        #expect(rows[0].source == "api")
        #expect(rows[1].provider == .codex)
        #expect(rows[1].enabled == false)
        #expect(rows[1].source == "cli")
    }

    @Test
    func backendExtractsMultipleJSONArraySegments() {
        let stdout = """
        [
          {
            "provider": "codex",
            "source": "cli"
          }
        ]
        [
          {
            "provider": "cli",
            "source": "cli",
            "error": {
              "code": 1,
              "message": "Error",
              "kind": "provider"
            }
          }
        ]
        """

        let segments = LinuxCLIBackend.extractJSONArraySegments(from: stdout)

        #expect(segments.count == 2)
        #expect(segments[0].contains("\"provider\": \"codex\""))
        #expect(segments[1].contains("\"provider\": \"cli\""))
    }

    @Test
    func backendDecodesProviderPayloadsAndDropsGenericCLIPayload() throws {
        let stdout = """
        [
          {
            "provider": "codex",
            "source": "auto",
            "error": {
              "code": 1,
              "message": "Provider failed",
              "kind": "provider"
            }
          },
          {
            "provider": "claude",
            "source": "auto"
          }
        ]
        [
          {
            "provider": "cli",
            "source": "cli",
            "error": {
              "code": 1,
              "message": "Error",
              "kind": "provider"
            }
          }
        ]
        """

        let payloads = try LinuxCLIBackend.decodePayloadsFromCLIStdout(stdout)

        #expect(payloads.count == 2)
        #expect(payloads.map(\.provider) == ["codex", "claude"])
    }

    @Test
    func backendBuildsUsageArgumentsForSingleEnabledProvider() {
        let arguments = LinuxCLIBackend.usageArguments(for: .claude, sourceMode: .oauth)

        #expect(arguments.contains("--json-only"))
        #expect(arguments.contains("--status"))
        #expect(arguments.contains("claude"))
        #expect(arguments.contains("--source"))
        #expect(arguments.contains("oauth"))
        #expect(!arguments.contains("all"))
    }

    @Test
    func backendPrefersLinuxSafeFallbackForWebCapableProviders() {
        let codexAttempts = LinuxCLIBackend.linuxSourceAttempts(for: .codex, configuredSource: .auto)
        let claudeAttempts = LinuxCLIBackend.linuxSourceAttempts(for: .claude, configuredSource: .auto)
        let kiloAttempts = LinuxCLIBackend.linuxSourceAttempts(for: .kilo, configuredSource: .auto)

        #expect(codexAttempts == [.oauth, .cli])
        #expect(claudeAttempts == [.oauth, .cli])
        #expect(kiloAttempts == [.auto])
    }

    @Test
    func backendDetectsSuccessfulPayloadForProvider() {
        let payloads = [
            LinuxProviderPayload(
                provider: "codex",
                account: nil,
                version: nil,
                source: "oauth",
                status: nil,
                usage: UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date(timeIntervalSince1970: 1_750_000_000), identity: nil),
                credits: nil,
                openaiDashboard: nil,
                error: nil),
            LinuxProviderPayload(
                provider: "cli",
                account: nil,
                version: nil,
                source: "cli",
                status: nil,
                usage: nil,
                credits: nil,
                openaiDashboard: nil,
                error: LinuxProviderErrorPayload(code: 1, message: "Error", kind: .provider)),
        ]

        #expect(LinuxCLIBackend.containsSuccessfulPayload(payloads, for: .codex))
        #expect(!LinuxCLIBackend.containsSuccessfulPayload(payloads, for: .claude))
    }
}
