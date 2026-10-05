import Foundation

/// Lazily connects one SMB client and retries a single dropped operation.
/// Concurrent callers share one in-flight connect. A connect that finishes after `reset()` is disconnected and discarded.
public actor ConnectionProvider {
    private struct InFlight {
        let task: Task<any SMBClient, Error>
        let generation: UInt64
    }

    private let server: ServerConfig
    private let credentials: any CredentialStoring
    private let factory: any SMBClientFactory
    private var client: (any SMBClient)?
    private var connecting: InFlight?
    private var generation: UInt64 = 0

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
        generation &+= 1
        connecting = nil
        let current = client
        client = nil
        await current?.disconnect()
    }

    private func connectedClient() async throws -> any SMBClient {
        if let client { return client }
        if let connecting {
            return try await adopt(connecting.task, generation: connecting.generation)
        }
        guard let credential = try credentials.credential(for: server.id) else {
            throw SMBError.authenticationFailed
        }
        let generation = self.generation
        let server = self.server
        let factory = self.factory
        let task = Task<any SMBClient, Error> {
            let made = factory.makeClient(server: server, credential: credential)
            do {
                try await made.connect()
            } catch {
                await made.disconnect()
                throw error
            }
            return made
        }
        connecting = InFlight(task: task, generation: generation)
        return try await adopt(task, generation: generation)
    }

    private func adopt(_ task: Task<any SMBClient, Error>, generation: UInt64) async throws -> any SMBClient {
        let made: any SMBClient
        do {
            made = try await task.value
        } catch {
            if self.generation == generation {
                connecting = nil
            }
            throw error
        }
        guard self.generation == generation else {
            await discardIfUnused(made)
            throw CancellationError()
        }
        if let installed = client {
            if !sameInstance(installed, made) {
                await made.disconnect()
            }
            connecting = nil
            return installed
        }
        client = made
        connecting = nil
        return made
    }

    /// `reset()` may have installed a newer client that is this same object (the tests share one fake).
    private func discardIfUnused(_ made: any SMBClient) async {
        if let installed = client, sameInstance(installed, made) { return }
        await made.disconnect()
    }

    private func sameInstance(_ lhs: any SMBClient, _ rhs: any SMBClient) -> Bool {
        (lhs as AnyObject) === (rhs as AnyObject)
    }
}
