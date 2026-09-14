import AppKit
import Testing
@testable import ClipChumCore

@Suite struct PasteboardParserTests {
    @Test func plainText() {
        let parsed = PasteboardParser.parse(FakePasteboard.text("hello world"))
        #expect(parsed == .text("hello world"))
    }

    @Test func urlDetectedFromPlainText() {
        let parsed = PasteboardParser.parse(FakePasteboard.text("https://example.com/path?q=1"))
        #expect(parsed == .url("https://example.com/path?q=1"))
    }

    @Test func textWithSpacesIsNotURL() {
        let parsed = PasteboardParser.parse(FakePasteboard.text("see https://example.com now"))
        #expect(parsed?.kind == .text)
    }

    @Test func concealedIsSkipped() {
        var pb = FakePasteboard.text("hunter2")
        pb.items["org.nspasteboard.ConcealedType"] = Data()
        #expect(PasteboardParser.parse(pb) == nil)
    }

    @Test func ownMarkerIsSkipped() {
        var pb = FakePasteboard.text("ours")
        pb.items[PasteboardParser.internalMarker.rawValue] = Data()
        #expect(PasteboardParser.parse(pb) == nil)
    }

    @Test func filesWinOverText() {
        var pb = FakePasteboard.text("/tmp/a.txt")
        pb.files = [URL(fileURLWithPath: "/tmp/a.txt")]
        #expect(PasteboardParser.parse(pb) == .files([URL(fileURLWithPath: "/tmp/a.txt")]))
    }

    @Test func richTextKeepsPlainPreview() {
        let attributed = NSAttributedString(string: "Bold idea", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
        var pb = FakePasteboard.text("Bold idea")
        pb.items[NSPasteboard.PasteboardType.rtf.rawValue] = rtf
        guard case .richText(let plain, let rtfData, _)? = PasteboardParser.parse(pb) else {
            Issue.record("expected rich text"); return
        }
        #expect(plain == "Bold idea")
        #expect(rtfData == rtf)
    }

    @Test func imageIsNormalisedToPNG() {
        let image = NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let tiff = image.tiffRepresentation!
        var pb = FakePasteboard()
        pb.items[NSPasteboard.PasteboardType.tiff.rawValue] = tiff
        guard case .image(let png, let w, let h)? = PasteboardParser.parse(pb) else {
            Issue.record("expected image"); return
        }
        #expect(w == 4 && h == 3)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func contentHashIsStable() {
        let a = PasteboardParser.contentHash(for: .text("x"))
        let b = PasteboardParser.contentHash(for: .text("x"))
        let c = PasteboardParser.contentHash(for: .url("x"))
        #expect(a == b)
        #expect(a != c)
    }
}
