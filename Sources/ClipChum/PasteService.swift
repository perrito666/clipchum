import AppKit
import ApplicationServices
import ClipChumCore

/// Writes clips back to the general pasteboard and optionally simulates ⌘V.
@MainActor
final class PasteService {
    let blobs: BlobStore
    /// The board clips are written to; only the smoke test swaps in a private one.
    let pasteboard: NSPasteboard
    /// The pasteboard change count right after our last write, so the monitor can ignore it.
    private(set) var lastWrittenChangeCount: Int = -1

    init(blobs: BlobStore, pasteboard: NSPasteboard = .general) {
        self.blobs = blobs
        self.pasteboard = pasteboard
    }

    /// Put the clip on the pasteboard. Returns false when nothing could be written
    /// (for example a file reference whose target is gone and was never dereferenced).
    @discardableResult
    func copy(_ clip: Clip) -> Bool {
        let pb = pasteboard
        pb.clearContents()
        let marker = NSPasteboardItem()
        marker.setData(Data(), forType: PasteboardParser.internalMarker)

        var objects: [NSPasteboardWriting] = []
        switch clip.kind {
        case .text:
            let item = NSPasteboardItem()
            item.setString(clip.text ?? "", forType: .string)
            objects = [item]
        case .url:
            let item = NSPasteboardItem()
            let s = clip.text ?? ""
            item.setString(s, forType: .string)
            item.setString(s, forType: .URL)
            objects = [item]
        case .richText:
            let item = NSPasteboardItem()
            if let rtf = clip.rtf { item.setData(rtf, forType: .rtf) }
            if let html = clip.html { item.setString(html, forType: .html) }
            item.setString(clip.text ?? "", forType: .string)
            objects = [item]
        case .image:
            var data: Data? = nil
            if let hash = clip.blobHash { data = try? blobs.data(for: hash) }
            if data == nil { data = clip.thumbnail }
            guard let png = data else { return false }
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            objects = [item]
        case .fileRef:
            let urls = resolvedFileURLs(for: clip)
            guard !urls.isEmpty else { return false }
            objects = urls.map { $0 as NSURL }
        }
        // The marker item goes first so `types` on the board includes it.
        pb.writeObjects([marker] + objects)
        lastWrittenChangeCount = pb.changeCount
        return true
    }

    /// Resolve bookmarks; when a file is gone but we hold its bytes, restore it to a
    /// scratch folder with its original name so the paste still works.
    func resolvedFileURLs(for clip: Clip) -> [URL] {
        let paths = clip.filePaths ?? []
        let bookmarks = clip.bookmarks ?? []
        var out: [URL] = []
        for (i, path) in paths.enumerated() {
            let bookmark = i < bookmarks.count && !bookmarks[i].isEmpty ? bookmarks[i] : nil
            let res = FileReference.resolve(bookmark: bookmark, path: path)
            if let url = res.url {
                out.append(url)
            } else if paths.count == 1, let hash = clip.blobHash, let restored = restore(hash: hash, name: (path as NSString).lastPathComponent) {
                out.append(restored)
            }
        }
        return out
    }

    private func restore(hash: String, name: String) -> URL? {
        let dir = AppPaths.supportDirectory.appendingPathComponent("Restored").appendingPathComponent(String(hash.prefix(12)))
        let target = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: blobs.url(for: hash), to: target)
            return target
        } catch {
            NSLog("ClipChum: could not restore blob \(hash): \(error)")
            return nil
        }
    }

    // MARK: - Paste-back

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Simulate ⌘V in whichever app is frontmost. Requires Accessibility permission.
    func pasteIntoFrontmostApp() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
