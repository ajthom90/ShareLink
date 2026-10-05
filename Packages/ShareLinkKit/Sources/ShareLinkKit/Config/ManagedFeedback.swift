import Foundation

public enum ManagedFeedback {
    public static let key = "com.apple.feedback.managed"

    public static func write(configuredShares: Int, signedInShares: Int, configErrors: [String],
                             appVersion: String, to defaults: UserDefaults = .standard) {
        defaults.set([
            "ConfiguredShares": configuredShares,
            "SignedInShares": signedInShares,
            "ConfigErrors": configErrors,
            "AppVersion": appVersion,
        ] as [String: Any], forKey: key)
    }
}
