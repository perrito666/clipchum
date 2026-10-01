import ClipChumCore
import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    var settings: Settings {
        didSet { if persists { settings.save() } }
    }
    private let persists: Bool

    init() {
        settings = Settings.load()
        persists = true
    }

    /// In-memory settings that never touch UserDefaults (smoke test).
    init(ephemeral settings: Settings) {
        self.settings = settings
        persists = false
    }
}
