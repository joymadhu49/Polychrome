import Foundation
import AppKit

struct ChromeProfile: Identifiable, Hashable {
    let browser: Browser
    let dirName: String     // "Default", "Profile 1"
    let displayName: String // "name" field
    let email: String?      // "user_name"
    let givenName: String?  // "gaia_given_name"
    let avatarImage: NSImage?

    /// Globally-unique across browsers: `chrome:Default`, `brave:Profile 1`.
    var id: String { "\(browser.rawValue):\(dirName)" }

    var initial: String {
        let src = givenName?.isEmpty == false ? givenName! : displayName
        return String(src.prefix(1)).uppercased()
    }
}
