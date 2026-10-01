import AppKit
import ClipChumCore
import KeyboardShortcuts

/// `ClipChum --smoke-test`: exercise storage, parsing and UI construction against a
/// throwaway directory, then exit. Used by CI on a runner with no clipboard to speak of.
enum SmokeTest {
    static func run() -> Never {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipchum-smoke-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let store = try ClipStore(path: dir.appendingPathComponent("clipchum.sqlite").path)
            let blobs = try BlobStore(directory: dir.appendingPathComponent("Blobs"))
            let ingester = Ingester(store: store, blobs: blobs)
            var settings = Settings()
            settings.maxItems = 5

            guard let text = PasteboardParser.parse(FakePasteboard.text("aardvark lantern clip")) else {
                throw Failure("parser returned nothing for plain text")
            }
            guard case .stored = try ingester.ingest(text, settings: settings, sourceBundleID: "to.perri.clipchum.smoke") else {
                throw Failure("text clip was not stored")
            }
            let file = dir.appendingPathComponent("hello.txt")
            try Data("hello".utf8).write(to: file)
            settings.dereferenceFiles = true
            guard case .stored(let clip, _) = try ingester.ingest(.files([file]), settings: settings, sourceBundleID: nil),
                  let hash = clip.blobHash, blobs.contains(hash) else {
                throw Failure("file clip was not dereferenced")
            }
            // Prefix search over text; the temp path must not contain the token.
            let hits = try store.search("aardv", limit: 10)
            guard hits.count == 1, hits.first?.kind == .text else {
                throw Failure("text search returned \(hits.map { "\($0.kind.rawValue):\($0.text ?? "")" })")
            }
            guard try store.search("hello", limit: 10).count == 1 else { throw Failure("file search found no match") }

            // Build the UI objects without running the app: catches crashes in view setup.
            _ = NSApplication.shared
            MainActor.assumeIsolated {
                // A private board and in-memory settings: the user's clipboard and
                // preferences are left alone, and no ⌘V is ever simulated.
                let board = NSPasteboard.withUniqueName()
                defer { board.releaseGlobally() }
                let paste = PasteService(blobs: blobs, pasteboard: board)
                let settingsStore = SettingsStore(ephemeral: settings)
                let model = ClipListModel(store: store, blobs: blobs, settings: settingsStore, paste: paste)
                let panel = ClipPanelController(model: model)
                precondition(model.items.count == 2, "panel model should see both clips")
                precondition(!panel.isVisible)

                // Picking an older clip copies it and promotes it to the top.
                precondition(model.items.map(\.kind) == [.fileRef, .text], "newest clip should be first")
                model.activate(model.items[1])
                model.reload()
                precondition(board.string(forType: .string) == "aardvark lantern clip", "picked clip should be on the pasteboard")
                precondition(model.items.map(\.kind) == [.text, .fileRef], "picked clip should move to the top")
                precondition(model.items.count == 2, "promotion must not duplicate the clip")

                // The settings window and its shortcut recorder. The recorder's labels live
                // in KeyboardShortcuts' resource bundle; when the app cannot find that
                // bundle the lookup traps, so this crashes for a badly packaged app.
                let actions = SettingsActions(clearHistory: {}, storageSummary: { "" }, openStorageFolder: {})
                let settingsWindow = SettingsWindowController(store: settingsStore, actions: actions)
                settingsWindow.window?.layoutIfNeeded()
                _ = KeyboardShortcuts.RecorderCocoa(for: .togglePanel)
            }
            try? FileManager.default.removeItem(at: dir)
            print("smoke test passed")
            exit(0)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            FileHandle.standardError.write(Data("smoke test failed: \(error)\n".utf8))
            exit(1)
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}
