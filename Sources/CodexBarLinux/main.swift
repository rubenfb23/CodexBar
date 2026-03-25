#if os(Linux)
import CodexBarLinuxSupport
import CodexBarLinuxUIBridge
import Foundation
import Glibc

private let appID = "com.steipete.codexbar.linux"

@main
enum CodexBarLinuxApp {
    static func main() {
        codexbar_linux_init()
        let controller = LinuxWindowController()
        controller.run()
    }
}

private func codexbarLinuxActivateCallback(_ app: OpaquePointer?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleActivate(application: app)
}

private func codexbarLinuxRefreshCallback(_ widget: OpaquePointer?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.refresh()
}

private func codexbarLinuxOpenConfigCallback(_ widget: OpaquePointer?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.openConfig()
}

private final class LinuxWindowController {
    private let backend = LinuxCLIBackend()
    private var application: OpaquePointer?
    private var window: OpaquePointer?
    private var subtitleLabel: OpaquePointer?
    private var cardsBox: OpaquePointer?
    private var retainedPointer: UnsafeMutableRawPointer?

    func run() {
        self.retainedPointer = Unmanaged.passRetained(self).toOpaque()
        self.application = appID.withCString { codexbar_linux_application_new($0) }
        guard let application, let retainedPointer else {
            fputs("Failed to create CodexBar Linux application.\n", stderr)
            return
        }
        codexbar_linux_application_on_activate(application, codexbarLinuxActivateCallback, retainedPointer)
        _ = codexbar_linux_application_run(application)
    }

    func handleActivate(application: OpaquePointer?) {
        guard let application else { return }
        if self.window == nil {
            self.buildWindow(application: application)
        }
        if let window = self.window {
            codexbar_linux_window_present(window)
        }
        self.refresh()
    }

    func refresh() {
        guard let subtitleLabel, let cardsBox else { return }
        self.setLabelText(subtitleLabel, "Refreshing usage from CodexBarCLI...")

        do {
            let loadResult = try self.backend.fetchUsagePayloads()
            let snapshot = LinuxDashboardPresenter.makeSnapshot(
                from: loadResult.payloads,
                cliBinaryPath: loadResult.cliBinaryPath)
            self.render(snapshot: snapshot, exitCode: loadResult.exitCode)
        } catch {
            self.renderRefreshError(error.localizedDescription)
            codexbar_linux_box_remove_all(cardsBox)
            let label = self.makeLabel(
                text: error.localizedDescription,
                xalign: 0,
                wrap: true,
                cssClasses: ["error"])
            codexbar_linux_box_append(cardsBox, label)
        }
    }

    func openConfig() {
        do {
            let fileURL = try self.backend.openConfigInDefaultApp()
            if let subtitleLabel = self.subtitleLabel {
                self.setLabelText(subtitleLabel, "Opened config at \(fileURL.path)")
            }
        } catch {
            self.renderRefreshError(error.localizedDescription)
        }
    }

    private func buildWindow(application: OpaquePointer) {
        let window = codexbar_linux_window_new(application)
        self.window = window
        "CodexBar Ubuntu".withCString { codexbar_linux_window_set_title(window, $0) }
        codexbar_linux_window_set_default_size(window, 960, 720)

        let root = codexbar_linux_box_new_vertical(16)
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
            text: "Native Ubuntu window backed by CodexBarCLI JSON.",
            xalign: 0,
            wrap: true,
            cssClasses: ["dim-label"])
        self.subtitleLabel = subtitleLabel
        codexbar_linux_box_append(root, subtitleLabel)

        let buttonRow = codexbar_linux_box_new_horizontal(12)
        let refreshButton = "Refresh".withCString { codexbar_linux_button_new($0) }
        let configButton = "Open Config".withCString { codexbar_linux_button_new($0) }
        if let retainedPointer = self.retainedPointer {
            codexbar_linux_button_on_clicked(refreshButton, codexbarLinuxRefreshCallback, retainedPointer)
            codexbar_linux_button_on_clicked(configButton, codexbarLinuxOpenConfigCallback, retainedPointer)
        }
        codexbar_linux_box_append(buttonRow, refreshButton)
        codexbar_linux_box_append(buttonRow, configButton)
        codexbar_linux_box_append(root, buttonRow)

        let separator = codexbar_linux_separator_new()
        codexbar_linux_box_append(root, separator)

        let scrolled = codexbar_linux_scrolled_window_new()
        codexbar_linux_widget_set_hexpand(scrolled, 1)
        codexbar_linux_widget_set_vexpand(scrolled, 1)
        let cardsBox = codexbar_linux_box_new_vertical(16)
        self.cardsBox = cardsBox
        codexbar_linux_scrolled_window_set_child(scrolled, cardsBox)
        codexbar_linux_box_append(root, scrolled)

        codexbar_linux_window_set_content(window, root)
    }

    private func render(snapshot: LinuxDashboardSnapshot, exitCode: Int32) {
        guard let subtitleLabel, let cardsBox else { return }

        var subtitle = LinuxDashboardPresenter.refreshSubtitle(for: snapshot)
        if exitCode != 0 {
            subtitle += " | CLI exited with \(exitCode), some providers may be unavailable."
        }
        self.setLabelText(subtitleLabel, subtitle)

        codexbar_linux_box_remove_all(cardsBox)
        if snapshot.cards.isEmpty {
            let emptyLabel = self.makeLabel(
                text: "CodexBarCLI returned no enabled providers.",
                xalign: 0,
                wrap: true,
                cssClasses: ["dim-label"])
            codexbar_linux_box_append(cardsBox, emptyLabel)
            return
        }

        for card in snapshot.cards {
            let widget = self.makeCardWidget(card)
            codexbar_linux_box_append(cardsBox, widget)
        }
    }

    private func renderRefreshError(_ message: String) {
        guard let subtitleLabel else { return }
        self.setLabelText(subtitleLabel, "Refresh failed: \(message)")
    }

    private func makeCardWidget(_ card: LinuxProviderCard) -> OpaquePointer {
        let frame = card.title.withCString { codexbar_linux_frame_new($0) }
        codexbar_linux_widget_set_hexpand(frame, 1)

        let content = codexbar_linux_box_new_vertical(8)
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

            let progressBar = codexbar_linux_progress_bar_new()
            codexbar_linux_widget_set_hexpand(progressBar, 1)
            codexbar_linux_progress_bar_set_fraction(progressBar, bar.fractionUsed)
            bar.detail.withCString { codexbar_linux_progress_bar_set_text(progressBar, $0) }
            codexbar_linux_progress_bar_set_show_text(progressBar, 1)
            codexbar_linux_box_append(content, progressBar)
        }

        codexbar_linux_frame_set_child(frame, content)
        return frame
    }

    private func makeLabel(text: String, xalign: Float, wrap: Bool, cssClasses: [String]) -> OpaquePointer {
        let label = text.withCString { codexbar_linux_label_new($0) }
        codexbar_linux_label_set_xalign(label, xalign)
        codexbar_linux_label_set_wrap(label, wrap ? 1 : 0)
        for className in cssClasses {
            className.withCString { codexbar_linux_widget_add_css_class(label, $0) }
        }
        return label
    }

    private func setLabelText(_ label: OpaquePointer, _ text: String) {
        text.withCString { codexbar_linux_label_set_text(label, $0) }
    }
}
#endif
