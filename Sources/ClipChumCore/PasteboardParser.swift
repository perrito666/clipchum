import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// What the parser extracted from one pasteboard change, before any storage decisions.
public enum ParsedClip: Sendable, Equatable {
    case text(String)
    case richText(plain: String, rtf: Data?, html: String?)
    case image(png: Data, width: Int, height: Int)
    case files([URL])
    case url(String)

    public var kind: ClipKind {
        switch self {
        case .text: return .text
        case .richText: return .richText
        case .image: return .image
        case .files: return .fileRef
        case .url: return .url
        }
    }
}

public enum PasteboardParser {
    /// Marker we add to our own pasteboard writes so the monitor ignores them.
    public static let internalMarker = NSPasteboard.PasteboardType("to.perri.clipchum.internal")

    /// Types that password managers and similar tools use to ask managers to look away.
    public static let skipTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        internalMarker.rawValue,
    ]

    public static let rtfType = NSPasteboard.PasteboardType.rtf
    public static let htmlType = NSPasteboard.PasteboardType.html

    /// Returns true when the board carries a type we must not record.
    public static func shouldSkip(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { skipTypes.contains($0.rawValue) }
    }

    /// Extract the most meaningful representation from the board.
    /// Priority: files → image → rich text → URL → plain text.
    public static func parse(_ board: PasteboardReading) -> ParsedClip? {
        guard let types = board.types, !types.isEmpty else { return nil }
        if shouldSkip(types) { return nil }
        let typeSet = Set(types.map(\.rawValue))

        // 1. Files copied from Finder or dragged out of an app.
        if typeSet.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            let urls = board.fileURLs()
            if !urls.isEmpty { return .files(urls) }
        }

        // 2. Image bytes.
        if let png = imagePNG(from: board, typeSet: typeSet) {
            return .image(png: png.data, width: png.width, height: png.height)
        }

        let plain = board.string(forType: .string)

        // 3. Rich text.
        let rtf = typeSet.contains(rtfType.rawValue) ? board.data(forType: rtfType) : nil
        let html = typeSet.contains(htmlType.rawValue) ? board.string(forType: htmlType) : nil
        if rtf != nil || html != nil {
            let text = plain ?? rtf.flatMap(plainText(fromRTF:)) ?? html.map(plainText(fromHTML:)) ?? ""
            // Some apps put RTF on the board for what is really a plain URL.
            if let u = urlString(plain: text, typeSet: typeSet, board: board), rtf == nil {
                return .url(u)
            }
            return .richText(plain: text, rtf: rtf, html: html)
        }

        // 4. A URL, either as public.url or as a bare link in the text.
        if let u = urlString(plain: plain, typeSet: typeSet, board: board) {
            return .url(u)
        }

        // 5. Plain text.
        if let plain, !plain.isEmpty {
            return .text(plain)
        }
        return nil
    }

    // MARK: - Helpers

    private static func urlString(plain: String?, typeSet: Set<String>, board: PasteboardReading) -> String? {
        if typeSet.contains(NSPasteboard.PasteboardType.URL.rawValue),
           let s = board.string(forType: .URL)?.trimmingCharacters(in: .whitespacesAndNewlines),
           isWebURL(s) {
            return s
        }
        if let p = plain?.trimmingCharacters(in: .whitespacesAndNewlines), isWebURL(p) {
            return p
        }
        return nil
    }

    static func isWebURL(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else { return false }
        return ["http", "https", "ftp", "mailto"].contains(scheme) || scheme.count > 1
    }

    private static func imagePNG(from board: PasteboardReading, typeSet: Set<String>) -> (data: Data, width: Int, height: Int)? {
        // Prefer PNG, then TIFF. Ignore image types when a file URL is present (handled earlier).
        let candidates: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in candidates where typeSet.contains(type.rawValue) {
            guard let data = board.data(forType: type), !data.isEmpty else { continue }
            return ImageProcessing.normalizePNG(data)
        }
        return nil
    }

    static func plainText(fromRTF data: Data) -> String? {
        NSAttributedString(rtf: data, documentAttributes: nil)?.string
    }

    static func plainText(fromHTML html: String) -> String {
        // Cheap tag strip; good enough for previews when no plain-text representation exists.
        var out = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { out.append(ch) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stable content hash for de-duplication.
    public static func contentHash(for parsed: ParsedClip) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(parsed.kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        switch parsed {
        case .text(let s), .url(let s):
            hasher.update(data: Data(s.utf8))
        case .richText(let plain, let rtf, let html):
            hasher.update(data: Data(plain.utf8))
            if let rtf { hasher.update(data: rtf) } else if let html { hasher.update(data: Data(html.utf8)) }
        case .image(let png, _, _):
            hasher.update(data: png)
        case .files(let urls):
            hasher.update(data: Data(urls.map(\.path).joined(separator: "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
