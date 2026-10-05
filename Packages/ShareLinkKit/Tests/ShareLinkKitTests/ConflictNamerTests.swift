import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConflictNamerTests {
    @Test func names() {
        let date = ISO8601DateFormatter().date(from: "2026-10-05T14:32:00Z")!
        let utc = TimeZone(identifier: "UTC")!
        #expect(ConflictNamer.name(for: "Report.docx", device: "iPad", date: date, timeZone: utc) == "Report (Conflict iPad 2026-10-05 1432).docx")
        #expect(ConflictNamer.name(for: "Notes", device: "iPhone", date: date, timeZone: utc) == "Notes (Conflict iPhone 2026-10-05 1432)")
        #expect(ConflictNamer.name(for: "a.b.xlsx", device: "iPad", date: date, timeZone: utc) == "a.b (Conflict iPad 2026-10-05 1432).xlsx")
    }
}
