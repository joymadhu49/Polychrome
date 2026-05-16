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

    private var filteredProfiles: [ChromeProfile] {
        guard !query.isEmpty else { return loader.profiles }
        let q = query.lowercased()
        return loader.profiles.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.email?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            if !axTrusted { axBanner }
            searchBar
            multiToolbar
            Divider().opacity(0.5)
            profileList
            if multiMode { multiActionBar }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            axTrusted = AXPermission.isTrusted()
            loader.reload()
            await refreshOpenWindowsAsync()
        }
    }

    private var axBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility required")
                    .font(.system(size: 12, weight: .semibold))
                Text("Side-by-side and duplicate-window detection need access.")
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

    // MARK: title bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            Text("Polychrome")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(loader.profiles.count) profiles")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 7)
    }

    // MARK: search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            TextField("Search profiles…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
    }

    private var multiToolbar: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $multiMode) {
                Label(multiMode ? "Selecting" : "Multi-select",
                      systemImage: multiMode ? "checkmark.square.fill" : "square.dashed")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .onChange(of: multiMode) { newValue in
                if !newValue { multiSelected.removeAll() }
            }

            if multiMode && !multiSelected.isEmpty {
                Text("\(multiSelected.count) selected")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
            }

            Spacer()

            Button {
                loader.reload()
                Task { await refreshOpenWindowsAsync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Refresh profiles")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: list

    private var profileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if let err = loader.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                ForEach(filteredProfiles) { p in
                    ProfileRow(
                        profile: p,
                        multiSelected: multiSelected.contains(p.dirName),
                        isOpen: openWindowsByDir[p.dirName] == true,
                        showEmail: settings.showEmails
                    ) {
                        handleTap(p)
                    }
                    .padding(.horizontal, 6)
                }

                if filteredProfiles.isEmpty {
                    Text("No profiles match.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 300, maxHeight: 430)
    }

    private func handleTap(_ p: ChromeProfile) {
        if multiMode {
            if let i = multiSelected.firstIndex(of: p.dirName) {
                multiSelected.remove(at: i)
            } else {
                multiSelected.append(p.dirName)
            }
        } else {
            if settings.focusExisting {
                ChromeLauncher.launchOrFocus(profile: p)
            } else {
                ChromeLauncher.launch(profileDir: p.dirName)
            }
            dismiss()
        }
    }

    // MARK: action bar

    private var multiActionBar: some View {
        HStack(spacing: 8) {
            Button {
                let dirs = multiSelected
                let profilesToOpen = loader.profiles.filter { dirs.contains($0.dirName) }
                ChromeLauncher.launchMany(profiles: profilesToOpen)
                resetMulti()
                dismiss()
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
                let dirs = multiSelected
                let profilesToOpen = loader.profiles.filter { dirs.contains($0.dirName) }
                resetMulti()
                dismiss()
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
            .help(axTrusted ? "Tile selected profiles side-by-side" : "Grant Accessibility access to enable")

            Spacer()

            Button("Clear") { multiSelected.removeAll() }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .disabled(multiSelected.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.07))
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            Spacer()

            Text(settings.hotkey.enabled ? settings.hotkey.displayString : "Hotkey off")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Quit Polychrome")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
