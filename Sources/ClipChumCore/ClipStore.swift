import Foundation
import GRDB

/// SQLite-backed clip storage with FTS5 search.
public final class ClipStore: Sendable {
    public let dbQueue: DatabaseQueue

    /// Open (or create) the on-disk database.
    public convenience init(path: String) throws {
        var config = Configuration()
        config.journalMode = .wal
        try self.init(dbQueue: DatabaseQueue(path: path, configuration: config))
    }

    /// In-memory database, for tests.
    public convenience init() throws {
        try self.init(dbQueue: DatabaseQueue())
    }

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "clips") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sourceBundleID", .text)
                t.column("text", .text)
                t.column("rtf", .blob)
                t.column("html", .text)
                t.column("filePaths", .text)
                t.column("bookmarks", .text)
                t.column("blobHash", .text)
                t.column("byteCount", .integer)
                t.column("thumbnail", .blob)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("contentHash", .text).notNull().unique()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("pasteboardTypes", .text)
            }
            try db.create(index: "clips_createdAt", on: "clips", columns: ["createdAt"])
            try db.create(index: "clips_blobHash", on: "clips", columns: ["blobHash"])
            try db.create(virtualTable: "clips_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clips")
                t.tokenizer = .unicode61()
                t.column("text")
                t.column("filePaths")
            }
        }
        return m
    }

    // MARK: - Writes

    public struct InsertResult: Sendable {
        public var clip: Clip
        /// True when an identical clip already existed and was moved to the top instead.
        public var deduplicated: Bool
        /// Blob hashes that lost their last referencing row during pruning.
        public var prunedBlobHashes: [String]
    }

    /// Insert a clip, or bump an identical one to the top, then prune to `maxItems`.
    public func insert(_ clip: Clip, maxItems: Int) throws -> InsertResult {
        try dbQueue.write { db in
            var stored = clip
            var dedup = false
            if var existing = try Clip.filter(Clip.Columns.contentHash == clip.contentHash).fetchOne(db) {
                existing.createdAt = clip.createdAt
                existing.sourceBundleID = clip.sourceBundleID ?? existing.sourceBundleID
                if existing.blobHash == nil, clip.blobHash != nil {
                    existing.blobHash = clip.blobHash
                    existing.byteCount = clip.byteCount
                }
                try existing.update(db)
                stored = existing
                dedup = true
            } else {
                try stored.insert(db)
            }
            let pruned = try Self.prune(db, maxItems: maxItems)
            return InsertResult(clip: stored, deduplicated: dedup, prunedBlobHashes: pruned)
        }
    }

    /// Delete unpinned rows beyond `maxItems`. Returns blob hashes no longer referenced.
    static func prune(_ db: Database, maxItems: Int) throws -> [String] {
        let victims = try Clip
            .filter(Clip.Columns.pinned == false)
            .order(Clip.Columns.createdAt.desc)
            .limit(Int.max, offset: max(0, maxItems))
            .fetchAll(db)
        guard !victims.isEmpty else { return [] }
        let ids = victims.compactMap(\.id)
        try Clip.filter(ids.contains(Clip.Columns.id)).deleteAll(db)
        let candidates = Set(victims.compactMap(\.blobHash))
        guard !candidates.isEmpty else { return [] }
        let stillUsed = try Set(String.fetchAll(db, sql: "SELECT DISTINCT blobHash FROM clips WHERE blobHash IS NOT NULL"))
        return candidates.subtracting(stillUsed).sorted()
    }

    /// Re-run pruning after the limit was lowered in settings.
    public func prune(maxItems: Int) throws -> [String] {
        try dbQueue.write { db in try Self.prune(db, maxItems: maxItems) }
    }

    public func delete(id: Int64) throws -> Clip? {
        try dbQueue.write { db in
            guard let clip = try Clip.fetchOne(db, key: id) else { return nil }
            try clip.delete(db)
            return clip
        }
    }

    /// Move an existing clip to the top of the list (it was picked again).
    public func promote(id: Int64, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE clips SET createdAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE clips SET pinned = ? WHERE id = ?", arguments: [pinned, id])
        }
    }

    /// Delete every clip. Pinned clips survive unless `includingPinned` is set.
    public func clearAll(includingPinned: Bool = false) throws {
        try dbQueue.write { db in
            if includingPinned {
                try Clip.deleteAll(db)
            } else {
                try Clip.filter(Clip.Columns.pinned == false).deleteAll(db)
            }
        }
    }

    // MARK: - Reads

    public func fetch(id: Int64) throws -> Clip? {
        try dbQueue.read { db in try Clip.fetchOne(db, key: id) }
    }

    public func recent(limit: Int) throws -> [Clip] {
        try dbQueue.read { db in
            try Clip.order(Clip.Columns.pinned.desc, Clip.Columns.createdAt.desc).limit(limit).fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try Clip.fetchCount(db) }
    }

    /// Full-text search over text and file paths, newest first. Falls back to LIKE
    /// when the query has no indexable tokens (e.g. only punctuation).
    public func search(_ query: String, limit: Int) throws -> [Clip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try recent(limit: limit) }
        return try dbQueue.read { db in
            if let pattern = try? db.makeFTS5Pattern(rawPattern: prefixPattern(trimmed), forTable: "clips_fts") {
                let rows = try Clip.fetchAll(db, sql: """
                    SELECT clips.* FROM clips
                    JOIN clips_fts ON clips_fts.rowid = clips.id
                    WHERE clips_fts MATCH ?
                    ORDER BY clips.pinned DESC, clips.createdAt DESC
                    LIMIT ?
                    """, arguments: [pattern, limit])
                if !rows.isEmpty { return rows }
            }
            let like = "%" + trimmed.replacingOccurrences(of: "%", with: "\\%") + "%"
            return try Clip.fetchAll(db, sql: """
                SELECT * FROM clips
                WHERE text LIKE ? ESCAPE '\\' OR filePaths LIKE ? ESCAPE '\\'
                ORDER BY pinned DESC, createdAt DESC
                LIMIT ?
                """, arguments: [like, like, limit])
        }
    }

    /// Turn "foo bar" into `"foo"* "bar"*` so every token matches as a prefix.
    private func prefixPattern(_ query: String) -> String {
        query.split(whereSeparator: { $0.isWhitespace })
            .map { token in
                let cleaned = token.replacingOccurrences(of: "\"", with: "")
                return "\"\(cleaned)\"*"
            }
            .joined(separator: " ")
    }

    public func referencedBlobHashes() throws -> Set<String> {
        try dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT blobHash FROM clips WHERE blobHash IS NOT NULL"))
        }
    }

    /// Observation that fires after any commit touching the clips table.
    public func observeChanges() -> DatabaseRegionObservation {
        DatabaseRegionObservation(tracking: Clip.all())
    }
}
