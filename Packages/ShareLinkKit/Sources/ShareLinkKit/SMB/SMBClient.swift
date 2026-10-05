import Foundation

public struct RemoteEntry: Equatable, Sendable {
    public var name: String
    public var path: String          // relative to the server's rootPath, normalized
    public var isDirectory: Bool
    public var size: Int64
    public var modified: Date
    public var created: Date?
    public var fileID: UInt64        // 0 = unknown

    public init(name: String, path: String, isDirectory: Bool, size: Int64, modified: Date, created: Date?, fileID: UInt64) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.created = created
        self.fileID = fileID
    }
}

public enum SMBError: Error, Equatable, Sendable {
    case authenticationFailed, notFound, alreadyExists, permissionDenied, serverUnreachable,
         encryptionUnsupported, noSpace, notEmpty, fileInUse, cancelled
    case other(String)

    public var userMessage: String {
        switch self {
        case .authenticationFailed:
            return "The username or password is incorrect."
        case .notFound:
            return "The item or share could not be found."
        case .alreadyExists:
            return "An item with that name already exists."
        case .permissionDenied:
            return "You don't have permission to do that."
        case .serverUnreachable:
            return "The server can't be reached. Check your network connection."
        case .encryptionUnsupported:
            return "The server doesn't support SMB encryption, which is required for this share."
        case .noSpace:
            return "The server is out of space."
        case .notEmpty:
            return "The folder isn't empty."
        case .fileInUse:
            return "The file is in use by someone else. Try again later."
        case .cancelled:
            return "The operation was cancelled."
        case .other(let message):
            return message
        }
    }
}

public typealias SMBReadProgress = @Sendable (_ bytes: Int64, _ total: Int64) -> Bool   // return false to cancel
public typealias SMBWriteProgress = @Sendable (_ bytes: Int64) -> Bool

public protocol SMBClient: Sendable {
    func connect() async throws
    func disconnect() async
    func list(_ path: String) async throws -> [RemoteEntry]
    func stat(_ path: String) async throws -> RemoteEntry
    func download(_ path: String, to localURL: URL, progress: SMBReadProgress?) async throws
    func upload(from localURL: URL, to path: String, overwrite: Bool, progress: SMBWriteProgress?) async throws
    func createDirectory(_ path: String) async throws
    func move(_ path: String, to newPath: String) async throws
    func remove(_ path: String) async throws        // files or directories (recursive)
}

public protocol SMBClientFactory: Sendable {
    func makeClient(server: ServerConfig, credential: Credential) -> any SMBClient
}
