import Foundation
import GRDB

/// The kind of content a clip holds.
public enum ClipKind: String, Codable, Sendable, CaseIterable, Hashable, DatabaseValueConvertible {
    case text
    case richText
    case image
    case fileRef
    case url

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich text"
        case .image: return "Images"
        case .fileRef: return "Files"
        case .url: return "Links"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .fileRef: return "doc"
        case .url: return "link"
        }
    }
}

/// One clipboard entry as stored in SQLite.
public struct Clip: Codable, Identifiable, Sendable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clips"

    public var id: Int64?
    public var kind: ClipKind
    public var createdAt: Date
    public var sourceBundleID: String?

    /// Searchable plain text: the text itself, the URL string, or file names.
    public var text: String?
    public var rtf: Data?
    public var html: String?

    /// File references (one clip may carry several files copied together).
    public var filePaths: [String]?
    public var bookmarks: [Data]?

    /// Content-addressed blob (SHA-256 hex) for stored image bytes or a dereferenced file.
    public var blobHash: String?
    public var byteCount: Int64?

    /// Small PNG preview for images.
    public var thumbnail: Data?
    public var imageWidth: Int?
    public var imageHeight: Int?

    /// Stable hash used for de-duplication.
    public var contentHash: String
    public var pinned: Bool
    /// Raw pasteboard UTIs seen at capture time, for debugging.
    public var pasteboardTypes: String?

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil,
        text: String? = nil,
        rtf: Data? = nil,
        html: String? = nil,
        filePaths: [String]? = nil,
        bookmarks: [Data]? = nil,
        blobHash: String? = nil,
        byteCount: Int64? = nil,
        thumbnail: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        contentHash: String,
        pinned: Bool = false,
        pasteboardTypes: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.text = text
        self.rtf = rtf
        self.html = html
        self.filePaths = filePaths
        self.bookmarks = bookmarks
        self.blobHash = blobHash
        self.byteCount = byteCount
        self.thumbnail = thumbnail
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.contentHash = contentHash
        self.pinned = pinned
        self.pasteboardTypes = pasteboardTypes
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let kind = Column(CodingKeys.kind)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let text = Column(CodingKeys.text)
        public static let contentHash = Column(CodingKeys.contentHash)
        public static let pinned = Column(CodingKeys.pinned)
        public static let blobHash = Column(CodingKeys.blobHash)
    }

    /// A one-line summary suitable for list rows and accessibility.
    public var title: String {
        switch kind {
        case .text, .richText, .url:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "(empty)" : t
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image \(w)×\(h)" }
            return "Image"
        case .fileRef:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.isEmpty ? "File" : names.joined(separator: ", ")
        }
    }
}
