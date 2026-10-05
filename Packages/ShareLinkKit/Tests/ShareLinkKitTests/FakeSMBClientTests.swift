import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct FakeSMBClientTests {
    @Test func listStatUploadDownload() async throws {
        let fake = FakeSMBClient()
        await fake.seedDirectory("Docs")
        await fake.seedFile("Docs/a.docx", contents: Data("A".utf8), modified: Date(timeIntervalSince1970: 100), fileID: 7)
        let list = try await fake.list("Docs")
        #expect(list.map(\.name) == ["a.docx"])
        #expect(list[0].path == "Docs/a.docx")
        #expect(list[0].fileID == 7)
        #expect(try await fake.stat("Docs").isDirectory)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("BB".utf8).write(to: tmp)
        await #expect(throws: SMBError.alreadyExists) { try await fake.upload(from: tmp, to: "Docs/a.docx", overwrite: false, progress: nil) }
        try await fake.upload(from: tmp, to: "Docs/a.docx", overwrite: true, progress: nil)
        #expect(await fake.contents(of: "Docs/a.docx") == Data("BB".utf8))

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await fake.download("Docs/a.docx", to: out, progress: nil)
        #expect(try Data(contentsOf: out) == Data("BB".utf8))
    }

    @Test func errorsAndInjectedFailures() async throws {
        let fake = FakeSMBClient()
        await #expect(throws: SMBError.notFound) { try await fake.stat("missing") }
        await fake.failNext(.authenticationFailed)
        await #expect(throws: SMBError.authenticationFailed) { try await fake.list("") }
        _ = try await fake.list("")   // only the next call fails
    }

    @Test func replaceSaveChangesFileIDKeepsPath() async throws {
        let fake = FakeSMBClient()
        await fake.seedFile("a.docx", contents: Data("1".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        await fake.replaceSave("a.docx", contents: Data("22".utf8), modified: Date(timeIntervalSince1970: 2))
        let e = try await fake.stat("a.docx")
        #expect(e.fileID != 1)
        #expect(e.size == 2)
    }

    @Test func moveAndRemoveDirectoryRecursively() async throws {
        let fake = FakeSMBClient()
        await fake.seedDirectory("A")
        await fake.seedFile("A/x.txt", contents: Data(), modified: .now, fileID: 2)
        try await fake.move("A", to: "B")
        #expect(try await fake.list("B").map(\.path) == ["B/x.txt"])
        try await fake.remove("B")
        await #expect(throws: SMBError.notFound) { try await fake.stat("B/x.txt") }
    }
}
