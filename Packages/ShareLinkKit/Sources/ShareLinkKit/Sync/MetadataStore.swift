import Foundation
import GRDB

public final class MetadataStore: Sendable {
    private let queue: DatabaseQueue

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("metadata.sqlite").path)
        try Self.migrate(queue)
        self.queue = queue
    }

    public static func inMemory() throws -> MetadataStore {
        let queue = try DatabaseQueue()
        try migrate(queue)
        return MetadataStore(queue: queue)
    }

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public func item(_ identifier: String) throws -> ItemRecord? {
        try queue.read { db in
            try ItemRecord.fetchOne(db, key: identifier)
        }
    }

    public func item(atPath path: String) throws -> ItemRecord? {
        try queue.read { db in
            try ItemRecord.fetchOne(db, sql: "SELECT * FROM items WHERE relativePath = ?", arguments: [path])
        }
    }

    public func children(of parent: String) throws -> [ItemRecord] {
        try queue.read { db in
            try Self.fetchChildren(db, parent: parent, offset: nil, limit: nil)
        }
    }

    public func children(of parent: String, offset: Int, limit: Int) throws -> [ItemRecord] {
        try queue.read { db in
            try Self.fetchChildren(db, parent: parent, offset: offset, limit: limit)
        }
    }

    public func nonRootItems(offset: Int, limit: Int) throws -> [ItemRecord] {
        try queue.read { db in
            try ItemRecord.fetchAll(db, sql: """
                SELECT * FROM items
                WHERE identifier != ?
                ORDER BY name COLLATE NOCASE, identifier
                LIMIT ? OFFSET ?
                """, arguments: [ItemRecord.rootIdentifier, limit, offset])
        }
    }

    public func apply(_ diff: FolderDiff, scannedAt: Date) throws {
        try queue.write { db in
            for rename in diff.renamedDirectories {
                try Self.rewriteDescendants(db, oldPath: rename.oldPath, newPath: rename.newPath)
            }
            for record in diff.updates {
                try Self.upsertPreservingLastScanned(record, db: db)
            }
            for record in diff.inserts {
                try record.insert(db)
            }
            for identifier in diff.deletes {
                try Self.deleteSubtree(db, identifier: identifier)
            }
            for record in diff.inserts {
                try Self.appendChange(db, identifier: record.identifier, parentIdentifier: record.parentIdentifier, kind: .update)
            }
            for record in diff.updates {
                try Self.appendChange(db, identifier: record.identifier, parentIdentifier: record.parentIdentifier, kind: .update)
            }
            if var folder = try ItemRecord.fetchOne(db, key: diff.folderIdentifier) {
                folder.lastScanned = scannedAt
                try folder.update(db)
            }
        }
    }

    public func recordLocalUpsert(_ record: ItemRecord) throws {
        try queue.write { db in
            // INSERT OR REPLACE drops a different identifier at this path without a delete change.
            if let occupant = try ItemRecord.fetchOne(db, sql: "SELECT * FROM items WHERE relativePath = ?", arguments: [record.relativePath]),
               occupant.identifier != record.identifier {
                try Self.deleteSubtree(db, identifier: occupant.identifier)
            }
            try record.insert(db, onConflict: .replace)
            try Self.appendChange(db, identifier: record.identifier, parentIdentifier: record.parentIdentifier, kind: .update)
        }
    }

    public func recordLocalMove(identifier: String, newParent: String, newName: String, newPath: String) throws {
        try queue.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: identifier) else {
                throw ItemRecord.recordNotFound(db, key: identifier)
            }
            if item.isDirectory {
                try Self.rewriteDescendants(db, oldPath: item.relativePath, newPath: newPath)
            }
            item.parentIdentifier = newParent
            item.name = newName
            item.relativePath = newPath
            try item.update(db)
            try Self.appendChange(db, identifier: identifier, parentIdentifier: newParent, kind: .update)
        }
    }

    public func recordLocalDelete(identifier: String) throws {
        try queue.write { db in
            try Self.deleteSubtree(db, identifier: identifier)
        }
    }

    public func currentAnchor() throws -> Int64 {
        try queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT MAX(seq) FROM changes") ?? 0
        }
    }

    public func oldestRetainedSeq() throws -> Int64? {
        try queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT MIN(seq) FROM changes")
        }
    }

    public func changes(after seq: Int64, limit: Int) throws -> [ChangeRecord] {
        try queue.read { db in
            try ChangeRecord.fetchAll(db, sql: """
                SELECT * FROM changes WHERE seq > ? ORDER BY seq LIMIT ?
                """, arguments: [seq, limit])
        }
    }

    public func pruneChanges(keepLast: Int) throws {
        try queue.write { db in
            try db.execute(sql: """
                DELETE FROM changes
                WHERE seq NOT IN (SELECT seq FROM changes ORDER BY seq DESC LIMIT ?)
                """, arguments: [keepLast])
        }
    }

    public func foldersNeedingScan(olderThan cutoff: Date, limit: Int) throws -> [ItemRecord] {
        try queue.read { db in
            try ItemRecord.fetchAll(db, sql: """
                SELECT * FROM items
                WHERE isDirectory = 1
                  AND lastScanned IS NOT NULL
                  AND lastScanned < ?
                ORDER BY lastScanned DESC, identifier
                LIMIT ?
                """, arguments: [cutoff.timeIntervalSince1970, limit])
        }
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE items (
                  identifier TEXT PRIMARY KEY NOT NULL,
                  parentIdentifier TEXT NOT NULL,
                  relativePath TEXT NOT NULL UNIQUE,
                  name TEXT NOT NULL,
                  isDirectory BOOLEAN NOT NULL,
                  size INTEGER NOT NULL,
                  modified DATETIME NOT NULL,
                  created DATETIME,
                  fileID INTEGER NOT NULL,
                  lastScanned DATETIME
                );
                CREATE INDEX items_parent ON items(parentIdentifier);
                CREATE TABLE changes (
                  seq INTEGER PRIMARY KEY AUTOINCREMENT,
                  identifier TEXT NOT NULL,
                  parentIdentifier TEXT NOT NULL,
                  kind TEXT NOT NULL
                );
                """)
        }
        try migrator.migrate(queue)
        try queue.write { db in
            if try ItemRecord.fetchOne(db, key: ItemRecord.rootIdentifier) == nil {
                let root = ItemRecord(
                    identifier: ItemRecord.rootIdentifier,
                    parentIdentifier: ItemRecord.rootIdentifier,
                    relativePath: "",
                    name: "",
                    isDirectory: true,
                    size: 0,
                    modified: Date(timeIntervalSince1970: 0),
                    created: nil,
                    fileID: 0,
                    lastScanned: nil)
                try root.insert(db)
            }
        }
    }

    /// Rewrites `oldPath/…` to `newPath/…`. The pattern escapes LIKE metacharacters
    /// and requires a `/` boundary so renaming `Docs` does not touch `Docs2`.
    private static func rewriteDescendants(_ db: Database, oldPath: String, newPath: String) throws {
        guard oldPath != newPath else { return }
        let pattern = likeEscape(oldPath) + "/%"
        try db.execute(sql: """
            UPDATE items
            SET relativePath = ? || substr(relativePath, length(?) + 1)
            WHERE relativePath LIKE ? ESCAPE '\\'
            """, arguments: [newPath, oldPath, pattern])
    }

    private static func likeEscape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static func upsertPreservingLastScanned(_ record: ItemRecord, db: Database) throws {
        if let existing = try ItemRecord.fetchOne(db, key: record.identifier) {
            var updated = record
            updated.lastScanned = existing.lastScanned
            try updated.update(db)
        } else {
            try record.insert(db)
        }
    }

    private static func deleteSubtree(_ db: Database, identifier: String) throws {
        let rows = try ItemRecord.fetchAll(db, sql: """
            WITH RECURSIVE subtree(identifier) AS (
              SELECT identifier FROM items WHERE identifier = ?
              UNION ALL
              SELECT i.identifier
              FROM items i
              JOIN subtree s ON i.parentIdentifier = s.identifier
              WHERE i.identifier != s.identifier
            )
            SELECT items.* FROM items
            JOIN subtree ON items.identifier = subtree.identifier
            ORDER BY length(items.relativePath), items.relativePath
            """, arguments: [identifier])
        var removed = Set<String>()
        for row in rows where removed.insert(row.identifier).inserted {
            try ItemRecord.deleteOne(db, key: row.identifier)
            try appendChange(db, identifier: row.identifier, parentIdentifier: row.parentIdentifier, kind: .delete)
        }
    }

    private static func appendChange(_ db: Database, identifier: String, parentIdentifier: String, kind: ChangeKind) throws {
        var change = ChangeRecord(seq: nil, identifier: identifier, parentIdentifier: parentIdentifier, kind: kind)
        try change.insert(db)
    }

    private static func fetchChildren(_ db: Database, parent: String, offset: Int?, limit: Int?) throws -> [ItemRecord] {
        if let offset, let limit {
            return try ItemRecord.fetchAll(db, sql: """
                SELECT * FROM items
                WHERE parentIdentifier = ? AND identifier != parentIdentifier
                ORDER BY name COLLATE NOCASE, identifier
                LIMIT ? OFFSET ?
                """, arguments: [parent, limit, offset])
        }
        return try ItemRecord.fetchAll(db, sql: """
            SELECT * FROM items
            WHERE parentIdentifier = ? AND identifier != parentIdentifier
            ORDER BY name COLLATE NOCASE, identifier
            """, arguments: [parent])
    }
}
