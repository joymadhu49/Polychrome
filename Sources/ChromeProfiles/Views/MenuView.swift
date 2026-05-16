import SwiftUI
import AppKit

struct MenuView: View {
    @ObservedObject var loader: ChromeProfileLoader
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let dismiss: () -> Void

    @State private var query: String = ""
    @State private var multiMode: Bool = false
    @State private var multiSelected: [String] = []
    @State private var openWindowsByDir: [String: Bool] = [:]
    @State private var axTrusted: Bool = AXPermission.isTrusted()

    // MARK: filtering

    private var queryIsURL: Bool {
        guard settings.quickLaunchEnabled else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return false }
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return true }
        // contains dot, no spaces, length looks like host
        if q.contains(".") && !q.contains(" ") && q.count >= 4 { return true }
        return false
    }

    private var normalizedURL: String {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return q }
        return "https://" + q
    }

    private var filteredProfiles: [ChromeProfile] {
        if queryIsURL { return loader.profiles }
        guard !query.isEmpty else { return loader.profiles }
        let q = query.lowercased()
        return loader.profiles.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            settings.tag(for: $0.dirName).displayName.lowercased().contains(q)
        }
    }

    private var openProfiles: [ChromeProfile] {
        filteredProfiles.filter { openWindowsByDir[$0.dirName] == true }
    }
    private var closedProfiles: [ChromeProfile] {
        filteredProfiles.filter { openWindowsByDir[$0.dirName] != true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            if !axTrusted { axBanner }
            searchBar
            if queryIsURL { urlBanner }
            multiToolbar
            Divider().opacity(0.4)
            profileList
            if multiMode { multiActionBar }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 300)
        .task {
            axTrusted = AXPermission.isTrusted()
            loader.reload()
            await refreshOpenWindowsAsync()
        }
    }

    // MARK: banners

    private var axBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility required")
                    .font(.system(size: 12, weight: .semibold))
                Text("Side-by-side + duplicate-window detection.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Grant") {
                _ = AXPermission.isTrusted(prompt: true)
                AXPermission.openSystemSettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }

    private var urlBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Open URL in profile")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(normalizedURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10))
    }

    // MARK: title

    private var titleBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.3.group.bubble.left.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Polychrome")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(loader.profiles.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: queryIsURL ? "link" : "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(queryIsURL ? Color.accentColor : .secondary)
            TextField(settings.quickLaunchEnabled ? "Search or paste URL" : "Search profiles", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
    }

    private var multiToolbar: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $multiMode) {
                HStack(spacing: 4) {
                    Image(systemName: multiMode ? "checkmark.square.fill" : "square.dashed")
                        .font(.system(size: 10, weight: .semibold))
                    Text(multiMode ? "Selecting" : "Multi-select")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .onChange(of: multiMode) { newValue in
                if !newValue { multiSelected.removeAll() }
            }

            if multiMode && !multiSelected.isEmpty {
                Text("\(multiSelected.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
            }

            Spacer()

            Button {
                loader.reload()
                Task { await refreshOpenWindowsAsync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh profiles")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: list

    private var profileList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                if let err = loader.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                if filteredProfiles.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18))
                                .foregroundStyle(.tertiary)
                            Text("No profiles match")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 28)
                } else if settings.groupByStatus {
                    if !openProfiles.isEmpty {
                        sectionHeader("OPEN", count: openProfiles.count, color: .green)
                        ForEach(openProfiles) { p in row(for: p) }
                    }
                    if !closedProfiles.isEmpty {
                        if !openProfiles.isEmpty {
                            Divider().opacity(0.3).padding(.horizontal, 10).padding(.vertical, 3)
                        }
                        sectionHeader("CLOSED", count: closedProfiles.count, color: .secondary)
                        ForEach(closedProfiles) { p in row(for: p) }
                    }
                } else {
                    ForEach(filteredProfiles) { p in row(for: p) }
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 240, maxHeight: 380)
    }

    private func sectionHeader(_ s: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(s)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(for p: ChromeProfile) -> some View {
        ProfileRow(
            profile: p,
            multiSelected: multiSelected.contains(p.dirName),
            isOpen: openWindowsByDir[p.dirName] == true,
            showEmail: settings.showEmails,
            tag: settings.tagsEnabled ? settings.tag(for: p.dirName) : .none,
            urlMode: queryIsURL
        ) {
            handleTap(p)
        }
        .padding(.horizontal, 6)
        .contextMenu {
            Button {
                ChromeLauncher.launchOrFocus(profile: p)
                dismiss()
            } label: { Label("Open or focus", systemImage: "arrow.up.forward.square") }

            Button {
                ChromeLauncher.launch(profileDir: p.dirName)
                dismiss()
            } label: { Label("Force new window", systemImage: "plus.rectangle.on.rectangle") }

            if settings.tagsEnabled {
                Divider()
                Menu {
                    ForEach(ProfileTag.allCases) { t in
                        Button {
                            settings.setTag(t, for: p.dirName)
                        } label: {
                            if t == .none {
                                Label("Clear", systemImage: "xmark.circle")
                            } else {
                                Label(t.displayName, systemImage: settings.tag(for: p.dirName) == t ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                } label: { Label("Tag", systemImage: "tag") }
            }
        }
    }

    private func handleTap(_ p: ChromeProfile) {
        if multiMode {
            if let i = multiSelected.firstIndex(of: p.dirName) {
                multiSelected.remove(at: i)
            } else {
                multiSelected.append(p.dirName)
            }
            return
        }
        if queryIsURL {
            ChromeLauncher.launchOrFocus(profile: p, url: normalizedURL)
        } else if settings.focusExisting {
            ChromeLauncher.launchOrFocus(profile: p)
        } else {
            ChromeLauncher.launch(profileDir: p.dirName)
        }
        dismiss()
    }

    // MARK: action bar

    private var multiActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if queryIsURL {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .bold))
                    Text("URL will open in each selected profile")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(.tint)
            }
            HStack(spacing: 8) {
                Button {
                    let dirs = multiSelected
                    let profilesToOpen = loader.profiles.filter { dirs.contains($0.dirName) }
                    let url: String? = queryIsURL ? normalizedURL : nil
                    ChromeLauncher.launchMany(profiles: profilesToOpen, url: url)
                    resetMulti()
                    dismiss()
                } label: {
                    Label(queryIsURL ? "Open URL in \(multiSelected.count)" : "Open \(multiSelected.count)",
                          systemImage: queryIsURL ? "link.badge.plus" : "square.and.arrow.up.on.square")
                        .font(.system(size: 12, weight: .medium))
                }
                .disabled(multiSelected.isEmpty)
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button {
                    guard AXPermission.isTrusted(prompt: true) else {
                        AXPermission.openSystemSettings()
                        return
                    }
                    let dirs = multiSelected
                    let profilesToOpen = loader.profiles.filter { dirs.contains($0.dirName) }
                    let url: String? = queryIsURL ? normalizedURL : nil
                    resetMulti()
                    dismiss()
                    Task { @MainActor in
                        await WindowTiler.launchAndTile(profiles: profilesToOpen, config: settings.layout, url: url)
                    }
                } label: {
                    Label("Side-by-side", systemImage: settings.layout.layout.icon)
                        .font(.system(size: 12, weight: .medium))
                }
                .disabled(multiSelected.count < 2 || !axTrusted)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Clear") { multiSelected.removeAll() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .disabled(multiSelected.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.07))
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                    Text("Settings")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            if settings.hotkey.enabled {
                Text(settings.hotkey.displayString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
                    .help("Global hotkey")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Polychrome")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func resetMulti() {
        multiSelected.removeAll()
        multiMode = false
    }

    private func refreshOpenWindowsAsync() async {
        let profiles = loader.profiles
        let map = await Task.detached(priority: .userInitiated) {
            WindowFinder.allWindowsMappedToProfiles(profiles)
        }.value
        var dict: [String: Bool] = [:]
        for p in profiles {
            dict[p.dirName] = map[p.dirName] != nil
        }
        openWindowsByDir = dict
    }
}
