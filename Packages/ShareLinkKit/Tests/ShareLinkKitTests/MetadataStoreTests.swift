import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct MetadataStoreTests {
    let root = ItemRecord.rootIdentifier
    func rec(_ id: String, parent: String, path: String, dir: Bool = false, size: Int64 = 1, fileID: Int64 = 0) -> ItemRecord {
        ItemRecord(identifier: id, parentIdentifier: parent, relativePath: path, name: SMBPath.lastComponent(path),
                   isDirectory: dir, size: size, modified: Date(timeIntervalSince1970: 10), created: nil, fileID: fileID, lastScanned: nil)
    }

    @Test func rootExistsAndAnchorStartsAtZero() throws {
        let s = try MetadataStore.inMemory()
        #expect(try s.item(root)?.relativePath == "")
        #expect(try s.currentAnchor() == 0)
        #expect(try s.oldestRetainedSeq() == nil)
    }

    @Test func applyDiffRecordsChangesInOrder() throws {
        let s = try MetadataStore.inMemory()
        let a = rec("A", parent: root, path: "a.docx"), d = rec("D", parent: root, path: "Docs", dir: true)
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [a, d], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        #expect(try s.children(of: root).map(\.identifier) == ["A", "D"])   // "a.docx" < "Docs" NOCASE
        #expect(try s.item(root)?.lastScanned != nil)
        let ch = try s.changes(after: 0, limit: 10)
        #expect(ch.map(\.identifier) == ["A", "D"])
        #expect(ch.allSatisfy { $0.kind == .update && $0.parentIdentifier == root })
        #expect(try s.currentAnchor() == 2)
    }

    @Test func deleteRemovesSubtreeAndRecordsEachDeletion() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D", inserts: [rec("X", parent: "D", path: "Docs/x.txt")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        let before = try s.currentAnchor()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [], updates: [], deletes: ["D"], renamedDirectories: []), scannedAt: .now)
        #expect(try s.item("D") == nil)
        #expect(try s.item("X") == nil)
        #expect(Set(try s.changes(after: before, limit: 10).map(\.identifier)) == ["D", "X"])
        #expect(try s.changes(after: before, limit: 10).allSatisfy { $0.kind == .delete })
    }

    @Test func renameDirectoryRewritesDescendantPaths() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D", inserts: [rec("S", parent: "D", path: "Docs/Sub", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "S", inserts: [rec("X", parent: "S", path: "Docs/Sub/x.txt")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.recordLocalMove(identifier: "D", newParent: root, newName: "Papers", newPath: "Papers")
        #expect(try s.item("D")?.relativePath == "Papers")
        #expect(try s.item("S")?.relativePath == "Papers/Sub")
        #expect(try s.item("X")?.relativePath == "Papers/Sub/x.txt")
        #expect(try s.item(atPath: "Papers/Sub/x.txt")?.identifier == "X")
    }

    @Test func renameDoesNotTouchPrefixSiblings() throws {
        let s = try MetadataStore.inMemory()
        // Prefix siblings (Docs vs Docs2) and LIKE metacharacters (%, _, \).
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [
            rec("D", parent: root, path: "Docs", dir: true),
            rec("D2", parent: root, path: "Docs2", dir: true),
            rec("U", parent: root, path: "A_B", dir: true),
            rec("UX", parent: root, path: "AxB", dir: true),
            rec("P", parent: root, path: "100%", dir: true),
            rec("PX", parent: root, path: "1000", dir: true),
            rec("B", parent: root, path: "a\\b", dir: true),
            rec("BX", parent: root, path: "ab", dir: true),
        ], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D", inserts: [rec("X", parent: "D", path: "Docs/x.txt")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D2", inserts: [rec("Y", parent: "D2", path: "Docs2/x")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "U", inserts: [rec("UC", parent: "U", path: "A_B/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "UX", inserts: [rec("UXC", parent: "UX", path: "AxB/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "P", inserts: [rec("PC", parent: "P", path: "100%/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "PX", inserts: [rec("PXC", parent: "PX", path: "1000/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "B", inserts: [rec("BC", parent: "B", path: "a\\b/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "BX", inserts: [rec("BXC", parent: "BX", path: "ab/child")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)

        try s.recordLocalMove(identifier: "D", newParent: root, newName: "Papers", newPath: "Papers")
        try s.recordLocalMove(identifier: "U", newParent: root, newName: "RenamedU", newPath: "RenamedU")
        try s.recordLocalMove(identifier: "P", newParent: root, newName: "RenamedP", newPath: "RenamedP")
        try s.recordLocalMove(identifier: "B", newParent: root, newName: "RenamedB", newPath: "RenamedB")

        #expect(try s.item("X")?.relativePath == "Papers/x.txt")
        #expect(try s.item("Y")?.relativePath == "Docs2/x")
        #expect(try s.item("D2")?.relativePath == "Docs2")
        #expect(try s.item("UC")?.relativePath == "RenamedU/child")
        #expect(try s.item("UXC")?.relativePath == "AxB/child")
        #expect(try s.item("UX")?.relativePath == "AxB")
        #expect(try s.item("PC")?.relativePath == "RenamedP/child")
        #expect(try s.item("PXC")?.relativePath == "1000/child")
        #expect(try s.item("PX")?.relativePath == "1000")
        #expect(try s.item("BC")?.relativePath == "RenamedB/child")
        #expect(try s.item("BXC")?.relativePath == "ab/child")
        #expect(try s.item("BX")?.relativePath == "ab")
    }

    @Test func versionStableAcrossReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modified = Date(timeIntervalSince1970: 1_700_000_000.123456789)
        let original = ItemRecord(
            identifier: "A", parentIdentifier: root, relativePath: "a", name: "a",
            isDirectory: false, size: 42, modified: modified, created: nil, fileID: 0, lastScanned: nil)
        let version = original.contentVersion
        do {
            let s = try MetadataStore(directory: dir)
            try s.recordLocalUpsert(original)
        }
        let reloaded = try #require(try MetadataStore(directory: dir).item("A"))
        #expect(reloaded.contentVersion == version)
    }

    @Test func pruneKeepsNewest() throws {
        let s = try MetadataStore.inMemory()
        for i in 0..<10 { try s.recordLocalUpsert(rec("I\(i)", parent: root, path: "f\(i)")) }
        try s.pruneChanges(keepLast: 3)
        #expect(try s.oldestRetainedSeq() == 8)
        #expect(try s.currentAnchor() == 10)
    }

    @Test func foldersNeedingScan() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: Date(timeIntervalSince1970: 100))
        #expect(try s.foldersNeedingScan(olderThan: Date(timeIntervalSince1970: 200), limit: 10).map(\.identifier) == [root])  // D never scanned
        #expect(try s.foldersNeedingScan(olderThan: Date(timeIntervalSince1970: 50), limit: 10).isEmpty)
    }

    @Test func persistsAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { let s = try MetadataStore(directory: dir); try s.recordLocalUpsert(rec("A", parent: root, path: "a")) }
        let s2 = try MetadataStore(directory: dir)
        #expect(try s2.item("A") != nil)
        #expect(try s2.currentAnchor() == 1)
    }
}
