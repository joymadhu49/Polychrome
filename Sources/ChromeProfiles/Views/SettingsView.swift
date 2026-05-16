import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var axTrusted: Bool = AXPermission.isTrusted()
    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, layout, hotkeys, permissions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general:     return "General"
            case .appearance:  return "Appearance"
            case .layout:      return "Side-by-Side"
            case .hotkeys:     return "Hotkeys"
            case .permissions: return "Permissions"
            }
        }
        var icon: String {
            switch self {
            case .general:     return "gearshape"
            case .appearance:  return "paintbrush"
            case .layout:      return "rectangle.split.2x1"
            case .hotkeys:     return "keyboard"
            case .permissions: return "lock.shield"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                Group {
                    switch selection {
                    case .general:     generalPane
                    case .appearance:  appearancePane
                    case .layout:      layoutPane
                    case .hotkeys:     hotkeyPane
                    case .permissions: permissionPane
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(selection.title)
        }
        .frame(width: 720, height: 520)
        .onAppear { axTrusted = AXPermission.isTrusted() }
    }

    // MARK: panes

    private var generalPane: some View {
        VStack(spacing: 18) {
            SettingsSection(title: "Behavior", description: "How Polychrome handles Chrome windows.") {
                SettingsToggle(title: "Launch at login",
                               subtitle: "Start Polychrome automatically when you log in.",
                               isOn: $settings.launchAtLogin)
                SettingsDivider()
                SettingsToggle(title: "Focus existing windows",
                               subtitle: "If a profile's window is already open, raise it instead of spawning a duplicate.",
                               isOn: $settings.focusExisting)
            }

            SettingsSection(title: "Menu features", description: "Toggle features in the menubar popover.") {
                SettingsToggle(title: "Group by Open / Closed",
                               subtitle: "Show two sections: profiles with active Chrome windows, and the rest.",
                               isOn: $settings.groupByStatus)
                SettingsDivider()
                SettingsToggle(title: "Quick-launch URL",
                               subtitle: "Paste or type a URL in the search field, then click any profile to open it there.",
                               isOn: $settings.quickLaunchEnabled)
                SettingsDivider()
                SettingsToggle(title: "Profile tags",
                               subtitle: "Right-click any profile to assign a color tag (Work, Personal, Test, etc.). Tags appear as a colored dot on the avatar.",
                               isOn: $settings.tagsEnabled)
            }
        }
    }

    private var appearancePane: some View {
        VStack(spacing: 18) {
            SettingsSection(title: "Theme", description: "Override the system appearance for Polychrome only.") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ThemeOverride.allCases) { t in
                        Label(t.displayName, systemImage: t.icon).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "Profile rows", description: "Control what's shown for each profile in the menubar popover.") {
                SettingsToggle(title: "Show email addresses",
                               subtitle: "Hide emails for screen-sharing or privacy.",
                               isOn: $settings.showEmails)
            }

            if settings.tagsEnabled {
                SettingsSection(title: "Tag palette", description: "Available tag colors. Assign tags by right-clicking a profile in the menu.") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 10), count: 6), spacing: 10) {
                        ForEach(ProfileTag.allCases.filter { $0 != .none }) { t in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(t.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 0.5))
                                Text(t.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
        }
    }

    private var layoutPane: some View {
        VStack(spacing: 18) {
            SettingsSection(title: "Layout", description: "How windows arrange when you click Side-by-side.") {
                Picker("Layout", selection: $settings.layout.layout) {
                    ForEach(TileLayout.allCases) { l in
                        Label(l.displayName, systemImage: l.icon).tag(l)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                SettingsDivider()

                LabelledSlider(title: "Padding",
                               value: Binding(
                                get: { Double(settings.layout.paddingPx) },
                                set: { settings.layout.paddingPx = CGFloat($0) }
                               ),
                               range: 0...32, step: 1, suffix: "px")

                if settings.layout.layout == .splitH || settings.layout.layout == .splitV {
                    SettingsDivider()
                    LabelledSlider(title: "First pane size",
                                   value: $settings.layout.splitPercent,
                                   range: 0.2...0.8, step: 0.05, suffix: "%",
                                   format: { "\(Int($0 * 100))%" })
                }

                SettingsDivider()

                SettingsToggle(title: "Avoid menu bar and Dock",
                               subtitle: "Use only the visible portion of the screen.",
                               isOn: $settings.layout.avoidMenubar)
            }

            SettingsSection(title: "Display", description: "Which display windows tile across.") {
                Picker("Display", selection: $settings.layout.displayID) {
                    Text("Main display").tag(nil as UInt32?)
                    ForEach(DisplayService.screens(), id: \.id) { d in
                        Text("\(d.name) — \(Int(d.frame.width))×\(Int(d.frame.height))")
                            .tag(Optional(d.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsSection(title: "Preview", description: "How 4 windows would tile right now.") {
                LayoutPreview(layout: settings.layout, count: 4)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
    }

    private var hotkeyPane: some View {
        SettingsSection(title: "Global hotkey",
                        description: "Press this shortcut anywhere to open the Polychrome menu.") {
            HStack {
                Text("Shortcut")
                    .frame(width: 80, alignment: .leading)
                HotkeyRecorder(config: $settings.hotkey)
                Spacer()
            }
            Text("Click the box, then press the keys to bind. The shortcut requires at least one modifier (⌘ ⌥ ⌃ ⇧).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var permissionPane: some View {
        VStack(spacing: 18) {
            SettingsSection(title: "Accessibility",
                            description: "Required for side-by-side tiling and duplicate-window detection.") {
                HStack(spacing: 10) {
                    Image(systemName: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(axTrusted ? Color.green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(axTrusted ? "Permission granted" : "Permission required")
                            .font(.system(size: 13, weight: .semibold))
                        Text(axTrusted
                             ? "Polychrome can position Chrome windows."
                             : "Grant in System Settings → Privacy & Security → Accessibility.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Button("Open System Settings") { AXPermission.openSystemSettings() }
                    Button("Re-check") { axTrusted = AXPermission.isTrusted() }
                }
                SettingsDivider()
                SettingsToggle(title: "Show banner in menu when not granted",
                               subtitle: "Hide the orange banner at the top of the menubar popover.",
                               isOn: $settings.showAXBanner)
            }

            SettingsSection(title: "Why does macOS keep asking?",
                            description: "Polychrome is ad-hoc signed. Each rebuild gets a new signature, so macOS treats it as a new app and re-prompts.") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workarounds")
                        .font(.system(size: 12, weight: .semibold))
                    Text("• Install Polychrome.app to /Applications and don't rebuild over it.")
                    Text("• Developers: create a persistent self-signed code-signing identity in Keychain Access, then sign builds with it (see README).")
                    Text("• On macOS 15+, a weekly Accessibility usage reminder is a system feature.")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: components

struct SettingsSection<Content: View>: View {
    let title: String
    let description: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.4)
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct LabelledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    var format: ((Double) -> String)? = nil

    var body: some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(format?(value) ?? "\(Int(value)) \(suffix)")
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(.secondary)
        }
    }
}

struct LayoutPreview: View {
    let layout: LayoutConfig
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let mock = DisplayInfo(id: 0, name: "preview", frame: rect, visibleFrame: rect, isMain: true)
            let frames = WindowTiler.frames(for: count, in: mock, layout: layout)
            ZStack(alignment: .topLeading) {
                ForEach(0..<frames.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.accentColor, lineWidth: 1)
                        )
                        .frame(width: max(0, frames[i].width), height: max(0, frames[i].height))
                        .offset(x: frames[i].minX, y: frames[i].minY)
                }
            }
        }
        .padding(6)
    }
}
