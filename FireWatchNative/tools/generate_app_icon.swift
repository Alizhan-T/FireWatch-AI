#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates a 1024px opaque PNG app icon using built-in macOS AppKit.
/// It has no external dependencies and is safe for XcodeGen / Personal Team builds.
let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assetDirectory = root.appendingPathComponent("FireWatchNative/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
let output = assetDirectory.appendingPathComponent("AppIcon.png")

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
defer { image.unlockFocus() }

NSColor(calibratedRed: 0.055, green: 0.059, blue: 0.076, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

// High-contrast minimal protective flame, intentionally without text or gradients.
let flame = NSBezierPath()
flame.move(to: NSPoint(x: 512, y: 870))
flame.curve(to: NSPoint(x: 670, y: 574),
            controlPoint1: NSPoint(x: 695, y: 776), controlPoint2: NSPoint(x: 675, y: 672))
flame.curve(to: NSPoint(x: 720, y: 602),
            controlPoint1: NSPoint(x: 649, y: 520), controlPoint2: NSPoint(x: 721, y: 515))
flame.curve(to: NSPoint(x: 805, y: 351),
            controlPoint1: NSPoint(x: 842, y: 478), controlPoint2: NSPoint(x: 827, y: 376))
flame.curve(to: NSPoint(x: 512, y: 142),
            controlPoint1: NSPoint(x: 773, y: 256), controlPoint2: NSPoint(x: 612, y: 181))
flame.curve(to: NSPoint(x: 219, y: 351),
            controlPoint1: NSPoint(x: 412, y: 181), controlPoint2: NSPoint(x: 251, y: 256))
flame.curve(to: NSPoint(x: 304, y: 604),
            controlPoint1: NSPoint(x: 196, y: 457), controlPoint2: NSPoint(x: 233, y: 550))
flame.curve(to: NSPoint(x: 354, y: 574),
            controlPoint1: NSPoint(x: 293, y: 522), controlPoint2: NSPoint(x: 354, y: 520))
flame.curve(to: NSPoint(x: 512, y: 870),
            controlPoint1: NSPoint(x: 348, y: 684), controlPoint2: NSPoint(x: 482, y: 746))
flame.close()

NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.12, alpha: 1).setFill()
flame.fill()

// Shield is negative space (charcoal) inside the fire.
let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 508))
shield.curve(to: NSPoint(x: 647, y: 455),
             controlPoint1: NSPoint(x: 552, y: 470), controlPoint2: NSPoint(x: 600, y: 460))
shield.curve(to: NSPoint(x: 512, y: 222),
             controlPoint1: NSPoint(x: 655, y: 322), controlPoint2: NSPoint(x: 585, y: 250))
shield.curve(to: NSPoint(x: 377, y: 455),
             controlPoint1: NSPoint(x: 439, y: 250), controlPoint2: NSPoint(x: 369, y: 322))
shield.curve(to: NSPoint(x: 512, y: 508),
             controlPoint1: NSPoint(x: 424, y: 460), controlPoint2: NSPoint(x: 472, y: 470))
shield.close()
NSColor(calibratedRed: 0.055, green: 0.059, blue: 0.076, alpha: 1).setFill()
shield.fill()

let core = NSBezierPath()
core.move(to: NSPoint(x: 512, y: 447))
core.curve(to: NSPoint(x: 546, y: 345),
           controlPoint1: NSPoint(x: 570, y: 386), controlPoint2: NSPoint(x: 566, y: 369))
core.curve(to: NSPoint(x: 512, y: 285),
           controlPoint1: NSPoint(x: 528, y: 325), controlPoint2: NSPoint(x: 512, y: 300))
core.curve(to: NSPoint(x: 478, y: 345),
           controlPoint1: NSPoint(x: 512, y: 297), controlPoint2: NSPoint(x: 496, y: 325))
core.curve(to: NSPoint(x: 512, y: 447),
           controlPoint1: NSPoint(x: 458, y: 369), controlPoint2: NSPoint(x: 454, y: 386))
core.close()
NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.12, alpha: 1).setFill()
core.fill()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render FireWatch app icon")
}
try data.write(to: output, options: .atomic)
print("FireWatch icon generated at \(output.path)")
