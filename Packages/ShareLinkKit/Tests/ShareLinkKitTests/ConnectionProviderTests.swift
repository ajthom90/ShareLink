import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConnectionProviderTests {
    private func makeProvider(fake: FakeSMBClient) throws -> ConnectionProvider {
        let creds = InMemoryCredentialStore()
        let server = ServerConfig(id: "s", source: .user, displayName: "Finance", host: "h", share: "S")
        try creds.setCredential(Credential(username: "jdoe", password: "pw"), for: "s")
        return ConnectionProvider(server: server, credentials: creds, factory: FakeSMBClientFactory(client: fake))
    }

    @Test func concurrentCallersShareOneConnection() async throws {
        let fake = FakeSMBClient(connectDelay: .milliseconds(200))
        let provider = try makeProvider(fake: fake)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = try await provider.withClient { try await $0.list("") }
                }
            }
            try await group.waitForAll()
        }
        #expect(await fake.connectCount == 1)
    }

    @Test func resetDuringConnectDoesNotInstallStaleClient() async throws {
        let fake = FakeSMBClient(connectDelay: .milliseconds(400))
        let provider = try makeProvider(fake: fake)
        let first = Task {
            try await provider.withClient { try await $0.list("") }
        }
        let deadline = ContinuousClock().now.advanced(by: .seconds(5))
        while await fake.connectStarted == 0 {
            if ContinuousClock().now >= deadline { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await provider.reset()
        _ = try? await first.value
        _ = try await provider.withClient { try await $0.list("") }
        #expect(await fake.connectCount == 2)
        #expect(await fake.disconnectCount >= 1)
    }
}
