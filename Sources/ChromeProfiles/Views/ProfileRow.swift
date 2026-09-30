import SwiftUI
import AppKit

struct ProfileAvatar: View {
    let profile: ChromeProfile
    var size: CGFloat = 28

    private var seedColor: Color {
        // Deterministic across launches (djb2 over UTF8) — String.hashValue is per-process seeded.
        var h: UInt64 = 5381
        for b in profile.dirName.utf8 { h = h &* 33 &+ UInt64(b) }
        let hues: [Double] = [0.02, 0.08, 0.14, 0.28, 0.42, 0.52, 0.60, 0.72, 0.84, 0.92]
        return Color(hue: hues[Int(h % UInt64(hues.count))], saturation: 0.45, brightness: 0.78)
    }

    var body: some View {
        Group {
            if let img = profile.avatarImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle().fill(seedColor)
                    Text(profile.initial)
                        .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: size, height: size)
            }
        }
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct ProfileRow: View {
    let profile: ChromeProfile
    var selectionMode: Bool = false
    var selected: Bool = false
    let isOpen: Bool
    let showEmail: Bool
    var showBrowserBadge: Bool = false
    let tag: ProfileTag
    let highlighted: Bool                  // keyboard focus or pointer — one shared highlight
    var dropTargeted: Bool = false         // a URL drag is hovering this row (drop handled by MenuView)
    var shortcut: String? = nil            // "⌘1"…"⌘9" for the first nine rows
    var revealShortcut: Bool = false       // ⌘ is held — show every row's shortcut
    var windowCount: Int = 0               // open windows attributed to this profile (0 = none/unknown)
    var windowAction: ((Int) -> Void)? = nil  // click on window box i (0-based) → focus that window
    var closeAction: (() -> Void)? = nil   // non-nil only for open profiles (needs AX)
    var onHover: () -> Void = {}
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if selectionMode {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                avatar

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if tag != .none {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 7, height: 7)
                                .help("Tag: \(tag.displayName)")
                        }
                    }
                    if showEmail, let email = profile.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 6)

                trailing
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
        .animation(.easeOut(duration: 0.12), value: selectionMode)
        .animation(.easeOut(duration: 0.08), value: highlighted)
        .animation(.easeOut(duration: 0.10), value: dropTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: pieces

    private var avatar: some View {
        ProfileAvatar(profile: profile, size: 28)
            .overlay(alignment: .bottomTrailing) {
                if isOpen {
                    // Presence dot, ringed in the menu's own background so it reads as a cutout.
                    Circle()
                        .fill(Color.green)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .offset(x: 2, y: 2)
                        .help("Window open")
                }
            }
            .overlay(alignment: .topLeading) {
                if showBrowserBadge {
                    Image(systemName: profile.browser.symbolName)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(Color(profile.browser.accent)))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: -3, y: -3)
                        .help(profile.browser.displayName)
                }
            }
    }

    @ViewBuilder
    private var trailing: some View {
        if dropTargeted {
            Label("Open here", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
        } else if !selectionMode {
            HStack(spacing: 8) {
                // A single window is what clicking the row already raises; boxes only
                // earn their space once there's a choice between windows.
                if windowCount > 1, let windowAction {
                    HStack(spacing: 3) {
                        ForEach(0..<min(windowCount, 4), id: \.self) { i in
                            WindowBox(index: i + 1) { windowAction(i) }
                        }
                        if windowCount > 4 {
                            Text("+\(windowCount - 4)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .help("\(windowCount) windows open")
                        }
                    }
                }
                if highlighted, let closeAction {
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(windowCount > 1 ? "Close all \(windowCount) windows" : "Close window")
                }
                if let shortcut, highlighted || revealShortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 22, alignment: .trailing)
                }
            }
        }
    }

    private var rowBackground: Color {
        if dropTargeted { return Color.accentColor.opacity(0.18) }
        if selectionMode && selected { return Color.accentColor.opacity(highlighted ? 0.18 : 0.12) }
        if highlighted { return Color.primary.opacity(0.07) }
        return .clear
    }

    private var accessibilityText: String {
        var parts = [profile.displayName]
        if isOpen { parts.append("open") }
        if selectionMode { parts.append(selected ? "selected" : "not selected") }
        return parts.joined(separator: ", ")
    }
}

/// A small clickable window glyph on an open profile row — one per browser window.
/// Drawn as a miniature window (title-bar strip + body); clicking it raises exactly
/// that window (a real window, not a tab).
struct WindowBox: View {
    let index: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                (hovering ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                Rectangle()
                    .fill(hovering ? Color.accentColor : Color.primary.opacity(0.22))
                    .frame(height: 3.5)
            }
            .frame(width: 18, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(hovering ? Color.accentColor : Color.primary.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .help("Window \(index) — click to switch to it")
    }
}
