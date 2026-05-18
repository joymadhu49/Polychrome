import Foundation
import AppKit
import ApplicationServices

enum WindowTiler {
    // MARK: AX helpers

    static func setFrame(_ window: AXUIElement, frame: CGRect) {
        var pos = frame.origin
        var size = frame.size
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: layout math

    static func frames(for count: Int, in screen: DisplayInfo, layout: LayoutConfig) -> [CGRect] {
        guard count > 0 else { return [] }
        let pad = layout.paddingPx
        let area = layout.avoidMenubar ? screen.visibleFrame : screen.frame
        // AX uses top-left origin in global coords with Y growing down? Actually AX uses screen coords with origin
        // at top-left of primary display. NSScreen.frame uses bottom-left origin.
        // Convert NSScreen rect to AX rect:
        let axOriginY = primaryFlipped(rect: area).origin.y
        let baseRect = CGRect(x: area.origin.x, y: axOriginY, width: area.width, height: area.height)

        let strategy: TileLayout = {
            switch layout.layout {
            case .smart:
                if count == 1 { return .row }
                if count == 2 { return .splitV } // side-by-side
                if count <= 3 { return .row }
                return .grid
            default: return layout.layout
            }
        }()

        switch strategy {
        case .row:
            return splitEvenly(rect: baseRect, axis: .horizontal, n: count, pad: pad)
        case .column:
            return splitEvenly(rect: baseRect, axis: .vertical, n: count, pad: pad)
        case .grid:
            return gridFrames(rect: baseRect, n: count, pad: pad)
        case .splitH:
            return splitHFrames(rect: baseRect, n: count, pad: pad, leftPercent: CGFloat(layout.splitPercent))
        case .splitV:
            if count == 1 { return [baseRect.insetBy(dx: pad, dy: pad)] }
            let n = count
            let totalPad = pad * CGFloat(n + 1)
            let w = (baseRect.width - totalPad) / CGFloat(n)
            let h = baseRect.height - pad * 2
            return (0..<n).map { i in
                CGRect(x: baseRect.minX + pad + (w + pad) * CGFloat(i),
                       y: baseRect.minY + pad,
                       width: w,
                       height: h)
            }
        case .smart:
            return [] // already handled
        }
    }

    private enum Axis { case horizontal, vertical }

    private static func splitHFrames(rect: CGRect, n: Int, pad: CGFloat, leftPercent: CGFloat) -> [CGRect] {
        if n == 1 { return [rect.insetBy(dx: pad, dy: pad)] }
        let usable = rect.width - pad * 3
        let leftW = usable * leftPercent
        let rightW = usable - leftW
        let h = rect.height - pad * 2
        let leftRect = CGRect(x: rect.minX + pad, y: rect.minY + pad, width: leftW, height: h)
        let rightRect = CGRect(x: leftRect.maxX + pad, y: rect.minY + pad, width: rightW, height: h)
        var out: [CGRect] = [leftRect, rightRect]
        if n > 2 {
            out.append(contentsOf: Array(repeating: rightRect, count: n - 2))
        }
        return out
    }

    private static func splitEvenly(rect: CGRect, axis: Axis, n: Int, pad: CGFloat) -> [CGRect] {
        guard n > 0 else { return [] }
        switch axis {
        case .vertical:
            let totalPad = pad * CGFloat(n + 1)
            let h = (rect.height - totalPad) / CGFloat(n)
            let w = rect.width - pad * 2
            return (0..<n).map { i in
                CGRect(x: rect.minX + pad,
                       y: rect.minY + pad + (h + pad) * CGFloat(i),
                       width: w,
                       height: h)
            }
        case .horizontal:
            let totalPad = pad * CGFloat(n + 1)
            let w = (rect.width - totalPad) / CGFloat(n)
            let h = rect.height - pad * 2
            return (0..<n).map { i in
                CGRect(x: rect.minX + pad + (w + pad) * CGFloat(i),
                       y: rect.minY + pad,
                       width: w,
                       height: h)
            }
        }
    }

    private static func gridFrames(rect: CGRect, n: Int, pad: CGFloat) -> [CGRect] {
        let cols = Int(ceil(sqrt(Double(n))))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let cellW = (rect.width - pad * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (rect.height - pad * CGFloat(rows + 1)) / CGFloat(rows)
        var out: [CGRect] = []
        for i in 0..<n {
            let r = i / cols
            let c = i % cols
            out.append(CGRect(
                x: rect.minX + pad + (cellW + pad) * CGFloat(c),
                y: rect.minY + pad + (cellH + pad) * CGFloat(r),
                width: cellW,
                height: cellH
            ))
        }
        return out
    }

    /// Convert an NSScreen-based rect (bottom-left origin, primary screen as anchor)
    /// to AX coords (top-left origin of primary screen).
    private static func primaryFlipped(rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.height - rect.maxY
        return CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
    }

    // MARK: launch-and-tile orchestration

    /// Reuse existing Chrome windows where possible; parallel-launch missing ones; then tile.
    /// If `url` provided, opens that URL in each profile (new tab in existing window, or new window if none).
    @MainActor
    static func launchAndTile(profiles: [ChromeProfile], config: LayoutConfig, url: String? = nil) async {
        guard !profiles.isEmpty else { return }

        var resolved: [String: AXUIElement] = WindowFinder.allWindowsMappedToProfiles(profiles)
        let needLaunch = profiles.filter { resolved[$0.id] == nil }

        NSLog("[Polychrome] tile: \(resolved.count) existing, \(needLaunch.count) to launch (url=\(url ?? "-"))")

        // For URL mode: also send URL to profiles with existing windows (opens new tab)
        if let url, !url.isEmpty {
            for p in profiles where resolved[p.id] != nil {
                ChromeLauncher.launch(profile: p, url: url)
            }
        }

        // Parallel launch missing (with URL if given)
        for p in needLaunch {
            ChromeLauncher.launch(profile: p, url: url)
        }

        if !needLaunch.isEmpty {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let map = WindowFinder.allWindowsMappedToProfiles(profiles)
                for (k, v) in map where resolved[k] == nil {
                    resolved[k] = v
                }
                if resolved.count >= profiles.count { break }
            }
        } else if url != nil {
            // Give Chrome a beat to open the new tab so the window settles before we move it
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let ordered: [AXUIElement] = profiles.compactMap { resolved[$0.id] }
        guard !ordered.isEmpty else { return }

        let screen = DisplayService.screen(for: config.displayID)
        let frames = WindowTiler.frames(for: ordered.count, in: screen, layout: config)

        for (idx, win) in ordered.enumerated() where idx < frames.count {
            setFrame(win, frame: frames[idx])
            raise(win)
        }
    }
}
