import Foundation

/// Lazily connects one SMB client and retries a single dropped operation.
public actor ConnectionProvider {
    private let server: ServerConfig
    private let credentials: any CredentialStoring
    private let factory: any SMBClientFactory
    private var client: (any SMBClient)?

    public init(server: ServerConfig, credentials: any CredentialStoring, factory: any SMBClientFactory) {
        self.server = server
        self.credentials = credentials
        self.factory = factory
    }

    /// Runs `body` on a connected client.
    /// `.serverUnreachable` from `connect()` propagates immediately.
    /// `.serverUnreachable` from `body` on an already-connected client resets, reconnects once, and retries `body` once.
    /// `.authenticationFailed` resets the client and rethrows.
    public func withClient<T: Sendable>(_ body: @Sendable (any SMBClient) async throws -> T) async throws -> T {
        let client = try await connectedClient()
        do {
            return try await body(client)
        } catch SMBError.serverUnreachable {
            await reset()
            let fresh = try await connectedClient()
            return try await body(fresh)
        } catch SMBError.authenticationFailed {
            await reset()
            throw SMBError.authenticationFailed
        }
    }

    public func reset() async {
        let current = client
        client = nil
        await current?.disconnect()
    }

    private func connectedClient() async throws -> any SMBClient {
        if let client { return client }
        guard let credential = try credentials.credential(for: server.id) else {
            throw SMBError.authenticationFailed
        }
        let made = factory.makeClient(server: server, credential: credential)
        do {
            try await made.connect()
        } catch {
            await made.disconnect()
            throw error
        }
        self.client = made
        return made
    }
}
