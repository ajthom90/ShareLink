import Foundation

public enum ConnectionTester {
    /// nil means the server accepted the credential and listed the share root.
    public static func test(server: ServerConfig, credential: Credential, factory: any SMBClientFactory) async -> SMBError? {
        let client = factory.makeClient(server: server, credential: credential)
        do {
            try await client.connect()
            _ = try await client.list("")
            await client.disconnect()
            return nil
        } catch {
            await client.disconnect()
            return SMBErrorMapper.map(error, duringConnect: true)
        }
    }
}
