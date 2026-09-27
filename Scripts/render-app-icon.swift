import AppKit

// Package the supplied artwork at every native macOS icon size.
// Usage: swift render-app-icon.swift Branding/wordproc.png /tmp/AppIcon.iconset
let input = URL(fileURLWithPath: CommandLine.arguments[1])
guard let artwork = NSImage(contentsOf: input) else { fatalError("Could not read icon artwork") }
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon canvas") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 1024
        let transform = AffineTransform(scale: factor)
        (transform as NSAffineTransform).concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
        NSColor.black.setFill()
        tile.fill()
        NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
        tile.lineWidth = 4
        tile.stroke()
        tile.addClip()
        context.imageInterpolation = .high
        artwork.draw(in: NSRect(x: 64, y: 64, width: 896, height: 896), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
