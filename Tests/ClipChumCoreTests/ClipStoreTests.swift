import Foundation
import Testing
@testable import ClipChumCore

@Suite struct ClipStoreTests {
    func makeClip(_ text: String, at date: Date = Date(), blob: String? = nil) -> Clip {
        Clip(kind: .text, createdAt: date, text: text, blobHash: blob,
             contentHash: PasteboardParser.contentHash(for: .text(text)))
    }

    @Test func insertAndRecentOrder() throws {
        let store = try ClipStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = try store.insert(makeClip("first", at: t0), maxItems: 10)
        _ = try store.insert(makeClip("second", at: t0.addingTimeInterval(1)), maxItems: 10)
        let recent = try store.recent(limit: 10)
        #expect(recent.map(\.text) == ["second", "first"])
    }

    @Test func duplicateBumpsToTop() throws {
        let store = try ClipStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = try store.insert(makeClip("a", at: t0), maxItems: 10)
        _ = try store.insert(makeClip("b", at: t0.addingTimeInterval(1)), maxItems: 10)
        let r = try store.insert(makeClip("a", at: t0.addingTimeInterval(2)), maxItems: 10)
        #expect(r.deduplicated)
        #expect(try store.count() == 2)
        #expect(try store.recent(limit: 10).map(\.text) == ["a", "b"])
    }

    @Test func promoteMovesPickedClipToTop() throws {
        let store = try ClipStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        let a = try store.insert(makeClip("a", at: t0), maxItems: 10)
        _ = try store.insert(makeClip("b", at: t0.addingTimeInterval(1)), maxItems: 10)
        _ = try store.insert(makeClip("c", at: t0.addingTimeInterval(2)), maxItems: 10)
        try store.promote(id: #require(a.clip.id), at: t0.addingTimeInterval(3))
        #expect(try store.count() == 3)
        #expect(try store.recent(limit: 10).map(\.text) == ["a", "c", "b"])
        // The search index follows the row, and results use the same ordering.
        _ = try store.insert(makeClip("a again", at: t0.addingTimeInterval(1)), maxItems: 10)
        #expect(try store.search("a", limit: 10).map(\.text) == ["a", "a again"])
    }

    @Test func pruneKeepsPinnedAndReportsOrphanBlobs() throws {
        let store = try ClipStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        var pinned = makeClip("keep me", at: t0, blob: "blob-pinned")
        pinned.pinned = true
        _ = try store.insert(pinned, maxItems: 2)
        _ = try store.insert(makeClip("old", at: t0.addingTimeInterval(1), blob: "blob-old"), maxItems: 2)
        _ = try store.insert(makeClip("shared", at: t0.addingTimeInterval(2), blob: "blob-shared"), maxItems: 2)
        let r = try store.insert(makeClip("new", at: t0.addingTimeInterval(3), blob: "blob-shared"), maxItems: 2)
        // "old" is pruned (its blob is orphaned); "shared" blob is still referenced by "new".
        #expect(r.prunedBlobHashes == ["blob-old"])
        let texts = try store.recent(limit: 10).map(\.text)
        #expect(texts.contains("keep me"))
        #expect(!texts.contains("old"))
        #expect(try store.count() == 3)
    }

    @Test func searchPrefixAndFallback() throws {
        let store = try ClipStore()
        _ = try store.insert(makeClip("Meeting notes for Tuesday"), maxItems: 10)
        _ = try store.insert(makeClip("grocery list: eggs, milk"), maxItems: 10)
        _ = try store.insert(makeClip("C++ && Rust"), maxItems: 10)
        #expect(try store.search("meet tue", limit: 10).map(\.text) == ["Meeting notes for Tuesday"])
        #expect(try store.search("milk", limit: 10).count == 1)
        #expect(try store.search("&&", limit: 10).map(\.text) == ["C++ && Rust"])
        #expect(try store.search("nothing-here", limit: 10).isEmpty)
    }

    @Test func fileClipIsSearchableByName() throws {
        let store = try ClipStore()
        let clip = Clip(kind: .fileRef, text: "report-final.pdf", filePaths: ["/Users/x/Documents/report-final.pdf"],
                        contentHash: "h1")
        _ = try store.insert(clip, maxItems: 10)
        #expect(try store.search("report", limit: 10).count == 1)
        #expect(try store.search("Documents", limit: 10).count == 1)
    }
}
