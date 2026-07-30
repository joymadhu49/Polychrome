import Foundation
import Carbon.HIToolbox
import AppKit

enum HotkeyRegistrationError: Error, Equatable {
    case handlerInstallation(OSStatus)
    case registration(OSStatus)

    var message: String {
        switch self {
        case .handlerInstallation(let status):
            return "Polychrome couldn't prepare the global hotkey (OSStatus \(status))."
        case .registration(let status) where status == eventHotKeyExistsErr:
            return "This shortcut is already used by macOS or another app."
        case .registration(let status):
            return "Polychrome couldn't register this shortcut (OSStatus \(status))."
        }
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onFire: (() -> Void)?

    @discardableResult
    func apply(_ cfg: HotkeyConfig) -> Result<Void, HotkeyRegistrationError> {
        unregister()
        guard cfg.enabled else { return .success(()) }

        let hkID = EventHotKeyID(signature: OSType(0x43504846 /* "CPHF" */), id: 1)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onFire?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else {
            NSLog("[Polychrome] HotkeyManager: InstallEventHandler failed (OSStatus \(handlerStatus))")
            unregister()
            return .failure(.handlerInstallation(handlerStatus))
        }

        let regStatus = RegisterEventHotKey(cfg.keyCode, cfg.modifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else {
            NSLog("[Polychrome] HotkeyManager: RegisterEventHotKey failed (OSStatus \(regStatus)) — the shortcut may already be claimed by another app")
            unregister()
            return .failure(.registration(regStatus))
        }
        return .success(())
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
