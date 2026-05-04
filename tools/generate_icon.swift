#!/usr/bin/env swift
// Generates the app icon at 1024x1024.
// Usage: swift tools/generate_icon.swift <output.png>

import Cocoa

let size = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    print("Failed to create bitmap")
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let ctx = NSGraphicsContext.current!.cgContext

let s = CGFloat(size)
let rect = CGRect(x: 0, y: 0, width: s, height: s)

// macOS Big Sur+ icon corner radius (squircle approximation): ~22.4% of size
let radius = s * 0.224
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// Background gradient: indigo -> pink (matches in-app accent)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    CGColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0), // indigo-600 #4f46e5
    CGColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1.0), // pink-500   #ec4899
] as CFArray
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s, y: 0),
    options: []
)

// Soft top-left highlight for depth
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
let highlight = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: s * 0.28, y: s * 0.78),
    startRadius: 0,
    endCenter: CGPoint(x: s * 0.28, y: s * 0.78),
    endRadius: s * 0.65,
    options: []
)

// Subtle bottom-right shadow for depth
let shadowColors = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.18),
    CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
] as CFArray
let shadowGrad = CGGradient(colorsSpace: colorSpace, colors: shadowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    shadowGrad,
    startCenter: CGPoint(x: s * 0.78, y: s * 0.18),
    startRadius: 0,
    endCenter: CGPoint(x: s * 0.78, y: s * 0.18),
    endRadius: s * 0.6,
    options: []
)

// Letter "N" centered, with subtle drop shadow
let fontSize: CGFloat = s * 0.62
let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.25)
shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
shadow.shadowBlurRadius = s * 0.025

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: -fontSize * 0.04,
    .shadow: shadow,
]
let letter = NSAttributedString(string: "N", attributes: attrs)
let letterSize = letter.size()
let xPos = (s - letterSize.width) / 2
let yPos = (s - letterSize.height) / 2 - s * 0.015 // slight optical adjustment
letter.draw(at: NSPoint(x: xPos, y: yPos))

ctx.restoreGState()

// Thin inner stroke for crisp edge on lighter backgrounds
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.05))
ctx.setLineWidth(2)
ctx.addPath(path)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG")
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath) (\(size)x\(size))")
} catch {
    print("Failed to write: \(error)")
    exit(1)
}
