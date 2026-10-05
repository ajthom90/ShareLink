import Foundation

/// Normalized configuration shared between the app and the extension via App Group defaults.
public final class ConfigStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private enum Key { static let managed = "managedConfiguration.v1"; static let user = "userServers.v1" }

    public init(defaults: UserDefaults) { self.defaults = defaults }
    public static func shared() -> ConfigStore { ConfigStore(defaults: AppGroup.defaults()) }

    public var managed: ManagedConfiguration {
        get { lock.withLock { decode(ManagedConfiguration.self, Key.managed) ?? .empty } }
        set { lock.withLock { encode(newValue, Key.managed) } }
    }

    public var userServers: [ServerConfig] {
        get { lock.withLock { decode([ServerConfig].self, Key.user) ?? [] } }
        set { lock.withLock { encode(newValue, Key.user) } }
    }

    /// Managed servers first, then user servers when allowed.
    public func allServers() -> [ServerConfig] {
        let m = managed
        return m.servers + (m.allowUserServers ? userServers : [])
    }

    public func server(id: String) -> ServerConfig? { allServers().first { $0.id == id } }

    public func saveUserServer(_ server: ServerConfig) {
        var list = userServers
        if let i = list.firstIndex(where: { $0.id == server.id }) { list[i] = server } else { list.append(server) }
        userServers = list
    }

    public func removeUserServer(id: String) { userServers = userServers.filter { $0.id != id } }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
