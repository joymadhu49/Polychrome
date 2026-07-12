import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var menuVisible: Bool = false
    @State private var dropTargetID: String?       // row currently hovered by a URL drag
    @FocusState private var searchFocused: Bool

    // MARK: filtering

    private var filteredProfiles: [ChromeProfile] {
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
    /// Open profiles always lead, across all browsers — they're the reachable ones.
    private var visibleOrdered: [ChromeProfile] {
        if settings.groupByStatus && axTrusted {
            let open = orderedByBrowser(filteredProfiles.filter { openWindowsByID[$0.id] == true })
            let closed = filteredProfiles.filter { openWindowsByID[$0.id] != true }
            return open + (settings.groupByBrowser ? orderedByBrowser(closed) : closed)
        }
        if settings.groupByBrowser { return orderedByBrowser(filteredProfiles) }
        return filteredProfiles
    }

    private func orderedByBrowser(_ list: [ChromeProfile]) -> [ChromeProfile] {
        Browser.allCases.flatMap { b in list.filter { $0.browser == b } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            if !axTrusted && settings.showAXBanner { axBanner }
            searchBar
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
            menuVisible = true
            loader.reload()
            await refreshOpenWindowsAsync()
            installKeyMonitor()
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .polychromeMenuWillShow)) { _ in
            axTrusted = AXPermission.isTrusted()
            menuVisible = true
            loader.reload()
            query = ""            // fresh start on every open, like Spotlight
            focusedIndex = 0
            installKeyMonitor()   // reused popover may not re-run .task; ensure arrow/return nav is live
            focusSearch()
            Task { await refreshOpenWindowsAsync() }
        }
        // Live-refresh the OPEN list while the menu is showing, so closing a window
        // (or one that finishes launching) updates the dots without a manual refresh.
        // No-op while hidden — the reused popover keeps this view alive between opens.
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            guard menuVisible else { return }
            Task { await refreshOpenWindowsAsync() }
        }
        .onDisappear {
            menuVisible = false
            removeKeyMonitor()
        }
    }

    // MARK: keyboard nav

    /// The popover window may not be key yet when the show notification fires,
    /// so retry shortly after — immediate assignment alone races makeKey().
    private func focusSearch() {
        searchFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            searchFocused = true
        }
    }

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
            case 53: // escape — progressive: clear search, exit multi-select, then close
                if !query.isEmpty {
                    query = ""
                } else if multiMode {
                    resetMulti()
                } else {
                    dismiss()
                }
                return nil
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
                Text("For tiling + focusing the right profile window. If it shows as ON, remove the old Polychrome row, then re-add this build.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Button {
                settings.pinned.toggle()
            } label: {
                Image(systemName: settings.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.pinned ? Color.accentColor : .secondary)
                    .rotationEffect(.degrees(settings.pinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: settings.pinned)
            .help(settings.pinned
                  ? "Unpin — menu closes when you click away"
                  : "Pin on top — keep the menu open above other windows")
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search profiles", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
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
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    Color.clear.frame(height: 1).id("list-top")
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
            .onChange(of: focusedIndex) { idx in
                let list = visibleOrdered
                guard !list.isEmpty else { return }
                let i = max(0, min(list.count - 1, idx))
                proxy.scrollTo(list[i].id, anchor: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .polychromeMenuWillShow)) { _ in
                // The popover view is reused between opens, so the scroll offset
                // would otherwise persist — always reopen at the top.
                proxy.scrollTo("list-top", anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if settings.groupByStatus && axTrusted {
            // Open profiles lead the whole list, whatever browser they belong to —
            // burying an open Brave window under every closed Chrome profile made
            // the most useful rows the hardest to reach.
            let open = orderedByBrowser(filteredProfiles.filter { openWindowsByID[$0.id] == true })
            let closed = filteredProfiles.filter { openWindowsByID[$0.id] != true }
            if !open.isEmpty {
                sectionHeader("OPEN", count: open.count, color: .green)
                ForEach(open) { p in row(for: p) }
            }
            if !closed.isEmpty {
                if !open.isEmpty {
                    Divider().opacity(0.3).padding(.horizontal, 10).padding(.vertical, 3)
                }
                sectionHeader("CLOSED", count: closed.count, color: .secondary)
                if settings.groupByBrowser {
                    ForEach(Array(Browser.allCases.filter { settings.enabledBrowsers.contains($0) }), id: \.self) { b in
                        let group = closed.filter { $0.browser == b }
                        if !group.isEmpty {
                            browserHeader(b, count: group.count)
                            ForEach(group) { p in row(for: p) }
                        }
                    }
                } else {
                    ForEach(closed) { p in row(for: p) }
                }
            }
        } else if settings.groupByBrowser {
            ForEach(Array(Browser.allCases.filter { settings.enabledBrowsers.contains($0) }), id: \.self) { b in
                let group = filteredProfiles.filter { $0.browser == b }
                if !group.isEmpty {
                    browserHeader(b, count: group.count)
                    ForEach(group) { p in row(for: p) }
                }
            }
        } else {
            ForEach(filteredProfiles) { p in row(for: p) }
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
        let canClose = axTrusted && openWindowsByID[p.id] == true
        ProfileRow(
            profile: p,
            multiSelected: multiSelected.contains(p.id),
            isOpen: openWindowsByID[p.id] == true,
            showEmail: settings.showEmails,
            tag: settings.tagsEnabled ? settings.tag(for: p) : .none,
            kbdFocused: focused,
            dropTargeted: dropTargetID == p.id,
            closeAction: canClose ? { closeWindows(of: p) } : nil
        ) {
            handleTap(p)
        }
        .padding(.horizontal, 6)
        // Drop target lives here, OUTSIDE ProfileRow's Button, so button
        // hit-testing can never shadow it. Covers the full row width.
        .onDrop(of: URLDrop.acceptedTypes, isTargeted: dropTargetBinding(for: p)) { providers in
            URLDrop.load(providers) { url in
                if let url { handleDroppedURL(url, on: p) }
            }
            return true
        }
        .contextMenu {
            Button {
                ChromeLauncher.launchOrFocus(profile: p)
                dismissUnlessPinned()
            } label: { Label("Open or focus", systemImage: "arrow.up.forward.square") }

            Button {
                ChromeLauncher.launch(profile: p)
                dismissUnlessPinned()
            } label: { Label("Force new window", systemImage: "plus.rectangle.on.rectangle") }

            Button {
                ChromeLauncher.launchOrFocus(profile: p, incognito: true)
                dismissUnlessPinned()
            } label: { Label("Open incognito window", systemImage: "eyeglasses") }

            if axTrusted && openWindowsByID[p.id] == true {
                Divider()
                Button {
                    closeWindows(of: p)
                } label: { Label("Close window", systemImage: "xmark.circle") }
            }

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
        .id(p.id)
    }

    private func dropTargetBinding(for p: ChromeProfile) -> Binding<Bool> {
        Binding(
            get: { dropTargetID == p.id },
            set: { on in
                if on { dropTargetID = p.id }
                else if dropTargetID == p.id { dropTargetID = nil }
            }
        )
    }

    /// A link dropped onto a profile row opens immediately in that profile.
    private func handleDroppedURL(_ url: String, on p: ChromeProfile) {
        dropTargetID = nil
        ChromeLauncher.launchOrFocus(profile: p, url: url)
        dismissUnlessPinned()
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
        if settings.focusExisting {
            ChromeLauncher.launchOrFocus(profile: p)
        } else {
            ChromeLauncher.launch(profile: p)
        }
        dismissUnlessPinned()
    }

    /// Close every window attributed to the profile, then re-scan so its green dot
    /// clears. The menu stays open — closing is a management action, and the user may
    /// want to close several profiles in a row.
    private func closeWindows(of p: ChromeProfile) {
        Task {
            await Task.detached(priority: .userInitiated) {
                // AX presses are synchronous IPC to the browser — keep them off the main thread.
                for w in WindowFinder.windows(forProfile: p) {
                    WindowFinder.close(w)
                }
            }.value
            // Give the browser a beat to tear the window down before re-scanning.
            try? await Task.sleep(nanoseconds: 700_000_000)
            await refreshOpenWindowsAsync()
        }
    }

    // MARK: action bar

    private var multiActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    let ids = multiSelected
                    let profilesToOpen = loader.profiles.filter { ids.contains($0.id) }
                    ChromeLauncher.launchMany(profiles: profilesToOpen)
                    resetMulti()
                    dismissUnlessPinned()
                } label: {
                    Label("Open \(multiSelected.count)", systemImage: "square.and.arrow.up.on.square")
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
                    resetMulti()
                    dismissUnlessPinned()
                    Task { @MainActor in
                        await WindowTiler.launchAndTile(profiles: profilesToOpen, config: settings.layout)
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

    /// Pinned menus stay open after launching — refresh the open dots
    /// (after a beat, so the new window exists) instead of closing.
    private func dismissUnlessPinned() {
        if settings.pinned {
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await refreshOpenWindowsAsync()
            }
        } else {
            dismiss()
        }
    }

    private func refreshOpenWindowsAsync() async {
        let profiles = loader.profiles
        let enabled = settings.enabledBrowsers
        // "Open" must mean "has a visible window," not "the browser process is holding this
        // profile's files open." Chrome keeps per-profile files open (sync, leveldb, extension
        // service workers, background apps) long after the last window of that profile closes,
        // so lsof alone reports a closed profile as active — the phantom green dot that sticks
        // at the top of OPEN and never clears. So we go per-browser:
        //   • title-transparent (Chrome multi-profile): AX titles name every open window →
        //     trust them, skip lsof → closed profiles' leases can't create phantoms.
        //   • title-opaque WITH windows (Brave, single-profile Chrome): titles omit the
        //     profile → fall back to lsof to tell which profiles are live.
        //   • no windows at all: nothing is open, regardless of any lingering background process.
        let trusted = axTrusted
        struct Result {
            var scan: WindowFinder.WindowScan
            var activeByBrowser: [Browser: Set<String>]
        }
        let result = await Task.detached(priority: .userInitiated) { () -> Result in
            let scan = WindowFinder.scanWindows(profiles)
            var active: [Browser: Set<String>] = [:]
            for b in enabled {
                let transparent = (scan.tokenMatchCount[b] ?? 0) > 0
                let hasWindows = (scan.windowCount[b] ?? 0) > 0
                // Only pay for lsof where AX can't name the windows itself.
                if !trusted || (!transparent && hasWindows) {
                    let dirs = Set(profiles.filter { $0.browser == b }.map { $0.dirName })
                    active[b] = BrowserActivity.activeDirs(for: b, knownDirs: dirs)
                }
            }
            return Result(scan: scan, activeByBrowser: active)
        }.value
        var dict: [String: Bool] = [:]
        for p in profiles {
            let b = p.browser
            let windowHit = result.scan.windowByProfileID[p.id] != nil
            let activeHit = result.activeByBrowser[b]?.contains(p.dirName) ?? false
            if trusted {
                let transparent = (result.scan.tokenMatchCount[b] ?? 0) > 0
                dict[p.id] = transparent ? windowHit : (windowHit || activeHit)
            } else {
                dict[p.id] = activeHit
            }
        }
        openWindowsByID = dict
        NSLog("[Polychrome] refreshOpenWindows: axTrusted=\(trusted) windows=\(result.scan.windowByProfileID.count) tokens=\(result.scan.tokenMatchCount) active=\(result.activeByBrowser)")
    }
}
