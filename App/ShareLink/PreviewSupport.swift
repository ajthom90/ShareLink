#if DEBUG
import Foundation
import ShareLinkKit

struct PreviewDomainManager: DomainManaging {
    func domains() async throws -> [DomainInfo] { [] }
    func addOrUpdate(id: String, displayName: String) async throws {}
    func remove(id: String) async throws {}
    func signalWorkingSet(id: String) async {}
    func evictAll(id: String) async {}
    func userVisibleRootURL(id: String) async -> URL? { nil }
    func isUserEnabled(id: String) async -> Bool? { nil }
}

@MainActor
enum PreviewData {
    static func model(
        allowUserServers: Bool = true,
        supportMessage: String = "",
        issues: [String] = [],
        servers: [ServerConfig] = []
    ) -> AppModel {
        let defaults = UserDefaults(suiteName: "sharelink-preview-\(UUID().uuidString)")!
        let store = ConfigStore(defaults: defaults)
        store.managed = ManagedConfiguration(
            servers: servers.filter(\.isManaged),
            allowUserServers: allowUserServers,
            supportMessage: supportMessage,
            issues: issues
        )
        store.userServers = servers.filter { !$0.isManaged }
        return AppModel(
            configStore: store,
            credentials: InMemoryCredentialStore(),
            domains: PreviewDomainManager(),
            clientFactory: AMSMB2ClientFactory(),
            appVersion: "1.0.0 (1)"
        )
    }

    static func financeServer(locked: Bool = true) -> ServerConfig {
        ServerConfig(
            id: "managed-1-preview",
            source: .managed(slot: 1),
            displayName: "Finance",
            host: "files.example.com",
            share: "Shared",
            rootPath: "Finance/Reports",
            domain: "EXAMPLE",
            username: "jdoe",
            usernameLocked: locked
        )
    }
}
#endif
