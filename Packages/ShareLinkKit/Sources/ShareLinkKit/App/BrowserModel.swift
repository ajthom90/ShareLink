import Foundation
import Observation

@MainActor
@Observable
public final class BrowserModel {
    public private(set) var entries: [RemoteEntry] = []
    public private(set) var error: SMBError?
    public private(set) var isLoading = false

    private let client: any SMBClient
    private let path: String

    public init(client: any SMBClient, path: String) {
        self.client = client
        self.path = path
    }

    /// Lists `path`, drops hidden names, and sorts folders first, then by name.
    public func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let listed = try await client.list(path)
            let visible = listed.filter { !HiddenNames.isHidden($0.name) }
            entries = visible.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order == .orderedSame {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return order == .orderedAscending
            }
        } catch let smb as SMBError {
            error = smb
        } catch {
            self.error = .other(error.localizedDescription)
        }
    }

    /// Downloads into a new temporary directory, keeping the entry's file name.
    public func download(_ entry: RemoteEntry) async throws -> URL {
        let name = URL(fileURLWithPath: entry.name).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            throw SMBError.other("The file name is not valid.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        do {
            try await client.download(entry.path, to: destination, progress: nil)
        } catch let smb as SMBError {
            throw smb
        } catch {
            throw SMBError.other(error.localizedDescription)
        }
        return destination
    }
}
