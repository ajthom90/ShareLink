import Foundation
import GRDB

public struct ItemRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "items"
    /// Matches `NSFileProviderItemIdentifier.rootContainer.rawValue`.
    public static let rootIdentifier = "NSFileProviderRootContainerItemIdentifier"

    public var identifier: String
    public var parentIdentifier: String
    public var relativePath: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int64
    public var modified: Date
    public var created: Date?
    public var fileID: Int64
    public var lastScanned: Date?

    /// Full `Date` precision. The default GRDB strategy keeps only milliseconds,
    /// which changes `contentVersion` after a round trip.
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }

    public init(identifier: String, parentIdentifier: String, relativePath: String, name: String,
                isDirectory: Bool, size: Int64, modified: Date, created: Date?, fileID: Int64, lastScanned: Date?) {
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
        self.relativePath = relativePath
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.created = created
        self.fileID = fileID
        self.lastScanned = lastScanned
    }

    public var contentVersion: Data {
        ItemVersion.content(size: size, modified: modified, isDirectory: isDirectory)
    }

    public var metadataVersion: Data {
        ItemVersion.metadata(content: contentVersion, name: name)
    }

    public static func from(_ entry: RemoteEntry, identifier: String, parentIdentifier: String) -> ItemRecord {
        ItemRecord(
            identifier: identifier,
            parentIdentifier: parentIdentifier,
            relativePath: entry.path,
            name: entry.name,
            isDirectory: entry.isDirectory,
            size: entry.size,
            modified: entry.modified,
            created: entry.created,
            fileID: Int64(bitPattern: entry.fileID),
            lastScanned: nil)
    }
}

public enum ChangeKind: String, Codable, Sendable, DatabaseValueConvertible {
    case update, delete

    public var databaseValue: DatabaseValue { rawValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> ChangeKind? {
        String.fromDatabaseValue(dbValue).flatMap(ChangeKind.init(rawValue:))
    }
}

public struct ChangeRecord: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "changes"

    public var seq: Int64?
    public var identifier: String
    public var parentIdentifier: String
    public var kind: ChangeKind

    public init(seq: Int64?, identifier: String, parentIdentifier: String, kind: ChangeKind) {
        self.seq = seq
        self.identifier = identifier
        self.parentIdentifier = parentIdentifier
        self.kind = kind
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        seq = inserted.rowID
    }
}

public struct DirectoryRename: Equatable, Sendable {
    public var oldPath: String
    public var newPath: String

    public init(oldPath: String, newPath: String) {
        self.oldPath = oldPath
        self.newPath = newPath
    }
}

public struct FolderDiff: Equatable, Sendable {
    public var folderIdentifier: String
    public var inserts: [ItemRecord]
    public var updates: [ItemRecord]
    public var deletes: [String]
    public var renamedDirectories: [DirectoryRename]

    public var isEmpty: Bool {
        inserts.isEmpty && updates.isEmpty && deletes.isEmpty && renamedDirectories.isEmpty
    }

    public init(folderIdentifier: String, inserts: [ItemRecord], updates: [ItemRecord],
                deletes: [String], renamedDirectories: [DirectoryRename]) {
        self.folderIdentifier = folderIdentifier
        self.inserts = inserts
        self.updates = updates
        self.deletes = deletes
        self.renamedDirectories = renamedDirectories
    }
}
