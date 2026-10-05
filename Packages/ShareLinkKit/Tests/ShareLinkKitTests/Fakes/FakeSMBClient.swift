import Foundation
@testable import ShareLinkKit

/// In-memory SMB tree. The empty path is always a directory. File IDs issued by
/// uploads, new directories, and `replaceSave` start at 1000.
actor FakeSMBClient: SMBClient {
    struct Node {
        var isDirectory: Bool
        var data: Data
        var modified: Date
        var created: Date?
        var fileID: UInt64
    }

    private var nodes: [String: Node]
    private var nextFileID: UInt64 = 1000
    private var pendingFailures: [SMBError] = []
    private let clock: @Sendable () -> Date

    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var listCount = 0

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        let root = Node(isDirectory: true, data: Data(), modified: .distantPast, created: nil, fileID: 0)
        self.nodes = ["": root]
    }

    func seedFile(_ path: String, contents: Data, modified: Date, fileID: UInt64) {
        let p = SMBPath.normalize(path)
        ensureParents(of: p, modified: modified)
        noteExplicitID(fileID)
        nodes[p] = Node(isDirectory: false, data: contents, modified: modified, created: modified, fileID: fileID)
    }

    func seedDirectory(_ path: String) {
        let p = SMBPath.normalize(path)
        guard !p.isEmpty else { return }
        ensureParents(of: p, modified: clock())
        if nodes[p]?.isDirectory == true { return }
        let now = clock()
        nodes[p] = Node(isDirectory: true, data: Data(), modified: now, created: now, fileID: allocateID())
    }

    func contents(of path: String) -> Data? {
        let p = SMBPath.normalize(path)
        guard let node = nodes[p], !node.isDirectory else { return nil }
        return node.data
    }

    func failNext(_ error: SMBError) {
        pendingFailures.append(error)
    }

    func setModified(_ path: String, _ date: Date) {
        nodes[SMBPath.normalize(path)]?.modified = date
    }

    /// Same path, new file ID. Simulates a temp file renamed over the original.
    func replaceSave(_ path: String, contents: Data, modified: Date) {
        let p = SMBPath.normalize(path)
        guard var node = nodes[p], !node.isDirectory else { return }
        node.data = contents
        node.modified = modified
        node.fileID = allocateID()
        nodes[p] = node
    }

    /// Server-side rename. Keeps file IDs and rewrites descendant paths.
    func rename(_ path: String, to newPath: String) throws {
        try rekey(path, to: newPath)
    }

    func connect() async throws {
        try consumeFailure()
        connectCount += 1
    }

    func disconnect() async {
        disconnectCount += 1
    }

    func list(_ path: String) async throws -> [RemoteEntry] {
        try consumeFailure()
        listCount += 1
        let p = SMBPath.normalize(path)
        guard let node = nodes[p], node.isDirectory else { throw SMBError.notFound }
        return directChildren(of: p).map(entry)
    }

    func stat(_ path: String) async throws -> RemoteEntry {
        try consumeFailure()
        let p = SMBPath.normalize(path)
        guard nodes[p] != nil else { throw SMBError.notFound }
        return entry(p)
    }

    func download(_ path: String, to localURL: URL, progress: SMBReadProgress?) async throws {
        try consumeFailure()
        let p = SMBPath.normalize(path)
        guard let node = nodes[p] else { throw SMBError.notFound }
        guard !node.isDirectory else { throw SMBError.other("Cannot download a directory") }
        let total = Int64(node.data.count)
        if let progress, progress(total, total) == false { throw SMBError.cancelled }
        try node.data.write(to: localURL)
    }

    func upload(from localURL: URL, to path: String, overwrite: Bool, progress: SMBWriteProgress?) async throws {
        try consumeFailure()
        let p = SMBPath.normalize(path)
        let parent = SMBPath.parent(of: p)
        guard let parentNode = nodes[parent], parentNode.isDirectory else { throw SMBError.notFound }
        if let existing = nodes[p], existing.isDirectory || !overwrite {
            throw SMBError.alreadyExists
        }
        let data = try Data(contentsOf: localURL)
        if let progress, progress(Int64(data.count)) == false { throw SMBError.cancelled }
        let now = clock()
        if var existing = nodes[p] {
            existing.data = data
            existing.modified = now
            nodes[p] = existing
        } else {
            nodes[p] = Node(isDirectory: false, data: data, modified: now, created: now, fileID: allocateID())
        }
    }

    func createDirectory(_ path: String) async throws {
        try consumeFailure()
        let p = SMBPath.normalize(path)
        if p.isEmpty { return }
        if nodes[p] != nil { throw SMBError.alreadyExists }
        let parent = SMBPath.parent(of: p)
        guard let parentNode = nodes[parent], parentNode.isDirectory else { throw SMBError.notFound }
        let now = clock()
        nodes[p] = Node(isDirectory: true, data: Data(), modified: now, created: now, fileID: allocateID())
    }

    func move(_ path: String, to newPath: String) async throws {
        try consumeFailure()
        try rekey(path, to: newPath)
    }

    func remove(_ path: String) async throws {
        try consumeFailure()
        let p = SMBPath.normalize(path)
        guard !p.isEmpty, nodes[p] != nil else { throw SMBError.notFound }
        let prefix = p + "/"
        nodes = nodes.filter { $0.key != p && !$0.key.hasPrefix(prefix) }
    }

    private func consumeFailure() throws {
        guard !pendingFailures.isEmpty else { return }
        throw pendingFailures.removeFirst()
    }

    private func allocateID() -> UInt64 {
        let id = nextFileID
        nextFileID += 1
        return id
    }

    private func noteExplicitID(_ id: UInt64) {
        if id >= nextFileID { nextFileID = id &+ 1 }
    }

    private func ensureParents(of path: String, modified: Date) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return }
        var prefix = ""
        for part in parts.dropLast() {
            prefix = prefix.isEmpty ? part : prefix + "/" + part
            if nodes[prefix]?.isDirectory == true { continue }
            nodes[prefix] = Node(isDirectory: true, data: Data(), modified: modified, created: modified, fileID: allocateID())
        }
    }

    private func directChildren(of parent: String) -> [String] {
        nodes.keys.filter { child in
            child != parent && SMBPath.parent(of: child) == parent
        }
        .sorted { SMBPath.lastComponent($0) < SMBPath.lastComponent($1) }
    }

    private func entry(_ path: String) -> RemoteEntry {
        let node = nodes[path]!
        return RemoteEntry(
            name: SMBPath.lastComponent(path),
            path: path,
            isDirectory: node.isDirectory,
            size: node.isDirectory ? 0 : Int64(node.data.count),
            modified: node.modified,
            created: node.created,
            fileID: node.fileID
        )
    }

    private func rekey(_ path: String, to newPath: String) throws {
        let src = SMBPath.normalize(path)
        let dst = SMBPath.normalize(newPath)
        guard !src.isEmpty, nodes[src] != nil else { throw SMBError.notFound }
        if src == dst { return }
        if dst.hasPrefix(src + "/") || nodes[dst] != nil { throw SMBError.alreadyExists }
        let parent = SMBPath.parent(of: dst)
        guard let parentNode = nodes[parent], parentNode.isDirectory else { throw SMBError.notFound }

        let prefix = src + "/"
        let moving = nodes.filter { $0.key == src || $0.key.hasPrefix(prefix) }
        for key in moving.keys { nodes.removeValue(forKey: key) }
        for (key, node) in moving {
            let relocated = key == src ? dst : dst + String(key.dropFirst(src.count))
            nodes[relocated] = node
        }
    }
}

struct FakeSMBClientFactory: SMBClientFactory {
    private final class CredentialBox: @unchecked Sendable {
        let lock = NSLock()
        var lastCredential: Credential?
    }

    private let client: FakeSMBClient
    private let credentials = CredentialBox()

    init(client: FakeSMBClient) { self.client = client }

    var lastCredential: Credential? {
        credentials.lock.withLock { credentials.lastCredential }
    }

    func makeClient(server: ServerConfig, credential: Credential) -> any SMBClient {
        credentials.lock.withLock { credentials.lastCredential = credential }
        return client
    }
}
