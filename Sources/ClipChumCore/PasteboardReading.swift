import AppKit

/// Abstraction over `NSPasteboard` so the parser can be tested with synthetic boards.
public protocol PasteboardReading {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    /// File URLs on the board, in order.
    func fileURLs() -> [URL]
}

extension NSPasteboard: PasteboardReading {
    public func fileURLs() -> [URL] {
        let objects = readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return objects ?? []
    }
}

/// In-memory pasteboard for tests.
public struct FakePasteboard: PasteboardReading, Sendable {
    public var changeCount: Int
    public var items: [String: Data]
    public var files: [URL]

    public init(changeCount: Int = 1, items: [String: Data] = [:], files: [URL] = []) {
        self.changeCount = changeCount
        self.items = items
        self.files = files
    }

    public static func text(_ s: String) -> FakePasteboard {
        FakePasteboard(items: [NSPasteboard.PasteboardType.string.rawValue: Data(s.utf8)])
    }

    public var types: [NSPasteboard.PasteboardType]? {
        var t = items.keys.map { NSPasteboard.PasteboardType($0) }
        if !files.isEmpty { t.append(.fileURL) }
        return t.isEmpty ? nil : t
    }

    public func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        items[type.rawValue]
    }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        items[type.rawValue].flatMap { String(data: $0, encoding: .utf8) }
    }

    public func fileURLs() -> [URL] { files }
}
