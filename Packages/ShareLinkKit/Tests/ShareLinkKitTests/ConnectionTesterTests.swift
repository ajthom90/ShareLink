import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConnectionTesterTests {
    private func server() -> ServerConfig {
        ServerConfig(id: "t", source: .user, displayName: "T", host: "files.example.com", share: "Shared", domain: "EXAMPLE", username: "jdoe")
    }

    private func credential() -> Credential {
        Credential(username: "jdoe", password: "secret")
    }

    @Test func successReturnsNilAndDisconnects() async {
        let fake = FakeSMBClient()
        let factory = FakeSMBClientFactory(client: fake)
        let result = await ConnectionTester.test(server: server(), credential: credential(), factory: factory)
        #expect(result == nil)
        #expect(await fake.connectCount == 1)
        #expect(await fake.listCount == 1)
        #expect(await fake.disconnectCount == 1)
    }

    @Test func authenticationFailureIsReturned() async {
        let fake = FakeSMBClient()
        await fake.failNext(.authenticationFailed)
        let factory = FakeSMBClientFactory(client: fake)
        let result = await ConnectionTester.test(server: server(), credential: credential(), factory: factory)
        #expect(result == .authenticationFailed)
        #expect(await fake.disconnectCount == 1)
    }
}
