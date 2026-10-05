import Testing
import Foundation
@testable import ShareLinkKit

@MainActor @Suite struct AppModelTests {
    func make() -> (AppModel, FakeDomainManager, InMemoryCredentialStore, FakeSMBClient, UserDefaults) {
        let fake = FakeSMBClient()
        let creds = InMemoryCredentialStore()
        let mgr = FakeDomainManager()
        let fb = UserDefaults(suiteName: "fb-\(UUID().uuidString)")!
        let model = AppModel(configStore: ConfigStore(defaults: UserDefaults(suiteName: "cs-\(UUID().uuidString)")!),
                             credentials: creds, domains: mgr, clientFactory: FakeSMBClientFactory(client: fake),
                             feedbackDefaults: fb, appVersion: "1.0.0 (1)")
        return (model, mgr, creds, fake, fb)
    }
    let managed: [String: Any] = ["Host": "files.example.com", "Share": "Shared", "Username": "jdoe", "SupportMessage": "Use your network password"]

    @Test func startWithManagedConfigRequestsSignIn() async throws {
        let (model, mgr, _, _, fb) = make()
        await model.start(managedConfig: managed)
        #expect(model.servers.count == 1)
        #expect(model.signInRequest?.id == model.servers[0].id)
        #expect(model.status(for: model.servers[0].id) == .needsSignIn)
        #expect(model.savedUsername(for: model.servers[0].id) == "jdoe")
        #expect(try await mgr.domains().count == 1)
        #expect((fb.dictionary(forKey: ManagedFeedback.key)?["ConfiguredShares"] as? Int) == 1)
    }

    @Test func signInSuccessAndFailure() async throws {
        let (model, mgr, creds, fake, fb) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        await fake.failNext(.authenticationFailed)
        await #expect(throws: SMBError.authenticationFailed) { try await model.signIn(serverID: id, username: "jdoe", password: "bad") }
        #expect(model.status(for: id) == .needsSignIn)
        try await model.signIn(serverID: id, username: "jdoe", password: "good")
        #expect(model.status(for: id) == .signedIn)
        #expect(try creds.credential(for: id)?.password == "good")
        #expect(model.signInRequest == nil)
        #expect(await mgr.signaled.contains(id))
        #expect((fb.dictionary(forKey: ManagedFeedback.key)?["SignedInShares"] as? Int) == 1)
    }

    @Test func signOutEvicts() async throws {
        let (model, mgr, creds, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        try await model.signIn(serverID: id, username: "jdoe", password: "pw")
        await model.signOut(serverID: id)
        #expect(try creds.credential(for: id) == nil)
        #expect(await mgr.evicted == [id])
        #expect(model.status(for: id) == .needsSignIn)
    }

    @Test func managedRemovalRemovesDomain() async throws {
        let (model, mgr, _, _, _) = make()
        await model.start(managedConfig: managed)
        await model.applyManagedConfiguration([:])
        #expect(model.servers.isEmpty)
        #expect(try await mgr.domains().isEmpty)
    }

    @Test func userServersBlockedWhenDisallowed() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed.merging(["AllowUserServers": false]) { $1 })
        let s = ServerConfig(id: ServerConfig.newUserID(), source: .user, displayName: "Mine", host: "nas.example.com", share: "Home")
        await #expect(throws: SMBError.self) { try await model.saveUserServer(s, username: "me", password: nil) }
    }

    @Test func addAndRemoveUserServer() async throws {
        let (model, mgr, _, _, _) = make()
        await model.start(managedConfig: [:])
        let s = ServerConfig(id: ServerConfig.newUserID(), source: .user, displayName: "Mine", host: "nas.example.com", share: "Home")
        try await model.saveUserServer(s, username: "me", password: "pw")
        #expect(model.status(for: s.id) == .signedIn)
        #expect(try await mgr.domains().map(\.id) == [s.id])
        await model.removeUserServer(id: s.id)
        #expect(model.servers.isEmpty)
        #expect(try await mgr.domains().isEmpty)
    }

    @Test func deepLinkSelectsServer() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        model.signInRequest = nil
        model.handle(url: URL(string: "sharelink://signin?domain=\(id)")!)
        #expect(model.signInRequest?.id == id)
    }

    @Test func filesLocationDisabledUntilUserEnablesIt() async throws {
        let (model, mgr, _, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        await mgr.setUserEnabled(false, for: id)
        try await model.signIn(serverID: id, username: "jdoe", password: "pw")
        #expect(model.filesLocationEnabled[id] == false)
        await mgr.setUserEnabled(true, for: id)
        await model.appDidBecomeActive()
        #expect(model.filesLocationEnabled[id] == true)
    }

    @Test func startRefreshesFilesLocationForSignedInServer() async throws {
        let (model, mgr, creds, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        try creds.setCredential(Credential(username: "jdoe", password: "pw"), for: id)
        await mgr.setUserEnabled(false, for: id)
        await model.start(managedConfig: managed)
        #expect(model.filesLocationEnabled[id] == false)
    }

    @Test func openInFilesURLUsesSharedDocumentsScheme() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed)
        let url = await model.openInFilesURL(for: model.servers[0].id)
        #expect(url?.scheme == "shareddocuments")
    }

    @Test func feedbackCountsManagedSharesOnly() async throws {
        let (model, _, _, _, fb) = make()
        await model.start(managedConfig: managed)
        let user = ServerConfig(id: ServerConfig.newUserID(), source: .user, displayName: "Mine", host: "nas.example.com", share: "Home")
        try await model.saveUserServer(user, username: "me", password: "pw")
        #expect(model.status(for: user.id) == .signedIn)
        let before = fb.dictionary(forKey: ManagedFeedback.key)
        #expect(before?["ConfiguredShares"] as? Int == 1)
        #expect(before?["SignedInShares"] as? Int == 0)
        let managedID = try #require(model.servers.first { $0.isManaged }?.id)
        try await model.signIn(serverID: managedID, username: "jdoe", password: "pw")
        let after = fb.dictionary(forKey: ManagedFeedback.key)
        #expect(after?["ConfiguredShares"] as? Int == 1)
        #expect(after?["SignedInShares"] as? Int == 1)
    }
}
