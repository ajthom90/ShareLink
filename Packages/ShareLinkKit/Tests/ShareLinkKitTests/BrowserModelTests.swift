import Foundation
import Testing
@testable import ShareLinkKit

@MainActor @Suite struct BrowserModelTests {
    @Test func loadFiltersSortsAndDownloadWrites() async throws {
        let fake = FakeSMBClient()
        await fake.seedDirectory("Docs")
        await fake.seedFile("Docs/b.txt", contents: Data("B".utf8), modified: Date(timeIntervalSince1970: 2), fileID: 2)
        await fake.seedFile("Docs/a.txt", contents: Data("A".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        await fake.seedDirectory("Docs/Folder")
        await fake.seedFile("Docs/.hidden", contents: Data("x".utf8), modified: .now, fileID: 3)
        await fake.seedFile("Docs/~$lock.docx", contents: Data(), modified: .now, fileID: 4)
        await fake.seedFile("Docs/Thumbs.db", contents: Data(), modified: .now, fileID: 5)
        let model = BrowserModel(client: fake, path: "Docs")
        await model.load()
        #expect(model.error == nil)
        #expect(model.isLoading == false)
        #expect(model.entries.map(\.name) == ["Folder", "a.txt", "b.txt"])
        let file = try #require(model.entries.first { $0.name == "a.txt" })
        let url = try await model.download(file)
        #expect(url.lastPathComponent == "a.txt")
        #expect(try Data(contentsOf: url) == Data("A".utf8))
    }
}
