import AppKit
import UniformTypeIdentifiers

enum ContextImage {
    private static let longestSide: CGFloat = 1568
    private static let jpegQuality = 0.75

    static func pastedImages(on pasteboard: NSPasteboard) -> [NSImage] {
        let files = imageFiles(on: pasteboard)
        if !files.isEmpty { return files }
        guard pasteboard.string(forType: .string) == nil else { return [] }
        return embeddedImages(on: pasteboard)
    }

    static func droppedImages(on pasteboard: NSPasteboard) -> [NSImage] {
        let files = imageFiles(on: pasteboard)
        return files.isEmpty ? embeddedImages(on: pasteboard) : files
    }

    static func jpeg(from image: NSImage) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), source.width > 0, source.height > 0 else { return nil }
        let scale = min(1, longestSide / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(bounds)
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(source, in: bounds)
        context.flushGraphics()
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
    }

    private static func imageFiles(on pasteboard: NSPasteboard) -> [NSImage] {
        let imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFileOptions) as? [URL] ?? []
        return urls.compactMap { (try? Data(contentsOf: $0)).flatMap(NSImage.init(data:)) }
    }

    private static func embeddedImages(on pasteboard: NSPasteboard) -> [NSImage] {
        guard pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier]) else { return [] }
        return pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
    }
}
