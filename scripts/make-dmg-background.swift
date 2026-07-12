#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates the Retina DMG backdrop with AppKit so every piece of copy uses
/// the same native San Francisco type system as Finder's icon labels.

let canvas = NSSize(width: 600, height: 420)
let scale = 2
let output = "Bundle/dmg-background.png"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height - y - height, width: width, height: height)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func centeredText(_ text: String, rect: NSRect, font: NSFont, foreground: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph,
        ]
    ).draw(in: rect)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width) * scale,
    pixelsHigh: Int(canvas.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create DMG background canvas")
}

bitmap.size = canvas
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let bounds = NSRect(origin: .zero, size: canvas)

// A quiet macOS-native midnight surface with a subtle violet-blue lift around
// the one interaction that matters.
NSGradient(colors: [color(0x262A3A), color(0x151823)])!.draw(in: bounds, angle: -90)
NSGradient(colors: [color(0x8B6CFF, alpha: 0.13), color(0x48B8FF, alpha: 0.00)])!
    .draw(fromCenter: NSPoint(x: 300, y: 230), radius: 0,
          toCenter: NSPoint(x: 300, y: 230), radius: 330,
          options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])

// Header: one native type family, with hierarchy carried by weight and size.
centeredText(
    "Install Polychrome",
    rect: rectFromTop(x: 70, y: 38, width: 460, height: 30),
    font: .systemFont(ofSize: 23, weight: .semibold),
    foreground: color(0xF6F7FC)
)
centeredText(
    "Drag Polychrome into Applications",
    rect: rectFromTop(x: 70, y: 73, width: 460, height: 22),
    font: .systemFont(ofSize: 13, weight: .regular),
    foreground: color(0xB7BED0)
)

// Cards intentionally include Finder's icon labels instead of stopping at the
// icon edge. This makes the native labels feel anchored rather than floating.
let leftCard = rectFromTop(x: 62, y: 112, width: 176, height: 218)
let rightCard = rectFromTop(x: 362, y: 112, width: 176, height: 218)

for card in [leftCard, rightCard] {
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, alpha: 0.30)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    roundedRect(card, radius: 24, fill: color(0xFFFFFF, alpha: 0.055))
    NSShadow().set()
    roundedRect(card, radius: 24, fill: color(0xFFFFFF, alpha: 0.025), stroke: color(0xFFFFFF, alpha: 0.15), lineWidth: 1)

    // Soft top-edge highlight, like a macOS material catching light.
    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: card.minX + 26, y: card.maxY - 1))
    highlight.line(to: NSPoint(x: card.maxX - 26, y: card.maxY - 1))
    highlight.lineWidth = 1
    color(0xFFFFFF, alpha: 0.13).setStroke()
    highlight.stroke()
}

// Layered arrow echoes the stacked-window Polychrome icon without turning the
// installer into a decorative poster.
func arrowPath(y: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let startX: CGFloat = 270
    let neckX: CGFloat = 322
    let endX: CGFloat = 342
    let half: CGFloat = 4.5
    let head: CGFloat = 14
    path.move(to: NSPoint(x: startX, y: y - half))
    path.line(to: NSPoint(x: neckX, y: y - half))
    path.line(to: NSPoint(x: neckX, y: y - head))
    path.line(to: NSPoint(x: endX, y: y))
    path.line(to: NSPoint(x: neckX, y: y + head))
    path.line(to: NSPoint(x: neckX, y: y + half))
    path.line(to: NSPoint(x: startX, y: y + half))
    path.close()
    return path
}

let arrowY: CGFloat = canvas.height - 210
for (offset, tint, opacity) in [
    (CGFloat(6), UInt32(0xD45CFF), CGFloat(0.18)),
    (CGFloat(3), UInt32(0x6B7CFF), CGFloat(0.30)),
] {
    let path = arrowPath(y: arrowY + offset)
    color(tint, alpha: opacity).setFill()
    path.fill()
}
let arrow = arrowPath(y: arrowY)
NSGradient(colors: [color(0x9C71FF), color(0x45BEFF)])!.draw(in: arrow, angle: 0)

// A compact completion cue uses the same system face and fills the formerly
// empty lower band without competing with the drag target.
let cue = rectFromTop(x: 146, y: 352, width: 308, height: 36)
roundedRect(cue, radius: 18, fill: color(0xFFFFFF, alpha: 0.055), stroke: color(0xFFFFFF, alpha: 0.10), lineWidth: 1)

let checkCenter = NSPoint(x: cue.minX + 22, y: cue.midY)
let checkCircle = NSBezierPath(ovalIn: NSRect(x: checkCenter.x - 8, y: checkCenter.y - 8, width: 16, height: 16))
color(0x5DDC9A, alpha: 0.20).setFill()
checkCircle.fill()
color(0x69E4A4).setStroke()
checkCircle.lineWidth = 1
checkCircle.stroke()
let check = NSBezierPath()
check.move(to: NSPoint(x: checkCenter.x - 4, y: checkCenter.y))
check.line(to: NSPoint(x: checkCenter.x - 1, y: checkCenter.y - 3))
check.line(to: NSPoint(x: checkCenter.x + 5, y: checkCenter.y + 4))
check.lineWidth = 1.7
check.lineCapStyle = .round
check.lineJoinStyle = .round
color(0x8AF0BC).setStroke()
check.stroke()

let cueParagraph = NSMutableParagraphStyle()
cueParagraph.alignment = .left
cueParagraph.lineBreakMode = .byTruncatingTail
NSAttributedString(
    string: "Then open Polychrome from Applications",
    attributes: [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
        .foregroundColor: color(0xCCD2DF),
        .paragraphStyle: cueParagraph,
    ]
).draw(in: NSRect(x: cue.minX + 39, y: cue.minY + 10, width: cue.width - 50, height: 18))

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
    fatalError("Unable to encode DMG background PNG")
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print("wrote \(output): \(Int(canvas.width) * scale)x\(Int(canvas.height) * scale) @2x (\(png.count) bytes)")
