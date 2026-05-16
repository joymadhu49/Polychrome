import Foundation
import AppKit

struct ChromeProfile: Identifiable, Hashable {
    let id: String          // dirName, stable
    let dirName: String     // "Default", "Profile 1"
    let displayName: String // "name" field
    let email: String?      // "user_name"
    let givenName: String?  // "gaia_given_name"
    let avatarImage: NSImage?

    var initial: String {
        let src = givenName?.isEmpty == false ? givenName! : displayName
        return String(src.prefix(1)).uppercased()
    }
}
