import AppKit

enum ScreenCapture {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    static func displayNumberUnderPointer() -> Int {
        let pointer = NSEvent.mouseLocation
        return (NSScreen.screens.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0) + 1
    }

    static func image(ofDisplay displayNumber: Int) -> NSImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clarify-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-D", "\(displayNumber)", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return (try? Data(contentsOf: file)).flatMap(NSImage.init(data:))
    }
}
