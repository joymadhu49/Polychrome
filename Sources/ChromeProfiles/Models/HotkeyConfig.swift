import Foundation
import AppKit
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32          // Carbon virtual key code
    var modifiers: UInt32        // Carbon modifier flags
    var enabled: Bool
    var displayCharacter: String? = nil // Presentation only; registration remains physical.

    static let storageKey = "HotkeyConfig.v1"

    static let defaultConfig = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey),
        enabled: true
    )

    static func recorded(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?,
        enabled: Bool
    ) -> HotkeyConfig {
        HotkeyConfig(
            keyCode: UInt32(keyCode),
            modifiers: carbonModifiers(from: modifierFlags),
            enabled: enabled,
            displayCharacter: normalizedDisplayCharacter(charactersIgnoringModifiers)
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> HotkeyConfig {
        guard let data = defaults.data(forKey: storageKey),
              let cfg = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return defaultConfig
        }
        return cfg
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    var displayString: String {
        let hasShift = modifiers & UInt32(shiftKey) != 0
        let baseName = Self.keyName(for: keyCode)
        let capturedName = Self.normalizedDisplayCharacter(displayCharacter)
        let shiftedName = hasShift ? Self.shiftedKeyName(for: keyCode) : nil
        let keyName = capturedName ?? shiftedName ?? baseName
        let shiftIsRepresented = shiftedName != nil || (capturedName != nil && capturedName != baseName)
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if hasShift && !shiftIsRepresented { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    static func normalizedDisplayCharacter(_ characters: String?) -> String? {
        guard let characters, characters.count == 1 else { return nil }
        let scalars = characters.unicodeScalars
        guard !scalars.contains(where: {
            let value = $0.value
            let isPrivateUse = (0xE000...0xF8FF).contains(value)
                || (0xF0000...0xFFFFD).contains(value)
                || (0x100000...0x10FFFD).contains(value)
            return CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.controlCharacters.contains($0)
                || isPrivateUse
        }) else {
            return nil
        }
        if scalars.count == 1, let scalar = scalars.first, (97...122).contains(scalar.value),
           let uppercase = UnicodeScalar(scalar.value - 32) {
            return String(uppercase)
        }
        return characters
    }

    static func shiftedKeyName(for keyCode: UInt32) -> String? {
        let map: [Int: String] = [
            kVK_ANSI_1:"!", kVK_ANSI_2:"@", kVK_ANSI_3:"#", kVK_ANSI_4:"$", kVK_ANSI_5:"%",
            kVK_ANSI_6:"^", kVK_ANSI_7:"&", kVK_ANSI_8:"*", kVK_ANSI_9:"(", kVK_ANSI_0:")",
            kVK_ANSI_Grave:"~", kVK_ANSI_Minus:"_", kVK_ANSI_Equal:"+",
            kVK_ANSI_LeftBracket:"{", kVK_ANSI_RightBracket:"}", kVK_ANSI_Backslash:"|",
            kVK_ANSI_Semicolon:":", kVK_ANSI_Quote:"\"", kVK_ANSI_Comma:"<",
            kVK_ANSI_Period:">", kVK_ANSI_Slash:"?"
        ]
        return map[Int(keyCode)]
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
            kVK_Delete:"⌫", kVK_ForwardDelete:"⌦",
            kVK_LeftArrow:"←", kVK_RightArrow:"→", kVK_UpArrow:"↑", kVK_DownArrow:"↓",
            kVK_ANSI_Grave:"`", kVK_ANSI_Minus:"-", kVK_ANSI_Equal:"=",
            kVK_ANSI_LeftBracket:"[", kVK_ANSI_RightBracket:"]",
            kVK_ANSI_Semicolon:";", kVK_ANSI_Quote:"'", kVK_ANSI_Backslash:"\\",
            kVK_ANSI_Comma:",", kVK_ANSI_Period:".", kVK_ANSI_Slash:"/",
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
