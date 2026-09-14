import CryptoKit
import Foundation

/// Content-addressed file store next to the database. Files are named by SHA-256 hex.
public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep Spotlight out of the blob folder.
        let marker = directory.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: marker.path) {
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
    }

    public func url(for hash: String) -> URL {
        directory.appendingPathComponent(hash)
    }

    public func contains(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    /// Store in-memory bytes. Returns the hash.
    @discardableResult
    public func store(data: Data) throws -> String {
        let hash = SHA256.hash(data: data).hex
        let target = url(for: hash)
        if !FileManager.default.fileExists(atPath: target.path) {
            try data.write(to: target, options: .atomic)
        }
        return hash
    }

    /// Copy a file from disk, hashing it in a streaming fashion. Returns hash and size.
    public func store(fileAt source: URL) throws -> (hash: String, byteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        let hash = hasher.finalize().hex
        let target = url(for: hash)
        if !FileManager.default.fileExists(atPath: target.path) {
            let tmp = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: source, to: tmp)
            do {
                try FileManager.default.moveItem(at: tmp, to: target)
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                // Another writer may have raced us; that is fine if the target now exists.
                if !FileManager.default.fileExists(atPath: target.path) { throw error }
            }
        }
        return (hash, total)
    }

    public func data(for hash: String) throws -> Data {
        try Data(contentsOf: url(for: hash))
    }

    public func remove(_ hash: String) {
        try? FileManager.default.removeItem(at: url(for: hash))
    }

    /// Delete every blob whose hash is not in `keeping`. Returns the number removed.
    @discardableResult
    public func collectGarbage(keeping: Set<String>) throws -> Int {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var removed = 0
        for name in names where !name.hasPrefix(".") && !keeping.contains(name) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }

    /// Total bytes on disk (excluding hidden files).
    public func totalBytes() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.filter { !$0.hasPrefix(".") }.reduce(0) { acc, name in
            let attrs = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            return acc + ((attrs?[.size] as? Int64) ?? 0)
        }
    }
}

extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
