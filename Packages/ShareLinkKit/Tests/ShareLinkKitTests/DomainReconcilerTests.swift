import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct DomainReconcilerTests {
    @Test func addsRemovesRenames() async throws {
        let mgr = FakeDomainManager()
        try await mgr.addOrUpdate(id: "gone", displayName: "Old")
        try await mgr.addOrUpdate(id: "keep", displayName: "Before")
        let creds = InMemoryCredentialStore()
        try creds.setCredential(Credential(username: "u", password: "p"), for: "gone")
        let removedData = LockedBox<[String]>([])
        let r = DomainReconciler(manager: mgr, credentials: creds, removeLocalData: { id in removedData.mutate { $0.append(id) } })
        let servers = [
            ServerConfig(id: "keep", source: .user, displayName: "After", host: "h", share: "s"),
            ServerConfig(id: "new", source: .user, displayName: "New", host: "h", share: "s"),
        ]
        let result = try await r.reconcile(servers: servers)
        #expect(result == ReconcileResult(added: ["new"], removed: ["gone"], renamed: ["keep"]))
        #expect(try await mgr.domains().map(\.id) == ["keep", "new"])
        #expect(try creds.credential(for: "gone") == nil)
        #expect(removedData.value == ["gone"])
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private var v: T; private let l = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { l.withLock { v } }
    func mutate(_ f: (inout T) -> Void) { l.withLock { f(&v) } }
}
