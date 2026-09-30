#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates the Retina DMG backdrop (Bundle/dmg-background.png) with AppKit, so every
/// piece of copy uses the same San Francisco type as Finder's own icon labels.
///
///     swift scripts/make-dmg-background.swift
///
/// Two Finder constraints shape this design:
///  • Finder draws icon labels over a background picture in dark text, whatever the
///    system appearance. A dark backdrop makes "Polychrome" and "Applications"
///    unreadable, so the canvas is light.
///  • Finder may lay its path bar (a per-user preference) over the bottom ~28 pt of the
///    window. Nothing that matters sits in the bottom `safeBottom` points.
///
/// Geometry must match scripts/make-dmg.sh: 640×400 content, icons centred at
/// (180, 200) and (460, 200), 112 pt icons.

let canvas = NSSize(width: 640, height: 400)
let scale = 2
let output = "Bundle/dmg-background.png"
let safeBottom: CGFloat = 44

let appCenter = NSPoint(x: 180, y: 200)       // from the top, like Finder
let appsCenter = NSPoint(x: 460, y: 200)
let iconSize: CGFloat = 112

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

/// AppKit draws bottom-up; the layout above is specified top-down like Finder's.
func fromTop(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x, y: canvas.height - p.y) }

func text(_ string: String, centerX: CGFloat, top: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let s = NSAttributedString(string: string, attributes: attrs)
    let size = s.size()
    s.draw(at: NSPoint(x: (centerX - size.width / 2).rounded(), y: canvas.height - top - size.height))
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width) * scale, pixelsHigh: Int(canvas.height) * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create DMG background canvas")
}
bitmap.size = canvas   // 2× pixels in 1× points → Finder shows it sharp on Retina

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
let bounds = NSRect(origin: .zero, size: canvas)

// Surface: warm paper white, with a faint dot grid — a quiet "canvas" texture that
// reads as intentional without competing with the two icons.
color(0xF6F6F3).setFill()
bounds.fill()

let dot = color(0x1C1C1A, alpha: 0.075)
dot.setFill()
let step: CGFloat = 16
var gy: CGFloat = step / 2
while gy < canvas.height {
    var gx: CGFloat = step / 2
    while gx < canvas.width {
        NSBezierPath(ovalIn: NSRect(x: gx - 0.6, y: gy - 0.6, width: 1.2, height: 1.2)).fill()
        gx += step
    }
    gy += step
}

// Clear the grid softly behind each icon + label, so they sit on clean paper.
for c in [appCenter, appsCenter] {
    let p = fromTop(NSPoint(x: c.x, y: c.y + 12))
    NSGradient(colors: [color(0xF6F6F3), color(0xF6F6F3, alpha: 0)])!
        .draw(fromCenter: p, radius: 0, toCenter: p, radius: 104,
              options: [.drawsBeforeStartingLocation])
}

// Header.
text("Install Polychrome", centerX: canvas.width / 2, top: 40,
     font: .systemFont(ofSize: 22, weight: .semibold), color: color(0x161615), kern: -0.2)
text("Drag the app onto your Applications folder.", centerX: canvas.width / 2, top: 72,
     font: .systemFont(ofSize: 13, weight: .regular), color: color(0x6E6E69))

// The drag: one dashed arc from app to folder, the gesture itself.
let start = fromTop(NSPoint(x: appCenter.x + iconSize / 2 + 18, y: appCenter.y - 6))
let end = fromTop(NSPoint(x: appsCenter.x - iconSize / 2 - 22, y: appCenter.y - 6))
let control = fromTop(NSPoint(x: canvas.width / 2, y: appCenter.y - 44))
let cp1 = NSPoint(x: (start.x + control.x) / 2, y: control.y)
let cp2 = NSPoint(x: (end.x + control.x) / 2, y: control.y)
let arc = NSBezierPath()
arc.move(to: start)
arc.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
arc.lineWidth = 1.5
arc.lineCapStyle = .round
arc.setLineDash([0.01, 6], count: 2, phase: 0)   // round-capped dots
color(0x161615, alpha: 0.6).setStroke()
arc.stroke()

// Arrowhead aligned with the curve's final tangent (a cubic ends heading cp2 → end).
let tangent = atan2(end.y - cp2.y, end.x - cp2.x)
let head = NSBezierPath()
let len: CGFloat = 8, spread: CGFloat = .pi / 5.5
head.move(to: NSPoint(x: end.x - len * cos(tangent - spread), y: end.y - len * sin(tangent - spread)))
head.line(to: end)
head.line(to: NSPoint(x: end.x - len * cos(tangent + spread), y: end.y - len * sin(tangent + spread)))
head.lineWidth = 1.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
color(0x161615, alpha: 0.7).setStroke()
head.stroke()

// What happens next — the one thing people get wrong with a menu bar app.
let footerTop = canvas.height - safeBottom - 30
text("Then open Polychrome from Applications. It lives in your menu bar.",
     centerX: canvas.width / 2, top: footerTop,
     font: .systemFont(ofSize: 12, weight: .regular), color: color(0x8A8A84))

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output) (\(Int(canvas.width))×\(Int(canvas.height)) pt @\(scale)x)")
