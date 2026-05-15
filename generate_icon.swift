#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Brand colour — matches BrowserCommander / BrowserNotes for consistent
// Jorvik suite identity in /Applications.
let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let cx = s / 2
    let cy = s / 2

    // ── Background ──
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    brandBlue.setFill()
    bgPath.fill()

    // Subtle radial gradient for depth — same recipe as the other Jorvik icons.
    let gradSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(white: 1.0, alpha: 0.08).cgColor,
        NSColor(white: 0.0, alpha: 0.10).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: gradSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(bgPath.cgPath)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx, y: cy + s * 0.12),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: s * 0.55,
            options: [])
        ctx.restoreGState()
    }

    // ── Marching-ants selection rectangle ──
    //
    // Sits behind the magnifying glass. Drawn as a dashed stroke at white/0.65
    // so it reads clearly on the navy background without competing with the
    // glass for attention. The rectangle inset of 0.16 leaves a comfortable
    // margin from the bundle's rounded corners and frames the glass with
    // visible "selection" intent.
    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    let selInset = s * 0.16
    let selRect = NSRect(x: selInset, y: selInset,
                          width: s - selInset * 2, height: s - selInset * 2)
    let selPath = NSBezierPath(roundedRect: selRect, xRadius: s * 0.05, yRadius: s * 0.05)
    selPath.lineWidth = max(2, s * 0.025)
    let dash: [CGFloat] = [s * 0.055, s * 0.038]
    selPath.setLineDash(dash, count: dash.count, phase: 0)
    NSColor(white: 1.0, alpha: 0.65).setStroke()
    selPath.stroke()

    ctx.restoreGState()

    // ── Magnifying glass ──
    //
    // Geometry: glass centre is slightly upper-left of icon centre so the
    // handle (drawn lower-right) has room to extend toward the selection
    // rectangle's lower-right corner. Lens is a hollow ring with a small
    // inner highlight; the rim is bold white, handle is the same bold
    // stroke ending with a rounded cap.
    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    let lensR = s * 0.18
    let lensCX = cx - s * 0.04
    let lensCY = cy + s * 0.04
    let rimW = s * 0.045
    let handleW = s * 0.045

    // Lens fill — very subtle inner glass tint so the rectangle behind shows
    // through gently. White/0.10 reads as "glass" against the navy.
    let lensRect = CGRect(x: lensCX - lensR, y: lensCY - lensR,
                           width: lensR * 2, height: lensR * 2)
    ctx.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
    ctx.fillEllipse(in: lensRect)

    // Inner highlight — small soft glow on the upper-left interior to give
    // the lens dimensionality. Drawn before the rim so the stroke sits
    // cleanly on top of any highlight bleed.
    let highlightColors = [
        NSColor(white: 1.0, alpha: 0.55).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    if let highlight = CGGradient(colorsSpace: gradSpace, colors: highlightColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(highlight,
            startCenter: CGPoint(x: lensCX - lensR * 0.35, y: lensCY + lensR * 0.35),
            startRadius: 0,
            endCenter: CGPoint(x: lensCX - lensR * 0.35, y: lensCY + lensR * 0.35),
            endRadius: lensR * 0.55,
            options: [])
    }

    // Rim — bold white circle.
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(rimW)
    ctx.setLineCap(.round)
    ctx.strokeEllipse(in: lensRect)

    // Handle — short stroke from the lower-right of the rim toward the
    // outer corner. Length tuned so the cap stays inside the selection
    // rectangle (which itself sits inside the bundle background).
    let angle: CGFloat = -.pi / 4   // 45° below horizontal, into lower-right
    let handleStart = CGPoint(
        x: lensCX + cos(angle) * (lensR + rimW * 0.35),
        y: lensCY + sin(angle) * (lensR + rimW * 0.35)
    )
    let handleLen = s * 0.14
    let handleEnd = CGPoint(
        x: handleStart.x + cos(angle) * handleLen,
        y: handleStart.y + sin(angle) * handleLen
    )
    ctx.setLineWidth(handleW)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// ── Iconset emission ─────────────────────────────────────────────────────────
//
// iconutil wants the standard naming scheme: icon_<size>x<size>.png plus an
// @2x variant at double the pixels (same logical size). Render both at the
// target resolution so neither is a resampled blur.

let outDir = "Resources/CopyLens.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let image = drawIcon(size: size)
    let tiff = image.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    let png = rep.representation(using: .png, properties: [:])!
    let path = "\(outDir)/icon_\(Int(size))x\(Int(size)).png"
    try? png.write(to: URL(fileURLWithPath: path))
    if size <= 512 {
        // @2x variant: render natively at 2× the pixel count so it's
        // pin-sharp at high-DPI rather than upsampled.
        let bigImage = drawIcon(size: size * 2)
        let bigTiff = bigImage.tiffRepresentation!
        let bigRep = NSBitmapImageRep(data: bigTiff)!
        let bigPng = bigRep.representation(using: .png, properties: [:])!
        let path2x = "\(outDir)/icon_\(Int(size))x\(Int(size))@2x.png"
        try? bigPng.write(to: URL(fileURLWithPath: path2x))
    }
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", outDir, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("→ Wrote Resources/AppIcon.icns")
