import Foundation
import Testing
@testable import ClipChumCore

@Suite struct IngesterTests {
    func makeEnv() throws -> (Ingester, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipchum-tests-\(UUID().uuidString)")
        let blobs = try BlobStore(directory: dir.appendingPathComponent("Blobs"))
        return (Ingester(store: try ClipStore(), blobs: blobs), dir)
    }

    @Test func disabledKindIsSkipped() throws {
        let (ingester, dir) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = Settings()
        settings.enabledKinds.remove(.text)
        guard case .skipped = try ingester.ingest(.text("nope"), settings: settings, sourceBundleID: nil) else {
            Issue.record("expected skip"); return
        }
    }

    @Test func excludedAppIsSkipped() throws {
        let (ingester, dir) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = Settings()
        settings.excludedApps = ["com.example.secret"]
        guard case .skipped = try ingester.ingest(.text("x"), settings: settings, sourceBundleID: "com.example.secret") else {
            Issue.record("expected skip"); return
        }
    }

    @Test func fileReferenceThenDereference() throws {
        let (ingester, dir) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: file)

        var settings = Settings()
        settings.dereferenceFiles = false
        guard case .stored(let ref, _) = try ingester.ingest(.files([file]), settings: settings, sourceBundleID: nil) else {
            Issue.record("expected stored"); return
        }
        #expect(ref.kind == .fileRef)
        #expect(ref.blobHash == nil)
        #expect(ref.filePaths == [file.path])
        #expect(ref.bookmarks?.first?.isEmpty == false)

        settings.dereferenceFiles = true
        guard case .stored(let deref, let dedup) = try ingester.ingest(.files([file]), settings: settings, sourceBundleID: nil) else {
            Issue.record("expected stored"); return
        }
        #expect(dedup)
        #expect(deref.blobHash != nil)
        #expect(deref.byteCount == 5)
        #expect(try ingester.blobs.data(for: deref.blobHash!) == Data("hello".utf8))

        // Deleting the original does not lose the stored bytes.
        try FileManager.default.removeItem(at: file)
        #expect(ingester.blobs.contains(deref.blobHash!))
    }

    @Test func pruneRemovesOrphanBlobs() throws {
        let (ingester, dir) = try makeEnv()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = Settings()
        settings.maxItems = 1
        let png1 = solidPNG(w: 2, h: 2, r: 10)
        let png2 = solidPNG(w: 3, h: 3, r: 200)
        guard case .stored(let first, _) = try ingester.ingest(.image(png: png1, width: 2, height: 2), settings: settings, sourceBundleID: nil),
              let firstHash = first.blobHash else { Issue.record("no blob"); return }
        _ = try ingester.ingest(.image(png: png2, width: 3, height: 3), settings: settings, sourceBundleID: nil, now: Date().addingTimeInterval(1))
        #expect(!ingester.blobs.contains(firstHash))
        #expect(try ingester.store.count() == 1)
    }

    func solidPNG(w: Int, h: Int, r: UInt8) -> Data {
        let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            NSColor(calibratedRed: CGFloat(r) / 255, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        return ImageProcessing.normalizePNG(image.tiffRepresentation!)!.data
    }
}
import AppKit
