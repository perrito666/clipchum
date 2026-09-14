import AppKit
import ClipChumCore
import SwiftUI

struct ClipRowView: View {
    let clip: Clip
    let isSelected: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                primary
                meta
            }
            Spacer(minLength: 0)
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .opacity(fileMissing ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.kind.displayName): \(clip.title)")
    }

    // MARK: - Pieces

    @ViewBuilder private var leading: some View {
        switch clip.kind {
        case .image:
            if let data = clip.thumbnail, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            } else {
                symbol
            }
        case .fileRef:
            if let path = clip.filePaths?.first {
                Image(nsImage: AppInfo.fileIcon(path: path))
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                symbol
            }
        default:
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: clip.kind.symbolName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    @ViewBuilder private var primary: some View {
        switch clip.kind {
        case .text, .richText:
            Text(previewText)
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.tail)
        case .url:
            VStack(alignment: .leading, spacing: 1) {
                Text(urlHost).font(.system(size: 13, weight: .semibold))
                Text(clip.text ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        case .image:
            Text(clip.title).font(.system(size: 13, weight: .medium))
        case .fileRef:
            VStack(alignment: .leading, spacing: 1) {
                Text(fileNames).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(fileMissing ? "Missing · \(parentPath)" : parentPath)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            badge
            if let app = clip.sourceBundleID {
                HStack(spacing: 3) {
                    if let icon = AppInfo.icon(for: app) {
                        Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                    }
                    Text(AppInfo.name(for: app)).lineLimit(1)
                }
            }
            Text(Self.relative.localizedString(for: clip.createdAt, relativeTo: Date()))
            if let size = sizeText { Text(size) }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }

    private var badge: some View {
        Text(badgeText)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(.quaternary.opacity(0.7)))
    }

    // MARK: - Derived

    private var previewText: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "(whitespace)" : t
    }

    private var badgeText: String {
        switch clip.kind {
        case .text: return "\(clip.text?.count ?? 0) chars"
        case .richText: return clip.rtf != nil ? "RTF" : "HTML"
        case .image: return clip.blobHash == nil ? "Preview only" : "PNG"
        case .fileRef:
            let n = clip.filePaths?.count ?? 0
            if clip.blobHash != nil { return "Stored copy" }
            return n > 1 ? "\(n) files" : "Reference"
        case .url: return "Link"
        }
    }

    private var sizeText: String? {
        guard let b = clip.byteCount, b > 0, clip.kind == .image || clip.kind == .fileRef else { return nil }
        return Self.bytes.string(fromByteCount: b)
    }

    private var urlHost: String {
        guard let s = clip.text, let u = URL(string: s) else { return clip.text ?? "" }
        return u.host ?? s
    }

    private var fileNames: String {
        (clip.filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    private var parentPath: String {
        guard let p = clip.filePaths?.first else { return "" }
        return (p as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var fileMissing: Bool {
        guard clip.kind == .fileRef, let paths = clip.filePaths else { return false }
        if clip.blobHash != nil { return false }
        let bookmarks = clip.bookmarks ?? []
        for (i, p) in paths.enumerated() {
            let bm = i < bookmarks.count && !bookmarks[i].isEmpty ? bookmarks[i] : nil
            if FileReference.resolve(bookmark: bm, path: p).exists { return false }
        }
        return true
    }
}
