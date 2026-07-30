import XCTest
import Carbon.HIToolbox
@testable import ChromeProfiles

@MainActor
final class AppSettingsHotkeyTests: XCTestCase {
    func testFailedUpdateKeepsPreviousShortcutAndRestoresItsRegistration() {
        let suiteName = "AppSettingsHotkeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey),
            enabled: true
        )
        let candidate = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: UInt32(shiftKey),
            enabled: true,
            displayCharacter: "~"
        )
        previous.save(to: defaults)
        var attempts: [HotkeyConfig] = []
        var results: [Result<Void, HotkeyRegistrationError>] = [
            .success(()),
            .failure(.registration(-9876)),
            .success(())
        ]
        let settings = AppSettings(
            hotkeyDefaults: defaults,
            hotkeyApply: { config in
                attempts.append(config)
                return results.removeFirst()
            },
            applyThemeOnInit: false
        )
        settings.applyHotkey()

        settings.updateHotkey(candidate)

        XCTAssertEqual(settings.hotkey, previous)
        XCTAssertEqual(settings.activeHotkey, previous)
        XCTAssertEqual(settings.hotkeyRegistrationIssue?.attempted, candidate)
        XCTAssertEqual(settings.hotkeyRegistrationIssue?.previousRestored, true)
        XCTAssertEqual(HotkeyConfig.load(from: defaults), previous)
        XCTAssertEqual(attempts, [previous, candidate, previous])
    }

    func testRetryActivatesShortcutAfterStartupConflictClears() {
        let suiteName = "AppSettingsHotkeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let saved = HotkeyConfig(
            keyCode: UInt32(kVK_ANSI_Grave),
            modifiers: UInt32(shiftKey),
            enabled: true,
            displayCharacter: "~"
        )
        saved.save(to: defaults)
        var attempts: [HotkeyConfig] = []
        var results: [Result<Void, HotkeyRegistrationError>] = [
            .failure(.registration(-9876)),
            .success(())
        ]
        let settings = AppSettings(
            hotkeyDefaults: defaults,
            hotkeyApply: { config in
                attempts.append(config)
                return results.removeFirst()
            },
            applyThemeOnInit: false
        )
        settings.applyHotkey()

        settings.retryHotkeyRegistration()

        XCTAssertEqual(settings.hotkey, saved)
        XCTAssertEqual(settings.activeHotkey, saved)
        XCTAssertNil(settings.hotkeyRegistrationIssue)
        XCTAssertEqual(attempts, [saved, saved])
    }
}
