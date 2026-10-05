import Foundation
import os

public enum Log {
    public static let app = Logger(subsystem: "com.ajthom90.sharelink", category: "app")
    public static let provider = Logger(subsystem: "com.ajthom90.sharelink", category: "provider")
    public static let smb = Logger(subsystem: "com.ajthom90.sharelink", category: "smb")
}

/// Append-only diagnostic file shared by the app and the extension.
/// Callers must pass only operation names, error case names, and counts — never
/// hostnames, usernames, paths, file names, or secrets.
public enum DiagnosticLog {
    private static let state = State()
    private static let maxBytes = 256 * 1024
    private static let retainedLines = 500

    private final class State: @unchecked Sendable {
        let lock = NSLock()
    }

    private static func logURL() -> URL {
        AppGroup.containerURL().appendingPathComponent("diagnostics.log")
    }

    public static func append(_ line: String) {
        state.lock.lock()
        defer { state.lock.unlock() }
        let url = logURL()
        let record = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(record.utf8))
        } catch {
            return
        }
        trimIfNeeded(at: url)
    }

    public static func tail(_ n: Int) -> [String] {
        guard n > 0 else { return [] }
        state.lock.lock()
        defer { state.lock.unlock() }
        return Array(lines(at: logURL()).suffix(n))
    }

    private static func trimIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > maxBytes else { return }
        let kept = lines(at: url).suffix(retainedLines)
        let text = kept.joined(separator: "\n")
        let output = text.isEmpty ? "" : text + "\n"
        try? Data(output.utf8).write(to: url, options: .atomic)
    }

    private static func lines(at url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}
