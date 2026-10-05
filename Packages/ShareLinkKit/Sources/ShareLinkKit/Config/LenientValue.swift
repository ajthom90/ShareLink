import Foundation

/// Tolerant conversions for MDM values, which may arrive typed or as strings.
enum LenientValue {
    static func string(_ value: Any?) -> String? {
        let raw: String?
        switch value {
        case let s as String: raw = s
        case let n as NSNumber: raw = n.stringValue
        default: raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// nil = absent; .failure = present but unparseable.
    static func int(_ value: Any?) -> Result<Int, Error>? {
        guard let value else { return nil }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return .success(n.intValue) }
        if let s = string(value), let i = Int(s) { return .success(i) }
        if string(value) == nil { return nil }
        return .failure(CocoaError(.formatting))
    }

    static func bool(_ value: Any?) -> Bool? {
        if let n = value as? NSNumber { return n.boolValue }
        guard let s = string(value)?.lowercased() else { return nil }
        if ["true", "yes", "1", "on"].contains(s) { return true }
        if ["false", "no", "0", "off"].contains(s) { return false }
        return nil
    }
}
