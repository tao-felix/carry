import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reads the shared item, shows it, writes it to `inbox/` (DATA-CONTRACT §6).
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case sending
        case sent
        case failed(String)
    }

    struct Preview: Equatable {
        var icon: String
        var title: String
        var subtitle: String
        var excerpt: String?
        var thumbnail: UIImage?
    }

    @Published private(set) var phase: Phase = .loading
    @Published var note = ""
    @Published private(set) var preview: Preview?

    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    private var draft: InboxDraft?
    private var store: ContainerStore?

    func load(from context: NSExtensionContext?) {
        Task {
            let resolving = Task.detached { ContainerStore.resolve() }
            let collected = await Self.collect(context)
            guard let location = await resolving.value else {
                phase = .failed("iCloud Drive is off for Carry. Turn it on in Settings › your name › iCloud, then share again.")
                return
            }
            store = ContainerStore(location: location)
            guard let collected else {
                phase = .failed("Carry could not read what was shared.")
                return
            }
            draft = collected
            preview = Self.preview(for: collected)
            phase = .ready
        }
    }

    func send() {
        guard phase == .ready, var draft, let store else { return }
        draft.note = note
        phase = .sending
        Task {
            do {
                try await store.ensureLayout()
                _ = try await InboxWriter.write(draft, to: store)
                phase = .sent
                try? await Task.sleep(nanoseconds: 900_000_000)
                onFinish?()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        onCancel?()
    }

    // MARK: Reading the extension items

    /// Priority: web URL, image, file, plain text. The first item only (the activation rule allows one).
    private static func collect(_ context: NSExtensionContext?) async -> InboxDraft? {
        guard let items = context?.inputItems as? [NSExtensionItem] else { return nil }
        let attachments = items.flatMap { $0.attachments ?? [] }
        let title = items.compactMap { $0.attributedTitle?.string }.first.flatMap(nonEmpty)
        let contentText = items.compactMap { $0.attributedContentText?.string }.first.flatMap(nonEmpty)

        if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                && !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }), let url = await loadURL(provider), !url.isFileURL {
            let text = contentText == url.absoluteString ? nil : contentText
            return InboxDraft(payload: .url(url, text: text), title: title)
        }
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
           let file = await loadImage(provider) {
            return InboxDraft(payload: .image(file), title: title ?? nonEmpty(provider.suggestedName))
        }
        if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || ($0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
                    && !$0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        }), let (file, name) = await loadFile(provider) {
            return InboxDraft(payload: .file(file, name: name), title: title)
        }
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
           let text = await loadText(provider).flatMap(nonEmpty) {
            return InboxDraft(payload: .text(text), title: title)
        }
        if let contentText { return InboxDraft(payload: .text(contentText), title: title) }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else { return nil }
        if let url = item as? URL { return url }
        if let string = item as? String { return URL(string: string) }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) { return URL(string: string) }
        return nil
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else { return nil }
        if let string = item as? String { return string }
        if let attributed = item as? NSAttributedString { return attributed.string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    /// A file first (cheap on memory); otherwise the in-memory image some apps hand over.
    private static func loadImage(_ provider: NSItemProvider) async -> URL? {
        let folder = tempFolder()
        if let copied = await copyFileRepresentation(provider, type: UTType.image.identifier, into: folder) {
            return copied.0
        }
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        var data: Data?
        if let image = item as? UIImage {
            data = image.jpegData(compressionQuality: 0.9)
        } else if let bytes = item as? Data {
            data = bytes
        } else if let url = item as? URL {
            data = try? Data(contentsOf: url)
        }
        guard let data else { return nil }
        let destination = folder.appendingPathComponent("image.jpg")
        try? data.write(to: destination)
        return destination
    }

    private static func loadFile(_ provider: NSItemProvider) async -> (URL, String)? {
        let folder = tempFolder()
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
           let url = item as? URL {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return nil }
            return (destination, url.lastPathComponent)
        }
        let type = [UTType.pdf, UTType.data].map(\.identifier).first(where: provider.hasItemConformingToTypeIdentifier)
            ?? provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
        return await copyFileRepresentation(provider, type: type, into: folder)
    }

    /// `loadFileRepresentation` hands over a URL that dies with the completion handler: copy inside it.
    private static func copyFileRepresentation(_ provider: NSItemProvider, type: String, into folder: URL) async -> (URL, String)? {
        let suggested = nonEmpty(provider.suggestedName)
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = suggested ?? url.lastPathComponent
                var destination = folder.appendingPathComponent(url.lastPathComponent)
                if destination.pathExtension.isEmpty, !URL(fileURLWithPath: name).pathExtension.isEmpty {
                    destination = folder.appendingPathComponent(name)
                }
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: (destination, name))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func tempFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("carry-share", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    nonisolated private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: Preview

    static func preview(for draft: InboxDraft) -> Preview {
        switch draft.payload {
        case .url(let url, let text):
            let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
            return Preview(icon: "link", title: draft.title ?? host, subtitle: url.absoluteString,
                           excerpt: text.map { clip($0, 180) }, thumbnail: nil)
        case .text(let text):
            return Preview(icon: "text.alignleft", title: draft.title ?? "Text",
                           subtitle: plural(text.count, "character"), excerpt: clip(text, 220), thumbnail: nil)
        case .image(let file):
            let thumbnail = ImageResizer.jpeg(.url(file), maxEdge: 200).flatMap(UIImage.init(data:))
            return Preview(icon: "photo", title: draft.title ?? "Image",
                           subtitle: "\(size(file)) · saved as JPEG, at most 2000 px", excerpt: nil, thumbnail: thumbnail)
        case .file(let file, let name):
            return Preview(icon: "doc", title: name,
                           subtitle: "\(size(file)) · \(file.pathExtension.uppercased())", excerpt: nil, thumbnail: nil)
        }
    }

    private static func size(_ file: URL) -> String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : flat
    }
}
