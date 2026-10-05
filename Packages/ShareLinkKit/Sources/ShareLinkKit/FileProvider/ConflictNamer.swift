import Foundation

public enum ConflictNamer {
    /// `"Report (Conflict iPad 2026-10-05 1432).docx"`. Names without an extension have no trailing dot.
    public static func name(for filename: String, device: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: date)
        let file = filename as NSString
        let ext = file.pathExtension
        let base = file.deletingPathExtension
        let stem = "\(base) (Conflict \(device) \(stamp))"
        if ext.isEmpty { return stem }
        return "\(stem).\(ext)"
    }
}
