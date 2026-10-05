import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct FolderScannerTests {
    let folder = ItemRecord(identifier: "F", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "Docs", name: "Docs",
                            isDirectory: true, size: 0, modified: .distantPast, created: nil, fileID: 1, lastScanned: nil)
    func entry(_ name: String, size: Int64 = 1, t: TimeInterval = 10, id: UInt64 = 0, dir: Bool = false) -> RemoteEntry {
        RemoteEntry(name: name, path: "Docs/\(name)", isDirectory: dir, size: size, modified: Date(timeIntervalSince1970: t), created: nil, fileID: id)
    }
    func record(_ id: String, _ e: RemoteEntry) -> ItemRecord { ItemRecord.from(e, identifier: id, parentIdentifier: "F") }
    func ids() -> () -> String { var n = 0; return { n += 1; return "new\(n)" } }

    @Test func insertsNewSkippingHidden() {
        let d = FolderScanner.diff(folder: folder, existing: [], listing: [entry("a.docx"), entry("~$a.docx"), entry(".DS_Store")], makeIdentifier: ids())
        #expect(d.inserts.map(\.identifier) == ["new1"])
        #expect(d.inserts[0].relativePath == "Docs/a.docx")
        #expect(d.inserts[0].parentIdentifier == "F")
        #expect(d.updates.isEmpty && d.deletes.isEmpty)
    }

    @Test func unchangedProducesEmptyDiff() {
        let e = entry("a.docx", id: 5)
        let d = FolderScanner.diff(folder: folder, existing: [record("A", e)], listing: [e])
        #expect(d.isEmpty)
    }

    @Test func modifiedKeepsIdentifier() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx", size: 1, t: 10, id: 5))],
                                   listing: [entry("a.docx", size: 2, t: 20, id: 5)])
        #expect(d.updates.map(\.identifier) == ["A"])
        #expect(d.updates[0].size == 2)
    }

    @Test func replaceSaveKeepsIdentifier() {
        // Windows/Office: temp file renamed over original -> same name, new fileID, new mtime.
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx", size: 1, t: 10, id: 5))],
                                   listing: [entry("a.docx", size: 3, t: 30, id: 99)])
        #expect(d.updates.map(\.identifier) == ["A"])
        #expect(d.updates[0].fileID == 99)
        #expect(d.inserts.isEmpty && d.deletes.isEmpty)
    }

    @Test func serverRenameDetectedByFileID() {
        let d = FolderScanner.diff(folder: folder, existing: [record("S", entry("Old", id: 7, dir: true))],
                                   listing: [entry("New", id: 7, dir: true)])
        #expect(d.updates.map(\.identifier) == ["S"])
        #expect(d.updates[0].relativePath == "Docs/New")
        #expect(d.renamedDirectories == [DirectoryRename(oldPath: "Docs/Old", newPath: "Docs/New")])
        #expect(d.inserts.isEmpty && d.deletes.isEmpty)
    }

    @Test func zeroFileIDRenameIsDeletePlusInsert() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("old.txt", id: 0))],
                                   listing: [entry("new.txt", id: 0)], makeIdentifier: ids())
        #expect(d.deletes == ["A"])
        #expect(d.inserts.map(\.identifier) == ["new1"])
    }

    @Test func removedChildIsDeleted() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx"))], listing: [])
        #expect(d.deletes == ["A"])
    }

    @Test func hiddenNameCreatedLocallySurvivesRescan() {
        let hidden = entry("~$a.docx")
        let d = FolderScanner.diff(folder: folder, existing: [record("H", hidden)], listing: [hidden], makeIdentifier: ids())
        #expect(d.deletes.isEmpty)
        #expect(d.inserts.isEmpty)
    }

    @Test func hiddenNameNotInDBStaysHidden() {
        let d = FolderScanner.diff(folder: folder, existing: [], listing: [entry("~$b.docx")], makeIdentifier: ids())
        #expect(d.inserts.isEmpty)
        #expect(d.deletes.isEmpty)
    }
}
