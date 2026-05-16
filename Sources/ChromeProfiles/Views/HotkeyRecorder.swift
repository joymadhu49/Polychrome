import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorder: View {
    @Binding var config: HotkeyConfig
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(recording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: recording ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                HStack {
                    Spacer()
                    Text(recording ? "Press keys…" : config.displayString)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(recording ? .accentColor : .primary)
                    Spacer()
                }
            }
            .frame(width: 160, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { toggleRecording() }

            Button(recording ? "Cancel" : "Change") {
                toggleRecording()
            }
            .controlSize(.small)

            Toggle("Enabled", isOn: Binding(
                get: { config.enabled },
                set: { config.enabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .onDisappear { stopMonitor() }
    }

    private func toggleRecording() {
        recording.toggle()
        if recording { startMonitor() } else { stopMonitor() }
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // ignore plain modifier-only presses; require a non-modifier key
            let mods = HotkeyConfig.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return event }
            let key = UInt32(event.keyCode)
            config = HotkeyConfig(keyCode: key, modifiers: mods, enabled: config.enabled)
            DispatchQueue.main.async { self.recording = false; self.stopMonitor() }
            return nil
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
