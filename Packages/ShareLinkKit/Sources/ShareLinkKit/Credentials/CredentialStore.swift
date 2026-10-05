import Foundation
import Security

public struct Credential: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
}

public protocol CredentialStoring: Sendable {
    func credential(for serverID: String) throws -> Credential?
    func setCredential(_ credential: Credential, for serverID: String) throws
    func removeCredential(for serverID: String) throws
}

public struct KeychainError: Error, Equatable { public let status: OSStatus }

public struct KeychainCredentialStore: CredentialStoring {
    public static let service = "com.ajthom90.sharelink"
    private let accessGroup: String?

    public init(accessGroup: String? = AppGroup.identifier) { self.accessGroup = accessGroup }

    private func baseQuery(_ serverID: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: serverID,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func credential(for serverID: String) throws -> Credential? {
        var q = baseQuery(serverID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    public func setCredential(_ credential: Credential, for serverID: String) throws {
        let data = try JSONEncoder().encode(credential)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(serverID) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let add = baseQuery(serverID).merging(attrs) { $1 }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func removeCredential(for serverID: String) throws {
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var items: [String: Credential] = [:]
    private let lock = NSLock()
    public init() {}
    public func credential(for serverID: String) throws -> Credential? { lock.withLock { items[serverID] } }
    public func setCredential(_ credential: Credential, for serverID: String) throws { lock.withLock { items[serverID] = credential } }
    public func removeCredential(for serverID: String) throws { lock.withLock { _ = items.removeValue(forKey: serverID) } }
}
