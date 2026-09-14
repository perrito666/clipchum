import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let onToggle: () -> Void
    private let onSettings: () -> Void

    init(onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSettings = onSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipChum")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ClipChum — clipboard history"
        }
    }

    /// Screen-space frame of the status button, for positioning the panel.
    var buttonFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @objc private func clicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Clips", action: #selector(menuToggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipChum", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuToggle() { onToggle() }
    @objc private func menuSettings() { onSettings() }
}
