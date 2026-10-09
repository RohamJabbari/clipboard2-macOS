import Testing
import AppKit
@testable import Clipboard2

struct ScreenTextTests {
    /// Renders text the way it would appear in a screenshot, then runs real on-device OCR.
    private func render(_ text: String) throws -> CGImage {
        let size = NSSize(width: 520, height: 70)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 14, y: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.white,
        ])
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.cgImage)
    }

    @Test func recognisesTextFromAScreenshot() async throws {
        let text = try await ScreenTextCapture.recognizeText(in: render("an awesome idea!!!"))
        #expect(text.lowercased().contains("awesome idea"))
    }

    @Test func ordersLinesTopToBottomAndLeftToRight() {
        let lines: [(text: String, box: CGRect)] = [
            ("second", CGRect(x: 0.1, y: 0.40, width: 0.3, height: 0.1)),
            ("right", CGRect(x: 0.6, y: 0.71, width: 0.3, height: 0.1)),
            ("left", CGRect(x: 0.1, y: 0.70, width: 0.3, height: 0.1)),
        ]
        #expect(ScreenTextCapture.orderedLines(lines) == "left right\nsecond")
    }

    @Test func clipboardImageRules() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Clipboard2Tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let png = try #require(ImageProcessor.encodePNG(try render("x")))

        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        #expect(ClipboardImage.current(in: pasteboard) != nil)          // screenshot / copied image

        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        pasteboard.setString("A1\tB1", forType: .string)
        #expect(ClipboardImage.current(in: pasteboard) == nil)          // spreadsheet: real text wins

        let file = FileManager.default.temporaryDirectory.appending(path: "clippy-ocr-test.png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.setString("clippy-ocr-test.png", forType: .string)
        #expect(ClipboardImage.current(in: pasteboard) != nil)          // Finder file copy
    }
}
