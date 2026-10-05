import Foundation
import CryptoKit

public enum ServerSource: Codable, Hashable, Sendable {
    case managed(slot: Int)
    case user
}

public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var source: ServerSource
    public var displayName: String
    public var host: String
    public var port: Int
    public var share: String
    public var rootPath: String
    public var domain: String
    public var username: String
    public var usernameLocked: Bool
    public var requireEncryption: Bool

    public init(id: String, source: ServerSource, displayName: String, host: String, port: Int = 445,
                share: String, rootPath: String = "", domain: String = "", username: String = "",
                usernameLocked: Bool = false, requireEncryption: Bool = false) {
        self.id = id; self.source = source; self.displayName = displayName; self.host = host
        self.port = port; self.share = share; self.rootPath = SMBPath.normalize(rootPath)
        self.domain = domain; self.username = username; self.usernameLocked = usernameLocked
        self.requireEncryption = requireEncryption
    }

    public var isManaged: Bool {
        if case .managed = source { return true }
        return false
    }

    /// "host/share/path" for display.
    public var summary: String {
        ([host, share] + (rootPath.isEmpty ? [] : [rootPath])).joined(separator: "/")
    }

    public static func defaultDisplayName(host: String, share: String) -> String {
        "\(share) on \(host)"
    }

    public static func managedID(slot: Int, host: String, share: String, rootPath: String) -> String {
        let key = [host.lowercased(), share.lowercased(), SMBPath.normalize(rootPath).lowercased()].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "managed-\(slot)-\(digest.prefix(12))"
    }

    public static func newUserID() -> String { "user-\(UUID().uuidString.lowercased())" }
}

public struct ManagedConfiguration: Codable, Equatable, Sendable {
    public var servers: [ServerConfig]
    public var allowUserServers: Bool
    public var supportMessage: String
    public var issues: [String]

    public init(servers: [ServerConfig] = [], allowUserServers: Bool = true, supportMessage: String = "", issues: [String] = []) {
        self.servers = servers; self.allowUserServers = allowUserServers
        self.supportMessage = supportMessage; self.issues = issues
    }

    public static let empty = ManagedConfiguration()
}
