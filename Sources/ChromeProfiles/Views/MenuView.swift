import SwiftUI
import AppKit

struct MenuView: View {
    @ObservedObject var loader: ChromeProfileLoader
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let dismiss: () -> Void

    @State private var query: String = ""
    @State private var multiMode: Bool = false
    @State private var multiSelected: [String] = []   // profile.id
    @State private var openWindowsByID: [String: Bool] = [:]
    @State private var axTrusted: Bool = AXPermission.isTrusted()
    @State private var focusedIndex: Int = 0
    @State private var keyMonitor: Any?

    // MARK: filtering

    private var queryIsURL: Bool {
        guard settings.quickLaunchEnabled else { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return false }
        if q.hasPrefix("-") { return false }   // never treat a switch-like token as a URL
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return true }
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
            $0.browser.displayName.lowercased().contains(q) ||
            settings.tag(for: $0).displayName.lowercased().contains(q)
        }
    }

    private var openProfiles: [ChromeProfile] {
        filteredProfiles.filter { openWindowsByID[$0.id] == true }
    }
    private var closedProfiles: [ChromeProfile] {
        filteredProfiles.filter { openWindowsByID[$0.id] != true }
    }

    /// The ordered, visible list — matches what the user sees top-to-bottom.
    /// Used by keyboard nav to map focusedIndex to a profile.
    private var visibleOrdered: [ChromeProfile] {
        if settings.groupByBrowser {
            var out: [ChromeProfile] = []
            for b in Browser.allCases where settings.enabledBrowsers.contains(b) {
                let group = filteredProfiles.filter { $0.browser == b }
                out.append(contentsOf: subgroup(group))
            }
            return out
        }
        return subgroup(filteredProfiles)
    }

    private func subgroup(_ list: [ChromeProfile]) -> [ChromeProfile] {
        if settings.groupByStatus && axTrusted {
            let open = list.filter { openWindowsByID[$0.id] == true }
            let closed = list.filter { openWindowsByID[$0.id] != true }
            return open + closed
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            if !axTrusted && settings.showAXBanner { axBanner }
            searchBar
            if queryIsURL { urlBanner }
            urlHistoryChips
            multiToolbar
            Divider().opacity(0.4)
            profileList
            if multiMode { multiActionBar }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 320)
        .task {
            axTrusted = AXPermission.isTrusted()
            loader.reload()
            await refreshOpenWindowsAsync()
            installKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .polychromeMenuWillShow)) { _ in
            axTrusted = AXPermission.isTrusted()
            loader.reload()
            focusedIndex = 0
            installKeyMonitor()   // reused popover may not re-run .task; ensure arrow/return nav is live
            Task { await refreshOpenWindowsAsync() }
        }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: keyboard nav

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            switch event.keyCode {
            case 125: // down
                moveFocus(by: 1)
                return nil
            case 126: // up
                moveFocus(by: -1)
                return nil
            case 36, 76: // return, enter
                if let p = focusedProfile() {
                    handleTap(p)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func moveFocus(by delta: Int) {
        let list = visibleOrdered
        guard !list.isEmpty else { return }
        let next = max(0, min(list.count - 1, focusedIndex + delta))
        focusedIndex = next
    }

    private func focusedProfile() -> ChromeProfile? {
        let list = visibleOrdered
        guard !list.isEmpty else { return nil }
        let i = max(0, min(list.count - 1, focusedIndex))
        return list[i]
    }

    // MARK: banners

    private var axBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility required")
                    .font(.system(size: 12, weight: .semibold))
                Text("For tiling + duplicate-window detection.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                _ = AXPermission.isTrusted(prompt: true)
                AXPermission.openSystemSettings()
            } label: {
                Text("Grant").font(.system(size: 11, weight: .medium))
            }
            .controlSize(.small)
            Button {
                settings.showAXBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Hide this banner")
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
            ForEach(Array(Browser.allCases.filter { settings.enabledBrowsers.contains($0) && $0.isInstalled }), id: \.self) { b in
                Image(systemName: b.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(b.accent))
                    .help(b.displayName)
            }
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
                .onChange(of: query) { _ in focusedIndex = 0 }
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

    // MARK: URL history chips

    @ViewBuilder
    private var urlHistoryChips: some View {
        let showChips = settings.quickLaunchEnabled
            && query.isEmpty
            && !settings.urlHistory.isEmpty
        if showChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(settings.urlHistory, id: \.self) { u in
                        Button { query = u } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(prettyHost(u))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(u)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.top, 6)
        }
    }

    private func prettyHost(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
                } else {
                    if settings.groupByStatus && !axTrusted {
                        axNeededInline
                    }
                    listBody
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 260, maxHeight: 400)
    }

    @ViewBuilder
    private var listBody: some View {
        if settings.groupByBrowser {
            ForEach(Array(Browser.allCases.filter { settings.enabledBrowsers.contains($0) }), id: \.self) { b in
                let group = filteredProfiles.filter { $0.browser == b }
                if !group.isEmpty {
                    browserHeader(b, count: group.count)
                    statusGroupedBody(group)
                }
            }
        } else {
            statusGroupedBody(filteredProfiles)
        }
    }

    @ViewBuilder
    private func statusGroupedBody(_ list: [ChromeProfile]) -> some View {
        if settings.groupByStatus && axTrusted {
            let open = list.filter { openWindowsByID[$0.id] == true }
            let closed = list.filter { openWindowsByID[$0.id] != true }
            if !open.isEmpty {
                sectionHeader("OPEN", count: open.count, color: .green)
                ForEach(open) { p in row(for: p) }
            }
            if !closed.isEmpty {
                if !open.isEmpty {
                    Divider().opacity(0.3).padding(.horizontal, 10).padding(.vertical, 3)
                }
                sectionHeader("CLOSED", count: closed.count, color: .secondary)
                ForEach(closed) { p in row(for: p) }
            }
        } else {
            ForEach(list) { p in row(for: p) }
        }
    }

    private var axNeededInline: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Grant Accessibility to detect open windows")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Grant") {
                _ = AXPermission.isTrusted(prompt: true)
                AXPermission.openSystemSettings()
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08))
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func browserHeader(_ b: Browser, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: b.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(b.accent))
            Text(b.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
        let visible = visibleOrdered
        let focused = (visible.firstIndex(of: p) == focusedIndex)
        ProfileRow(
            profile: p,
            multiSelected: multiSelected.contains(p.id),
            isOpen: openWindowsByID[p.id] == true,
            showEmail: settings.showEmails,
            tag: settings.tagsEnabled ? settings.tag(for: p) : .none,
            urlMode: queryIsURL,
            kbdFocused: focused
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
                ChromeLauncher.launch(profile: p)
                dismiss()
            } label: { Label("Force new window", systemImage: "plus.rectangle.on.rectangle") }

            Button {
                ChromeLauncher.launchOrFocus(profile: p, incognito: true)
                dismiss()
            } label: { Label("Open incognito window", systemImage: "eyeglasses") }

            if settings.tagsEnabled {
                Divider()
                Menu {
                    ForEach(ProfileTag.allCases) { t in
                        Button {
                            settings.setTag(t, for: p)
                        } label: {
                            if t == .none {
                                Label("Clear", systemImage: "xmark.circle")
                            } else {
                                Label(t.displayName, systemImage: settings.tag(for: p) == t ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                } label: { Label("Tag", systemImage: "tag") }
            }
        }
    }

    private func handleTap(_ p: ChromeProfile) {
        if multiMode {
            if let i = multiSelected.firstIndex(of: p.id) {
                multiSelected.remove(at: i)
            } else {
                multiSelected.append(p.id)
            }
            return
        }
        if queryIsURL {
            let url = normalizedURL
            settings.remember(url: url)
            ChromeLauncher.launchOrFocus(profile: p, url: url)
        } else if settings.focusExisting {
            ChromeLauncher.launchOrFocus(profile: p)
        } else {
            ChromeLauncher.launch(profile: p)
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
                    let ids = multiSelected
                    let profilesToOpen = loader.profiles.filter { ids.contains($0.id) }
                    let url: String? = queryIsURL ? normalizedURL : nil
                    if let url { settings.remember(url: url) }
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
                    let ids = multiSelected
                    let profilesToOpen = loader.profiles.filter { ids.contains($0.id) }
                    let url: String? = queryIsURL ? normalizedURL : nil
                    if let url { settings.remember(url: url) }
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
        let enabled = settings.enabledBrowsers
        struct Result {
            var titleMap: [String: AXUIElement]
            var activeByBrowser: [Browser: Set<String>]
        }
        let result = await Task.detached(priority: .userInitiated) { () -> Result in
            let titleMap = WindowFinder.allWindowsMappedToProfiles(profiles)
            var active: [Browser: Set<String>] = [:]
            for b in enabled {
                let dirs = Set(profiles.filter { $0.browser == b }.map { $0.dirName })
                active[b] = BrowserActivity.activeDirs(for: b, knownDirs: dirs)
            }
            return Result(titleMap: titleMap, activeByBrowser: active)
        }.value
        var dict: [String: Bool] = [:]
        for p in profiles {
            let titleHit = result.titleMap[p.id] != nil
            let activeHit = result.activeByBrowser[p.browser]?.contains(p.dirName) ?? false
            dict[p.id] = titleHit || activeHit
        }
        openWindowsByID = dict
        NSLog("[Polychrome] refreshOpenWindows: axTrusted=\(AXPermission.isTrusted()) title=\(result.titleMap.count) active=\(result.activeByBrowser)")
    }
}
