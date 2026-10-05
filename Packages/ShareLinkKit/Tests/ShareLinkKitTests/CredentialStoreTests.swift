import Testing
@testable import ShareLinkKit

@Suite struct CredentialStoreTests {
    @Test func inMemoryRoundTrip() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.credential(for: "a") == nil)
        try store.setCredential(Credential(username: "jdoe", password: "pw"), for: "a")
        #expect(try store.credential(for: "a") == Credential(username: "jdoe", password: "pw"))
        try store.setCredential(Credential(username: "jdoe", password: "pw2"), for: "a")
        #expect(try store.credential(for: "a")?.password == "pw2")
        try store.removeCredential(for: "a")
        #expect(try store.credential(for: "a") == nil)
    }
}
