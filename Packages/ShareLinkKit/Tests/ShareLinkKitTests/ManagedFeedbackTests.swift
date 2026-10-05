import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ManagedFeedbackTests {
    @Test func writesExpectedDictionary() {
        let defaults = UserDefaults(suiteName: "fb-\(UUID().uuidString)")!
        ManagedFeedback.write(configuredShares: 2, signedInShares: 1, configErrors: ["Share 2: missing Share2.Host"], appVersion: "1.0.0 (5)", to: defaults)
        let dict = defaults.dictionary(forKey: ManagedFeedback.key)
        #expect(dict?["ConfiguredShares"] as? Int == 2)
        #expect(dict?["SignedInShares"] as? Int == 1)
        #expect(dict?["ConfigErrors"] as? [String] == ["Share 2: missing Share2.Host"])
        #expect(dict?["AppVersion"] as? String == "1.0.0 (5)")
    }
}
