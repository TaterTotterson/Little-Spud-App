#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate_play_store_feature_graphic.swift <mascot.png> <output.png>\n", stderr)
    exit(2)
}

let mascotURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let mascot = NSImage(contentsOf: mascotURL) else {
    fputs("Could not load mascot at \(mascotURL.path)\n", stderr)
    exit(1)
}

let width = 1_024
let height = 500
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create output bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let background = NSGradient(
    starting: NSColor(calibratedRed: 0.075, green: 0.078, blue: 0.098, alpha: 1),
    ending: NSColor(calibratedRed: 0.145, green: 0.125, blue: 0.105, alpha: 1)
)!
background.draw(in: canvas, angle: 0)

NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.08, alpha: 0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: -130, y: -150, width: 600, height: 600)).fill()
NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.12, alpha: 0.07).setFill()
NSBezierPath(ovalIn: NSRect(x: 800, y: 270, width: 350, height: 350)).fill()

mascot.draw(
    in: NSRect(x: 25, y: 15, width: 455, height: 455),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 72, weight: .heavy),
    .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 1),
    .kern: -1.5,
]
NSString(string: "Little Spud").draw(
    at: NSPoint(x: 472, y: 292),
    withAttributes: titleAttributes
)

let accent = NSColor(calibratedRed: 1.0, green: 0.59, blue: 0.06, alpha: 1)
accent.setFill()
NSBezierPath(roundedRect: NSRect(x: 476, y: 270, width: 112, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 25, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1),
]
NSString(string: "Your pocket-sized connection to Tater").draw(
    at: NSPoint(x: 476, y: 216),
    withAttributes: subtitleAttributes
)

let pillLabels = ["CHAT", "HOME", "MUSIC"]
let pillWidths: [CGFloat] = [102, 112, 120]
var pillX: CGFloat = 476
for (label, pillWidth) in zip(pillLabels, pillWidths) {
    NSColor(calibratedWhite: 1, alpha: 0.075).setFill()
    NSBezierPath(roundedRect: NSRect(x: pillX, y: 135, width: pillWidth, height: 48), xRadius: 24, yRadius: 24).fill()
    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .bold),
        .foregroundColor: accent,
        .kern: 1.4,
    ]
    let labelSize = NSString(string: label).size(withAttributes: labelAttributes)
    NSString(string: label).draw(
        at: NSPoint(x: pillX + (pillWidth - labelSize.width) / 2, y: 149),
        withAttributes: labelAttributes
    )
    pillX += pillWidth + 14
}

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.63, alpha: 1),
]
NSString(string: "Built for your self-hosted Tater.").draw(
    at: NSPoint(x: 476, y: 84),
    withAttributes: footerAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("Could not write \(outputURL.path): \(error)\n", stderr)
    exit(1)
}
