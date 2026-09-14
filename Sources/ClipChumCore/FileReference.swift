import Foundation

/// Helpers for durable file references. Outside the sandbox a plain bookmark is
/// inode-based, so it survives renames and moves within the same volume.
public enum FileReference {
    public static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public struct Resolution: Sendable {
        public var url: URL?
        public var stale: Bool
        public var exists: Bool { url != nil }
    }

    /// Resolve a bookmark, falling back to the recorded path. Never shows UI.
    public static func resolve(bookmark: Data?, path: String) -> Resolution {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                return Resolution(url: url, stale: stale)
            }
        }
        if FileManager.default.fileExists(atPath: path) {
            return Resolution(url: URL(fileURLWithPath: path), stale: bookmark != nil)
        }
        return Resolution(url: nil, stale: false)
    }

    /// True for regular files (not directories or packages) that we are willing to copy.
    public static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .isDirectoryKey])
        return values?.isRegularFile == true && values?.isPackage != true && values?.isDirectory != true
    }

    public static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}
