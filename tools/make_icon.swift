// Generates the 1024x1024 app icon. Run: swift tools/make_icon.swift <output.png>
import AppKit
import Foundation

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "icon-1024.png"
let side: CGFloat = 1024

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(side),
                                 pixelsHigh: Int(side),
                                 bitsPerSample: 8,
                                 samplesPerPixel: 4,
                                 hasAlpha: true,
                                 isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0,
                                 bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("cannot create bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: side, height: side)
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.09, blue: 0.32, alpha: 1),
    NSColor(srgbRed: 0.03, green: 0.02, blue: 0.08, alpha: 1)
])!
background.draw(in: canvas, angle: -90)

let glowRect = NSRect(x: 132, y: 232, width: 760, height: 760)
NSColor(srgbRed: 1.0, green: 0.45, blue: 0.35, alpha: 0.16).setFill()
NSBezierPath(ovalIn: glowRect).fill()

struct Slab {
    let emoji: String
    let rect: NSRect
    let angle: CGFloat
}

let slabs = [
    Slab(emoji: "🍋", rect: NSRect(x: 96, y: 236, width: 340, height: 340), angle: -11),
    Slab(emoji: "🍇", rect: NSRect(x: 342, y: 452, width: 340, height: 340), angle: 0),
    Slab(emoji: "🍎", rect: NSRect(x: 588, y: 236, width: 340, height: 340), angle: 11)
]

for slab in slabs {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: slab.rect.midX, yBy: slab.rect.midY)
    transform.rotate(byDegrees: slab.angle)
    transform.concat()
    let centered = slab.rect.offsetBy(dx: -slab.rect.midX, dy: -slab.rect.midY)

    let slabPath = NSBezierPath(roundedRect: centered, xRadius: 74, yRadius: 74)
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10).setFill()
    slabPath.fill()
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20).setStroke()
    slabPath.lineWidth = 5
    slabPath.stroke()

    let font = NSFont.systemFont(ofSize: 236)
    let attributed = NSAttributedString(string: slab.emoji, attributes: [.font: font])
    let bounds = attributed.size()
    attributed.draw(at: NSPoint(x: centered.midX - bounds.width / 2,
                                y: centered.midY - bounds.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode png\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(png.count) bytes)")
