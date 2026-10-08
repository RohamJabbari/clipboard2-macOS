import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ContentHasher {
    /// Text and rich text share a namespace so the same words copied with and without
    /// formatting dedupe into one item.
    static func hash(text: String) -> String { "text:" + sha256(Data(text.utf8)) }
    static func hash(fileURLs: [URL]) -> String {
        "file:" + sha256(Data(fileURLs.map(\.path).joined(separator: "\n").utf8))
    }
    static func hash(imageData: Data) -> String { "image:" + sha256(imageData) }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum ImageProcessor {
    struct Output: Sendable {
        var png: Data
        var thumbnail: Data
        var width: Int
        var height: Int
    }

    static func process(_ data: Data, thumbnailMaxPixels: Int = 480) -> Output? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        guard let png = isPNG ? data : encodePNG(image) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let thumb = encodePNG(thumbImage)
        else { return nil }

        return Output(png: png, thumbnail: thumb, width: image.width, height: image.height)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

nonisolated enum CaptureProcessor {
    /// Runs off the main actor: hashing and image encoding can take tens of milliseconds.
    @concurrent
    static func process(_ raw: RawCapture, blobs: BlobStore) async -> ProcessedCapture? {
        switch raw.kind {
        case .text, .richText:
            return ProcessedCapture(
                kind: raw.kind,
                text: raw.text,
                preview: TextPreview.make(raw.text),
                rtfData: raw.rtfData,
                htmlData: raw.htmlData,
                fileURLs: [],
                source: raw.source,
                hash: ContentHasher.hash(text: raw.text),
                byteCount: raw.text.utf8.count + (raw.rtfData?.count ?? 0) + (raw.htmlData?.count ?? 0)
            )

        case .file:
            let names = raw.fileURLs.map(\.lastPathComponent)
            return ProcessedCapture(
                kind: .file,
                text: raw.fileURLs.map(\.path).joined(separator: "\n"),
                preview: names.count == 1 ? names[0] : "\(names.count) files: " + names.joined(separator: ", "),
                fileURLs: raw.fileURLs,
                source: raw.source,
                hash: ContentHasher.hash(fileURLs: raw.fileURLs)
            )

        case .image:
            guard let data = raw.imageData, let output = ImageProcessor.process(data) else { return nil }
            let base = UUID().uuidString
            let full = "\(base).png"
            let thumb = "\(base)-thumb.png"
            do {
                try blobs.write(output.png, name: full)
                try blobs.write(output.thumbnail, name: thumb)
            } catch {
                blobs.delete(full)
                blobs.delete(thumb)
                Log.capture.error("Failed writing image blob: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            return ProcessedCapture(
                kind: .image,
                text: "",
                preview: "Image \(output.width)×\(output.height)",
                fileURLs: [],
                source: raw.source,
                hash: ContentHasher.hash(imageData: data),
                imageFile: full,
                thumbnailFile: thumb,
                imageWidth: output.width,
                imageHeight: output.height,
                byteCount: output.png.count
            )
        }
    }
}
