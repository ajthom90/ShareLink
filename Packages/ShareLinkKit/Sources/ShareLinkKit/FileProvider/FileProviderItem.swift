import Foundation
import FileProvider
import UniformTypeIdentifiers

public final class FileProviderItem: NSObject, NSFileProviderItem, @unchecked Sendable {
    public let record: ItemRecord
    private let rootDisplayName: String

    public init(record: ItemRecord, rootDisplayName: String) {
        self.record = record
        self.rootDisplayName = rootDisplayName
        super.init()
    }

    public var itemIdentifier: NSFileProviderItemIdentifier {
        record.identifier == ItemRecord.rootIdentifier
            ? .rootContainer
            : NSFileProviderItemIdentifier(record.identifier)
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        record.parentIdentifier == ItemRecord.rootIdentifier
            ? .rootContainer
            : NSFileProviderItemIdentifier(record.parentIdentifier)
    }

    public var filename: String {
        record.identifier == ItemRecord.rootIdentifier ? rootDisplayName : record.name
    }

    public var contentType: UTType {
        if record.isDirectory { return .folder }
        let ext = (record.name as NSString).pathExtension
        return UTType(filenameExtension: ext) ?? .data
    }

    public var documentSize: NSNumber? {
        record.isDirectory ? nil : NSNumber(value: record.size)
    }

    public var creationDate: Date? { record.created }

    public var contentModificationDate: Date? { record.modified }

    public var capabilities: NSFileProviderItemCapabilities {
        if record.identifier == ItemRecord.rootIdentifier {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]
        }
        if record.isDirectory {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems,
                    .allowsRenaming, .allowsReparenting, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting, .allowsDeleting]
    }

    public var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: record.contentVersion, metadataVersion: record.metadataVersion)
    }
}
