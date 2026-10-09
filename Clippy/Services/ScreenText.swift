import AppKit
import Vision
import UniformTypeIdentifiers

/// On-device text recognition (Vision) for a captured screen region or a clipboard image.
/// Nothing is uploaded; captured screenshots are deleted right after recognition.
nonisolated enum ScreenTextCapture {
    /// Lets the user drag a region with the standard screenshot UI. Nil if cancelled.
    static func captureRegion() async -> CGImage? {
        let url = FileManager.default.temporaryDirectory.appending(path: "clippy-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await CLIRunner.run(URL(fileURLWithPath: "/usr/sbin/screencapture"), ["-i", "-x", url.path])
        guard result.status == 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    /// Recognises text in reading order (top to bottom, then left to right), one line per row.
    @concurrent
    static func recognizeText(in image: CGImage) async throws -> String {
        try recognizeTextNow(in: image)
    }

    /// Synchronous variant for the Services menu, whose API requires an immediate answer.
    static func recognizeTextNow(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        return orderedLines(observations.compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        })
    }

    /// Vision's normalized boxes have their origin at the bottom left. Lines whose vertical
    /// centres are within half a line height are treated as the same row.
    static func orderedLines(_ items: [(text: String, box: CGRect)]) -> String {
        let sorted = items.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(text: String, box: CGRect)]] = []
        for item in sorted {
            if let last = rows.last?.first, abs(last.box.midY - item.box.midY) < max(last.box.height, item.box.height) / 2 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The image on the clipboard that "Paste as text" should read: a copied image file (Finder also
/// adds its name as text, which we ignore), or bitmap data that has no real text alongside it
/// (apps like Excel put both a picture and the actual text; the text wins there).
enum ClipboardImage {
    static func current(in pasteboard: NSPasteboard) -> CGImage? {
        let hasText = pasteboard.string(forType: .string)?.isEmpty == false
        if !hasText, let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first,
           UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }
}
