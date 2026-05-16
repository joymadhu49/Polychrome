import Foundation
import AppKit
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32          // Carbon virtual key code
    var modifiers: UInt32        // Carbon modifier flags
    var enabled: Bool

    static let storageKey = "HotkeyConfig.v1"

    static let defaultConfig = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey),
        enabled: true
    )

    static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cfg = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return defaultConfig
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A:"A", kVK_ANSI_B:"B", kVK_ANSI_C:"C", kVK_ANSI_D:"D", kVK_ANSI_E:"E",
            kVK_ANSI_F:"F", kVK_ANSI_G:"G", kVK_ANSI_H:"H", kVK_ANSI_I:"I", kVK_ANSI_J:"J",
            kVK_ANSI_K:"K", kVK_ANSI_L:"L", kVK_ANSI_M:"M", kVK_ANSI_N:"N", kVK_ANSI_O:"O",
            kVK_ANSI_P:"P", kVK_ANSI_Q:"Q", kVK_ANSI_R:"R", kVK_ANSI_S:"S", kVK_ANSI_T:"T",
            kVK_ANSI_U:"U", kVK_ANSI_V:"V", kVK_ANSI_W:"W", kVK_ANSI_X:"X", kVK_ANSI_Y:"Y",
            kVK_ANSI_Z:"Z",
            kVK_ANSI_0:"0", kVK_ANSI_1:"1", kVK_ANSI_2:"2", kVK_ANSI_3:"3", kVK_ANSI_4:"4",
            kVK_ANSI_5:"5", kVK_ANSI_6:"6", kVK_ANSI_7:"7", kVK_ANSI_8:"8", kVK_ANSI_9:"9",
            kVK_Space:"Space", kVK_Return:"↩", kVK_Tab:"⇥", kVK_Escape:"⎋",
            kVK_F1:"F1", kVK_F2:"F2", kVK_F3:"F3", kVK_F4:"F4", kVK_F5:"F5",
            kVK_F6:"F6", kVK_F7:"F7", kVK_F8:"F8", kVK_F9:"F9", kVK_F10:"F10",
            kVK_F11:"F11", kVK_F12:"F12"
        ]
        return map[Int(keyCode)] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if nsFlags.contains(.command)  { mods |= UInt32(cmdKey) }
        if nsFlags.contains(.shift)    { mods |= UInt32(shiftKey) }
        if nsFlags.contains(.option)   { mods |= UInt32(optionKey) }
        if nsFlags.contains(.control)  { mods |= UInt32(controlKey) }
        return mods
    }
}
