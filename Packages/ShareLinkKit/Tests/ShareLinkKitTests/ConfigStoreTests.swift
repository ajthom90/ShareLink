import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConfigStoreTests {
    func makeStore() -> ConfigStore {
        ConfigStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }
    let managedServer = ServerConfig(id: "managed-1-aaaaaaaaaaaa", source: .managed(slot: 1), displayName: "M", host: "m.example.com", share: "S")
    let userServer = ServerConfig(id: "user-1", source: .user, displayName: "U", host: "u.example.com", share: "S")

    @Test func roundTripsManagedAndUser() {
        let store = makeStore()
        store.managed = ManagedConfiguration(servers: [managedServer], allowUserServers: true, supportMessage: "Hi")
        store.saveUserServer(userServer)
        #expect(store.managed.supportMessage == "Hi")
        #expect(store.allServers().map(\.id) == [managedServer.id, userServer.id])
        #expect(store.server(id: "user-1") == userServer)
    }

    @Test func userServersHiddenWhenNotAllowed() {
        let store = makeStore()
        store.saveUserServer(userServer)
        store.managed = ManagedConfiguration(servers: [managedServer], allowUserServers: false)
        #expect(store.allServers().map(\.id) == [managedServer.id])
        #expect(store.server(id: "user-1") == nil)
    }

    @Test func saveReplacesAndRemoveDeletes() {
        let store = makeStore()
        store.saveUserServer(userServer)
        var edited = userServer; edited.displayName = "Edited"
        store.saveUserServer(edited)
        #expect(store.userServers.map(\.displayName) == ["Edited"])
        store.removeUserServer(id: "user-1")
        #expect(store.userServers.isEmpty)
    }
}
