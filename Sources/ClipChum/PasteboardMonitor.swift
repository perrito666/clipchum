import AppKit
import ClipChumCore

/// Polls `NSPasteboard.general.changeCount` and feeds changes to the ingester.
/// macOS offers no notification for pasteboard changes; polling an integer is the
/// standard approach and costs next to nothing.
@MainActor
final class PasteboardMonitor {
    private let ingester: Ingester
    private let settings: SettingsStore
    private let paste: PasteService
    private var timer: Timer?
    private var lastChangeCount: Int
    private var activeInterval: Double = 0

    init(ingester: Ingester, settings: SettingsStore, paste: PasteService) {
        self.ingester = ingester
        self.settings = settings
        self.paste = paste
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let interval = settings.settings.pollInterval
        guard timer == nil || interval != activeInterval else { return }
        timer?.invalidate()
        activeInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Check the pasteboard right now (used after a ⌘C is observed, or on demand).
    func tick() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if count == paste.lastWrittenChangeCount { return }

        let typeNames = (pb.types ?? []).map(\.rawValue)
        guard let parsed = PasteboardParser.parse(pb) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let current = settings.settings
        let ingester = self.ingester
        Task.detached(priority: .utility) {
            do {
                let outcome = try ingester.ingest(parsed, settings: current, sourceBundleID: source, pasteboardTypes: typeNames)
                if case .skipped(let reason) = outcome {
                    NSLog("ClipChum: skipped clip (\(reason))")
                }
            } catch {
                NSLog("ClipChum: failed to store clip: \(error)")
            }
        }
    }
}
