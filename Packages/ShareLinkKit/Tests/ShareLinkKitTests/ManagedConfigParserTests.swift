import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ManagedConfigParserTests {
    @Test func singleShareWithDefaults() {
        let cfg = ManagedConfigParser.parse(["Host": "files.example.com", "Share": "Shared"])
        #expect(cfg.servers.count == 1)
        let s = cfg.servers[0]
        #expect(s.host == "files.example.com")
        #expect(s.share == "Shared")
        #expect(s.port == 445)
        #expect(s.rootPath == "")
        #expect(s.displayName == "Shared on files.example.com")
        #expect(s.source == .managed(slot: 1))
        #expect(s.requireEncryption == false)
        #expect(s.usernameLocked == false)
        #expect(cfg.allowUserServers == true)
        #expect(cfg.supportMessage == "")
        #expect(cfg.issues.isEmpty)
    }

    @Test func lenientValuesAndPathNormalization() {
        let cfg = ManagedConfigParser.parse([
            "Host": "  files.example.com ", "Share": " Shared ", "Path": "\\Finance\\Reports\\",
            "Port": "1445", "RequireEncryption": "YES", "UsernameLocked": 1,
            "Username": " jdoe ", "Domain": "EXAMPLE", "DisplayName": " Finance ",
            "AllowUserServers": "false", "SupportMessage": " Use your network password ",
        ])
        let s = cfg.servers[0]
        #expect(s.host == "files.example.com")
        #expect(s.share == "Shared")
        #expect(s.rootPath == "Finance/Reports")
        #expect(s.port == 1445)
        #expect(s.requireEncryption)
        #expect(s.usernameLocked)
        #expect(s.username == "jdoe")
        #expect(s.domain == "EXAMPLE")
        #expect(s.displayName == "Finance")
        #expect(cfg.allowUserServers == false)
        #expect(cfg.supportMessage == "Use your network password")
    }

    @Test func numberedShares() {
        let cfg = ManagedConfigParser.parse([
            "Host": "a.example.com", "Share": "One",
            "Share2.Host": "b.example.com", "Share2.Share": "Two", "Share2.Port": 4450,
            "Share10.Host": "c.example.com", "Share10.Share": "Ten",
            "Share11.Host": "ignored.example.com", "Share11.Share": "Ignored",
        ])
        #expect(cfg.servers.map(\.share) == ["One", "Two", "Ten"])
        #expect(cfg.servers.map(\.source) == [.managed(slot: 1), .managed(slot: 2), .managed(slot: 10)])
        #expect(cfg.servers[1].port == 4450)
    }

    @Test func defaultsOnlySlotIsIgnored() {
        let cfg = ManagedConfigParser.parse([
            "Host": "a.example.com", "Share": "S",
            "Share2.Port": "445", "Share2.RequireEncryption": false,
        ])
        #expect(cfg.servers.count == 1)
        #expect(cfg.issues.isEmpty)
    }

    @Test func missingRequiredKeysRecordIssues() {
        let cfg = ManagedConfigParser.parse(["Host": "a.example.com", "Share2.Share": "Two"])
        #expect(cfg.servers.isEmpty)
        #expect(cfg.issues.count == 2)
        #expect(cfg.issues.contains { $0.contains("Share 1") && $0.contains("Share") })
        #expect(cfg.issues.contains { $0.contains("Share 2") && $0.contains("Host") })
    }

    @Test func invalidPortFallsBackWithIssue() {
        let cfg = ManagedConfigParser.parse(["Host": "a.example.com", "Share": "S", "Port": "abc"])
        #expect(cfg.servers[0].port == 445)
        #expect(cfg.issues.count == 1)
    }

    @Test func emptyDictionaryIsEmptyConfig() {
        #expect(ManagedConfigParser.parse([:]) == .empty)
    }

    @Test func managedIDIsDeterministicAndContentSensitive() {
        let a = ServerConfig.managedID(slot: 1, host: "a.example.com", share: "S", rootPath: "")
        let b = ServerConfig.managedID(slot: 1, host: "A.EXAMPLE.COM", share: "S", rootPath: "")
        let c = ServerConfig.managedID(slot: 1, host: "a.example.com", share: "S", rootPath: "x")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasPrefix("managed-1-"))
        #expect(a.count == "managed-1-".count + 12)
        let parsed = ManagedConfigParser.parse(["Host": "a.example.com", "Share": "S"])
        #expect(parsed.servers[0].id == a)
    }
}
