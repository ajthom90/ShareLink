import Foundation

public struct DomainInfo: Equatable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public protocol DomainManaging: Sendable {
    func domains() async throws -> [DomainInfo]
    func addOrUpdate(id: String, displayName: String) async throws
    func remove(id: String) async throws
    func signalWorkingSet(id: String) async
    func evictAll(id: String) async
    func userVisibleRootURL(id: String) async -> URL?
}

public struct ReconcileResult: Equatable, Sendable {
    public var added: [String]
    public var removed: [String]
    public var renamed: [String]

    public init(added: [String], removed: [String], renamed: [String]) {
        self.added = added
        self.removed = removed
        self.renamed = renamed
    }
}

public struct DomainReconciler: Sendable {
    private let manager: any DomainManaging
    private let credentials: any CredentialStoring
    private let removeLocalData: @Sendable (String) -> Void

    public init(manager: any DomainManaging, credentials: any CredentialStoring,
                removeLocalData: @escaping @Sendable (String) -> Void = { try? FileManager.default.removeItem(at: AppGroup.domainDirectory(for: $0)) }) {
        self.manager = manager
        self.credentials = credentials
        self.removeLocalData = removeLocalData
    }

    /// Domains missing from `servers` are removed, including their credentials and local data.
    /// Missing domains are added. A display-name change is `addOrUpdate` and counts as renamed.
    public func reconcile(servers: [ServerConfig]) async throws -> ReconcileResult {
        let existing = try await manager.domains()
        let names = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0.displayName) })
        let serverIDs = Set(servers.map(\.id))

        var removed: [String] = []
        for domain in existing where !serverIDs.contains(domain.id) {
            try await manager.remove(id: domain.id)
            try credentials.removeCredential(for: domain.id)
            removeLocalData(domain.id)
            removed.append(domain.id)
        }

        var added: [String] = []
        var renamed: [String] = []
        for server in servers {
            if let currentName = names[server.id] {
                if currentName != server.displayName {
                    try await manager.addOrUpdate(id: server.id, displayName: server.displayName)
                    renamed.append(server.id)
                }
            } else {
                try await manager.addOrUpdate(id: server.id, displayName: server.displayName)
                added.append(server.id)
            }
        }
        return ReconcileResult(added: added, removed: removed, renamed: renamed)
    }
}
