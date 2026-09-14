import ClipChumCore
import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    var settings: Settings {
        didSet { settings.save() }
    }

    init() {
        settings = Settings.load()
    }
}
