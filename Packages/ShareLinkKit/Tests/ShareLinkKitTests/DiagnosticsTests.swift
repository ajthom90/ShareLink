import Testing
@testable import ShareLinkKit

@Suite struct DiagnosticsTests {
    @Test func redactsSecretsAndHosts() {
        let s = ServerConfig(id: "managed-1-abc", source: .managed(slot: 1), displayName: "Finance", host: "files.example.com",
                             share: "Shared", rootPath: "Finance/Reports", domain: "EXAMPLE", username: "jdoe")
        let text = Diagnostics.report(servers: [s], statuses: [s.id: .signedIn], issues: ["Share 2: missing Share2.Host"],
                                      appVersion: "1.0.0 (3)", logTail: ["provider: enumerate ok"])
        #expect(text.contains("1.0.0 (3)"))
        #expect(text.contains("managed slot 1"))
        #expect(text.contains("signed in"))
        #expect(text.contains("Share 2: missing Share2.Host"))
        #expect(text.contains("provider: enumerate ok"))
        #expect(!text.contains("jdoe"))
        #expect(text.contains("j***"))
        #expect(!text.contains("files.example.com"))
        #expect(text.contains("f***.com"))
    }

    @Test func redactsIPv4AndOmitsShare() {
        let s = ServerConfig(id: "user-1", source: .user, displayName: "NAS", host: "192.168.1.20", share: "Home", username: "me")
        let text = Diagnostics.report(servers: [s], statuses: [s.id: .needsSignIn], issues: [], appVersion: "1.0.0 (1)", logTail: [])
        #expect(text.contains("x.x.x.20"))
        #expect(text.contains("(user)"))
        #expect(text.contains("needs sign-in"))
        #expect(text.contains("encryption optional"))
        #expect(text.contains("m***"))
        #expect(!text.contains("192.168.1.20"))
        #expect(!text.contains("Home"))
    }
}
