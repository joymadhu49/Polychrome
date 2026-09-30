import XCTest
import ApplicationServices
@testable import ChromeProfiles

final class WindowAttributionTests: XCTestCase {
    private func profile(_ dir: String, name: String, given: String? = nil, browser: Browser = .chrome) -> ChromeProfile {
        ChromeProfile(browser: browser, dirName: dir, displayName: name, email: nil, givenName: given, avatarImage: nil)
    }

    // MARK: title tokens

    func testTokenUsesLastMarkerSoPageTitlesCantFoolIt() {
        let title = "Why - Google Chrome - is great - Google Chrome - Joy"
        XCTAssertEqual(WindowFinder.profileToken(from: title, appLabel: "Google Chrome"), "Joy")
    }

    func testTokenToleratesDashVariantsAndIsNilWithoutMarker() {
        XCTAssertEqual(WindowFinder.profileToken(from: "Inbox — Google Chrome — Joy", appLabel: "Google Chrome"), "Joy")
        XCTAssertEqual(WindowFinder.profileToken(from: "Inbox – Google Chrome – Joy", appLabel: "Google Chrome"), "Joy")
        XCTAssertNil(WindowFinder.profileToken(from: "GitHub - Brave", appLabel: "Brave"))
        XCTAssertNil(WindowFinder.profileToken(from: "DevTools - example.com", appLabel: "Google Chrome"))
    }

    func testParentheticalNamesListEverySplitLongestFirst() {
        XCTAssertEqual(WindowFinder.parentheticalNames(in: "Joy (JOY_M)"), ["JOY_M"])
        XCTAssertEqual(WindowFinder.parentheticalNames(in: "Joy (Joy (Work))"), ["Joy (Work)", "Work)"])
        XCTAssertEqual(WindowFinder.parentheticalNames(in: "Joy"), [])
        XCTAssertEqual(WindowFinder.parentheticalNames(in: "Joy ()"), [])
    }

    // MARK: matching

    func testParentheticalPicksTheRightProfileAmongSharedGivenNames() {
        let work = profile("Profile 1", name: "JOY_M", given: "Joy")
        let personal = profile("Profile 2", name: "Personal", given: "Joy")
        let a = WindowFinder.attribute(
            titles: ["Inbox - Google Chrome - Joy (Personal)", "Docs - Google Chrome - Joy (JOY_M)"],
            browser: .chrome, profiles: [work, personal])
        XCTAssertEqual(a.indicesByProfileID[personal.id], [0])
        XCTAssertEqual(a.indicesByProfileID[work.id], [1])
        XCTAssertEqual(a.unattributed, [])
        XCTAssertEqual(a.tokenWindowCount, 2)
    }

    func testBareTokenMatchesTheProfileName() {
        let p = profile("Default", name: "Sumaiya", given: "Sumaiya")
        let other = profile("Profile 1", name: "Work")
        let a = WindowFinder.attribute(titles: ["News - Google Chrome - Sumaiya"], browser: .chrome, profiles: [p, other])
        XCTAssertEqual(a.indicesByProfileID, [p.id: [0]])
    }

    func testProfileNamesContainingParenthesesAreNotSplit() {
        let old = profile("Profile 1", name: "Work (old)")
        let nested = profile("Profile 2", name: "Joy (Work)", given: "Joy")
        let decoy = profile("Profile 3", name: "old")
        let a = WindowFinder.attribute(
            titles: ["A - Google Chrome - Work (old)", "B - Google Chrome - Joy (Joy (Work))"],
            browser: .chrome, profiles: [old, nested, decoy])
        XCTAssertEqual(a.indicesByProfileID[old.id], [0])
        XCTAssertEqual(a.indicesByProfileID[nested.id], [1])
        XCTAssertNil(a.indicesByProfileID[decoy.id])
    }

    func testBareGivenNameMatchesOnlyWhenUnambiguous() {
        let one = profile("Profile 1", name: "Work", given: "Joy")
        let unique = WindowFinder.attribute(titles: ["X - Google Chrome - Joy"], browser: .chrome,
                                            profiles: [one, profile("Profile 2", name: "Home", given: "Sam")])
        XCTAssertEqual(unique.indicesByProfileID[one.id], [0])

        let ambiguous = WindowFinder.attribute(titles: ["X - Google Chrome - Joy"], browser: .chrome,
                                               profiles: [one, profile("Profile 2", name: "Home", given: "Joy")])
        XCTAssertEqual(ambiguous.indicesByProfileID, [:])
        XCTAssertEqual(ambiguous.unattributed, [0])
    }

    // MARK: windows that must not be handed to a closed profile

    /// Tiling A + B while unselected C has a window must not tile C's window as B's.
    func testWindowNamingAnotherProfileIsNeverGivenToAClosedOne() {
        let a = profile("Default", name: "Alice")
        let b = profile("Profile 1", name: "Bob")
        let result = WindowFinder.attribute(
            titles: ["Mail - Google Chrome - Alice", "Docs - Google Chrome - Carol"],
            browser: .chrome, profiles: [a, b])
        XCTAssertEqual(result.indicesByProfileID, [a.id: [0]])
        XCTAssertEqual(result.unattributed, [1])
        XCTAssertEqual(result.tokenWindowCount, 2)
    }

    /// DevTools, incognito and app windows carry no profile marker in a multi-profile browser.
    func testUntokenedWindowInTitleTransparentBrowserStaysUnattributed() {
        let a = profile("Default", name: "Alice")
        let b = profile("Profile 1", name: "Bob")
        let result = WindowFinder.attribute(
            titles: ["Mail - Google Chrome - Alice", "DevTools - example.com"],
            browser: .chrome, profiles: [a, b])
        XCTAssertEqual(result.indicesByProfileID, [a.id: [0]])
        XCTAssertEqual(result.unattributed, [1])
    }

    // MARK: title-opaque browsers

    func testSingleProfileOpaqueBrowserOwnsEveryWindow() {
        let only = profile("Default", name: "Me", browser: .brave)
        let result = WindowFinder.attribute(titles: ["GitHub - Brave", "News - Brave", "Docs - Brave"],
                                            browser: .brave, profiles: [only])
        XCTAssertEqual(result.indicesByProfileID, [only.id: [0, 1, 2]])
        XCTAssertEqual(result.tokenWindowCount, 0)
    }

    func testMultiProfileOpaqueBrowserCantAttributeFromTitles() {
        let a = profile("Default", name: "Me", browser: .brave)
        let b = profile("Profile 1", name: "Work", browser: .brave)
        let result = WindowFinder.attribute(titles: ["GitHub - Brave"], browser: .brave, profiles: [a, b])
        XCTAssertEqual(result.indicesByProfileID, [:])
        XCTAssertEqual(result.unattributed, [0])
    }

    func testOtherBrowsersProfilesAreIgnored() {
        let chrome = profile("Default", name: "Me")
        let brave = profile("Default", name: "Me", browser: .brave)
        let result = WindowFinder.attribute(titles: ["GitHub - Brave"], browser: .brave, profiles: [chrome, brave])
        XCTAssertEqual(result.indicesByProfileID, [brave.id: [0]])
    }

    // MARK: lsof fallback

    private func loneWindowScan(_ browser: Browser, tokens: Int = 0) -> WindowFinder.WindowScan {
        var scan = WindowFinder.WindowScan()
        let element = AXUIElementCreateApplication(getpid())
        scan.unattributed[browser] = [WindowFinder.ProfileWindow(element: element, title: "GitHub")]
        scan.windowCount[browser] = 1
        scan.tokenWindowCount[browser] = tokens
        return scan
    }

    func testLoneWindowGoesToTheOnlyLiveProfile() {
        let a = profile("Default", name: "Me", browser: .brave)
        let b = profile("Profile 1", name: "Work", browser: .brave)
        var scan = loneWindowScan(.brave)
        scan.applyActivity(["Profile 1"], browser: .brave, profiles: [a, b])
        XCTAssertEqual(scan.windowsByProfileID[b.id]?.count, 1)
        XCTAssertNil(scan.windowsByProfileID[a.id])
        XCTAssertNil(scan.unattributed[.brave])
    }

    /// A closed profile whose files Chrome still holds open must not claim a live sibling's window.
    func testLoneWindowIsNobodysWhenSeveralProfilesLookLive() {
        let a = profile("Default", name: "Me", browser: .brave)
        let b = profile("Profile 1", name: "Work", browser: .brave)
        var scan = loneWindowScan(.brave)
        scan.applyActivity(["Default", "Profile 1"], browser: .brave, profiles: [a, b])
        XCTAssertTrue(scan.windowsByProfileID.isEmpty)
        XCTAssertEqual(scan.unattributed[.brave]?.count, 1)
    }

    func testLsofNeverOverridesTitleTransparentBrowsers() {
        let a = profile("Default", name: "Alice")
        let b = profile("Profile 1", name: "Bob")
        var scan = loneWindowScan(.chrome, tokens: 1)
        scan.applyActivity(["Profile 1"], browser: .chrome, profiles: [a, b])
        XCTAssertTrue(scan.windowsByProfileID.isEmpty)
    }
}
