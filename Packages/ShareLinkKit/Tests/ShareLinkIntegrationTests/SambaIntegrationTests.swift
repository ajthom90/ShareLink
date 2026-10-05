import Testing
import Foundation
import Darwin
@testable import ShareLinkKit

enum SambaEnv {
    static let credential = Credential(username: "testuser", password: "ShareLink-Test-1")
    static func server(share: String = "signed", encrypted: Bool = false, root: String = "") -> ServerConfig {
        ServerConfig(id: "it", source: .user, displayName: "IT", host: "127.0.0.1", port: 1445,
                     share: share, rootPath: root, requireEncryption: encrypted)
    }

    /// TCP probe of 127.0.0.1:1445. Never waits longer than 1 second, so a stopped
    /// Docker daemon skips the suite instead of hanging test discovery.
    static var isReachable: Bool { reachability }

    private static let reachability: Bool = probe()

    private static func probe(port: UInt16 = 1445, timeoutMS: Int32 = 1000) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { _ = close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let parsed = withUnsafeMutablePointer(to: &addr.sin_addr) { pointer in
            inet_pton(AF_INET, "127.0.0.1", pointer)
        }
        guard parsed == 1 else { return false }

        let rc = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let waited = poll(&pfd, nfds_t(1), timeoutMS)
        guard waited > 0 else { return false }

        var soerr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        let got = withUnsafeMutablePointer(to: &soerr) { pointer in
            getsockopt(fd, SOL_SOCKET, SO_ERROR, pointer, &len)
        }
        return got == 0 && soerr == 0
    }
}

@Suite(.enabled(if: SambaEnv.isReachable), .serialized) struct SambaIntegrationTests {
    func connected(_ server: ServerConfig = SambaEnv.server()) async throws -> AMSMB2Client {
        let c = AMSMB2Client(server: server, credential: SambaEnv.credential)
        try await c.connect()
        return c
    }
    func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var data = Data(count: bytes)
        for i in 0..<min(bytes, 4096) { data[i] = UInt8(i % 251) }
        try data.write(to: url)
        return url
    }

    @Test func crudRoundTripWithSpecialNames() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        let name = "Q3 Report #1 – café.docx"
        let src = try tempFile(bytes: 10_000)
        try await c.upload(from: src, to: "\(dir)/\(name)", overwrite: false, progress: nil)
        let listed = try await c.list(dir)
        #expect(listed.map(\.name) == [name])
        #expect(listed[0].size == 10_000)
        #expect(listed[0].path == "\(dir)/\(name)")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await c.download("\(dir)/\(name)", to: out, progress: nil)
        #expect(try Data(contentsOf: out) == Data(contentsOf: src))
        try await c.move("\(dir)/\(name)", to: "\(dir)/renamed.docx")
        #expect(try await c.stat("\(dir)/renamed.docx").size == 10_000)
        await #expect(throws: SMBError.alreadyExists) {
            try await c.upload(from: src, to: "\(dir)/renamed.docx", overwrite: false, progress: nil)
        }
        try await c.remove(dir)
        await #expect(throws: SMBError.notFound) { try await c.stat(dir) }
        await c.disconnect()
    }

    @Test func overwriteTruncates() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        try await c.upload(from: try tempFile(bytes: 3_000_000), to: "\(dir)/f.bin", overwrite: false, progress: nil)
        let small = try tempFile(bytes: 1_024)
        try await c.upload(from: small, to: "\(dir)/f.bin", overwrite: true, progress: nil)
        #expect(try await c.stat("\(dir)/f.bin").size == 1_024)
        let empty = try tempFile(bytes: 0)
        try await c.upload(from: empty, to: "\(dir)/f.bin", overwrite: true, progress: nil)
        #expect(try await c.stat("\(dir)/f.bin").size == 0)
        try await c.remove(dir); await c.disconnect()
    }

    @Test func largeFileStreams() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        let src = try tempFile(bytes: 50 * 1024 * 1024)
        try await c.upload(from: src, to: "\(dir)/big.bin", overwrite: false, progress: nil)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await c.download("\(dir)/big.bin", to: out, progress: nil)
        #expect((try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.intValue == 50 * 1024 * 1024)
        try await c.remove(dir); await c.disconnect()
    }

    @Test func rootPathScopesPaths() async throws {
        let base = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await base.createDirectory(dir); try await base.createDirectory("\(dir)/inner")
        let scoped = try await connected(SambaEnv.server(root: dir))
        #expect(try await scoped.list("").map(\.path) == ["inner"])
        try await base.remove(dir); await scoped.disconnect(); await base.disconnect()
    }

    @Test func wrongPasswordIsAuthenticationFailed() async {
        let c = AMSMB2Client(server: SambaEnv.server(), credential: Credential(username: "testuser", password: "wrong"))
        await #expect(throws: SMBError.authenticationFailed) { try await c.connect() }
    }

    @Test func encryptedShareWorksWithEncryption() async throws {
        let c = try await connected(SambaEnv.server(share: "encrypted", encrypted: true))
        _ = try await c.list(""); await c.disconnect()
    }

    @Test func concurrentOperationsOnOneClient() async throws {
        let c = try await connected()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = try await c.list("") } }
            try await group.waitForAll()
        }
        await c.disconnect()
    }

    @Test func unreachablePortIsServerUnreachable() async {
        var s = SambaEnv.server(); s.port = 1446
        let c = AMSMB2Client(server: s, credential: SambaEnv.credential, timeout: 3)
        await #expect(throws: SMBError.serverUnreachable) { try await c.connect() }
    }
}
