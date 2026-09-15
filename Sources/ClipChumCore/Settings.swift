import Foundation

/// User-configurable behaviour. Persisted as JSON in UserDefaults.
public struct Settings: Codable, Equatable, Sendable {
    /// Number of most recent clips shown when the panel opens without a query.
    public var showCount: Int = 10
    /// Maximum number of clips kept in the database (pinned clips do not count).
    public var maxItems: Int = 500
    /// Kinds of clips that are recorded at all.
    public var enabledKinds: Set<ClipKind> = Set(ClipKind.allCases)
    /// Keep full image bytes (as opposed to only a thumbnail).
    public var storeImageData: Bool = true
    public var imageCapMB: Int = 20
    /// Copy file contents into the blob store instead of only keeping a reference.
    public var dereferenceFiles: Bool = false
    public var fileCapMB: Int = 50
    /// Bundle identifiers whose copies are ignored.
    public var excludedApps: [String] = []
    /// Simulate ⌘V after selecting a clip (requires Accessibility permission).
    public var pasteDirectly: Bool = false
    /// Poll interval for the pasteboard change counter.
    public var pollInterval: Double = 0.4

    public init() {}

    public var imageCapBytes: Int64 { Int64(imageCapMB) * 1_048_576 }
    public var fileCapBytes: Int64 { Int64(fileCapMB) * 1_048_576 }

    /// Clamp values to sane ranges.
    public func normalized() -> Settings {
        var s = self
        s.showCount = min(max(s.showCount, 1), 200)
        s.maxItems = min(max(s.maxItems, s.showCount), 100_000)
        s.imageCapMB = max(1, s.imageCapMB)
        s.fileCapMB = max(1, s.fileCapMB)
        s.pollInterval = min(max(s.pollInterval, 0.1), 5)
        return s
    }

    private static let defaultsKey = "to.perri.clipchum.settings"

    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s.normalized()
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized()) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
