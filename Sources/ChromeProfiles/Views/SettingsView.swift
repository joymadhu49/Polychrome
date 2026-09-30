import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, menu, browsers, tiling, shortcuts, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .menu:        return "Menu"
        case .browsers:    return "Browsers"
        case .tiling:      return "Tiling"
        case .shortcuts:   return "Shortcuts"
        case .permissions: return "Permissions"
        case .about:       return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .menu:        return "menubar.rectangle"
        case .browsers:    return "globe"
        case .tiling:      return "rectangle.split.2x1.fill"
        case .shortcuts:   return "command"
        case .permissions: return "hand.raised.fill"
        case .about:       return "info.circle.fill"
        }
    }

    /// Sidebar tile color, System Settings style.
    var tint: Color {
        switch self {
        case .general:     return .gray
        case .menu:        return .blue
        case .browsers:    return .teal
        case .tiling:      return .indigo
        case .shortcuts:   return .pink
        case .permissions: return .orange
        case .about:       return .gray
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateController
    @ObservedObject var router: SettingsRouter
    @State private var axTrusted: Bool = AXPermission.isTrusted()

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
    static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(
                get: { Optional(router.pane) },
                set: { if let p = $0 { router.pane = p } }
            )) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        SidebarIcon(systemName: pane.icon, tint: pane.tint)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch router.pane {
                case .general:     generalPane
                case .menu:        menuPane
                case .browsers:    browsersPane
                case .tiling:      tilingPane
                case .shortcuts:   shortcutsPane
                case .permissions: permissionsPane
                case .about:       aboutPane
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .navigationTitle(router.pane.title)
        }
        .frame(width: 720, height: 540)
        .onAppear {
            axTrusted = AXPermission.isTrusted()
            settings.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings is the moment the grant (or a login item) usually changes.
            axTrusted = AXPermission.isTrusted()
            settings.refreshLaunchAtLogin()
        }
    }

    // MARK: General

    private var generalPane: some View {
        Form {
            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingLabel("Launch at login",
                                 settings.launchAtLoginNeedsApproval
                                     ? "Waiting for your approval in System Settings → General → Login Items."
                                     : "Start Polychrome automatically when you log in.")
                }
                if settings.launchAtLoginNeedsApproval {
                    LabeledContent {
                        Button("Open Login Items…") { LaunchAtLogin.openSystemSettings() }
                    } label: {
                        Label("macOS needs you to allow Polychrome", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Toggle(isOn: $settings.focusExisting) {
                    SettingLabel("Focus existing windows",
                                 "If a profile already has a window open, bring it forward instead of opening another.")
                }
            }

            Section {
                if updates.isAvailable {
                    Toggle(isOn: $updates.automaticallyChecks) {
                        SettingLabel("Check for updates automatically",
                                     "Polychrome checks once a day. The check sends nothing about your profiles.")
                    }
                    Toggle(isOn: $updates.automaticallyDownloads) {
                        SettingLabel("Download and install automatically",
                                     "Updates install in the background and apply the next time Polychrome starts.")
                    }
                    .disabled(!updates.automaticallyChecks)
                    LabeledContent {
                        Button("Check Now") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates)
                    } label: {
                        SettingLabel("Version \(Self.appVersion)", lastCheckText)
                    }
                } else {
                    LabeledContent {
                        EmptyView()
                    } label: {
                        SettingLabel("Version \(Self.appVersion)",
                                     "This is a development build. Updates are delivered to release builds only.")
                    }
                }
            } header: {
                Text("Updates")
            }
        }
    }

    private var lastCheckText: String {
        guard let d = updates.lastCheck else { return "Not checked yet." }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Last checked \(f.localizedString(for: d, relativeTo: Date()))."
    }

    // MARK: Menu

    private var menuPane: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(ThemeOverride.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Overrides the system appearance for Polychrome only.")
                    .settingsFootnote()
            }

            Section {
                Toggle(isOn: $settings.groupByStatus) {
                    SettingLabel("Show open profiles first",
                                 "Profiles with a window open get their own section at the top.")
                }
                Toggle(isOn: $settings.groupByBrowser) {
                    SettingLabel("Group by browser",
                                 "Separate sections per browser, when more than one has profiles.")
                }
                Toggle(isOn: $settings.pinned) {
                    SettingLabel("Keep menu pinned on top",
                                 "The menu stays open when you click away or open a profile. The pin in the menu toggles this too.")
                }
            } header: {
                Text("List")
            }

            Section {
                Toggle(isOn: $settings.showEmails) {
                    SettingLabel("Show email addresses",
                                 "Turn off while screen sharing to keep account emails private.")
                }
                Toggle(isOn: $settings.tagsEnabled) {
                    SettingLabel("Color tags",
                                 "Right-click a profile in the menu to tag it. Tags show as a dot after the name and are searchable.")
                }
                if settings.tagsEnabled {
                    LabeledContent("Tag colors") {
                        HStack(spacing: 6) {
                            ForEach(ProfileTag.allCases.filter { $0 != .none }) { t in
                                Circle()
                                    .fill(t.color)
                                    .frame(width: 12, height: 12)
                                    .help(t.displayName)
                            }
                        }
                    }
                }
            } header: {
                Text("Profile rows")
            }
        }
    }

    // MARK: Browsers

    private var browsersPane: some View {
        Form {
            Section {
                ForEach(Browser.allCases) { b in browserRow(b) }
            } footer: {
                Text("Polychrome reads each browser’s profile list from its Local State file. Nothing is modified.")
                    .settingsFootnote()
            }
        }
    }

    private func browserRow(_ b: Browser) -> some View {
        let installed = b.isInstalled
        return Toggle(isOn: Binding(
            get: { settings.enabledBrowsers.contains(b) },
            set: { isOn in
                var s = settings.enabledBrowsers
                if isOn { s.insert(b) } else { s.remove(b) }
                if s.isEmpty { s.insert(.chrome) } // never empty
                settings.enabledBrowsers = s
            }
        )) {
            HStack(spacing: 10) {
                SidebarIcon(systemName: b.symbolName, tint: installed ? Color(b.accent) : .gray, size: 26)
                SettingLabel(b.displayName, installed ? "Installed" : "Not installed")
            }
        }
        .disabled(!installed)
        .accessibilityLabel(b.displayName)
    }

    // MARK: Tiling

    private var tilingPane: some View {
        Form {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(TileLayout.allCases) { l in
                        LayoutCard(layout: l,
                                   config: settings.layout,
                                   selected: settings.layout.layout == l) {
                            settings.layout.layout = l
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Layout")
            } footer: {
                Text(layoutFootnote).settingsFootnote()
            }

            Section {
                SliderRow(title: "Gap between windows",
                          value: Binding(get: { Double(settings.layout.paddingPx) },
                                         set: { settings.layout.paddingPx = CGFloat($0) }),
                          range: 0...32,
                          format: { "\(Int($0)) pt" })
                if settings.layout.layout == .splitH || settings.layout.layout == .splitV {
                    SliderRow(title: "Main window size",
                              value: $settings.layout.splitPercent,
                              range: 0.2...0.8, step: 0.05,
                              format: { "\(Int(($0 * 100).rounded()))%" })
                }
                Toggle("Avoid the menu bar and Dock", isOn: $settings.layout.avoidMenubar)
                Picker("Display", selection: displaySelection) {
                    Text("Main display").tag(nil as UInt32?)
                    ForEach(screens, id: \.id) { d in
                        Text("\(d.name) — \(Int(d.frame.width))×\(Int(d.frame.height))")
                            .tag(Optional(d.id))
                    }
                }
            } header: {
                Text("Arrangement")
            }
        }
    }

    private var screens: [DisplayInfo] { DisplayService.screens() }

    /// A saved display that's no longer connected tiles on the main display
    /// (DisplayService falls back), so show that instead of an empty picker.
    private var displaySelection: Binding<UInt32?> {
        Binding(
            get: {
                let id = settings.layout.displayID
                return screens.contains { $0.id == id } ? id : nil
            },
            set: { settings.layout.displayID = $0 }
        )
    }

    private var layoutFootnote: String {
        switch settings.layout.layout {
        case .smart:  return "Up to three windows sit side by side; four or more form a grid."
        case .row:    return "Every window gets an equal-width column."
        case .column: return "Every window gets an equal-height row."
        case .grid:   return "Windows fill the most square grid that fits them."
        case .splitH: return "The first profile you select gets the large pane; the rest stack on the right."
        case .splitV: return "The first profile you select gets the large pane; the rest share the bottom."
        }
    }

    // MARK: Shortcuts

    private var shortcutsPane: some View {
        Form {
            Section {
                Toggle("Enable global shortcut", isOn: Binding(
                    get: { settings.hotkey.enabled },
                    set: { on in
                        var c = settings.hotkey
                        c.enabled = on
                        settings.updateHotkey(c)
                    }
                ))
                LabeledContent("Open the menu") {
                    HotkeyRecorder(config: Binding(
                        get: { settings.hotkey },
                        set: { settings.updateHotkey($0) }
                    ))
                }
                .disabled(!settings.hotkey.enabled)

                if let issue = settings.hotkeyRegistrationIssue {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Couldn’t use \(issue.attempted.displayString)")
                                .font(.system(size: 12, weight: .semibold))
                            Text(issue.message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Retry") { settings.retryHotkeyRegistration() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Global")
            } footer: {
                Text("Click the field, then press the keys. A shortcut needs ⌘, ⌥ or ⌃ so it can’t take over normal typing; Shift alone works only with F1–F20.")
                    .settingsFootnote()
            }

            Section {
                ShortcutRow("Open or focus the highlighted profile", keys: ["↩"])
                ShortcutRow("Open profile 1 – 9", keys: ["⌘", "1 – 9"])
                ShortcutRow("Move the highlight", keys: ["↑", "↓"])
                ShortcutRow("Clear search, leave selection, close", keys: ["esc"])
                ShortcutRow("Refresh profiles", keys: ["⌘", "R"])
                ShortcutRow("Settings", keys: ["⌘", ","])
                ShortcutRow("Quit Polychrome", keys: ["⌘", "Q"])
            } header: {
                Text("In the menu")
            } footer: {
                Text("Hold ⌘ while the menu is open to see each profile’s number.")
                    .settingsFootnote()
            }
        }
    }

    // MARK: Permissions

    private var permissionsPane: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(axTrusted ? Color.green : .orange)
                    SettingLabel(axTrusted ? "Accessibility access is on" : "Accessibility access is off",
                                 axTrusted
                                     ? "Polychrome can find each profile’s windows, focus them, and tile them."
                                     : "Without it Polychrome can still open profiles, but can’t tell which are open, switch between their windows, or tile them.")
                    Spacer()
                }
                .padding(.vertical, 2)
                HStack {
                    Spacer()
                    Button("Check Again") { axTrusted = AXPermission.isTrusted() }
                    Button("Open System Settings…") {
                        _ = AXPermission.isTrusted(prompt: true)
                        AXPermission.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("If Polychrome is listed in System Settings but still shows as off, remove it with the – button and add it again.")
                    .settingsFootnote()
            }

            Section {
                Toggle(isOn: $settings.showAXBanner) {
                    SettingLabel("Remind me in the menu",
                                 "Show a banner at the top of the menu while access is off.")
                }
            }
        }
    }

    // MARK: About

    private var aboutPane: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                    Text("Polychrome")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Version \(Self.appVersion) (\(Self.buildNumber))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Every Chrome and Brave profile, one click from the menu bar.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if updates.isAvailable {
                        Button("Check for Updates…") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Section {
                LinkRow(title: "Release notes", url: "https://github.com/joymadhu49/Polychrome/releases")
                LinkRow(title: "Source code", url: "https://github.com/joymadhu49/Polychrome")
                LinkRow(title: "Report an issue", url: "https://github.com/joymadhu49/Polychrome/issues/new")
            } footer: {
                Text((Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String).map { "\($0) · MIT License" } ?? "MIT License")
                    .settingsFootnote()
            }
        }
    }
}

// MARK: - components

/// Title with an optional secondary line — the System Settings row label.
struct SettingLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// White glyph on a rounded colored tile, like System Settings' sidebar.
struct SidebarIcon: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(tint.gradient)
            )
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                slider
                    .frame(maxWidth: 220)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    /// A stepped Slider draws a tick per step (32 for the gap). Without a step,
    /// the value is rounded to whole numbers instead, and the track stays clean.
    @ViewBuilder private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let keys: [String]

    init(_ title: String, keys: [String]) {
        self.title = title
        self.keys = keys
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { KeyCap($0) }
            }
        }
    }
}

struct LinkRow: View {
    let title: String
    let url: String

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A selectable thumbnail of one tiling layout.
struct LayoutCard: View {
    let layout: TileLayout
    let config: LayoutConfig
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    /// The user's own split size, but a thumbnail-scale gap.
    private var previewConfig: LayoutConfig {
        var c = config
        c.layout = layout
        c.paddingPx = 3
        return c
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                LayoutPreview(layout: previewConfig, count: layout == .splitH || layout == .splitV ? 3 : 4,
                              highlighted: selected)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                Text(layout.shortName)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.10)
                                   : Color.primary.opacity(hovering ? 0.04 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10),
                                  lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(layout.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LayoutPreview: View {
    let layout: LayoutConfig
    let count: Int
    var highlighted: Bool = true

    var body: some View {
        GeometryReader { geo in
            let frames = WindowTiler.frames(for: count, in: CGRect(origin: .zero, size: geo.size), layout: layout)
            let tint = highlighted ? Color.accentColor : Color.secondary
            ZStack(alignment: .topLeading) {
                ForEach(0..<frames.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tint.opacity(i == 0 ? 0.45 : 0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .strokeBorder(tint.opacity(0.7), lineWidth: 0.75)
                        )
                        .frame(width: max(0, frames[i].width), height: max(0, frames[i].height))
                        .offset(x: frames[i].minX, y: frames[i].minY)
                }
            }
        }
        .padding(4)
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        self.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
