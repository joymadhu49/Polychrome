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
        return Color(hue: hues[Int(h % UInt64(hues.count))], saturation: 0.58, brightness: 0.82)
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
                    Circle().fill(
                        LinearGradient(
                            colors: [seedColor, seedColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    Text(profile.initial)
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: size, height: size)
            }
        }
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
    }
}

struct ProfileRow: View {
    let profile: ChromeProfile
    let multiSelected: Bool
    let isOpen: Bool
    let showEmail: Bool
    let tag: ProfileTag
    let urlMode: Bool       // true when search query is URL-like
    let kbdFocused: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(profile: profile)
                    // Browser glyph at bottom-left (small badge)
                    Image(systemName: profile.browser.symbolName)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 11, height: 11)
                        .background(Circle().fill(Color(profile.browser.accent)))
                        .overlay(Circle().stroke(.background, lineWidth: 1))
                        .offset(x: -22, y: 1)
                    if tag != .none {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                            .offset(x: 1, y: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(profile.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isOpen {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .shadow(color: .green.opacity(0.6), radius: 2)
                                .help("Window open")
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

                Spacer(minLength: 4)

                if multiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tint)
                } else if urlMode {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tint)
                } else if hovering || kbdFocused {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(kbdFocused ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.10), value: multiSelected)
        .animation(.easeOut(duration: 0.10), value: kbdFocused)
    }

    private var rowBackground: Color {
        if multiSelected { return Color.accentColor.opacity(0.18) }
        if kbdFocused { return Color.accentColor.opacity(0.10) }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}
