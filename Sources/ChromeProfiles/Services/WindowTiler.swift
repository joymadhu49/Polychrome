import Foundation
import AppKit
import ApplicationServices

enum WindowTiler {
    // MARK: AX helpers

    /// Size, move, then size again: macOS clamps a window to the display it's on, so moving a
    /// large window onto a smaller display (or a small one onto a larger) needs the second pass
    /// to land at exactly `frame`. The window must not be minimized — see `restoreIfMinimized`.
    static func setFrame(_ window: AXUIElement, frame: CGRect) {
        var pos = frame.origin
        var size = frame.size
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
    }

    /// A minimized window ignores moves and resizes, and restoring it afterwards would put it
    /// back at its old frame. Returns true when the window was minimized and is now restoring.
    static func restoreIfMinimized(_ window: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &raw) == .success,
              (raw as? Bool) == true else { return false }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        return true
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: layout math

    static func frames(for count: Int, in screen: DisplayInfo, layout: LayoutConfig) -> [CGRect] {
        let area = layout.avoidMenubar ? screen.visibleFrame : screen.frame
        // AX uses global coords with the origin at the top-left of the primary display, Y growing
        // down; NSScreen uses a bottom-left origin. Convert before laying out.
        return frames(for: count, in: primaryFlipped(rect: area), layout: layout)
    }

    /// Pure layout geometry inside `baseRect`, which is already in top-left-origin coordinates.
    /// No screen lookups — the Settings previews and the unit tests call this directly.
    static func frames(for count: Int, in baseRect: CGRect, layout: LayoutConfig) -> [CGRect] {
        guard count > 0 else { return [] }
        let pad = layout.paddingPx

        let strategy: TileLayout = {
            switch layout.layout {
            case .smart:
                if count <= 3 { return .row } // 1–3 windows: even side-by-side columns
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
            return splitVFrames(rect: baseRect, n: count, pad: pad, topPercent: CGFloat(layout.splitPercent))
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
        let rightX = leftRect.maxX + pad
        if n == 2 {
            return [leftRect, CGRect(x: rightX, y: rect.minY + pad, width: rightW, height: h)]
        }
        // 3+ windows: window 0 takes the left pane; stack the remaining n-1 down the right column
        // instead of piling them all on the same frame.
        let rightCount = n - 1
        let cellH = (h - pad * CGFloat(rightCount - 1)) / CGFloat(rightCount)
        var out: [CGRect] = [leftRect]
        for i in 0..<rightCount {
            out.append(CGRect(x: rightX,
                              y: rect.minY + pad + (cellH + pad) * CGFloat(i),
                              width: rightW,
                              height: cellH))
        }
        return out
    }

    /// Top/bottom counterpart of `splitHFrames` — `rect` is in AX coords (top-left origin),
    /// so minY is the top edge. Window 0 takes the top pane sized by `topPercent`; the
    /// remaining n-1 share the bottom pane as an even row.
    private static func splitVFrames(rect: CGRect, n: Int, pad: CGFloat, topPercent: CGFloat) -> [CGRect] {
        if n == 1 { return [rect.insetBy(dx: pad, dy: pad)] }
        let usable = rect.height - pad * 3
        let topH = usable * topPercent
        let bottomH = usable - topH
        let w = rect.width - pad * 2
        let topRect = CGRect(x: rect.minX + pad, y: rect.minY + pad, width: w, height: topH)
        let bottomY = topRect.maxY + pad
        if n == 2 {
            return [topRect, CGRect(x: rect.minX + pad, y: bottomY, width: w, height: bottomH)]
        }
        let bottomCount = n - 1
        let cellW = (w - pad * CGFloat(bottomCount - 1)) / CGFloat(bottomCount)
        var out: [CGRect] = [topRect]
        for i in 0..<bottomCount {
            out.append(CGRect(x: rect.minX + pad + (cellW + pad) * CGFloat(i),
                              y: bottomY,
                              width: cellW,
                              height: bottomH))
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
        // The primary display is the one anchored at the global origin (it carries the menu bar),
        // which is not guaranteed to be NSScreen.screens.first. Anchor the flip to its top edge so
        // rects on secondary displays convert correctly on multi-monitor setups.
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return rect }
        let flippedY = primary.frame.maxY - rect.maxY
        return CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
    }

    // MARK: launch-and-tile orchestration

    /// How long to wait for launched profiles' windows. A cold browser start routinely takes
    /// several seconds; the wait ends as soon as every window has been found.
    static let launchTimeout: TimeInterval = 10

    /// Reuse existing windows where possible, launch the missing profiles in parallel, then tile
    /// in `profiles` order. `all` is every known profile: windows are attributed against all of
    /// them, so a window whose title names an unselected profile never stands in for a selected one.
    @MainActor
    static func launchAndTile(profiles: [ChromeProfile], among all: [ChromeProfile], config: LayoutConfig) async {
        guard !profiles.isEmpty else { return }
        var known = all
        for p in profiles where !known.contains(where: { $0.id == p.id }) { known.append(p) }
        let everyone = known

        // AX enumeration and lsof are synchronous IPC — keep them off the main thread.
        let initial = await Task.detached(priority: .userInitiated) {
            WindowFinder.snapshot(everyone).scan
        }.value
        var resolved: [String: AXUIElement] = [:]
        for p in profiles {
            if let w = initial.windowsByProfileID[p.id]?.first { resolved[p.id] = w.element }
        }
        let needLaunch = profiles.filter { resolved[$0.id] == nil }
        NSLog("[Polychrome] tile: \(resolved.count) existing, \(needLaunch.count) to launch")

        for p in needLaunch { ChromeLauncher.launch(profile: p) }

        if !needLaunch.isEmpty {
            // Every window that existed before launching, so the new ones can be told apart.
            let preexisting = (initial.windowsByProfileID.values.flatMap { $0 }
                               + initial.unattributed.values.flatMap { $0 }).map(\.element)
            let deadline = Date().addingTimeInterval(launchTimeout)
            while resolved.count < profiles.count, Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let scan = await Task.detached(priority: .userInitiated) {
                    WindowFinder.scanWindows(everyone)
                }.value
                for p in needLaunch where resolved[p.id] == nil {
                    if let w = scan.windowsByProfileID[p.id]?.first { resolved[p.id] = w.element }
                }
                pairNewWindows(in: scan, launched: needLaunch, preexisting: preexisting, resolved: &resolved)
            }
            let missing = profiles.filter { resolved[$0.id] == nil }.map(\.id)
            if !missing.isEmpty {
                NSLog("[Polychrome] tile: no window found for \(missing) within \(Int(launchTimeout)) s")
            }
        }

        let ordered: [AXUIElement] = profiles.compactMap { resolved[$0.id] }
        guard !ordered.isEmpty else { return }

        let screen = DisplayService.screen(for: config.displayID)
        let placements = Array(zip(ordered, frames(for: ordered.count, in: screen, layout: config)))

        let restoring = await Task.detached(priority: .userInitiated) { () -> Bool in
            var any = false
            for (win, _) in placements where restoreIfMinimized(win) { any = true }
            return any
        }.value
        // Let the un-minimize animation finish; it would otherwise land on the old frame after ours.
        if restoring { try? await Task.sleep(nanoseconds: 450_000_000) }

        await Task.detached(priority: .userInitiated) {
            for (win, frame) in placements {
                setFrame(win, frame: frame)
                raise(win)
            }
        }.value
    }

    /// Title-opaque browsers (e.g. Brave with several profiles) never name their windows, but a
    /// window that appeared after launching can only belong to a launched profile. Pair them once
    /// every launch in that browser has surfaced — all the right windows get tiled, though with
    /// several launches in one such browser, which window takes which slot can't be known.
    private static func pairNewWindows(in scan: WindowFinder.WindowScan, launched: [ChromeProfile],
                                       preexisting: [AXUIElement], resolved: inout [String: AXUIElement]) {
        for browser in Set(launched.map(\.browser)) where scan.isTitleOpaque(browser) {
            let waiting = launched.filter { $0.browser == browser && resolved[$0.id] == nil }
            let taken = Array(resolved.values)
            let fresh = (scan.unattributed[browser] ?? []).map(\.element).filter { w in
                !preexisting.contains { CFEqual($0, w) } && !taken.contains { CFEqual($0, w) }
            }
            guard !waiting.isEmpty, fresh.count >= waiting.count else { continue }
            for (p, w) in zip(waiting, fresh) { resolved[p.id] = w }
        }
    }
}
