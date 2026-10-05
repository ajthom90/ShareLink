import Foundation

public enum FolderScanner {
    public static func diff(
        folder: ItemRecord,
        existing: [ItemRecord],
        listing: [RemoteEntry],
        makeIdentifier: () -> String = { UUID().uuidString }
    ) -> FolderDiff {
        var byName: [String: ItemRecord] = [:]
        for item in existing where byName[item.name] == nil {
            byName[item.name] = item
        }

        var matched = Set<String>()
        var updates: [ItemRecord] = []
        var unmatchedListing: [RemoteEntry] = []

        // Skip hidden listing names only when no existing child has that name.
        for entry in listing {
            if let current = byName[entry.name] {
                matched.insert(current.identifier)
                if changed(current, entry) {
                    updates.append(record(folder: folder, entry: entry, identifier: current.identifier, lastScanned: current.lastScanned))
                }
            } else if !HiddenNames.isHidden(entry.name) {
                unmatchedListing.append(entry)
            }
        }

        var unmatchedExisting = existing.filter { !matched.contains($0.identifier) }
        var inserts: [ItemRecord] = []
        var renamedDirectories: [DirectoryRename] = []

        for entry in unmatchedListing {
            let fileID = Int64(bitPattern: entry.fileID)
            if entry.fileID != 0,
               let index = unmatchedExisting.firstIndex(where: {
                   $0.fileID == fileID && $0.isDirectory == entry.isDirectory
               }) {
                let current = unmatchedExisting.remove(at: index)
                let newPath = SMBPath.join(folder.relativePath, entry.name)
                if current.isDirectory {
                    renamedDirectories.append(DirectoryRename(oldPath: current.relativePath, newPath: newPath))
                }
                updates.append(record(folder: folder, entry: entry, identifier: current.identifier, lastScanned: current.lastScanned))
            } else {
                inserts.append(record(folder: folder, entry: entry, identifier: makeIdentifier(), lastScanned: nil))
            }
        }

        return FolderDiff(
            folderIdentifier: folder.identifier,
            inserts: inserts,
            updates: updates,
            deletes: unmatchedExisting.map(\.identifier),
            renamedDirectories: renamedDirectories)
    }

    private static func changed(_ current: ItemRecord, _ entry: RemoteEntry) -> Bool {
        current.size != entry.size
            || current.modified != entry.modified
            || current.isDirectory != entry.isDirectory
            || current.fileID != Int64(bitPattern: entry.fileID)
    }

    private static func record(folder: ItemRecord, entry: RemoteEntry, identifier: String, lastScanned: Date?) -> ItemRecord {
        var item = ItemRecord.from(entry, identifier: identifier, parentIdentifier: folder.identifier)
        item.name = entry.name
        item.relativePath = SMBPath.join(folder.relativePath, entry.name)
        item.lastScanned = lastScanned
        return item
    }
}
