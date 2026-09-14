import AppKit

struct AppIcon {
    let symbol: String
    let icnsName: String
    let previewPath: String?
}

let icons = [
    AppIcon(symbol: "pencil.and.scribble", icnsName: "Clarify", previewPath: "docs/icon.png"),
    AppIcon(symbol: "gearshape", icnsName: "ClarifySettings", previewPath: nil),
]

let canvas: CGFloat = 1024
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
let iconsetSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(_ icon: AppIcon, pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let scale = CGFloat(pixels) / canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let shape = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.shadowBlurRadius = 28 * scale
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(white: 0.26, alpha: 1), ending: NSColor(white: 0.04, alpha: 1))!.draw(in: shape, angle: -90)
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: cornerRadius - 3, yRadius: cornerRadius - 3)
    rim.lineWidth = 6
    NSColor(white: 1, alpha: 0.12).setStroke()
    rim.stroke()

    let glyph = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold).applying(.init(paletteColors: [.white])))!
    let box = tile.insetBy(dx: 200, dy: 200)
    let fit = min(box.width / glyph.size.width, box.height / glyph.size.height)
    let drawn = NSSize(width: glyph.size.width * fit, height: glyph.size.height * fit)
    glyph.draw(in: NSRect(x: box.midX - drawn.width / 2, y: box.midY - drawn.height / 2, width: drawn.width, height: drawn.height))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to path: String) {
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for icon in icons {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(icon.icnsName).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in iconsetSizes {
        writePNG(render(icon, pixels: size.pixels), to: iconset.appendingPathComponent("\(size.name).png").path)
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/\(icon.icnsName).icns"]
    try! iconutil.run()
    iconutil.waitUntilExit()
    print("Resources/\(icon.icnsName).icns exit \(iconutil.terminationStatus)")
    if let previewPath = icon.previewPath {
        writePNG(render(icon, pixels: 512), to: previewPath)
        print(previewPath)
    }
}
