import Testing
import Foundation
import FileProvider
import UniformTypeIdentifiers
@testable import ShareLinkKit

/// Minimal template used for createItem.
final class Template: NSObject, NSFileProviderItem {
    let itemIdentifier = NSFileProviderItemIdentifier("template")
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    init(parent: NSFileProviderItemIdentifier, name: String, type: UTType) { parentItemIdentifier = parent; filename = name; contentType = type }
}

@Suite struct ProviderEngineTests {
    struct Harness {
        let fake: FakeSMBClient
        let engine: ProviderEngine
        let store: MetadataStore
        let signals: SignalCounter
    }
    final class SignalCounter: @unchecked Sendable { var count = 0; let lock = NSLock(); func hit() { lock.withLock { count += 1 } } }
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000); let lock = NSLock()
        func advance(_ s: TimeInterval) { lock.withLock { now += s } }; func get() -> Date { lock.withLock { now } } }

    func makeHarness(clock: Clock = Clock(), credential: Credential? = Credential(username: "jdoe", password: "pw")) throws -> Harness {
        let fake = FakeSMBClient()
        let creds = InMemoryCredentialStore()
        let server = ServerConfig(id: "s", source: .user, displayName: "Finance", host: "h", share: "S")
        if let credential { try creds.setCredential(credential, for: "s") }
        let store = try MetadataStore.inMemory()
        let signals = SignalCounter()
        let engine = ProviderEngine(server: server, store: store,
                                    connection: ConnectionProvider(server: server, credentials: creds, factory: FakeSMBClientFactory(client: fake)),
                                    deviceName: "iPad", now: { clock.get() }, signalWorkingSet: { signals.hit() })
        return Harness(fake: fake, engine: engine, store: store, signals: signals)
    }
    func tmp(_ s: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try Data(s.utf8).write(to: u); return u
    }

    @Test func enumerateRootListsServerAndHidesJunk() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("A".utf8), modified: .now, fileID: 1)
        await h.fake.seedFile("~$a.docx", contents: Data(), modified: .now, fileID: 2)
        await h.fake.seedDirectory("Docs")
        let (items, next) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(items.map(\.filename) == ["a.docx", "Docs"])
        #expect(next == nil)
    }

    @Test func pagination() async throws {
        let h = try makeHarness()
        for i in 0..<(ProviderEngine.pageSize + 5) { await h.fake.seedFile(String(format: "f%04d.txt", i), contents: Data(), modified: .now, fileID: UInt64(i + 1)) }
        let (first, next) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(first.count == ProviderEngine.pageSize)
        let (second, end) = try await h.engine.enumerateItems(in: .rootContainer, page: try #require(next))
        #expect(second.count == 5)
        #expect(end == nil)
        #expect(await h.fake.listCount == 1)   // later pages come from the DB
    }

    @Test func missingCredentialIsNotAuthenticated() async throws {
        let h = try makeHarness(credential: nil)
        await #expect(throws: SMBError.authenticationFailed) { _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil) }
    }

    @Test func changesDetectRemoteEditsAfterRescanInterval() async throws {
        let clock = Clock(); let h = try makeHarness(clock: clock)
        await h.fake.seedFile("a.docx", contents: Data("A".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let anchor = try await h.engine.currentAnchor()
        await h.fake.replaceSave("a.docx", contents: Data("AB".utf8), modified: Date(timeIntervalSince1970: 2))
        let early = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(early.updated.isEmpty)                    // not stale yet
        clock.advance(ProviderEngine.rescanInterval + 1)
        let batch = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(batch.updated.map(\.filename) == ["a.docx"])
        #expect(batch.updated[0].documentSize == 2)
        #expect(batch.deleted.isEmpty)
        let again = try await h.engine.changes(in: .workingSet, since: batch.anchor)
        #expect(again.updated.isEmpty && again.deleted.isEmpty)
    }

    @Test func remoteDeleteReported() async throws {
        let clock = Clock(); let h = try makeHarness(clock: clock)
        await h.fake.seedFile("a.docx", contents: Data(), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let anchor = try await h.engine.currentAnchor()
        try await h.fake.remove("a.docx")
        clock.advance(ProviderEngine.rescanInterval + 1)
        let batch = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(batch.deleted == [items[0].itemIdentifier])
    }

    @Test func expiredAnchor() async throws {
        let h = try makeHarness()
        for i in 0..<(ProviderEngine.changesRetained + 10) {
            try h.store.recordLocalUpsert(ItemRecord(identifier: "I\(i)", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "f\(i)", name: "f\(i)",
                                                    isDirectory: false, size: 0, modified: .now, created: nil, fileID: 0, lastScanned: nil))
        }
        _ = try await h.engine.changes(in: .workingSet, since: NSFileProviderSyncAnchor(Data("\(ProviderEngine.changesRetained + 9)".utf8)))   // triggers prune
        await #expect(throws: NSFileProviderError.self) {
            _ = try await h.engine.changes(in: .workingSet, since: NSFileProviderSyncAnchor(Data("1".utf8)))
        }
    }

    @Test func fetchContentsDownloads() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("hello".utf8), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (url, item) = try await h.engine.fetchContents(for: items[0].itemIdentifier, into: dir, progress: Progress())
        #expect(try Data(contentsOf: url) == Data("hello".utf8))
        #expect(item.filename == "a.docx")
    }

    @Test func createFileAndFolder() async throws {
        let h = try makeHarness()
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let folder = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: false, progress: Progress())
        let file = try await h.engine.createItem(template: Template(parent: folder.itemIdentifier, name: "b.txt", type: .plainText), fields: [.contents], contents: try tmp("B"), mayAlreadyExist: false, progress: Progress())
        #expect(await h.fake.contents(of: "New/b.txt") == Data("B".utf8))
        #expect(file.parentItemIdentifier == folder.itemIdentifier)
        await #expect(throws: SMBError.alreadyExists) {
            _ = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: false, progress: Progress())
        }
        let existing = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: true, progress: Progress())
        #expect(existing.itemIdentifier == folder.itemIdentifier)
    }

    @Test func modifyContentsOverwritesInPlace() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("old".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let updated = try await h.engine.modifyItem(items[0], baseVersion: items[0].itemVersion, changedFields: [.contents], contents: try tmp("new!"), progress: Progress())
        #expect(await h.fake.contents(of: "a.docx") == Data("new!".utf8))
        #expect(updated.itemIdentifier == items[0].itemIdentifier)
        #expect(updated.documentSize == 4)
    }

    @Test func modifyWithStaleBaseCreatesConflictCopy() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("v1".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        await h.fake.replaceSave("a.docx", contents: Data("server".utf8), modified: Date(timeIntervalSince1970: 5))
        let result = try await h.engine.modifyItem(items[0], baseVersion: items[0].itemVersion, changedFields: [.contents], contents: try tmp("local"), progress: Progress())
        #expect(await h.fake.contents(of: "a.docx") == Data("server".utf8))           // server copy untouched
        let names = try await h.fake.list("").map(\.name)
        #expect(names.contains { $0.hasPrefix("a (Conflict iPad ") && $0.hasSuffix(").docx") })
        #expect(result.documentSize == 6)
        #expect(h.signals.count >= 1)
    }

    @Test func renameFolderThenFetchChild() async throws {
        let h = try makeHarness()
        await h.fake.seedDirectory("Docs")
        await h.fake.seedFile("Docs/x.txt", contents: Data("x".utf8), modified: .now, fileID: 2)
        let (rootItems, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let docs = rootItems[0]
        let (children, _) = try await h.engine.enumerateItems(in: docs.itemIdentifier, page: nil)
        let renamedTemplate = Template(parent: .rootContainer, name: "Papers", type: .folder)
        let renamed = try await h.engine.modifyItem(ItemWithIdentifier(docs.itemIdentifier, template: renamedTemplate), baseVersion: docs.itemVersion,
                                                    changedFields: [.filename], contents: nil, progress: Progress())
        #expect(renamed.itemIdentifier == docs.itemIdentifier)
        #expect(renamed.filename == "Papers")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (url, child) = try await h.engine.fetchContents(for: children[0].itemIdentifier, into: dir, progress: Progress())
        #expect(child.itemIdentifier == children[0].itemIdentifier)
        #expect(try Data(contentsOf: url) == Data("x".utf8))
    }

    @Test func deleteRemovesAndToleratesMissing() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data(), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        try await h.fake.remove("a.docx")
        try await h.engine.deleteItem(items[0].itemIdentifier)
        await #expect(throws: (any Error).self) { _ = try await h.engine.item(for: items[0].itemIdentifier) }
    }

    @Test func reconnectsOnceAfterDroppedConnection() async throws {
        let h = try makeHarness()
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        await h.fake.failNext(.serverUnreachable)
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(await h.fake.connectCount == 2)
    }

    @Test func connectUnreachableIsNotRetried() async throws {
        let h = try makeHarness()
        await h.fake.failNext(.serverUnreachable)
        await #expect(throws: SMBError.serverUnreachable) {
            _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        }
        #expect(await h.fake.connectCount == 0)
    }

    @Test func trashAndUnknownItemsDoNotExist() async throws {
        let h = try makeHarness()
        await #expect(throws: NSFileProviderError.self) {
            _ = try await h.engine.enumerateItems(in: .trashContainer, page: nil)
        }
        await #expect(throws: NSFileProviderError.self) {
            _ = try await h.engine.item(for: NSFileProviderItemIdentifier("missing"))
        }
        #expect(await h.fake.connectCount == 0)
    }
}

/// An item that reuses an identifier with new name/parent (how the system describes a rename).
final class ItemWithIdentifier: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    init(_ id: NSFileProviderItemIdentifier, template: Template) {
        itemIdentifier = id; parentItemIdentifier = template.parentItemIdentifier; filename = template.filename; contentType = template.contentType
    }
}
