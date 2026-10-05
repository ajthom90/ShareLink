import Foundation

public enum ManagedConfigParser {
    public static let maxShares = 10
    public static let managedConfigKey = "com.apple.configuration.managed"

    public static func parse(_ dict: [String: Any]) -> ManagedConfiguration {
        var result = ManagedConfiguration.empty
        result.allowUserServers = LenientValue.bool(dict["AllowUserServers"]) ?? true
        result.supportMessage = LenientValue.string(dict["SupportMessage"]) ?? ""

        for slot in 1...maxShares {
            let prefix = slot == 1 ? "" : "Share\(slot)."
            func value(_ key: String) -> Any? { dict[prefix + key] }
            let host = LenientValue.string(value("Host"))
            let share = LenientValue.string(value("Share"))
            // Consoles upload default Port/RequireEncryption for unused slots. Those are not a share.
            guard host != nil || share != nil else { continue }
            var missing: [String] = []
            if host == nil { missing.append("Host") }
            if share == nil { missing.append("Share") }
            if !missing.isEmpty {
                result.issues.append("Share \(slot): missing \(missing.map { prefix + $0 }.joined(separator: ", "))")
                continue
            }

            var port = 445
            switch LenientValue.int(value("Port")) {
            case .success(let p) where (1...65535).contains(p): port = p
            case .success, .failure:
                result.issues.append("Share \(slot): invalid \(prefix)Port, using 445")
            case nil: break
            }

            let rootPath = SMBPath.normalize(LenientValue.string(value("Path")) ?? "")
            result.servers.append(ServerConfig(
                id: ServerConfig.managedID(slot: slot, host: host!, share: share!, rootPath: rootPath),
                source: .managed(slot: slot),
                displayName: LenientValue.string(value("DisplayName")) ?? ServerConfig.defaultDisplayName(host: host!, share: share!),
                host: host!, port: port, share: share!, rootPath: rootPath,
                domain: LenientValue.string(value("Domain")) ?? "",
                username: LenientValue.string(value("Username")) ?? "",
                usernameLocked: LenientValue.bool(value("UsernameLocked")) ?? false,
                requireEncryption: LenientValue.bool(value("RequireEncryption")) ?? false
            ))
        }
        return result
    }
}
