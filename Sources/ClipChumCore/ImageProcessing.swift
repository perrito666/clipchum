import AppKit

public enum ImageProcessing {
    /// Decode any bitmap data the pasteboard gave us and re-encode as PNG.
    public static func normalizePNG(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, w, h)
    }

    /// Downscale to fit `maxDimension` (in pixels) and encode as PNG.
    public static func thumbnailPNG(from data: Data, maxDimension: CGFloat = 160) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let rep = image.representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxDimension / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        out.size = NSSize(width: tw, height: th)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: tw, height: th),
                   from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
                   operation: .copy, fraction: 1)
        return out.representation(using: .png, properties: [:])
    }
}
