import Foundation
@testable import ShareLinkKit

actor FakeDomainManager: DomainManaging {
    var current: [String: String] = [:]
    var signaled: [String] = []
    var evicted: [String] = []
    /// Per-id override. A domain with no entry is enabled. A missing domain is `nil`.
    var userEnabled: [String: Bool] = [:]
    func domains() async throws -> [DomainInfo] { current.map { DomainInfo(id: $0.key, displayName: $0.value) }.sorted { $0.id < $1.id } }
    func addOrUpdate(id: String, displayName: String) async throws { current[id] = displayName }
    func remove(id: String) async throws {
        current[id] = nil
        userEnabled[id] = nil
    }
    func signalWorkingSet(id: String) async { signaled.append(id) }
    func evictAll(id: String) async { evicted.append(id) }
    func userVisibleRootURL(id: String) async -> URL? { URL(fileURLWithPath: "/private/var/mobile/Library/CloudStorage/\(id)") }
    func setUserEnabled(_ enabled: Bool, for id: String) { userEnabled[id] = enabled }
    func isUserEnabled(id: String) async -> Bool? {
        guard current[id] != nil else { return nil }
        return userEnabled[id] ?? true
    }
}
