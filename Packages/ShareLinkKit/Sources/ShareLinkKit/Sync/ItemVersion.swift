import Foundation

public enum ItemVersion {
    /// `"<size>-<nanoseconds since 1970>"`. Directories always use size 0.
    public static func content(size: Int64, modified: Date, isDirectory: Bool) -> Data {
        let nanos = Int64((modified.timeIntervalSince1970 * 1_000_000_000).rounded())
        return Data("\(isDirectory ? 0 : size)-\(nanos)".utf8)
    }

    public static func metadata(content: Data, name: String) -> Data {
        var data = content
        data.append(contentsOf: "-\(name)".utf8)
        return data
    }
}
