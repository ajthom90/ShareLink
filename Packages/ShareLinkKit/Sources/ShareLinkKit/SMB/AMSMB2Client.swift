import Foundation
import Darwin
import AMSMB2

public final class AMSMB2Client: SMBClient, @unchecked Sendable {
    private let server: ServerConfig
    private let credential: Credential
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var manager: SMB2Manager?
    static let chunkSize = 2 * 1024 * 1024

    public init(server: ServerConfig, credential: Credential, timeout: TimeInterval = 30) {
        self.server = server
        self.credential = credential
        self.timeout = timeout
    }

    private func fullPath(_ relative: String) -> String { SMBPath.join(server.rootPath, relative) }

    private func relative(_ full: String) -> String {
        let f = SMBPath.normalize(full), root = SMBPath.normalize(server.rootPath)
        guard !root.isEmpty else { return f }
        if f == root { return "" }
        return f.hasPrefix(root + "/") ? String(f.dropFirst(root.count + 1)) : f
    }

    public func connect() async throws {
        var comps = URLComponents()
        comps.scheme = "smb"
        comps.host = server.host
        comps.port = server.port
        guard let url = comps.url,
              let m = SMB2Manager(url: url, domain: server.domain,
                                  credential: URLCredential(user: credential.username, password: credential.password, persistence: .forSession))
        else { throw SMBError.other("Invalid server address") }
        m.timeout = timeout
        do {
            try await m.connectShare(name: server.share, encrypted: server.requireEncryption)
            if !server.rootPath.isEmpty { _ = try await m.attributesOfItem(atPath: server.rootPath) }
        } catch {
            // AMSMB2 4.0.3 destroys the smb2 context before copying smb2_get_error,
            // so a refused TCP port and a bad password both arrive as POSIX EPERM
            // "Error code 1: ". A port that is not accepting connections is unreachable.
            let mapped = SMBErrorMapper.map(error, duringConnect: true)
            if Self.lostLibsmb2Detail(error),
               await Self.tcpAccepts(host: server.host, port: server.port, timeout: timeout) == false {
                throw SMBError.serverUnreachable
            }
            throw mapped
        }
        lock.withLock { manager = m }
    }

    public func disconnect() async {
        let m = lock.withLock { () -> SMB2Manager? in
            defer { manager = nil }
            return manager
        }
        try? await m?.disconnectShare(gracefully: false)
    }

    private func requireManager() throws -> SMB2Manager {
        guard let m = lock.withLock({ manager }) else { throw SMBError.serverUnreachable }
        return m
    }

    private func run<T: Sendable>(_ body: (SMB2Manager) async throws -> T) async throws -> T {
        let m = try requireManager()
        do { return try await body(m) } catch { throw SMBErrorMapper.map(error, duringConnect: false) }
    }

    private func entry(_ attrs: [URLResourceKey: any Sendable], fallbackPath: String) -> RemoteEntry {
        let path = (attrs[.pathKey] as? String).map(relative) ?? fallbackPath
        let name = (attrs[.nameKey] as? String) ?? SMBPath.lastComponent(path)
        return RemoteEntry(
            name: name, path: SMBPath.normalize(path),
            isDirectory: (attrs[.isDirectoryKey] as? NSNumber)?.boolValue ?? false,
            size: (attrs[.fileSizeKey] as? NSNumber)?.int64Value ?? 0,
            modified: (attrs[.contentModificationDateKey] as? Date) ?? .distantPast,
            created: attrs[.creationDateKey] as? Date,
            fileID: (attrs[.documentIdentifierKey] as? NSNumber)?.uint64Value ?? 0)
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        try await run { m in
            // The async overload returns non-Sendable `[URLResourceKey: Any]`.
            // The callback overload returns Sendable attribute dictionaries.
            let items = try await Self.directoryContents(m, atPath: self.fullPath(path))
            return items.map { attrs in
                var e = self.entry(attrs, fallbackPath: SMBPath.join(path, attrs[.nameKey] as? String ?? ""))
                e.path = SMBPath.join(path, e.name)
                return e
            }
        }
    }

    public func stat(_ path: String) async throws -> RemoteEntry {
        try await run { m in
            var e = self.entry(try await m.attributesOfItem(atPath: self.fullPath(path)), fallbackPath: path)
            e.path = SMBPath.normalize(path)
            e.name = SMBPath.lastComponent(path)
            return e
        }
    }

    public func download(_ path: String, to localURL: URL, progress: SMBReadProgress?) async throws {
        try await run { m in
            try await m.downloadItem(atPath: self.fullPath(path), to: localURL, progress: { bytes, total in
                progress?(bytes, total) ?? true
            })
        }
    }

    public func upload(from localURL: URL, to path: String, overwrite: Bool, progress: SMBWriteProgress?) async throws {
        try await run { m in
            let target = self.fullPath(path)
            guard overwrite else {
                try await m.uploadItem(at: localURL, toPath: target, progress: { progress?($0) ?? true })
                return
            }
            // In-place overwrite (keeps server ACLs): chunked writes at increasing offsets.
            // append(offset:) truncates the remote file to `offset` before writing.
            let handle = try FileHandle(forReadingFrom: localURL)
            defer { try? handle.close() }
            var offset: Int64 = 0
            var wroteAny = false
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try await m.append(data: chunk, toPath: target, offset: offset, progress: nil)
                offset += Int64(chunk.count)
                wroteAny = true
                if progress?(offset) == false { throw SMBError.cancelled }
            }
            if !wroteAny {
                do { try await m.truncateFile(atPath: target, atOffset: 0) }
                catch { try await m.write(data: Data(), toPath: target, progress: nil) }
            }
        }
    }

    public func createDirectory(_ path: String) async throws {
        try await run { m in try await m.createDirectory(atPath: self.fullPath(path)) }
    }

    public func move(_ path: String, to newPath: String) async throws {
        try await run { m in try await m.moveItem(atPath: self.fullPath(path), toPath: self.fullPath(newPath)) }
    }

    public func remove(_ path: String) async throws {
        try await run { m in
            let target = self.fullPath(path)
            let attrs = try await m.attributesOfItem(atPath: target)
            if (attrs[.isDirectoryKey] as? NSNumber)?.boolValue == true {
                try await m.removeDirectory(atPath: target, recursive: true)
            } else {
                try await m.removeFile(atPath: target)
            }
        }
    }

    /// True for the blank EPERM AMSMB2 throws after `smb2_destroy_context`.
    private static func lostLibsmb2Detail(_ error: any Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) else { return false }
        let text = (ns.userInfo[NSLocalizedDescriptionKey] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "Error code \(EPERM):"
    }

    /// Whether `host:port` accepts a TCP connection within `timeout`.
    /// A refused port returns immediately; only a black-holed route waits out `timeout`.
    private static func tcpAccepts(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let servicePort = UInt16(exactly: port) else { return false }
        let timeoutMS = Int32(max(1, min(timeout * 1000, Double(Int32.max))))
        return await Task.detached {
            probeTCP(host: host, port: servicePort, timeoutMS: timeoutMS)
        }.value
    }

    private static func probeTCP(host: String, port: UInt16, timeoutMS: Int32) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        hints.ai_protocol = IPPROTO_TCP
        var resolved: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &resolved)
        guard rc == 0, let resolved else { return false }
        defer { freeaddrinfo(resolved) }
        var cursor: UnsafeMutablePointer<addrinfo>? = resolved
        while let ai = cursor {
            cursor = ai.pointee.ai_next
            if attemptConnect(ai, timeoutMS: timeoutMS) { return true }
        }
        return false
    }

    private static func attemptConnect(_ ai: UnsafeMutablePointer<addrinfo>, timeoutMS: Int32) -> Bool {
        let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { _ = close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }
        let connected = Darwin.connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
        if connected == 0 { return true }
        if errno != EINPROGRESS { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, nfds_t(1), timeoutMS) > 0 else { return false }
        var soerr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        let got = withUnsafeMutablePointer(to: &soerr) { pointer in
            getsockopt(fd, SOL_SOCKET, SO_ERROR, pointer, &len)
        }
        return got == 0 && soerr == 0
    }

    private static func directoryContents(_ m: SMB2Manager, atPath path: String) async throws -> [[URLResourceKey: any Sendable]] {
        try await withCheckedThrowingContinuation { continuation in
            m.contentsOfDirectory(atPath: path, recursive: false) { result in
                continuation.resume(with: result)
            }
        }
    }
}

public struct AMSMB2ClientFactory: SMBClientFactory {
    public init() {}
    public func makeClient(server: ServerConfig, credential: Credential) -> any SMBClient {
        AMSMB2Client(server: server, credential: credential)
    }
}
