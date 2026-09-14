import AppKit
import ClipChumCore
import GRDB
import Observation

/// State behind the panel: current query, visible items, keyboard selection.
@Observable
@MainActor
final class ClipListModel {
    let store: ClipStore
    let blobs: BlobStore
    let settings: SettingsStore
    let paste: PasteService

    var query: String = "" {
        didSet { if query != oldValue { reload() } }
    }
    private(set) var items: [Clip] = []
    var selectedIndex: Int = 0
    /// Bumped every time the panel is shown so the search field re-takes focus.
    private(set) var focusToken: Int = 0
    var status: String?

    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    @ObservationIgnored private var observer: AnyDatabaseCancellable?
    @ObservationIgnored private var statusResetTask: Task<Void, Never>?

    init(store: ClipStore, blobs: BlobStore, settings: SettingsStore, paste: PasteService) {
        self.store = store
        self.blobs = blobs
        self.settings = settings
        self.paste = paste
        observer = store.observeChanges().start(in: store.dbQueue, onError: { error in
            NSLog("ClipChum: observation error \(error)")
        }, onChange: { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
        reload()
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func prepareForShow() {
        query = ""
        selectedIndex = 0
        status = nil
        focusToken += 1
        reload()
    }

    func reload() {
        do {
            if isSearching {
                items = try store.search(query, limit: 200)
            } else {
                items = try store.recent(limit: settings.settings.showCount)
            }
        } catch {
            NSLog("ClipChum: reload failed \(error)")
            items = []
        }
        if items.isEmpty { selectedIndex = 0 } else { selectedIndex = min(selectedIndex, items.count - 1) }
    }

    var footerText: String {
        let total = (try? store.count()) ?? 0
        if isSearching { return "\(items.count) match\(items.count == 1 ? "" : "es") in \(total) clips" }
        return "Showing \(items.count) of \(total) clips · ↩ copy · ⌘⌫ delete · ⌘P pin"
    }

    // MARK: - Keyboard

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func activateSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        activate(items[selectedIndex])
    }

    func deleteSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        delete(items[selectedIndex])
    }

    func togglePinSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        togglePin(items[selectedIndex])
    }

    // MARK: - Actions

    func activate(_ clip: Clip) {
        guard paste.copy(clip) else {
            flash("File is no longer available")
            return
        }
        // Re-copying moves the clip to the top; do it through the store so the
        // pasteboard monitor's dedupe path is not needed.
        if let id = clip.id {
            try? store.dbQueue.write { db in
                try db.execute(sql: "UPDATE clips SET createdAt = ? WHERE id = ?", arguments: [Date(), id])
            }
        }
        onDismiss?()
        if settings.settings.pasteDirectly {
            if PasteService.isAccessibilityTrusted(prompt: true) {
                let paste = self.paste
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    paste.pasteIntoFrontmostApp()
                }
            }
        }
    }

    func delete(_ clip: Clip) {
        guard let id = clip.id else { return }
        do {
            if let removed = try store.delete(id: id), let hash = removed.blobHash,
               !(try store.referencedBlobHashes()).contains(hash) {
                blobs.remove(hash)
            }
        } catch {
            NSLog("ClipChum: delete failed \(error)")
        }
    }

    func togglePin(_ clip: Clip) {
        guard let id = clip.id else { return }
        try? store.setPinned(id: id, !clip.pinned)
    }

    func revealInFinder(_ clip: Clip) {
        let urls = paste.resolvedFileURLs(for: clip)
        guard !urls.isEmpty else { flash("File is no longer available"); return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        onDismiss?()
    }

    func openURL(_ clip: Clip) {
        guard clip.kind == .url, let s = clip.text, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
        onDismiss?()
    }

    private func flash(_ message: String) {
        status = message
        statusResetTask?.cancel()
        statusResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { status = nil }
        }
    }
}
