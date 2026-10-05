import Foundation
import FileProvider
import UniformTypeIdentifiers

public struct ChangeBatch: Sendable {
    public var updated: [FileProviderItem]
    public var deleted: [NSFileProviderItemIdentifier]
    public var anchor: NSFileProviderSyncAnchor
    public var moreComing: Bool

    public init(updated: [FileProviderItem], deleted: [NSFileProviderItemIdentifier],
                anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
        self.updated = updated
        self.deleted = deleted
        self.anchor = anchor
        self.moreComing = moreComing
    }
}

/// File Provider operations against one server. The extension supplies directories,
/// `Progress`, and the working-set signal; this type does not call extension-only APIs.
public actor ProviderEngine {
    public static let pageSize = 200
    public static let changeBatchSize = 500
    public static let rescanInterval: TimeInterval = 15
    public static let maxFoldersPerRescan = 50
    public static let changesRetained = 5000

    private let server: ServerConfig
    private let store: MetadataStore
    private let connection: ConnectionProvider
    private let deviceName: String
    private let now: @Sendable () -> Date
    private let signalWorkingSet: @Sendable () -> Void

    public init(server: ServerConfig, store: MetadataStore, connection: ConnectionProvider,
                deviceName: String, now: @escaping @Sendable () -> Date = { Date() },
                signalWorkingSet: @escaping @Sendable () -> Void = {}) {
        self.server = server
        self.store = store
        self.connection = connection
        self.deviceName = deviceName
        self.now = now
        self.signalWorkingSet = signalWorkingSet
    }

    public func item(for identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem {
        guard let record = try store.item(storageIdentifier(identifier)) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return makeItem(record)
    }

    public func enumerateItems(in container: NSFileProviderItemIdentifier, page: Data?) async throws -> (items: [FileProviderItem], nextPage: Data?) {
        if container == .trashContainer { throw NSFileProviderError(.noSuchItem) }
        let offset = pageOffset(page)
        if container == .workingSet {
            let records = try store.nonRootItems(offset: offset, limit: Self.pageSize)
            return pageResult(records, offset: offset)
        }
        guard let folder = try store.item(storageIdentifier(container)) else {
            throw NSFileProviderError(.noSuchItem)
        }
        if offset == 0 {
            if try await rescan(folder) == .removed { throw NSFileProviderError(.noSuchItem) }
        }
        let records = try store.children(of: folder.identifier, offset: offset, limit: Self.pageSize)
        return pageResult(records, offset: offset)
    }

    public func changes(in container: NSFileProviderItemIdentifier, since anchor: NSFileProviderSyncAnchor) async throws -> ChangeBatch {
        if container == .trashContainer { throw NSFileProviderError(.noSuchItem) }
        let anchorSeq = Self.decodeAnchor(anchor)
        // Expired when the seq just after the anchor was pruned: oldest != nil && anchor + 1 < oldest.
        if let oldest = try store.oldestRetainedSeq(), anchorSeq + 1 < oldest {
            throw NSFileProviderError(.syncAnchorExpired)
        }
        try await rescanForChanges(in: container)
        let rows = try store.changes(after: anchorSeq, limit: Self.changeBatchSize)
        let batch = try makeBatch(rows: rows, container: container, fallback: anchor)
        try store.pruneChanges(keepLast: Self.changesRetained)
        return batch
    }

    public func currentAnchor() async throws -> NSFileProviderSyncAnchor {
        Self.encodeAnchor(try store.currentAnchor())
    }

    public func fetchContents(for identifier: NSFileProviderItemIdentifier, into directory: URL, progress: Progress) async throws -> (URL, FileProviderItem) {
        let existing = try await item(for: identifier)
        let record = existing.record
        let entry = try await stat(record.relativePath)
        progress.totalUnitCount = entry.size
        let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(record.name)")
        try await connection.withClient { client in
            try await client.download(record.relativePath, to: destination, progress: { bytes, total in
                progress.totalUnitCount = total
                progress.completedUnitCount = bytes
                return !progress.isCancelled
            })
        }
        let refreshed = self.record(from: entry, identifier: record.identifier,
                                    parentIdentifier: record.parentIdentifier, lastScanned: record.lastScanned)
        if refreshed.contentVersion != record.contentVersion || refreshed.metadataVersion != record.metadataVersion {
            try store.recordLocalUpsert(refreshed)
        }
        return (destination, makeItem(refreshed))
    }

    public func createItem(template: NSFileProviderItem, fields: NSFileProviderItemFields, contents: URL?, mayAlreadyExist: Bool, progress: Progress) async throws -> FileProviderItem {
        let parentID = storageIdentifier(template.parentItemIdentifier)
        let filename = template.filename
        let isFolder = template.contentType == .folder
        guard let parent = try store.item(parentID) else { throw NSFileProviderError(.noSuchItem) }
        let path = SMBPath.join(parent.relativePath, filename)
        do {
            if isFolder {
                try await connection.withClient { try await $0.createDirectory(path) }
            } else {
                let source = try localContents(contents)
                defer { if contents == nil { try? FileManager.default.removeItem(at: source) } }
                try await upload(from: source, to: path, overwrite: false, progress: progress)
            }
        } catch SMBError.alreadyExists {
            if mayAlreadyExist { return try await adoptExisting(path: path, parentID: parentID) }
            throw SMBError.alreadyExists
        }
        let entry = try await stat(path)
        let created = try observedRecord(entry, path: path, fallbackParent: parentID)
        try store.recordLocalUpsert(created)
        return makeItem(created)
    }

    public func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents: URL?, progress: Progress) async throws -> FileProviderItem {
        let identifier = item.itemIdentifier.rawValue
        let requestedName = item.filename
        let requestedParent = item.parentItemIdentifier
        let baseContent = Data(baseVersion.contentVersion)
        guard var record = try store.item(identifier) else { throw NSFileProviderError(.noSuchItem) }

        if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
            let newName = changedFields.contains(.filename) ? requestedName : record.name
            let newParentID = changedFields.contains(.parentItemIdentifier) ? storageIdentifier(requestedParent) : record.parentIdentifier
            guard let newParent = try store.item(newParentID) else { throw NSFileProviderError(.noSuchItem) }
            let newPath = SMBPath.join(newParent.relativePath, newName)
            let sourcePath = record.relativePath
            try await connection.withClient { try await $0.move(sourcePath, to: newPath) }
            try store.recordLocalMove(identifier: record.identifier, newParent: newParentID, newName: newName, newPath: newPath)
            guard let moved = try store.item(record.identifier) else { throw NSFileProviderError(.noSuchItem) }
            record = moved
        }

        if changedFields.contains(.contents), let contents {
            let serverEntry: RemoteEntry
            do {
                serverEntry = try await stat(record.relativePath)
            } catch SMBError.notFound {
                // The file is gone on the server. Put the user's bytes back at the same path.
                // A missing parent still throws from the upload.
                try await upload(from: contents, to: record.relativePath, overwrite: false, progress: progress)
                let after = try await stat(record.relativePath)
                let recreated = self.record(from: after, identifier: record.identifier,
                                            parentIdentifier: record.parentIdentifier, lastScanned: record.lastScanned)
                try store.recordLocalUpsert(recreated)
                return makeItem(recreated)
            }
            let serverRecord = self.record(from: serverEntry, identifier: record.identifier,
                                           parentIdentifier: record.parentIdentifier, lastScanned: record.lastScanned)
            if serverRecord.contentVersion != baseContent {
                let conflictName = ConflictNamer.name(for: record.name, device: deviceName, date: now())
                let conflictPath = SMBPath.join(SMBPath.parent(of: record.relativePath), conflictName)
                try await upload(from: contents, to: conflictPath, overwrite: false, progress: progress)
                let conflictEntry = try await stat(conflictPath)
                let conflict = try observedRecord(conflictEntry, path: conflictPath, fallbackParent: record.parentIdentifier)
                try store.recordLocalUpsert(conflict)
                signalWorkingSet()
                let refreshedEntry = try await stat(record.relativePath)
                let refreshed = self.record(from: refreshedEntry, identifier: record.identifier,
                                            parentIdentifier: record.parentIdentifier, lastScanned: record.lastScanned)
                try store.recordLocalUpsert(refreshed)
                return makeItem(refreshed)
            }
            try await upload(from: contents, to: record.relativePath, overwrite: true, progress: progress)
            let after = try await stat(record.relativePath)
            let updated = self.record(from: after, identifier: record.identifier,
                                     parentIdentifier: record.parentIdentifier, lastScanned: record.lastScanned)
            try store.recordLocalUpsert(updated)
            return makeItem(updated)
        }

        return makeItem(record)
    }

    public func deleteItem(_ identifier: NSFileProviderItemIdentifier) async throws {
        guard let record = try store.item(storageIdentifier(identifier)) else {
            throw NSFileProviderError(.noSuchItem)
        }
        do {
            try await connection.withClient { try await $0.remove(record.relativePath) }
        } catch SMBError.notFound {
            // Already gone on the server. Drop the local row anyway.
        }
        try store.recordLocalDelete(identifier: record.identifier)
    }

    // MARK: - Scanning

    private enum ScanResult: Sendable { case scanned, removed }

    private func rescanForChanges(in container: NSFileProviderItemIdentifier) async throws {
        if container == .workingSet {
            let cutoff = now().addingTimeInterval(-Self.rescanInterval)
            let folders = try store.foldersNeedingScan(olderThan: cutoff, limit: Self.maxFoldersPerRescan)
            for folder in folders {
                _ = try await rescan(folder)
            }
            return
        }
        guard let folder = try store.item(storageIdentifier(container)) else {
            throw NSFileProviderError(.noSuchItem)
        }
        if folder.isDirectory {
            _ = try await rescan(folder)
        }
    }

    /// Lists `folder`, diffs it, and applies the result. A missing non-root folder is deleted locally.
    private func rescan(_ folder: ItemRecord) async throws -> ScanResult {
        let previouslyScanned = folder.lastScanned != nil
        let listing: [RemoteEntry]
        do {
            listing = try await connection.withClient { try await $0.list(folder.relativePath) }
        } catch SMBError.notFound {
            if folder.identifier == ItemRecord.rootIdentifier { throw SMBError.notFound }
            try store.recordLocalDelete(identifier: folder.identifier)
            if previouslyScanned { signalWorkingSet() }
            return .removed
        }
        let existing = try store.children(of: folder.identifier)
        let diff = FolderScanner.diff(folder: folder, existing: existing, listing: listing)
        try store.apply(diff, scannedAt: now())
        if !diff.isEmpty && previouslyScanned { signalWorkingSet() }
        return .scanned
    }

    private func makeBatch(rows: [ChangeRecord], container: NSFileProviderItemIdentifier, fallback: NSFileProviderSyncAnchor) throws -> ChangeBatch {
        let filter = container == .workingSet ? nil : storageIdentifier(container)
        var latest: [String: ChangeRecord] = [:]
        var order: [String] = []
        for row in rows {
            if latest[row.identifier] == nil { order.append(row.identifier) }
            latest[row.identifier] = row
        }
        var updated: [FileProviderItem] = []
        var deleted: [NSFileProviderItemIdentifier] = []
        for identifier in order {
            guard let row = latest[identifier] else { continue }
            if let filter, row.parentIdentifier != filter { continue }
            switch row.kind {
            case .delete:
                deleted.append(NSFileProviderItemIdentifier(identifier))
            case .update:
                guard let record = try store.item(identifier) else { continue }
                updated.append(makeItem(record))
            }
        }
        let anchor: NSFileProviderSyncAnchor
        if let seq = rows.last?.seq {
            anchor = Self.encodeAnchor(seq)
        } else {
            anchor = fallback
        }
        return ChangeBatch(updated: updated, deleted: deleted, anchor: anchor, moreComing: rows.count == Self.changeBatchSize)
    }

    // MARK: - SMB

    private func stat(_ path: String) async throws -> RemoteEntry {
        try await connection.withClient { try await $0.stat(path) }
    }

    private func upload(from localURL: URL, to path: String, overwrite: Bool, progress: Progress) async throws {
        let values = try localURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize { progress.totalUnitCount = Int64(size) }
        try await connection.withClient { client in
            try await client.upload(from: localURL, to: path, overwrite: overwrite, progress: { bytes in
                progress.completedUnitCount = bytes
                return !progress.isCancelled
            })
        }
    }

    private func adoptExisting(path: String, parentID: String) async throws -> FileProviderItem {
        let entry = try await stat(path)
        let adopted = try observedRecord(entry, path: path, fallbackParent: parentID)
        try store.recordLocalUpsert(adopted)
        return makeItem(adopted)
    }

    /// A rescan can insert this path under its own identifier before we record the upload.
    /// Reuse that row so the same path does not get a second identifier.
    private func observedRecord(_ entry: RemoteEntry, path: String, fallbackParent: String) throws -> ItemRecord {
        let existing = try store.item(atPath: path) ?? store.item(atPath: entry.path)
        return record(
            from: entry,
            identifier: existing?.identifier ?? UUID().uuidString,
            parentIdentifier: existing?.parentIdentifier ?? fallbackParent,
            lastScanned: existing?.lastScanned)
    }

    private func localContents(_ contents: URL?) throws -> URL {
        if let contents { return contents }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: empty)
        return empty
    }

    // MARK: - Records and pages

    private func makeItem(_ record: ItemRecord) -> FileProviderItem {
        FileProviderItem(record: record, rootDisplayName: server.displayName)
    }

    private func record(from entry: RemoteEntry, identifier: String, parentIdentifier: String, lastScanned: Date?) -> ItemRecord {
        var record = ItemRecord.from(entry, identifier: identifier, parentIdentifier: parentIdentifier)
        record.lastScanned = lastScanned
        return record
    }

    private func storageIdentifier(_ identifier: NSFileProviderItemIdentifier) -> String {
        identifier == .rootContainer ? ItemRecord.rootIdentifier : identifier.rawValue
    }

    private func pageResult(_ records: [ItemRecord], offset: Int) -> (items: [FileProviderItem], nextPage: Data?) {
        let items = records.map(makeItem)
        let next: Data? = records.count == Self.pageSize ? Data(String(offset + Self.pageSize).utf8) : nil
        return (items, next)
    }

    private func pageOffset(_ page: Data?) -> Int {
        guard let page else { return 0 }
        let initialName = NSFileProviderPage.initialPageSortedByName as Data
        let initialDate = NSFileProviderPage.initialPageSortedByDate as Data
        if page == initialName || page == initialDate { return 0 }
        guard let value = Int(String(decoding: page, as: UTF8.self)), value >= 0 else { return 0 }
        return value
    }

    private static func decodeAnchor(_ anchor: NSFileProviderSyncAnchor) -> Int64 {
        Int64(String(data: anchor.rawValue, encoding: .utf8) ?? "") ?? 0
    }

    private static func encodeAnchor(_ seq: Int64) -> NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(Data(String(seq).utf8))
    }
}
