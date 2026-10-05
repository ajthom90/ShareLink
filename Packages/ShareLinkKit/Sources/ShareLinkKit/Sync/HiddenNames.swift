import Foundation

public enum HiddenNames {
    private static let exactNames: Set<String> = [
        "thumbs.db",
        "desktop.ini",
        "$recycle.bin",
        "system volume information",
    ]

    public static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("~$") || exactNames.contains(name.lowercased())
    }
}
