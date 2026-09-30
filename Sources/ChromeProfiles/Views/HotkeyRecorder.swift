import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click-to-record shortcut field. Esc cancels; the first chord with a modifier is kept.
struct HotkeyRecorder: View {
    @Binding var config: HotkeyConfig
    @State private var recording = false
    @State private var hovering = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                if recording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Type shortcut…")
                        .foregroundStyle(.tint)
                } else {
                    Text(config.displayString)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 12))
            .frame(minWidth: 120, minHeight: 24)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering || recording ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: recording ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recording ? "Press a shortcut, or Esc to cancel" : "Click to record a new shortcut")
        .accessibilityLabel(recording ? "Recording shortcut" : "Shortcut \(config.displayString)")
        .onDisappear { stopMonitor(); recording = false }
    }

    private func toggleRecording() {
        recording.toggle()
        if recording { startMonitor() } else { stopMonitor() }
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels recording without binding a shortcut.
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.recording = false; self.stopMonitor() }
                return nil
            }
            // ignore plain modifier-only presses; require a non-modifier key
            let mods = HotkeyConfig.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return event }
            config = HotkeyConfig.recorded(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                enabled: config.enabled
            )
            DispatchQueue.main.async { self.recording = false; self.stopMonitor() }
            return nil
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
