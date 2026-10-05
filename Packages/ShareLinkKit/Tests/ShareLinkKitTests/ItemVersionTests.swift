import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ItemVersionTests {
    @Test func contentVersionFormat() {
        let d = Date(timeIntervalSince1970: 1.5)
        #expect(String(decoding: ItemVersion.content(size: 10, modified: d, isDirectory: false), as: UTF8.self) == "10-1500000000")
        #expect(String(decoding: ItemVersion.content(size: 10, modified: d, isDirectory: true), as: UTF8.self) == "0-1500000000")
        let m = ItemVersion.metadata(content: Data("10-1".utf8), name: "a.docx")
        #expect(String(decoding: m, as: UTF8.self) == "10-1-a.docx")
    }
}
