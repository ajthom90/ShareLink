import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct AppGroupTests {
    @Test func identifierIsStable() {
        #expect(AppGroup.identifier == "group.com.ajthom90.sharelink")
    }

    @Test func domainDirectoryIsUnderContainerAndSanitized() {
        let dir = AppGroup.domainDirectory(for: "managed-1-abc/../x")
        #expect(dir.path.hasPrefix(AppGroup.containerURL().path))
        #expect(!dir.lastPathComponent.contains("/"))
        #expect(dir.deletingLastPathComponent().lastPathComponent == "Domains")
    }
}
