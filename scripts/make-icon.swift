#!/usr/bin/env swift
// Generates Clippy's app icon set (macOS 26 style: rounded square, layered glass, clipboard motif).
// Usage: swift scripts/make-icon.swift <path/to/AppIcon.appiconset>
import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

/// Continuous-corner ("squircle") rounded rect approximation used by Apple's icon grid.
func squircle(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.28  // extend the corner curve for a smoother, continuous look
    let c = min(r * k, min(rect.width, rect.height) / 2)
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    p.move(to: CGPoint(x: minX + c, y: maxY))
    p.addLine(to: CGPoint(x: maxX - c, y: maxY))
    p.addCurve(to: CGPoint(x: maxX, y: maxY - c), control1: CGPoint(x: maxX - c * 0.36, y: maxY), control2: CGPoint(x: maxX, y: maxY - c * 0.36))
    p.addLine(to: CGPoint(x: maxX, y: minY + c))
    p.addCurve(to: CGPoint(x: maxX - c, y: minY), control1: CGPoint(x: maxX, y: minY + c * 0.36), control2: CGPoint(x: maxX - c * 0.36, y: minY))
    p.addLine(to: CGPoint(x: minX + c, y: minY))
    p.addCurve(to: CGPoint(x: minX, y: minY + c), control1: CGPoint(x: minX + c * 0.36, y: minY), control2: CGPoint(x: minX, y: minY + c * 0.36))
    p.addLine(to: CGPoint(x: minX, y: maxY - c))
    p.addCurve(to: CGPoint(x: minX + c, y: maxY), control1: CGPoint(x: minX, y: maxY - c * 0.36), control2: CGPoint(x: minX + c * 0.36, y: maxY))
    p.closeSubpath()
    return p
}

func linearGradient(_ ctx: CGContext, path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.interpolationQuality = .high

    // 1. Base plate on Apple's 1024 grid: 824×824 body, 100pt margin.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(body, radius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.32))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x2F6BFF))
    ctx.fillPath()
    ctx.restoreGState()

    linearGradient(ctx, path: bodyPath,
                   colors: [color(0x5AC8FA), color(0x2F7BFF), color(0x3A4BD8)],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // Soft top glow — the "glass" layer.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    // 2. Paper sheet (clipboard board), floating with its own shadow.
    let board = CGRect(x: 262, y: 168, width: 500, height: 610)
    let boardPath = squircle(board, radius: 64)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x0A1F66, 0.42))
    ctx.addPath(boardPath)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, path: boardPath,
                   colors: [color(0xFFFFFF), color(0xE8EEF9)],
                   from: CGPoint(x: 512, y: board.maxY), to: CGPoint(x: 512, y: board.minY))

    // Glass rim on the sheet.
    ctx.saveGState()
    ctx.addPath(boardPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // 3. List rows: bullet + bar, alternating lengths.
    let rows: [(CGFloat, CGFloat)] = [(612, 250), (512, 300), (412, 210), (312, 270)]
    for (index, row) in rows.enumerated() {
        let (y, width) = row
        let alpha: CGFloat = index == 0 ? 1 : 0.55
        let bullet = CGRect(x: 322, y: y - 22, width: 44, height: 44)
        ctx.setFillColor(color(index == 0 ? 0x2F7BFF : 0x8AA4D6, alpha))
        ctx.fillEllipse(in: bullet)
        let bar = CGRect(x: 392, y: y - 15, width: width, height: 30)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 15, cornerHeight: 15, transform: nil))
        ctx.setFillColor(color(index == 0 ? 0x2F7BFF : 0xA9BBDD, index == 0 ? 0.85 : 0.75))
        ctx.fillPath()
    }

    // 4. Metal clip on top, its own raised layer.
    let clip = CGRect(x: 392, y: 718, width: 240, height: 118)
    let clipPath = squircle(clip, radius: 40)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x000000, 0.35))
    ctx.addPath(clipPath)
    ctx.setFillColor(color(0x3B4252))
    ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, path: clipPath,
                   colors: [color(0x6B7385), color(0x2E3442)],
                   from: CGPoint(x: 512, y: clip.maxY), to: CGPoint(x: 512, y: clip.minY))
    // Clip hole.
    let hole = CGRect(x: 467, y: 772, width: 90, height: 34)
    ctx.addPath(CGPath(roundedRect: hole, cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setFillColor(color(0x1C2030))
    ctx.fillPath()
    // Clip highlight.
    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Specular rim on the plate.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.28))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

struct Entry { let points: Int; let scale: Int }
let entries = [16, 32, 128, 256, 512].flatMap { [Entry(points: $0, scale: 1), Entry(points: $0, scale: 2)] }

var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    writePNG(drawIcon(size: pixels), to: outDir.appendingPathComponent(name))
    images.append([
        "idiom": "mac",
        "size": "\(entry.points)x\(entry.points)",
        "scale": "\(entry.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(entries.count) icons to \(outDir.path)")
