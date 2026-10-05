import Foundation

public struct Acknowledgement: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var license: String
    public var text: String

    public init(id: String, name: String, license: String, text: String) {
        self.id = id
        self.name = name
        self.license = license
        self.text = text
    }
}

public enum Acknowledgements {
    private static let catalog: [String: (name: String, license: String)] = [
        "ShareLink-MIT": ("ShareLink", "MIT"),
        "AMSMB2": ("AMSMB2", "LGPL-2.1"),
        "GRDB.swift": ("GRDB.swift", "MIT"),
        "libsmb2": ("libsmb2", "LGPL-2.1-or-later"),
    ]

    /// Reads the copied `Licenses/*.txt` resources. ShareLink is first; the rest are alphabetical.
    public static func all() -> [Acknowledgement] {
        guard let directory = licenseDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let items: [Acknowledgement] = urls.compactMap { url in
            guard url.pathExtension == "txt" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            guard let info = catalog[stem],
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Acknowledgement(id: info.name, name: info.name, license: info.license, text: text)
        }
        let shareLink = items.filter { $0.name == "ShareLink" }
        let rest = items
            .filter { $0.name != "ShareLink" }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return shareLink + rest
    }

    private static func licenseDirectory() -> URL? {
        if let url = Bundle.module.url(forResource: "Licenses", withExtension: nil) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return Bundle.module.url(forResource: "ShareLink-MIT", withExtension: "txt", subdirectory: "Licenses")?
            .deletingLastPathComponent()
    }
}
