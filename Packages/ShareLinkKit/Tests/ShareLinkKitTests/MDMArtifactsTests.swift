import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct MDMArtifactsTests {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()   // Tests/ShareLinkKitTests/X.swift -> repo root

    @Test func examplePlistParses() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("MDM/example-managed-config.plist"))
        let dict = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let cfg = ManagedConfigParser.parse(dict)
        #expect(cfg.issues.isEmpty)
        #expect(cfg.servers.count == 2)
        #expect(cfg.servers.allSatisfy { $0.host.hasSuffix("example.com") })
    }

    @Test func appConfigKeysAreKnown() throws {
        let xml = try String(contentsOf: repoRoot.appendingPathComponent("MDM/sharelink-appconfig.xml"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"keyName="([^"]+)""#)
        let keys = Set(regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).map { String(xml[Range($0.range(at: 1), in: xml)!]) })
        let base = ["Host", "Share", "Path", "DisplayName", "Port", "Domain", "Username", "UsernameLocked", "RequireEncryption"]
        let known = Set(["AllowUserServers", "SupportMessage"] + base + base.map { "Share2.\($0)" })
        #expect(!keys.isEmpty)
        #expect(keys.isSubset(of: known))
    }
}
