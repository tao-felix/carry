import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the share sheet collected, before it becomes an `inbox/<id>.json`.
public struct InboxDraft {
    public enum Payload {
        case url(URL, text: String?)
        case text(String)
        /// A local file the extension already copied into its own temp folder.
        case image(URL)
        case file(URL, name: String)
    }

    public var payload: Payload
    public var title: String?
    public var note: String?
    public var fromApp: String?

    public init(payload: Payload, title: String? = nil, note: String? = nil, fromApp: String? = nil) {
        self.payload = payload
        self.title = title
        self.note = note
        self.fromApp = fromApp
    }
}

public enum InboxWriterError: LocalizedError {
    case imageUnreadable

    public var errorDescription: String? {
        switch self {
        case .imageUnreadable: return "This image could not be read."
        }
    }
}

/// Writes one inbox item (§6): attachment first, then the JSON that names it.
public enum InboxWriter {
    /// Contract §1: keep every file small (< 5 MB).
    public static let maxAttachmentBytes = 5 * 1024 * 1024
    public static let maxImageEdge = 2000

    public static func write(_ draft: InboxDraft, to store: ContainerStore) async throws -> InboxItem {
        let now = Date()
        let id = Ids.inbox(now: now)
        var item = InboxItem(id: id, ts: RFC3339.string(now), kind: .text, title: draft.title, url: nil,
                             text: nil, file: nil, fromApp: draft.fromApp, note: nonEmpty(draft.note))

        switch draft.payload {
        case .url(let url, let text):
            item.kind = .url
            item.url = url.absoluteString
            item.text = nonEmpty(text)
        case .text(let text):
            item.kind = .text
            item.text = text
        case .image(let source):
            item.kind = .image
            guard let jpeg = ImageResizer.jpeg(.url(source), maxEdge: maxImageEdge) else {
                throw InboxWriterError.imageUnreadable
            }
            let name = "\(id).jpg"
            try await store.writeData(jpeg, to: "inbox/\(name)")
            item.file = name
        case .file(let source, let name):
            item.kind = .file
            item.title = item.title ?? name
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > maxAttachmentBytes {
                item.text = "Attachment skipped: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) is over the 5 MB limit."
            } else {
                let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
                let sibling = "\(id).\(ext)"
                try await store.copyFile(from: source, to: "inbox/\(sibling)")
                item.file = sibling
            }
        }

        try await store.writeJSON(item, to: "inbox/\(id).json")
        AppGroup.markCapture(.inbox, at: now)
        return item
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

/// JPEG re-encoding with ImageIO (memory-friendly; extensions have a small budget).
public enum ImageResizer {
    public enum Input {
        case url(URL)
        case data(Data)
        case cgImage(CGImage)
    }

    public static func jpeg(_ input: Input, maxEdge: Int, quality: CGFloat = 0.85) -> Data? {
        let image: CGImage?
        switch input {
        case .url(let url):
            image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { thumbnail($0, maxEdge: maxEdge) }
        case .data(let data):
            image = CGImageSourceCreateWithData(data as CFData, nil).flatMap { thumbnail($0, maxEdge: maxEdge) }
        case .cgImage(let cg):
            image = cg
        }
        guard let image else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private static func thumbnail(_ source: CGImageSource, maxEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
