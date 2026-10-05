import Foundation

public enum AppGroup {
    public static let identifier = "group.com.ajthom90.sharelink"
    public static let deviceModelKey = "deviceModel"

    /// App Group container; falls back to a temp directory when the entitlement is
    /// missing (unit tests on macOS, previews).
    public static func containerURL() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("ShareLinkAppGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static func domainDirectory(for serverID: String) -> URL {
        let safe = serverID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return containerURL()
            .appendingPathComponent("Domains", isDirectory: true)
            .appendingPathComponent(String(safe), isDirectory: true)
    }

    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
