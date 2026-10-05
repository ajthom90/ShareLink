import Foundation

/// Share-relative paths: "/" separators, no leading/trailing slash, "" is the root.
public enum SMBPath {
    public static func normalize(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .joined(separator: "/")
    }

    public static func join(_ base: String, _ component: String) -> String {
        let a = normalize(base), b = normalize(component)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "/" + b
    }

    public static func parent(of path: String) -> String {
        let p = normalize(path)
        guard let idx = p.lastIndex(of: "/") else { return "" }
        return String(p[..<idx])
    }

    public static func lastComponent(_ path: String) -> String {
        let p = normalize(path)
        guard let idx = p.lastIndex(of: "/") else { return p }
        return String(p[p.index(after: idx)...])
    }
}
