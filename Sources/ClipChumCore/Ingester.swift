import Foundation

/// Turns a parsed pasteboard change into a stored `Clip`, applying settings.
public struct Ingester: Sendable {
    public let store: ClipStore
    public let blobs: BlobStore

    public init(store: ClipStore, blobs: BlobStore) {
        self.store = store
        self.blobs = blobs
    }

    public enum Outcome: Sendable {
        case stored(Clip, deduplicated: Bool)
        case skipped(reason: String)
    }

    /// Build and persist a clip. Runs blob writes, so call off the main thread for large payloads.
    public func ingest(
        _ parsed: ParsedClip,
        settings: Settings,
        sourceBundleID: String?,
        pasteboardTypes: [String] = [],
        now: Date = Date()
    ) throws -> Outcome {
        guard settings.enabledKinds.contains(parsed.kind) else {
            return .skipped(reason: "kind \(parsed.kind.rawValue) disabled")
        }
        if let app = sourceBundleID, settings.excludedApps.contains(app) {
            return .skipped(reason: "app \(app) excluded")
        }

        var clip = Clip(
            kind: parsed.kind,
            createdAt: now,
            sourceBundleID: sourceBundleID,
            contentHash: PasteboardParser.contentHash(for: parsed),
            pasteboardTypes: pasteboardTypes.isEmpty ? nil : pasteboardTypes.joined(separator: " ")
        )

        switch parsed {
        case .text(let s):
            clip.text = s
        case .url(let s):
            clip.text = s
        case .richText(let plain, let rtf, let html):
            clip.text = plain
            clip.rtf = rtf
            clip.html = html
        case .image(let png, let w, let h):
            clip.imageWidth = w
            clip.imageHeight = h
            clip.thumbnail = ImageProcessing.thumbnailPNG(from: png)
            clip.byteCount = Int64(png.count)
            if settings.storeImageData, Int64(png.count) <= settings.imageCapBytes {
                clip.blobHash = try blobs.store(data: png)
            }
        case .files(let urls):
            clip.filePaths = urls.map(\.path)
            clip.bookmarks = urls.map { FileReference.bookmark(for: $0) ?? Data() }
            clip.text = urls.map(\.lastPathComponent).joined(separator: "\n")
            if urls.count == 1, let url = urls.first, FileReference.isRegularFile(url) {
                let size = FileReference.fileSize(url) ?? 0
                clip.byteCount = size
                if settings.dereferenceFiles, size <= settings.fileCapBytes {
                    let stored = try blobs.store(fileAt: url)
                    clip.blobHash = stored.hash
                    clip.byteCount = stored.byteCount
                }
            }
        }

        let result = try store.insert(clip, maxItems: settings.maxItems)
        if !result.prunedBlobHashes.isEmpty {
            for hash in result.prunedBlobHashes { blobs.remove(hash) }
        }
        return .stored(result.clip, deduplicated: result.deduplicated)
    }

    /// Remove blobs no row references any more.
    @discardableResult
    public func collectGarbage() throws -> Int {
        try blobs.collectGarbage(keeping: try store.referencedBlobHashes())
    }
}
