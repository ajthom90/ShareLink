import Testing
@testable import ShareLinkKit

@Suite struct HiddenNamesTests {
    @Test(arguments: [".DS_Store", "Thumbs.db", "thumbs.db", "desktop.ini", "~$Report.docx", ".hidden", "$RECYCLE.BIN", "System Volume Information"])
    func hidden(name: String) { #expect(HiddenNames.isHidden(name)) }

    @Test(arguments: ["Report.docx", "~Report.docx", "a.b", "Desktop"])
    func visible(name: String) { #expect(!HiddenNames.isHidden(name)) }
}
