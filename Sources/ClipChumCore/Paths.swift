import Foundation

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClipChum", isDirectory: true)
    }
    public static var databaseURL: URL { supportDirectory.appendingPathComponent("clipchum.sqlite") }
    public static var blobsDirectory: URL { supportDirectory.appendingPathComponent("Blobs", isDirectory: true) }
}
