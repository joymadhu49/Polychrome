import XCTest
@testable import ChromeProfiles

/// Pure layout geometry (`WindowTiler.frames(for:in:layout:)` with a CGRect) — the same
/// path the Settings previews draw, with no screen lookups.
final class WindowTilerFramesTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func config(_ layout: TileLayout, pad: CGFloat = 10, split: Double = 0.5) -> LayoutConfig {
        var c = LayoutConfig()
        c.layout = layout
        c.paddingPx = pad
        c.splitPercent = split
        return c
    }

    private func frames(_ n: Int, _ c: LayoutConfig) -> [CGRect] {
        WindowTiler.frames(for: n, in: screen, layout: c)
    }

    func testZeroWindowsProducesNoFrames() {
        XCTAssertTrue(frames(0, config(.grid)).isEmpty)
    }

    func testRowSplitsWidthEvenlyWithGaps() {
        let f = frames(2, config(.row))
        XCTAssertEqual(f, [
            CGRect(x: 10, y: 10, width: 485, height: 580),
            CGRect(x: 505, y: 10, width: 485, height: 580),
        ])
    }

    func testColumnStacksTopToBottom() {
        let f = frames(3, config(.column, pad: 0))
        XCTAssertEqual(f.map(\.minY), [0, 200, 400])
        XCTAssertTrue(f.allSatisfy { $0.width == 1000 && $0.height == 200 })
    }

    func testSmartIsSideBySideUpToThreeThenGrid() {
        XCTAssertEqual(frames(3, config(.smart)), frames(3, config(.row)))
        XCTAssertEqual(frames(4, config(.smart)), frames(4, config(.grid)))
    }

    func testGridIsSquareIsh() {
        let f = frames(5, config(.grid, pad: 0))   // 3 columns × 2 rows
        XCTAssertEqual(f.count, 5)
        XCTAssertEqual(Set(f.map(\.minX)).count, 3)
        XCTAssertEqual(Set(f.map(\.minY)).count, 2)
    }

    func testSplitHGivesFirstWindowTheLeftPaneAndStacksTheRest() {
        let f = frames(3, config(.splitH, pad: 0, split: 0.6))
        XCTAssertEqual(f[0], CGRect(x: 0, y: 0, width: 600, height: 600))
        XCTAssertEqual(f[1], CGRect(x: 600, y: 0, width: 400, height: 300))
        XCTAssertEqual(f[2], CGRect(x: 600, y: 300, width: 400, height: 300))
    }

    func testSplitVGivesFirstWindowTheTopPaneAndRowsTheRest() {
        let f = frames(3, config(.splitV, pad: 0, split: 0.5))
        XCTAssertEqual(f[0], CGRect(x: 0, y: 0, width: 1000, height: 300))
        XCTAssertEqual(f[1], CGRect(x: 0, y: 300, width: 500, height: 300))
        XCTAssertEqual(f[2], CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    func testFramesStayInsideTheScreen() {
        for layout in TileLayout.allCases {
            for n in 1...7 {
                for r in frames(n, config(layout)) {
                    XCTAssertTrue(screen.contains(r), "\(layout) n=\(n): \(r) escapes the screen")
                }
            }
        }
    }
}
