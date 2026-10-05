import Foundation
import FileProvider

public enum FileProviderErrors {
    /// Maps an `SMBError` to the File Provider / Cocoa error the system shows.
    /// An error already in `NSFileProviderErrorDomain` is returned unchanged.
    public static func nsError(for error: any Error) -> NSError {
        let ns = error as NSError
        if ns.domain == NSFileProviderErrorDomain { return ns }
        guard let smb = error as? SMBError else { return ns }
        switch smb {
        case .authenticationFailed:
            return NSFileProviderError(.notAuthenticated) as NSError
        case .serverUnreachable, .encryptionUnsupported:
            return NSFileProviderError(.serverUnreachable) as NSError
        case .notFound:
            return NSFileProviderError(.noSuchItem) as NSError
        case .alreadyExists:
            return NSFileProviderError(.filenameCollision) as NSError
        case .noSpace:
            return NSFileProviderError(.insufficientQuota) as NSError
        case .permissionDenied:
            return CocoaError(.fileWriteNoPermission) as NSError
        case .fileInUse:
            return NSFileProviderError(.cannotSynchronize) as NSError
        case .cancelled:
            return CocoaError(.userCancelled) as NSError
        case .notEmpty, .other:
            return NSError(domain: NSCocoaErrorDomain,
                           code: CocoaError.fileWriteUnknown.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: smb.userMessage])
        }
    }
}
