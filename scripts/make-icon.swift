// Renders Support/AppIcon/icon-1024.png: a rounded tile with the clipboard glyph.
// Run once with `make icon`; the PNG is committed so builds need no drawing.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let tile = NSBezierPath(roundedRect: inset, xRadius: size * 0.2237, yRadius: size * 0.2237)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.42, alpha: 1),
    ])!
    gradient.draw(in: tile, angle: -70)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return false }
    let tinted = NSImage(size: symbol.size, flipped: false) { r in
        symbol.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    let origin = NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2)
    tinted.draw(in: NSRect(origin: origin, size: s))
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = image.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(origin: .zero, size: image.size))
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
