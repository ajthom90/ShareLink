import Testing
@testable import ShareLinkKit

@Suite struct SMBPathTests {
    @Test(arguments: [
        ("", ""), ("/", ""), ("Finance", "Finance"), ("/Finance/Reports/", "Finance/Reports"),
        ("Finance\\Reports", "Finance/Reports"), ("  //Finance//Reports  ", "Finance/Reports"),
        ("./Finance/./Reports", "Finance/Reports"),
    ])
    func normalize(input: String, expected: String) {
        #expect(SMBPath.normalize(input) == expected)
    }

    @Test func joinParentLast() {
        #expect(SMBPath.join("", "a.docx") == "a.docx")
        #expect(SMBPath.join("Finance", "a.docx") == "Finance/a.docx")
        #expect(SMBPath.join("Finance/", "/Q3/a.docx") == "Finance/Q3/a.docx")
        #expect(SMBPath.parent(of: "Finance/Q3/a.docx") == "Finance/Q3")
        #expect(SMBPath.parent(of: "a.docx") == "")
        #expect(SMBPath.lastComponent("Finance/Q3/a.docx") == "a.docx")
        #expect(SMBPath.lastComponent("") == "")
    }
}
