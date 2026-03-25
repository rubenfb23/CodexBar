#if os(Linux)
import CodexBarCore
import CodexBarLinuxSupport
import CodexBarLinuxUIBridge
import Dispatch
import Foundation
import Glibc

private let appID = "com.steipete.codexbar.linux"
private typealias LinuxAppPtr = UnsafeMutablePointer<AdwApplication>
private typealias LinuxWindowPtr = UnsafeMutablePointer<AdwApplicationWindow>
private typealias LinuxWidgetPtr = UnsafeMutablePointer<GtkWidget>
private typealias LinuxPlainWindowPtr = UnsafeMutablePointer<GtkWindow>

private func requireValue<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        fatalError(message)
    }
    return value
}

@main
enum CodexBarLinuxApp {
    static func main() {
        codexbar_linux_init()
        let controller = LinuxWindowController()
        controller.run()
    }
}

private func codexbarLinuxActivateCallback(_ app: LinuxAppPtr?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleActivate(application: app)
}

private func codexbarLinuxWidgetCallback(_ widget: LinuxWidgetPtr?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let handler = Unmanaged<LinuxWidgetHandlerBox>.fromOpaque(userData).takeUnretainedValue()
    handler.handle(widget)
}

private func codexbarLinuxMainThreadCallback(_ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let handler = Unmanaged<LinuxMainThreadHandlerBox>.fromOpaque(userData).takeRetainedValue()
    handler.handle()
}

private func codexbarLinuxTimeoutCallback(_ userData: UnsafeMutableRawPointer?) -> Int32 {
    guard let userData else { return 0 }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleRefreshTimerFired()
    return 1
}

private final class LinuxWidgetHandlerBox {
    let handle: (LinuxWidgetPtr?) -> Void

    init(handle: @escaping (LinuxWidgetPtr?) -> Void) {
        self.handle = handle
    }
}

private final class LinuxMainThreadHandlerBox {
    let handle: () -> Void

    init(handle: @escaping () -> Void) {
        self.handle = handle
    }
}

private final class LinuxWindowController: @unchecked Sendable {
    private let backend = LinuxCLIBackend()
    private var preferences: LinuxPreferences
    private var application: LinuxAppPtr?
    private var subtitleLabel: LinuxWidgetPtr?
    private var overviewBox: LinuxWidgetPtr?
    private var providersBox: LinuxWidgetPtr?
    private var generalBox: LinuxWidgetPtr?
    private var displayBox: LinuxWidgetPtr?
    private var aboutBox: LinuxWidgetPtr?
    private var retainedPointer: UnsafeMutableRawPointer?
    private var retainedHandlers: [LinuxWidgetHandlerBox] = []
    private var refreshSequence = 0
    private var refreshTimerID: UInt32 = 0
    private var refreshInFlight = false
    // Compact popup (undecorated, persistent — built once and hidden)
    private var popupWindow: LinuxPlainWindowPtr?
    private var popupCardsBox: LinuxWidgetPtr?
    private var popupHeaderTimestampLabel: LinuxWidgetPtr?
    // Preferences window (the existing full tabbed window — built lazily)
    private var preferencesWindow: LinuxWindowPtr?
    private var sniRegistered = false

    init() {
        self.preferences = self.backend.loadPreferences()
    }

    func run() {
        self.retainedPointer = Unmanaged.passRetained(self).toOpaque()
        self.application = requireValue(
            appID.withCString { codexbar_linux_application_new($0) },
            "Failed to create CodexBar Linux application.")
        guard let application, let retainedPointer else { return }
        codexbar_linux_application_on_activate(application, codexbarLinuxActivateCallback, retainedPointer)
        _ = codexbar_linux_application_run(application)
    }

    func handleActivate(application: LinuxAppPtr?) {
        guard let application else { return }
        // Build popup once
        if self.popupWindow == nil {
            self.buildAndHidePopup()
        }
        // Build and show preferences window (kept for development — Task 6 replaces this)
        if self.preferencesWindow == nil {
            self.buildPreferencesWindow(application: application)
        }
        if let preferencesWindow = self.preferencesWindow {
            codexbar_linux_window_present(preferencesWindow)
        }
        self.configureRefreshTimer()
        self.refresh()
    }

    func refresh() {
        guard let subtitleLabel,
              self.overviewBox != nil,
              self.providersBox != nil,
              self.generalBox != nil,
              self.displayBox != nil,
              self.aboutBox != nil
        else {
            return
        }
        guard !self.refreshInFlight else { return }

        self.preferences = self.backend.loadPreferences()
        self.refreshInFlight = true
        self.setLabelText(subtitleLabel, "Refreshing usage from CodexBarCLI...")
        let renderOptions = self.renderOptions()
        self.refreshSequence += 1
        let refreshToken = self.refreshSequence

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result: Result<(LinuxDashboardLoadResult, CodexBarConfig), Error>
            do {
                let loadResult = try self.backend.fetchUsagePayloads()
                let config = try self.backend.loadConfig()
                result = .success((loadResult, config))
            } catch {
                result = .failure(error)
            }

            let handler = LinuxMainThreadHandlerBox { [weak self] in
                guard let self, refreshToken == self.refreshSequence else { return }
                self.applyRefreshResult(result, options: renderOptions)
            }
            codexbar_linux_main_context_invoke(
                codexbarLinuxMainThreadCallback,
                Unmanaged.passRetained(handler).toOpaque())
        }
    }

    func handleRefreshTimerFired() {
        self.refresh()
    }

    private func applyRefreshResult(
        _ result: Result<(LinuxDashboardLoadResult, CodexBarConfig), Error>,
        options: LinuxDashboardRenderOptions)
    {
        guard let subtitleLabel,
              let overviewBox,
              let providersBox,
              let generalBox,
              let displayBox,
              let aboutBox
        else {
            return
        }
        self.refreshInFlight = false

        switch result {
        case let .success((loadResult, config)):
            let snapshot = LinuxDashboardPresenter.makeSnapshot(
                from: loadResult.payloads,
                cliBinaryPath: loadResult.cliBinaryPath,
                options: options)
            self.renderOverview(snapshot: snapshot, exitCode: loadResult.exitCode, into: overviewBox)
            self.renderProvidersPage(config: config, snapshot: snapshot, into: providersBox)
            self.renderGeneralPage(into: generalBox)
            self.renderDisplayPage(into: displayBox)
            self.renderAboutPage(into: aboutBox)

            var subtitle = LinuxDashboardPresenter.refreshSubtitle(for: snapshot)
            if loadResult.exitCode != 0 {
                subtitle += " | CLI exited with \(loadResult.exitCode), some providers may be unavailable."
            }
            if !loadResult.cachedProviderIDs.isEmpty {
                let count = loadResult.cachedProviderIDs.count
                let noun = count == 1 ? "provider" : "providers"
                subtitle += " | Showing cached data for \(count) \(noun)."
            }
            self.setLabelText(subtitleLabel, subtitle)
            self.updatePopupCards(snapshot: snapshot, options: options)

        case let .failure(error):
            self.renderRefreshError(error.localizedDescription)
            codexbar_linux_box_remove_all(overviewBox)
            codexbar_linux_box_remove_all(providersBox)
            codexbar_linux_box_remove_all(generalBox)
            codexbar_linux_box_remove_all(displayBox)
            codexbar_linux_box_remove_all(aboutBox)

            let errorLabel = self.makeLabel(
                text: error.localizedDescription,
                xalign: 0,
                wrap: true,
                cssClasses: ["error"])
            codexbar_linux_box_append(overviewBox, errorLabel)
            self.renderGeneralPage(into: generalBox)
            self.renderDisplayPage(into: displayBox)
            self.renderAboutPage(into: aboutBox)
        }
    }

    private func openConfig() {
        do {
            let fileURL = try self.backend.openConfigInDefaultApp()
            if let subtitleLabel = self.subtitleLabel {
                self.setLabelText(subtitleLabel, "Opened config at \(fileURL.path)")
            }
        } catch {
            self.renderRefreshError(error.localizedDescription)
        }
    }

    private func setRefreshFrequency(_ frequency: LinuxRefreshFrequency) {
        self.preferences.refreshFrequency = frequency
        do {
            try self.backend.savePreferences(self.preferences)
        } catch {
            self.renderRefreshError(error.localizedDescription)
        }
        self.configureRefreshTimer()
        self.refresh()
    }

    private func setPreference(_ update: (inout LinuxPreferences) -> Void) {
        update(&self.preferences)
        do {
            try self.backend.savePreferences(self.preferences)
        } catch {
            self.renderRefreshError(error.localizedDescription)
        }
        self.configureRefreshTimer()
        self.refresh()
    }

    private func setProviderEnabled(_ provider: UsageProvider, enabled: Bool) {
        do {
            try self.backend.setProviderEnabled(provider, enabled: enabled)
        } catch {
            self.renderRefreshError(error.localizedDescription)
        }
        self.refresh()
    }

    private func buildPreferencesWindow(application: LinuxAppPtr) {
        let window = requireValue(codexbar_linux_window_new(application), "Failed to create application window.")
        self.preferencesWindow = window
        "CodexBar Ubuntu".withCString { codexbar_linux_window_set_title(window, $0) }
        codexbar_linux_window_set_default_size(window, 1080, 780)

        let root = requireValue(codexbar_linux_box_new_vertical(16), "Failed to create root box.")
        codexbar_linux_widget_set_margin_all(root, 24)
        codexbar_linux_widget_set_hexpand(root, 1)
        codexbar_linux_widget_set_vexpand(root, 1)

        let titleLabel = self.makeLabel(
            text: "CodexBar Ubuntu",
            xalign: 0,
            wrap: false,
            cssClasses: ["title-2"])
        codexbar_linux_box_append(root, titleLabel)

        let subtitleLabel = self.makeLabel(
            text: "Native Ubuntu port shaped after the macOS app.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"])
        self.subtitleLabel = subtitleLabel
        codexbar_linux_box_append(root, subtitleLabel)

        let toolbar = requireValue(codexbar_linux_box_new_horizontal(12), "Failed to create toolbar.")
        codexbar_linux_box_append(toolbar, self.makeButton(title: "Refresh") { [weak self] _ in
            self?.refresh()
        })
        codexbar_linux_box_append(toolbar, self.makeButton(title: "Open Config") { [weak self] _ in
            self?.openConfig()
        })
        codexbar_linux_box_append(root, toolbar)

        let stack = requireValue(codexbar_linux_stack_new(), "Failed to create page stack.")
        let switcher = requireValue(codexbar_linux_stack_switcher_new(), "Failed to create stack switcher.")
        codexbar_linux_stack_switcher_set_stack(switcher, stack)
        codexbar_linux_box_append(root, switcher)

        let overviewPage = self.makePageContainer()
        let providersPage = self.makePageContainer()
        let generalPage = self.makePageContainer()
        let displayPage = self.makePageContainer()
        let aboutPage = self.makePageContainer()

        self.overviewBox = overviewPage
        self.providersBox = providersPage
        self.generalBox = generalPage
        self.displayBox = displayPage
        self.aboutBox = aboutPage

        self.addPage(to: stack, name: "overview", title: "Overview", content: overviewPage)
        self.addPage(to: stack, name: "providers", title: "Providers", content: providersPage)
        self.addPage(to: stack, name: "general", title: "General", content: generalPage)
        self.addPage(to: stack, name: "display", title: "Display", content: displayPage)
        self.addPage(to: stack, name: "about", title: "About", content: aboutPage)

        codexbar_linux_widget_set_hexpand(stack, 1)
        codexbar_linux_widget_set_vexpand(stack, 1)
        codexbar_linux_box_append(root, stack)

        codexbar_linux_window_set_content(window, root)
    }

    private func buildAndHidePopup() {
        let popupWindow = requireValue(
            codexbar_linux_plain_window_new(),
            "Failed to create popup window.")
        self.popupWindow = popupWindow

        codexbar_linux_window_set_keep_above(popupWindow, 1)
        codexbar_linux_window_set_skip_taskbar(popupWindow, 1)

        let root = requireValue(codexbar_linux_box_new_vertical(0), "Failed to create popup root.")

        // --- Header ---
        let header = requireValue(codexbar_linux_box_new_horizontal(0), "Failed to create popup header.")
        codexbar_linux_widget_set_margin_all(header, 12)
        let titleLabel = self.makeLabel(text: "CodexBar", xalign: 0, wrap: false, cssClasses: ["title-4"])
        codexbar_linux_widget_set_hexpand(titleLabel, 1)
        let timestampLabel = self.makeLabel(text: "", xalign: 1, wrap: false, cssClasses: ["dim-label"])
        self.popupHeaderTimestampLabel = timestampLabel
        codexbar_linux_box_append(header, titleLabel)
        codexbar_linux_box_append(header, timestampLabel)
        codexbar_linux_box_append(root, header)
        codexbar_linux_box_append(root, requireValue(codexbar_linux_separator_new(), "sep"))

        // --- Scrollable cards area ---
        let scroll = requireValue(codexbar_linux_scrolled_window_new(), "Failed to create popup scroll.")
        codexbar_linux_widget_set_vexpand(scroll, 1)
        let cardsBox = requireValue(codexbar_linux_box_new_vertical(0), "Failed to create cards box.")
        codexbar_linux_widget_set_margin_all(cardsBox, 8)
        self.popupCardsBox = cardsBox
        codexbar_linux_scrolled_window_set_child(scroll, cardsBox)
        codexbar_linux_box_append(root, scroll)
        codexbar_linux_box_append(root, requireValue(codexbar_linux_separator_new(), "sep"))

        // --- Footer (icon buttons only) ---
        let footer = requireValue(codexbar_linux_box_new_horizontal(4), "Failed to create popup footer.")
        codexbar_linux_widget_set_margin_all(footer, 8)

        let spacer = requireValue(codexbar_linux_box_new_horizontal(0), "Failed to create spacer.")
        codexbar_linux_widget_set_hexpand(spacer, 1)
        codexbar_linux_box_append(footer, spacer)

        codexbar_linux_box_append(footer, self.makeButton(title: "⚙") { [weak self] _ in
            self?.showPreferences()
        })
        codexbar_linux_box_append(footer, self.makeButton(title: "↻") { [weak self] _ in
            self?.refresh()
        })
        codexbar_linux_box_append(footer, self.makeButton(title: "✕") { [weak self] _ in
            guard let self, let application = self.application else { return }
            g_application_quit(UnsafeMutablePointer<GApplication>(OpaquePointer(application)))
        })
        codexbar_linux_box_append(root, footer)

        codexbar_linux_plain_window_set_child(popupWindow, root)
        // Hide immediately — will be shown when tray icon is clicked
        let popupWidget = UnsafeMutablePointer<GtkWidget>(OpaquePointer(popupWindow))
        codexbar_linux_widget_set_visible(popupWidget, 0)
    }

    private func showPreferences() {
        guard let application else { return }
        if self.preferencesWindow == nil {
            self.buildPreferencesWindow(application: application)
        }
        if let preferencesWindow = self.preferencesWindow {
            codexbar_linux_window_present(preferencesWindow)
        }
    }

    private func updatePopupCards(snapshot: LinuxDashboardSnapshot, options: LinuxDashboardRenderOptions) {
        guard let popupCardsBox, let popupHeaderTimestampLabel else { return }

        // Update timestamp
        let elapsed = Int(-snapshot.refreshedAt.timeIntervalSinceNow / 60)
        let timestampText = elapsed < 1 ? "just now" : "↻ \(elapsed) min ago"
        self.setLabelText(popupHeaderTimestampLabel, timestampText)

        // Rebuild cards
        codexbar_linux_box_remove_all(popupCardsBox)

        if snapshot.cards.isEmpty {
            let emptyLabel = self.makeLabel(
                text: "No providers configured.",
                xalign: 0.5, wrap: false, cssClasses: ["dim-label"])
            codexbar_linux_widget_set_margin_all(emptyLabel, 16)
            codexbar_linux_box_append(popupCardsBox, emptyLabel)
            return
        }

        var isFirst = true
        for card in snapshot.cards {
            if !isFirst {
                codexbar_linux_box_append(popupCardsBox, requireValue(codexbar_linux_separator_new(), "sep"))
            }
            isFirst = false
            codexbar_linux_box_append(popupCardsBox, self.makePopupCard(card))
        }
    }

    private func makePopupCard(_ card: LinuxProviderCard) -> LinuxWidgetPtr {
        let cardBox = requireValue(codexbar_linux_box_new_vertical(6), "Failed to create card box.")
        codexbar_linux_widget_set_margin_all(cardBox, 10)

        // Title row: [logo] Name  ● Status
        let titleRow = requireValue(codexbar_linux_box_new_horizontal(7), "Failed to create title row.")

        let logoWidget = self.makeProviderLogo(providerID: card.providerID)
        codexbar_linux_box_append(titleRow, logoWidget)

        let nameLabel = self.makeLabel(text: card.title, xalign: 0, wrap: false, cssClasses: ["heading"])
        codexbar_linux_widget_set_hexpand(nameLabel, 1)
        codexbar_linux_box_append(titleRow, nameLabel)

        if let statusLevel = card.statusLevel {
            let statusCSSClass: String
            switch statusLevel {
            case .operational: statusCSSClass = "success"
            case .degraded:    statusCSSClass = "warning"
            case .incident:    statusCSSClass = "error"
            }
            let statusDot = self.makeLabel(text: "●", xalign: 1, wrap: false, cssClasses: [statusCSSClass])
            codexbar_linux_box_append(titleRow, statusDot)
        }
        codexbar_linux_box_append(cardBox, titleRow)

        // Usage bars
        for bar in card.usageBars {
            let barRow = requireValue(codexbar_linux_box_new_horizontal(6), "Failed to create bar row.")

            let windowLabel = self.makeLabel(text: bar.title, xalign: 1, wrap: false, cssClasses: [])
            codexbar_linux_box_append(barRow, windowLabel)

            let progressBar = requireValue(codexbar_linux_progress_bar_new(), "Failed to create progress bar.")
            codexbar_linux_widget_set_hexpand(progressBar, 1)
            codexbar_linux_progress_bar_set_fraction(progressBar, bar.fractionFilled)
            codexbar_linux_box_append(barRow, progressBar)

            let pct = Int((bar.fractionFilled * 100).rounded())
            let pctCSS = pct < 20 ? ["error"] : ["dim-label"]
            let pctLabel = self.makeLabel(text: "\(pct)%", xalign: 1, wrap: false, cssClasses: pctCSS)
            codexbar_linux_box_append(barRow, pctLabel)

            codexbar_linux_box_append(cardBox, barRow)
        }

        if let errorMessage = card.errorMessage {
            let errorLabel = self.makeLabel(text: errorMessage, xalign: 0, wrap: true, cssClasses: ["error"])
            codexbar_linux_box_append(cardBox, errorLabel)
        }

        return cardBox
    }

    private func makeProviderLogo(providerID: String) -> LinuxWidgetPtr {
        // Only include providers whose SVG is actually bundled in the GResource
        // (openai/codex and opencode slugs don't exist in Simple Icons — they fall back)
        let resourceMap: [String: (path: String, bgColor: String)] = [
            "claude":    ("/com/steipete/codexbar/icons/claude.svg",    "#CC785C"),
            "cursor":    ("/com/steipete/codexbar/icons/cursor.svg",    "#1C1C1E"),
            "copilot":   ("/com/steipete/codexbar/icons/copilot.svg",   "#24292E"),
            "openrouter":("/com/steipete/codexbar/icons/openrouter.svg","#6467F2"),
            "jetbrains": ("/com/steipete/codexbar/icons/jetbrains.svg", "#000000"),
        ]

        if let entry = resourceMap[providerID] {
            let imageWidget = entry.path.withCString { codexbar_linux_image_from_resource($0, 12) }
            let container = requireValue(codexbar_linux_box_new_horizontal(0), "container")
            entry.bgColor.withCString { codexbar_linux_widget_set_background_color(container, $0) }
            if let imageWidget {
                codexbar_linux_box_append(container, imageWidget)
            }
            return container
        }

        // Fallback: initial letter
        let initial = String(providerID.prefix(1).uppercased())
        return self.makeLabel(text: initial, xalign: 0.5, wrap: false, cssClasses: ["dim-label"])
    }

    private func configureRefreshTimer() {
        if self.refreshTimerID != 0 {
            codexbar_linux_source_remove(self.refreshTimerID)
            self.refreshTimerID = 0
        }

        guard let retainedPointer, let interval = self.preferences.refreshFrequency.seconds else { return }
        self.refreshTimerID = codexbar_linux_timeout_add_seconds(interval, codexbarLinuxTimeoutCallback, retainedPointer)
    }

    private func renderOptions() -> LinuxDashboardRenderOptions {
        LinuxDashboardRenderOptions(
            hidePersonalInfo: self.preferences.hidePersonalInfo,
            usageBarsShowUsed: self.preferences.usageBarsShowUsed,
            resetTimeDisplayStyle: self.preferences.resetTimesShowAbsolute ? .absolute : .countdown,
            showOptionalCreditsAndExtraUsage: self.preferences.showOptionalCreditsAndExtraUsage)
    }

    private func renderOverview(snapshot: LinuxDashboardSnapshot, exitCode: Int32, into box: LinuxWidgetPtr) {
        codexbar_linux_box_remove_all(box)
        if snapshot.cards.isEmpty {
            let emptyLabel = self.makeLabel(
                text: "CodexBarCLI returned no enabled providers.",
                xalign: 0,
                wrap: true,
                cssClasses: ["dim-label"])
            codexbar_linux_box_append(box, emptyLabel)
            return
        }

        for card in snapshot.cards {
            let widget = self.makeCardWidget(card)
            codexbar_linux_box_append(box, widget)
        }

        if exitCode != 0 {
            let footer = self.makeLabel(
                text: "The refresh completed with CLI errors. Some cards may be partial.",
                xalign: 0,
                wrap: true,
                cssClasses: ["dim-label"])
            codexbar_linux_box_append(box, footer)
        }
    }

    private func renderProvidersPage(config: CodexBarConfig, snapshot: LinuxDashboardSnapshot, into box: LinuxWidgetPtr) {
        codexbar_linux_box_remove_all(box)

        let intro = self.makeLabel(
            text: "Providers mirrors the macOS Providers pane: toggle providers and inspect source/config status.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"])
        codexbar_linux_box_append(box, intro)

        let cardsByProvider = Dictionary(uniqueKeysWithValues: snapshot.cards.map { ($0.providerID, $0) })
        let rows = LinuxPreferencesPresenter.providerRows(config: config)
        for row in rows {
            let frame = requireValue(row.displayName.withCString { codexbar_linux_frame_new($0) }, "Failed to create frame.")
            let content = requireValue(codexbar_linux_box_new_vertical(8), "Failed to create provider content box.")
            codexbar_linux_widget_set_margin_all(content, 16)

            let toggle = self.makeCheckButton(title: "Enabled", active: row.enabled) { [weak self] widget in
                guard let self else { return }
                let active = codexbar_linux_check_button_get_active(widget) != 0
                self.setProviderEnabled(row.provider, enabled: active)
            }
            codexbar_linux_box_append(content, toggle)

            let subtitle = self.makeLabel(text: row.subtitle, xalign: 0, wrap: true, cssClasses: ["dim-label"])
            codexbar_linux_box_append(content, subtitle)

            let source = self.makeLabel(
                text: "Source mode: \(row.source)",
                xalign: 0,
                wrap: false,
                cssClasses: [])
            codexbar_linux_box_append(content, source)

            if let card = cardsByProvider[row.provider.rawValue] {
                let status = self.makeLabel(text: card.statusLine, xalign: 0, wrap: true, cssClasses: [])
                codexbar_linux_box_append(content, status)
                if let footerLine = card.footerLine {
                    let footer = self.makeLabel(text: footerLine, xalign: 0, wrap: true, cssClasses: ["dim-label"])
                    codexbar_linux_box_append(content, footer)
                }
            } else {
                let noUsage = self.makeLabel(
                    text: "No usage snapshot rendered in the current refresh.",
                    xalign: 0,
                    wrap: true,
                    cssClasses: ["dim-label"])
                codexbar_linux_box_append(content, noUsage)
            }

            codexbar_linux_frame_set_child(frame, content)
            codexbar_linux_box_append(box, frame)
        }
    }

    private func renderGeneralPage(into box: LinuxWidgetPtr) {
        codexbar_linux_box_remove_all(box)

        codexbar_linux_box_append(box, self.makeSectionTitle("System"))
        codexbar_linux_box_append(box, self.makeLabel(
            text: "Ubuntu launch-at-login and notifications will be added separately. The refresh cadence below is now active in the running app.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"]))

        codexbar_linux_box_append(box, self.makeSeparator())
        codexbar_linux_box_append(box, self.makeSectionTitle("Usage"))
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Show cost summary",
            subtitle: "Matches the macOS General pane toggle for local token cost usage.",
            active: self.preferences.costUsageEnabled)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.costUsageEnabled = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Check provider status",
            subtitle: "Poll provider status pages during refresh.",
            active: self.preferences.statusChecksEnabled)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.statusChecksEnabled = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Session quota notifications",
            subtitle: "Persisted now; Linux desktop notifications come later.",
            active: self.preferences.sessionQuotaNotificationsEnabled)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.sessionQuotaNotificationsEnabled = active }
        })

        codexbar_linux_box_append(box, self.makeSeparator())
        codexbar_linux_box_append(box, self.makeSectionTitle("Automation"))
        let cadenceInfo = self.makeLabel(
            text: self.preferences.refreshFrequency == .manual
                ? "Refresh cadence: Manual only"
                : "Refresh cadence: \(self.preferences.refreshFrequency.label) auto-refresh",
            xalign: 0,
            wrap: false,
            cssClasses: [])
        codexbar_linux_box_append(box, cadenceInfo)

        let cadenceButtons = codexbar_linux_box_new_horizontal(8)
        for frequency in LinuxRefreshFrequency.allCases {
            let isSelected = frequency == self.preferences.refreshFrequency
            codexbar_linux_box_append(cadenceButtons, self.makeButton(
                title: frequency.label,
                cssClasses: isSelected ? ["suggested-action"] : ["flat"])
            { [weak self] _ in
                self?.setRefreshFrequency(frequency)
            })
        }
        codexbar_linux_box_append(box, cadenceButtons)
    }

    private func renderDisplayPage(into box: LinuxWidgetPtr) {
        codexbar_linux_box_remove_all(box)

        codexbar_linux_box_append(box, self.makeSectionTitle("Menu content"))
        codexbar_linux_box_append(box, self.makeLabel(
            text: "These toggles now affect the cards rendered in Overview.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"]))
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Show usage as used",
            subtitle: "Switch between used and remaining percentages in the bars and labels.",
            active: self.preferences.usageBarsShowUsed)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.usageBarsShowUsed = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Show reset time as clock",
            subtitle: "Switch reset details between countdown style and absolute clock time.",
            active: self.preferences.resetTimesShowAbsolute)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.resetTimesShowAbsolute = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Show credits + extra usage",
            subtitle: "Show or hide optional credits lines in provider cards.",
            active: self.preferences.showOptionalCreditsAndExtraUsage)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.showOptionalCreditsAndExtraUsage = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Hide personal info",
            subtitle: "Redacts account emails in the overview and providers pages.",
            active: self.preferences.hidePersonalInfo)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.hidePersonalInfo = active }
        })

        codexbar_linux_box_append(box, self.makeSeparator())
        codexbar_linux_box_append(box, self.makeSectionTitle("Merged view"))
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Merge icons",
            subtitle: "Kept for parity with macOS preferences; tray behaviour will use this later.",
            active: self.preferences.mergeIcons)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.mergeIcons = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Switcher shows icons",
            subtitle: "Stored now for future tray/menu switcher work.",
            active: self.preferences.switcherShowsIcons)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.switcherShowsIcons = active }
        })
        codexbar_linux_box_append(box, self.makeCheckButtonRow(
            title: "Show most-used provider",
            subtitle: "Stored now for future merged/tray routing.",
            active: self.preferences.menuBarShowsHighestUsage)
        { [weak self] widget in
            guard let self else { return }
            let active = codexbar_linux_check_button_get_active(widget) != 0
            self.setPreference { $0.menuBarShowsHighestUsage = active }
        })
    }

    private func renderAboutPage(into box: LinuxWidgetPtr) {
        codexbar_linux_box_remove_all(box)
        codexbar_linux_box_append(box, self.makeSectionTitle("About"))
        for line in LinuxPreferencesPresenter.aboutLines() {
            let label = self.makeLabel(text: line, xalign: 0, wrap: true, cssClasses: [])
            codexbar_linux_box_append(box, label)
        }

        let capabilities = self.makeLabel(
            text: "Current Ubuntu app scope: native window, provider toggles, live refresh, display preferences, CLI-backed usage cards.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"])
        codexbar_linux_box_append(box, capabilities)

        let paths = self.makeLabel(
            text: "Config: \(CodexBarConfigStore.defaultURL().path)\nLinux prefs: \(LinuxPreferencesStore.defaultURL().path)",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"])
        codexbar_linux_box_append(box, paths)
    }

    private func renderRefreshError(_ message: String) {
        guard let subtitleLabel else { return }
        self.setLabelText(subtitleLabel, "Refresh failed: \(message)")
    }

    private func addPage(to stack: LinuxWidgetPtr, name: String, title: String, content: LinuxWidgetPtr) {
        let scroll = requireValue(codexbar_linux_scrolled_window_new(), "Failed to create scrolled page.")
        codexbar_linux_widget_set_hexpand(scroll, 1)
        codexbar_linux_widget_set_vexpand(scroll, 1)
        codexbar_linux_scrolled_window_set_child(scroll, content)
        name.withCString { pageName in
            title.withCString { pageTitle in
                codexbar_linux_stack_add_titled(stack, scroll, pageName, pageTitle)
            }
        }
    }

    private func makePageContainer() -> LinuxWidgetPtr {
        let box = requireValue(codexbar_linux_box_new_vertical(16), "Failed to create page container.")
        codexbar_linux_widget_set_margin_all(box, 12)
        codexbar_linux_widget_set_hexpand(box, 1)
        return box
    }

    private func makeSectionTitle(_ text: String) -> LinuxWidgetPtr {
        self.makeLabel(text: text, xalign: 0, wrap: false, cssClasses: ["heading"])
    }

    private func makeSeparator() -> LinuxWidgetPtr {
        requireValue(codexbar_linux_separator_new(), "Failed to create separator.")
    }

    private func makeCardWidget(_ card: LinuxProviderCard) -> LinuxWidgetPtr {
        let frame = requireValue(card.title.withCString { codexbar_linux_frame_new($0) }, "Failed to create card frame.")
        codexbar_linux_widget_set_hexpand(frame, 1)

        let content = requireValue(codexbar_linux_box_new_vertical(8), "Failed to create card content.")
        codexbar_linux_widget_set_margin_all(content, 16)

        let subtitle = self.makeLabel(text: card.subtitle, xalign: 0, wrap: true, cssClasses: ["heading"])
        codexbar_linux_box_append(content, subtitle)

        let status = self.makeLabel(text: card.statusLine, xalign: 0, wrap: true, cssClasses: [])
        codexbar_linux_box_append(content, status)

        if let metadataLine = card.metadataLine {
            let metadata = self.makeLabel(text: metadataLine, xalign: 0, wrap: true, cssClasses: ["dim-label"])
            codexbar_linux_box_append(content, metadata)
        }

        if let footerLine = card.footerLine {
            let footer = self.makeLabel(text: footerLine, xalign: 0, wrap: true, cssClasses: ["dim-label"])
            codexbar_linux_box_append(content, footer)
        }

        if let errorMessage = card.errorMessage {
            let errorLabel = self.makeLabel(text: errorMessage, xalign: 0, wrap: true, cssClasses: ["error"])
            codexbar_linux_box_append(content, errorLabel)
        }

        for bar in card.usageBars {
            let titleLabel = self.makeLabel(text: bar.title, xalign: 0, wrap: false, cssClasses: [])
            codexbar_linux_box_append(content, titleLabel)

            let progressBar = requireValue(codexbar_linux_progress_bar_new(), "Failed to create progress bar.")
            codexbar_linux_widget_set_hexpand(progressBar, 1)
            codexbar_linux_progress_bar_set_fraction(progressBar, bar.fractionFilled)
            bar.detail.withCString { codexbar_linux_progress_bar_set_text(progressBar, $0) }
            codexbar_linux_progress_bar_set_show_text(progressBar, 1)
            codexbar_linux_box_append(content, progressBar)
        }

        codexbar_linux_frame_set_child(frame, content)
        return frame
    }

    private func makeCheckButtonRow(
        title: String,
        subtitle: String,
        active: Bool,
        onToggle: @escaping (LinuxWidgetPtr) -> Void) -> LinuxWidgetPtr
    {
        let row = requireValue(codexbar_linux_box_new_vertical(4), "Failed to create check button row.")
        let toggle = self.makeCheckButton(title: title, active: active, onToggle: onToggle)
        codexbar_linux_box_append(row, toggle)
        let subtitleLabel = self.makeLabel(text: subtitle, xalign: 0, wrap: true, cssClasses: ["dim-label"])
        codexbar_linux_box_append(row, subtitleLabel)
        return row
    }

    private func makeCheckButton(
        title: String,
        active: Bool,
        onToggle: @escaping (LinuxWidgetPtr) -> Void) -> LinuxWidgetPtr
    {
        let button = requireValue(title.withCString { codexbar_linux_check_button_new($0) }, "Failed to create check button.")
        codexbar_linux_check_button_set_active(button, active ? 1 : 0)
        let handler = LinuxWidgetHandlerBox { widget in
            guard let widget else { return }
            onToggle(widget)
        }
        self.retainedHandlers.append(handler)
        codexbar_linux_check_button_on_toggled(
            button,
            codexbarLinuxWidgetCallback,
            Unmanaged.passUnretained(handler).toOpaque())
        return button
    }

    private func makeButton(
        title: String,
        cssClasses: [String] = [],
        onClick: @escaping (LinuxWidgetPtr?) -> Void) -> LinuxWidgetPtr
    {
        let button = requireValue(title.withCString { codexbar_linux_button_new($0) }, "Failed to create button.")
        for className in cssClasses {
            className.withCString { codexbar_linux_widget_add_css_class(button, $0) }
        }
        let handler = LinuxWidgetHandlerBox(handle: onClick)
        self.retainedHandlers.append(handler)
        codexbar_linux_button_on_clicked(button, codexbarLinuxWidgetCallback, Unmanaged.passUnretained(handler).toOpaque())
        return button
    }

    private func makeLabel(text: String, xalign: Float, wrap: Bool, cssClasses: [String]) -> LinuxWidgetPtr {
        let label = requireValue(text.withCString { codexbar_linux_label_new($0) }, "Failed to create label.")
        codexbar_linux_label_set_xalign(label, xalign)
        codexbar_linux_label_set_wrap(label, wrap ? 1 : 0)
        for className in cssClasses {
            className.withCString { codexbar_linux_widget_add_css_class(label, $0) }
        }
        return label
    }

    private func setLabelText(_ label: LinuxWidgetPtr, _ text: String) {
        text.withCString { codexbar_linux_label_set_text(label, $0) }
    }
}
#endif
