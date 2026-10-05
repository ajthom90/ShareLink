import Testing
@testable import ShareLinkKit

@Suite struct AcknowledgementsTests {
    @Test func bundledLicensesPresent() {
        let names = Acknowledgements.all().map(\.name)
        #expect(names.contains("ShareLink"))
        #expect(names.contains("libsmb2"))
        #expect(names.contains("AMSMB2"))
        #expect(names.contains("GRDB.swift"))
        let libsmb2 = Acknowledgements.all().first { $0.name == "libsmb2" }!
        #expect(libsmb2.text.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        #expect(libsmb2.text.contains("RSA Data Security, Inc. MD4 Message-Digest Algorithm"))
    }

    @Test func shareLinkFirstThenAlphabetical() {
        let items = Acknowledgements.all()
        #expect(items.map(\.name) == ["ShareLink", "AMSMB2", "GRDB.swift", "libsmb2"])
        #expect(items.map(\.license) == ["MIT", "LGPL-2.1", "MIT", "LGPL-2.1-or-later"])
    }
}
