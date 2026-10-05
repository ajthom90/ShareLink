import Foundation
import Observation

public enum ServerStatus: Equatable, Sendable {
    case needsSignIn
    case signedIn
    case error(String)
}

@MainActor
@Observable
public final class AppModel {
    public private(set) var servers: [ServerConfig] = []
    public private(set) var allowUserServers = true
    public private(set) var supportMessage = ""
    public private(set) var configIssues: [String] = []
    public private(set) var statuses: [String: ServerStatus] = [:]
    public var signInRequest: ServerConfig?

    private let configStore: ConfigStore
    private let credentials: any CredentialStoring
    private let domains: any DomainManaging
    private let clientFactory: any SMBClientFactory
    private let feedbackDefaults: UserDefaults
    private let appVersion: String

    public init(configStore: ConfigStore, credentials: any CredentialStoring, domains: any DomainManaging,
                clientFactory: any SMBClientFactory, feedbackDefaults: UserDefaults = .standard, appVersion: String = "") {
        self.configStore = configStore
        self.credentials = credentials
        self.domains = domains
        self.clientFactory = clientFactory
        self.feedbackDefaults = feedbackDefaults
        self.appVersion = appVersion
        refresh()
    }

    public func start(managedConfig: [String: Any]) async {
        await apply(ManagedConfigParser.parse(managedConfig))
    }

    /// Same as `start`, but skips work when the parsed configuration matches what is stored.
    public func applyManagedConfiguration(_ dict: [String: Any]) async {
        let parsed = ManagedConfigParser.parse(dict)
        guard parsed != configStore.managed else { return }
        await apply(parsed)
    }

    public func signIn(serverID: String, username: String, password: String) async throws {
        guard let server = servers.first(where: { $0.id == serverID }) else { throw SMBError.notFound }
        try await authenticate(server: server, username: username, password: password)
        await domains.signalWorkingSet(id: serverID)
        if signInRequest?.id == serverID { signInRequest = nil }
        writeFeedback()
    }

    public func signOut(serverID: String) async {
        try? credentials.removeCredential(for: serverID)
        await domains.evictAll(id: serverID)
        statuses[serverID] = .needsSignIn
        writeFeedback()
    }

    public func saveUserServer(_ server: ServerConfig, username: String, password: String?) async throws {
        guard allowUserServers else {
            throw SMBError.other("Adding servers is disabled by your organization.")
        }
        guard !server.host.isEmpty, !server.share.isEmpty else {
            throw SMBError.other("Server and share are required.")
        }
        var stored = server
        stored.username = username
        if let password {
            try await authenticate(server: stored, username: username, password: password)
        }
        configStore.saveUserServer(stored)
        refresh()
        try await reconcile()
        recomputeStatuses()
        writeFeedback()
    }

    public func removeUserServer(id: String) async {
        guard let server = servers.first(where: { $0.id == id }), server.source == .user else { return }
        configStore.removeUserServer(id: id)
        refresh()
        try? await reconcile()
        statuses.removeValue(forKey: id)
        if signInRequest?.id == id { signInRequest = nil }
        writeFeedback()
    }

    public func testConnection(_ server: ServerConfig, username: String, password: String) async -> SMBError? {
        await ConnectionTester.test(server: server, credential: Credential(username: username, password: password), factory: clientFactory)
    }

    public func savedUsername(for serverID: String) -> String? {
        if let credential = try? credentials.credential(for: serverID) {
            return credential.username
        }
        return servers.first { $0.id == serverID }?.username
    }

    public func makeBrowserClient(for serverID: String) -> (any SMBClient)? {
        guard let server = servers.first(where: { $0.id == serverID }),
              let credential = try? credentials.credential(for: serverID) else { return nil }
        return clientFactory.makeClient(server: server, credential: credential)
    }

    public func handle(url: URL) {
        guard url.scheme == "sharelink", url.host == "signin",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "domain" })?.value,
              let server = servers.first(where: { $0.id == id }) else { return }
        signInRequest = server
    }

    public func appDidBecomeActive() async {
        for server in servers where status(for: server.id) == .signedIn {
            await domains.signalWorkingSet(id: server.id)
        }
    }

    /// Replaces the `file` scheme on the user-visible root URL and keeps the path.
    public func openInFilesURL(for serverID: String) async -> URL? {
        guard let fileURL = await domains.userVisibleRootURL(id: serverID),
              var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "shareddocuments"
        return components.url
    }

    public func status(for serverID: String) -> ServerStatus {
        statuses[serverID] ?? .needsSignIn
    }

    private func apply(_ parsed: ManagedConfiguration) async {
        configStore.managed = parsed
        if !parsed.allowUserServers {
            configStore.userServers = []
        }
        refresh()
        try? await reconcile()
        recomputeStatuses()
        writeFeedback()
        if let request = signInRequest, !servers.contains(where: { $0.id == request.id }) {
            signInRequest = nil
        }
        if signInRequest == nil {
            signInRequest = servers.first { $0.isManaged && status(for: $0.id) == .needsSignIn }
        }
    }

    private func authenticate(server: ServerConfig, username: String, password: String) async throws {
        let credential = Credential(username: username, password: password)
        if let error = await ConnectionTester.test(server: server, credential: credential, factory: clientFactory) {
            if case .authenticationFailed = error {
                statuses[server.id] = .needsSignIn
            } else {
                statuses[server.id] = .error(error.userMessage)
            }
            throw error
        }
        try credentials.setCredential(credential, for: server.id)
        statuses[server.id] = .signedIn
    }

    private func reconcile() async throws {
        _ = try await DomainReconciler(manager: domains, credentials: credentials).reconcile(servers: servers)
    }

    private func refresh() {
        let configuration = configStore.managed
        allowUserServers = configuration.allowUserServers
        supportMessage = configuration.supportMessage
        configIssues = configuration.issues
        servers = configStore.allServers()
    }

    private func recomputeStatuses() {
        var next: [String: ServerStatus] = [:]
        for server in servers {
            if (try? credentials.credential(for: server.id)) != nil {
                next[server.id] = .signedIn
            } else {
                next[server.id] = .needsSignIn
            }
        }
        statuses = next
    }

    /// `ConfiguredShares` and `SignedInShares` count managed shares only (spec §4).
    private func writeFeedback() {
        let managed = servers.filter(\.isManaged)
        let signedIn = managed.filter { status(for: $0.id) == .signedIn }.count
        ManagedFeedback.write(configuredShares: managed.count, signedInShares: signedIn,
                              configErrors: configIssues, appVersion: appVersion, to: feedbackDefaults)
    }
}
