import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One titled run of rows in the menu. The list and keyboard navigation both read
/// from `sections`, so what you see top-to-bottom and what ↑/↓/⌘1–9 reach can never
/// drift apart.
private struct MenuSection: Identifiable {
    let id: String
    let title: String?          // nil = no header (a single flat list)
    let browser: Browser?       // set when the section is one browser's profiles
    let profiles: [ChromeProfile]
}

private enum MenuMetrics {
    static let width: CGFloat = 340
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 28
    static let listMaxHeight: CGFloat = 440
}

struct MenuView: View {
    @ObservedObject var loader: ChromeProfileLoader
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateController
    let openSettings: (SettingsPane?) -> Void
    let dismiss: () -> Void

    @State private var query: String = ""
    @State private var multiMode: Bool = false
    @State private var multiSelected: [String] = []   // profile.id
    @State private var openWindowsByID: [String: Bool] = [:]
    @State private var profileWindows: [String: [WindowFinder.ProfileWindow]] = [:]
    @State private var axTrusted: Bool = AXPermission.isTrusted()
    @State private var focusedIndex: Int = 0
    @State private var keyMonitor: Any?
    @State private var menuVisible: Bool = false
    @State private var commandHeld: Bool = false
    @State private var hoverSuppressedUntil: Date = .distantPast
    @State private var dropTargetID: String?       // row currently hovered by a URL drag
    @FocusState private var searchFocused: Bool

    // MARK: data

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

    private func isOpen(_ p: ChromeProfile) -> Bool { openWindowsByID[p.id] == true }

    /// More than one browser actually contributes profiles — only then are browser
    /// headers and avatar badges worth the space.
    private var showsBrowserIdentity: Bool {
        Set(loader.profiles.map(\.browser)).count > 1
    }

    private var showsOpenGroup: Bool { settings.groupByStatus && axTrusted }

    private var sections: [MenuSection] {
        let list = filteredProfiles
        let splitByBrowser = settings.groupByBrowser && showsBrowserIdentity

        func byBrowser(_ ps: [ChromeProfile], prefix: String) -> [MenuSection] {
            Browser.allCases.compactMap { b in
                let group = ps.filter { $0.browser == b }
                guard !group.isEmpty else { return nil }
                return MenuSection(id: prefix + b.rawValue, title: b.displayName, browser: b, profiles: group)
            }
        }

        if showsOpenGroup {
            // Open profiles lead the whole list, whatever browser they belong to —
            // they're the ones you're most likely reaching for.
            let open = Browser.allCases.flatMap { b in list.filter { $0.browser == b && isOpen($0) } }
            let rest = list.filter { !isOpen($0) }
            var out: [MenuSection] = []
            if !open.isEmpty {
                out.append(MenuSection(id: "open", title: "Open", browser: nil, profiles: open))
            }
            if splitByBrowser {
                out += byBrowser(rest, prefix: "rest-")
            } else if !rest.isEmpty {
                out.append(MenuSection(id: "rest", title: open.isEmpty ? nil : "Other profiles",
                                       browser: nil, profiles: rest))
            }
            return out
        }
        if splitByBrowser { return byBrowser(list, prefix: "") }
        return list.isEmpty ? [] : [MenuSection(id: "all", title: nil, browser: nil, profiles: list)]
    }

    private var listHeight: CGFloat {
        let secs = sections
        guard !secs.isEmpty else { return 132 }
        var h: CGFloat = 12
        for s in secs {
            if s.title != nil { h += MenuMetrics.headerHeight }
            h += CGFloat(s.profiles.count) * MenuMetrics.rowHeight
        }
        if settings.groupByStatus && !axTrusted { h += 36 }
        if loader.lastError != nil { h += 30 }
        return min(h, MenuMetrics.listMaxHeight)
    }

    // MARK: body

    var body: some View {
        let secs = sections
        let ordered = secs.flatMap(\.profiles)
        VStack(spacing: 0) {
            header
            Divider()
            if !axTrusted && settings.showAXBanner { axBanner }
            profileList(secs, ordered: ordered)
            if let version = updates.pendingVersion { updateBanner(version) }
            Divider()
            footer
        }
        .frame(width: MenuMetrics.width)
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
            commandHeld = false
            // Rows appearing under a resting pointer fire hover-enter; the first row
            // should stay highlighted until the mouse actually moves.
            hoverSuppressedUntil = Date().addingTimeInterval(0.5)
            installKeyMonitor()   // reused popover may not re-run .task; ensure arrow/return nav is live
            focusSearch()
            Task { await refreshOpenWindowsAsync() }
        }
        // Live-refresh the open state while the menu is showing, so closing a window
        // (or one that finishes launching) updates without a manual refresh.
        // No-op while hidden — the reused popover keeps this view alive between opens.
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            guard menuVisible else { return }
            Task { await refreshOpenWindowsAsync() }
        }
        .onDisappear {
            menuVisible = false
            commandHeld = false
            removeKeyMonitor()
        }
    }

    // MARK: keyboard

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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .flagsChanged {
                // Only the four chord modifiers — Caps Lock or fn must not hide the hints.
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                commandHeld = mods == .command
                return event
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if mods == .command, let ch = event.charactersIgnoringModifiers {
                switch ch {
                case "1"..."9":
                    let list = sections.flatMap(\.profiles)
                    if let n = Int(ch), n <= list.count { handleTap(list[n - 1]) }
                    return nil
                case ",":
                    openSettings(nil)
                    return nil
                case "q":
                    NSApp.terminate(nil)
                    return nil
                case "r":
                    refresh()
                    return nil
                default:
                    return event
                }
            }
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
        let count = sections.reduce(0) { $0 + $1.profiles.count }
        guard count > 0 else { return }
        hoverSuppressedUntil = Date().addingTimeInterval(0.35)
        focusedIndex = max(0, min(count - 1, focusedIndex + delta))
    }

    private func focusedProfile() -> ChromeProfile? {
        let list = sections.flatMap(\.profiles)
        guard !list.isEmpty else { return nil }
        return list[max(0, min(list.count - 1, focusedIndex))]
    }

    /// The pointer and the arrow keys drive one shared highlight, like a native menu.
    /// Arrow-key scrolling slides rows under a resting pointer, which would otherwise
    /// yank the highlight back to the mouse — so hover is ignored right after a key
    /// (and right after the menu opens).
    private func hoverFocus(_ index: Int) {
        guard Date() >= hoverSuppressedUntil else { return }
        focusedIndex = index
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search profiles", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onChange(of: query) { _ in focusedIndex = 0 }
            if !query.isEmpty {
                IconButton(systemName: "xmark.circle.fill", help: "Clear search") { query = "" }
            }
            IconButton(systemName: settings.pinned ? "pin.fill" : "pin",
                       help: settings.pinned
                           ? "Unpin — the menu closes when you click away"
                           : "Pin — keep the menu open above other windows",
                       active: settings.pinned) {
                settings.pinned.toggle()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    // MARK: banners

    private var axBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Allow Accessibility access")
                    .font(.system(size: 12, weight: .semibold))
                Text("Needed to find open windows and tile them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Allow") {
                _ = AXPermission.isTrusted(prompt: true)
                AXPermission.openSystemSettings()
            }
            .controlSize(.small)
            IconButton(systemName: "xmark", help: "Hide this banner", size: 10) {
                settings.showAXBanner = false
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func updateBanner(_ version: String) -> some View {
        Button {
            dismiss()
            updates.checkForUpdates()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                Text("Polychrome \(version) is available")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("Update…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: list

    private func profileList(_ secs: [MenuSection], ordered: [ChromeProfile]) -> some View {
        // Index lookup built once per render (was a linear search per row).
        let indexByID = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        let focusedID = ordered.isEmpty ? nil : ordered[max(0, min(ordered.count - 1, focusedIndex))].id

        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 6).id("list-top")
                    if let err = loader.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    if settings.groupByStatus && !axTrusted && !secs.isEmpty {
                        axNeededInline
                    }
                    if secs.isEmpty {
                        emptyState
                    } else {
                        ForEach(secs) { section in
                            if let title = section.title {
                                sectionHeader(title, browser: section.browser, count: section.profiles.count)
                            }
                            ForEach(section.profiles) { p in
                                let idx = indexByID[p.id] ?? 0
                                row(for: p, index: idx, focused: p.id == focusedID)
                            }
                        }
                    }
                    Color.clear.frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)
            .onChange(of: focusedIndex) { idx in
                let list = sections.flatMap(\.profiles)
                // Only keyboard moves scroll; hover-driven focus is already on screen.
                guard !list.isEmpty, Date() < hoverSuppressedUntil else { return }
                proxy.scrollTo(list[max(0, min(list.count - 1, idx))].id, anchor: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .polychromeMenuWillShow)) { _ in
                // The popover view is reused between opens, so the scroll offset
                // would otherwise persist — always reopen at the top.
                proxy.scrollTo("list-top", anchor: .top)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: query.isEmpty ? "person.crop.circle.badge.questionmark" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No profiles found" : "No profiles match “\(query)”")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Enable a browser in Settings → Browsers.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var axNeededInline: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Allow Accessibility to see which profiles are open.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Allow") {
                _ = AXPermission.isTrusted(prompt: true)
                AXPermission.openSystemSettings()
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func sectionHeader(_ title: String, browser: Browser?, count: Int) -> some View {
        HStack(spacing: 5) {
            if let browser {
                Image(systemName: browser.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(browser.accent))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(height: MenuMetrics.headerHeight, alignment: .bottom)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(for p: ChromeProfile, index: Int, focused: Bool) -> some View {
        let open = isOpen(p)
        let wins = axTrusted ? (profileWindows[p.id] ?? []) : []
        let shortcut: String? = index < 9 && !multiMode ? "⌘\(index + 1)" : nil
        ProfileRow(
            profile: p,
            selectionMode: multiMode,
            selected: multiSelected.contains(p.id),
            isOpen: open,
            showEmail: settings.showEmails,
            showBrowserBadge: showsBrowserIdentity && !settings.groupByBrowser,
            tag: settings.tagsEnabled ? settings.tag(for: p) : .none,
            highlighted: focused,
            dropTargeted: dropTargetID == p.id,
            shortcut: shortcut,
            revealShortcut: commandHeld,
            windowCount: wins.count,
            windowAction: wins.isEmpty ? nil : { i in
                if i < wins.count { focusWindow(wins[i]) }
            },
            closeAction: axTrusted && open ? { closeWindows(of: p) } : nil,
            onHover: { hoverFocus(index) }
        ) {
            handleTap(p)
        }
        .frame(height: MenuMetrics.rowHeight)
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
            } label: { Label("Open or Focus", systemImage: "arrow.up.forward.square") }

            Button {
                ChromeLauncher.launch(profile: p)
                dismissUnlessPinned()
            } label: { Label("New Window", systemImage: "plus.rectangle.on.rectangle") }

            Button {
                ChromeLauncher.launchOrFocus(profile: p, incognito: true)
                dismissUnlessPinned()
            } label: { Label("New Incognito Window", systemImage: "eyeglasses") }

            if axTrusted && open {
                Divider()
                Button {
                    closeWindows(of: p)
                } label: { Label(wins.count > 1 ? "Close \(wins.count) Windows" : "Close Window",
                                 systemImage: "xmark.circle") }
            }

            if settings.tagsEnabled {
                Divider()
                Menu {
                    ForEach(ProfileTag.allCases) { t in
                        Button {
                            settings.setTag(t, for: p)
                        } label: {
                            if t == .none {
                                Label("No Tag", systemImage: "circle.slash")
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

    // MARK: footer

    @ViewBuilder
    private var footer: some View {
        if multiMode { selectionFooter } else { standardFooter }
    }

    private var standardFooter: some View {
        HStack(spacing: 6) {
            FooterButton(title: "Select", systemName: "checkmark.circle",
                         help: "Select several profiles to open or tile together") {
                multiMode = true
            }

            Spacer()

            if let hotkey = settings.activeHotkey {
                KeyCap(hotkey.displayString)
                    .help("Global shortcut — opens this menu from anywhere")
            } else if settings.hotkey.enabled && settings.hotkeyRegistrationIssue != nil {
                Button { openSettings(.shortcuts) } label: {
                    Label("Shortcut unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Open Settings to choose another global shortcut")
            }

            Menu {
                Button("Settings…") { openSettings(nil) }
                    .keyboardShortcut(",", modifiers: .command)
                if updates.isAvailable {
                    Button("Check for Updates…") {
                        dismiss()
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }
                Button("Refresh Profiles") { refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("About Polychrome") { openSettings(.about) }
                Button("Quit Polychrome") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .help("Settings, updates and quit")
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 40)
    }

    private var selectionFooter: some View {
        HStack(spacing: 8) {
            Text(multiSelected.isEmpty ? "Select profiles" : "\(multiSelected.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(multiSelected.isEmpty ? .secondary : .primary)
                .monospacedDigit()

            Spacer()

            Button("Cancel") { resetMulti() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)

            Button {
                let ids = multiSelected
                ChromeLauncher.launchMany(profiles: loader.profiles.filter { ids.contains($0.id) })
                resetMulti()
                dismissUnlessPinned()
            } label: {
                Text("Open")
            }
            .controlSize(.small)
            .disabled(multiSelected.isEmpty)

            Button {
                guard AXPermission.isTrusted(prompt: true) else {
                    AXPermission.openSystemSettings()
                    return
                }
                let ids = multiSelected
                // Keep the user's selection order — it's the order windows tile in.
                let profilesToTile = ids.compactMap { id in loader.profiles.first { $0.id == id } }
                resetMulti()
                dismissUnlessPinned()
                Task { @MainActor in
                    await WindowTiler.launchAndTile(profiles: profilesToTile, config: settings.layout)
                }
            } label: {
                Label("Tile", systemImage: settings.layout.layout.icon)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(multiSelected.count < 2 || !axTrusted)
            .help(axTrusted ? "Arrange the selected profiles' windows side by side"
                            : "Tiling needs Accessibility access")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: actions

    /// Jump straight to one specific browser window (not a tab).
    ///
    /// Order matters: the popover made Polychrome the active app, and closing a
    /// transient popover hands activation back to the previously active app. If we
    /// focused Chrome first and closed after, that late reactivation would undo the
    /// raise — so close first, then focus once the teardown has settled.
    private func focusWindow(_ w: WindowFinder.ProfileWindow) {
        let element = w.element
        if settings.pinned {
            WindowFinder.focus(element)
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await refreshOpenWindowsAsync()
            }
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                WindowFinder.focus(element)
            }
        }
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

    private func refresh() {
        loader.reload()
        Task { await refreshOpenWindowsAsync() }
    }

    /// Close every window attributed to the profile, then re-scan so its open state
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

    private func resetMulti() {
        multiSelected.removeAll()
        multiMode = false
    }

    /// Pinned menus stay open after launching — refresh the open state
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
        // so lsof alone reports a closed profile as active — the phantom open state that sticks
        // at the top of the list and never clears. So we go per-browser:
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
        profileWindows = result.scan.windowsByProfileID
        NSLog("[Polychrome] refreshOpenWindows: axTrusted=\(trusted) windows=\(result.scan.windowByProfileID.count) tokens=\(result.scan.tokenMatchCount) active=\(result.activeByBrowser)")
    }
}

// MARK: - small controls

/// A borderless SF Symbol button with a hover wash, sized for the menu's chrome.
struct IconButton: View {
    let systemName: String
    let help: String
    var active: Bool = false
    var size: CGFloat = 12
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Text + symbol button for the footer, with the same hover wash as `IconButton`.
struct FooterButton: View {
    let title: String
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A keyboard-shortcut glyph drawn as a key cap.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
