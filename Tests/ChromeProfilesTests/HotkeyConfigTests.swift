import XCTest
import Carbon.HIToolbox
@testable import ChromeProfiles

final class HotkeyConfigTests: XCTestCase {
    func testRecordedShortcutKeepsPhysicalKeyAndTypedCharacter() {
        let config = HotkeyConfig.recorded(
            keyCode: UInt16(kVK_ANSI_Grave),
            modifierFlags: [.shift],
            charactersIgnoringModifiers: "~",
            enabled: true
        )

        XCTAssertEqual(config.keyCode, UInt32(kVK_ANSI_Grave))
        XCTAssertEqual(config.modifiers, UInt32(shiftKey))
        XCTAssertEqual(config.displayCharacter, "~")
        XCTAssertEqual(config.displayString, "~")
    }

    func testLegacyPayloadWithoutDisplayCharacterStillDecodes() throws {
        let json = """
        {
          "keyCode": \(kVK_ANSI_Grave),
          "modifiers": \(shiftKey),
          "enabled": true
        }
        """

        let config = try JSONDecoder().decode(HotkeyConfig.self, from: Data(json.utf8))

        XCTAssertNil(config.displayCharacter)
        XCTAssertEqual(config.displayString, "~")
    }

    func testSaveAndLoadRoundTripUsesProvidedDefaults() {
        let suiteName = "HotkeyConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: UInt32(cmdKey | shiftKey),
            enabled: true,
            displayCharacter: "~"
        )

        expected.save(to: defaults)

        XCTAssertEqual(HotkeyConfig.load(from: defaults), expected)
    }

    func testShiftGraveDisplaysTilde() {
        let config = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: UInt32(shiftKey),
            enabled: true
        )

        XCTAssertEqual(config.displayString, "~")
    }

    func testCapturedCharacterOverridesUSFallback() throws {
        let json = """
        {
          "keyCode": \(kVK_ANSI_2),
          "modifiers": \(shiftKey),
          "enabled": true,
          "displayCharacter": "é"
        }
        """
        let config = try JSONDecoder().decode(HotkeyConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.displayString, "é")
    }

    func testPrivateUseFunctionCharactersFallBackToNamedKeys() {
        let config = HotkeyConfig(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(shiftKey),
            enabled: true,
            displayCharacter: "\u{F702}"
        )

        XCTAssertEqual(config.displayString, "⇧←")
    }

    func testInvalidCapturedCharactersFallBackToKeyMap() {
        for captured in ["", " ", "\t", "ab"] {
            let config = HotkeyConfig(
                keyCode: UInt32(kVK_ANSI_Grave),
                modifiers: UInt32(shiftKey),
                enabled: true,
                displayCharacter: captured
            )
            XCTAssertEqual(config.displayString, "~", "captured value \(captured.debugDescription)")
        }
    }

    func testGlobalChordNeedsCommandOptionOrControl() {
        for mods in [cmdKey, optionKey, controlKey, cmdKey | shiftKey, controlKey | optionKey] {
            XCTAssertTrue(HotkeyConfig.isAllowedGlobalChord(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(mods)),
                          "modifiers \(mods)")
        }
    }

    func testShiftAloneIsRejectedOnKeysThatType() {
        for key in [kVK_ANSI_A, kVK_ANSI_1, kVK_ANSI_Grave, kVK_Space, kVK_LeftArrow, kVK_Return] {
            XCTAssertFalse(HotkeyConfig.isAllowedGlobalChord(keyCode: UInt32(key), modifiers: UInt32(shiftKey)),
                           "key code \(key)")
        }
        XCTAssertFalse(HotkeyConfig.isAllowedGlobalChord(keyCode: UInt32(kVK_ANSI_A), modifiers: 0))
    }

    func testShiftAloneIsAllowedOnFunctionKeys() {
        XCTAssertTrue(HotkeyConfig.isAllowedGlobalChord(keyCode: UInt32(kVK_F5), modifiers: UInt32(shiftKey)))
        XCTAssertFalse(HotkeyConfig.isAllowedGlobalChord(keyCode: UInt32(kVK_F5), modifiers: 0))
    }

    func testLegacyShiftedPunctuationUsesTypedSymbols() {
        let cases: [(Int, String)] = [
            (kVK_ANSI_1, "!"), (kVK_ANSI_2, "@"), (kVK_ANSI_3, "#"),
            (kVK_ANSI_4, "$"), (kVK_ANSI_5, "%"), (kVK_ANSI_6, "^"),
            (kVK_ANSI_7, "&"), (kVK_ANSI_8, "*"), (kVK_ANSI_9, "("),
            (kVK_ANSI_0, ")"), (kVK_ANSI_Minus, "_"), (kVK_ANSI_Equal, "+"),
            (kVK_ANSI_LeftBracket, "{"), (kVK_ANSI_RightBracket, "}"),
            (kVK_ANSI_Backslash, "|"), (kVK_ANSI_Semicolon, ":"),
            (kVK_ANSI_Quote, "\""), (kVK_ANSI_Comma, "<"),
            (kVK_ANSI_Period, ">"), (kVK_ANSI_Slash, "?"),
            (kVK_ANSI_Grave, "~")
        ]

        for (keyCode, expected) in cases {
            let config = HotkeyConfig(
                keyCode: UInt32(keyCode),
                modifiers: UInt32(shiftKey),
                enabled: true
            )
            XCTAssertEqual(config.displayString, expected, "key code \(keyCode)")
        }
    }
}
