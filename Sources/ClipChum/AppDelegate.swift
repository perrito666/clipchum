import AppKit
import ClipChumCore
import KeyboardShortcuts
import notify

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var store: ClipStore!
    private var blobs: BlobStore!
    private var ingester: Ingester!
    private var paste: PasteService!
    private var monitor: PasteboardMonitor!
    private var statusItem: StatusItemController!
    private var panel: ClipPanelController!
    private var model: ClipListModel!
    private var settingsWindow: SettingsWindowController?
    private var toggleToken: Int32 = 0
    private var settingsToken: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
            store = try ClipStore(path: AppPaths.databaseURL.path)
            blobs = try BlobStore(directory: AppPaths.blobsDirectory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "ClipChum could not open its database"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        settings = SettingsStore()
        ingester = Ingester(store: store, blobs: blobs)
        paste = PasteService(blobs: blobs)
        model = ClipListModel(store: store, blobs: blobs, settings: settings, paste: paste)
        panel = ClipPanelController(model: model)
        model.onDismiss = { [weak self] in self?.panel.hide() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.togglePanel() },
            onSettings: { [weak self] in self?.showSettings() }
        )

        monitor = PasteboardMonitor(ingester: ingester, settings: settings, paste: paste)
        monitor.start()

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel(fromHotkey: true)
        }

        // Apply a lowered limit and sweep unreferenced blobs in the background.
        let ingester = self.ingester!
        let maxItems = settings.settings.maxItems
        Task.detached(priority: .background) {
            _ = try? ingester.store.prune(maxItems: maxItems)
            _ = try? ingester.collectGarbage()
        }
        observeSettings()

        // Scriptable toggle, e.g. from a launcher:  notifyutil -p to.perri.clipchum.toggle
        notify_register_dispatch("to.perri.clipchum.toggle", &toggleToken, DispatchQueue.main) { [weak self] _ in
            self?.togglePanel(fromHotkey: true)
        }
        notify_register_dispatch("to.perri.clipchum.settings", &settingsToken, DispatchQueue.main) { [weak self] _ in
            self?.showSettings()
        }
    }

    private var lastSettings: Settings?
    private func observeSettings() {
        lastSettings = settings.settings
        withObservationTracking {
            _ = settings.settings
        } onChange: { [weak self] in
            Task { @MainActor in self?.settingsDidChange() }
        }
    }

    private func settingsDidChange() {
        let new = settings.settings
        defer { observeSettings() }
        guard let old = lastSettings, old != new else { return }
        if old.pollInterval != new.pollInterval { monitor.start() }
        if new.maxItems < old.maxItems {
            let ingester = self.ingester!
            Task.detached(priority: .utility) {
                _ = try? ingester.store.prune(maxItems: new.maxItems)
                _ = try? ingester.collectGarbage()
            }
        }
        if old.showCount != new.showCount { model.reload() }
    }

    func togglePanel(fromHotkey: Bool = false) {
        settingsWindow?.window?.orderOut(nil)
        panel.toggle(anchor: fromHotkey ? nil : statusItem.buttonFrame)
    }

    func showSettings() {
        panel.hide()
        if settingsWindow == nil {
            let store = self.store!, blobs = self.blobs!, ingester = self.ingester!
            let actions = SettingsActions(
                clearHistory: {
                    try? store.clearAll()
                    try? ingester.collectGarbage()
                },
                storageSummary: {
                    let f = ByteCountFormatter()
                    let count = (try? store.count()) ?? 0
                    let dbSize = (try? FileManager.default.attributesOfItem(atPath: AppPaths.databaseURL.path)[.size] as? Int64) ?? 0
                    return "\(count) clips · database \(f.string(fromByteCount: dbSize)) · blobs \(f.string(fromByteCount: blobs.totalBytes()))"
                },
                openStorageFolder: {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.databaseURL])
                }
            )
            settingsWindow = SettingsWindowController(store: settings, actions: actions)
        }
        settingsWindow?.present()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
