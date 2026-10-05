import Testing
import Foundation
import FileProvider
import UniformTypeIdentifiers
@testable import ShareLinkKit

@Suite struct FileProviderItemTests {
    @Test func rootFileAndFolderMapping() throws {
        let store = try MetadataStore.inMemory()
        let root = try #require(try store.item(ItemRecord.rootIdentifier))
        let rootItem = FileProviderItem(record: root, rootDisplayName: "Finance")
        #expect(rootItem.itemIdentifier == .rootContainer)
        #expect(rootItem.filename == "Finance")
        #expect(!rootItem.capabilities.contains(.allowsDeleting))

        let file = ItemRecord(identifier: "A", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "a.docx", name: "a.docx",
                              isDirectory: false, size: 42, modified: Date(timeIntervalSince1970: 1), created: nil, fileID: 1, lastScanned: nil)
        let item = FileProviderItem(record: file, rootDisplayName: "Finance")
        #expect(item.parentItemIdentifier == .rootContainer)
        #expect(item.contentType == UTType(filenameExtension: "docx"))
        #expect(item.documentSize == 42)
        #expect(item.capabilities.contains(.allowsWriting))
        #expect(item.itemVersion.contentVersion == file.contentVersion)
    }

    @Test func errorMapping() {
        #expect((FileProviderErrors.nsError(for: SMBError.authenticationFailed) as NSError).code == NSFileProviderError.notAuthenticated.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.authenticationFailed).domain == NSFileProviderErrorDomain)
        #expect(FileProviderErrors.nsError(for: SMBError.alreadyExists).code == NSFileProviderError.filenameCollision.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.notFound).code == NSFileProviderError.noSuchItem.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.permissionDenied).domain == NSCocoaErrorDomain)
    }

    @Test func passesThroughFileProviderErrorsAndMapsTheRest() {
        let original = NSFileProviderError(.syncAnchorExpired) as NSError
        let passed = FileProviderErrors.nsError(for: original)
        #expect(passed.domain == original.domain)
        #expect(passed.code == original.code)

        let unreachable = FileProviderErrors.nsError(for: SMBError.serverUnreachable)
        #expect(unreachable.domain == NSFileProviderErrorDomain)
        #expect(unreachable.code == NSFileProviderError.serverUnreachable.rawValue)

        let quota = FileProviderErrors.nsError(for: SMBError.noSpace)
        #expect(quota.code == NSFileProviderError.insufficientQuota.rawValue)

        let inUse = FileProviderErrors.nsError(for: SMBError.fileInUse)
        #expect(inUse.code == NSFileProviderError.cannotSynchronize.rawValue)

        let cancelled = FileProviderErrors.nsError(for: SMBError.cancelled)
        #expect(cancelled.domain == NSCocoaErrorDomain)
        #expect(cancelled.code == CocoaError.userCancelled.rawValue)

        let empty = FileProviderErrors.nsError(for: SMBError.notEmpty)
        #expect(empty.domain == NSCocoaErrorDomain)
        #expect(empty.code == CocoaError.fileWriteUnknown.rawValue)
        #expect(empty.localizedDescription == SMBError.notEmpty.userMessage)

        let other = FileProviderErrors.nsError(for: SMBError.other("disk busy"))
        #expect(other.localizedDescription == "disk busy")

        let encryption = FileProviderErrors.nsError(for: SMBError.encryptionUnsupported)
        #expect(encryption.code == NSFileProviderError.serverUnreachable.rawValue)
    }
}
