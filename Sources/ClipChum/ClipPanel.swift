import AppKit
import SwiftUI

/// A floating panel that can take keyboard focus without activating the app,
/// so the app the user is working in stays frontmost.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipPanelController {
    let panel: ClipPanel
    private let model: ClipListModel
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var lastHide = Date.distantPast

    var isVisible: Bool { panel.isVisible }

    init(model: ClipListModel) {
        self.model = model
        let size = ClipListView.size
        panel = ClipPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        let hosting = NSHostingView(rootView: ClipListView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
    }

    /// Show under `anchor` (status item frame in screen coordinates) or near the mouse.
    func show(anchor: NSRect?) {
        // Clicking the status item while open triggers resignKey → hide, then toggle;
        // swallow that re-open.
        guard Date().timeIntervalSince(lastHide) > 0.25 else { return }
        model.prepareForShow()
        position(anchor: anchor)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        lastHide = Date()
    }

    func toggle(anchor: NSRect?) {
        if isVisible { hide() } else { show(anchor: anchor) }
    }

    private func position(anchor: NSRect?) {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin: NSPoint
        if let a = anchor {
            origin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 6)
        } else {
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height + 20)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func installMonitors() {
        removeMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // esc
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        case 125: model.moveSelection(by: 1); return true       // down
        case 126: model.moveSelection(by: -1); return true      // up
        case 36, 76: model.activateSelected(); return true      // return, keypad enter
        case 51 where cmd: model.deleteSelected(); return true  // ⌘⌫
        case 35 where cmd: model.togglePinSelected(); return true // ⌘P
        case 43 where cmd: model.onOpenSettings?(); return true // ⌘,
        default: return false
        }
    }
}
