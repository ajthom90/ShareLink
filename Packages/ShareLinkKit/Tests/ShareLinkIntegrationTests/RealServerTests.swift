import Testing
import Foundation
@testable import ShareLinkKit

/// Read-only check against a server described by `SHARELINK_TEST_SERVER_JSON`.
/// The file uses the `TestServer.example.json` shape. Output is the entry count only.
enum RealServerEnv {
    static var jsonURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["SHARELINK_TEST_SERVER_JSON"],
              !path.isEmpty,
              FileManager.default.isReadableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

private struct RealServerFile: Decodable {
    var host: String
    var port: Int
    var share: String
    var path: String
    var domain: String
    var username: String
    var password: String
    var requireEncryption: Bool
}

@Suite(.enabled(if: RealServerEnv.jsonURL != nil)) struct RealServerTests {
    @Test func listRootAndStatFirst() async throws {
        let url = try #require(RealServerEnv.jsonURL)
        let file = try JSONDecoder().decode(RealServerFile.self, from: Data(contentsOf: url))
        let server = ServerConfig(
            id: "real", source: .user, displayName: "Real",
            host: file.host, port: file.port, share: file.share, rootPath: file.path,
            domain: file.domain, username: file.username, requireEncryption: file.requireEncryption)
        let client = AMSMB2Client(server: server, credential: Credential(username: file.username, password: file.password))
        try await client.connect()
        let entries = try await client.list("")
        if let first = entries.first {
            _ = try await client.stat(first.path)
        }
        await client.disconnect()
        print("entry count \(entries.count)")
    }
}
