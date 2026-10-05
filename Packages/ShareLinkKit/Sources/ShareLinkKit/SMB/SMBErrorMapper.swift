import Foundation

public enum SMBErrorMapper {
    public static func map(_ error: any Error, duringConnect: Bool) -> SMBError {
        if let e = error as? SMBError { return e }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        let text = (ns.userInfo[NSLocalizedDescriptionKey] as? String ?? ns.localizedDescription).uppercased()
        if text.contains("LOGON_FAILURE") || text.contains("WRONG_PASSWORD") || text.contains("ACCOUNT_DISABLED")
            || text.contains("PASSWORD_EXPIRED") || text.contains("ACCOUNT_RESTRICTION") || text.contains("INVALID_LOGON_HOURS")
            || text.contains("ACCOUNT_LOCKED") {
            return .authenticationFailed
        }
        if text.contains("ENCRYPT") && (text.contains("NOT SUPPORT") || text.contains("DOES NOT SUPPORT")) {
            return .encryptionUnsupported
        }
        guard ns.domain == NSPOSIXErrorDomain, let code = POSIXErrorCode(rawValue: Int32(ns.code)) else {
            return .other(ns.localizedDescription)
        }
        switch code {
        case .ENOENT, .ENOTDIR: return .notFound
        case .EEXIST: return .alreadyExists
        case .EACCES, .EPERM: return duringConnect ? .authenticationFailed : .permissionDenied
        case .ENOTEMPTY: return .notEmpty
        case .ETXTBSY, .EDEADLK, .EBUSY: return .fileInUse
        case .ENOSPC, .EDQUOT: return .noSpace
        case .ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN, .ECONNRESET,
             .ENOTCONN, .EPIPE, .ECONNABORTED, .EHOSTDOWN: return .serverUnreachable
        case .ECANCELED: return .cancelled
        default: return .other(ns.localizedDescription)
        }
    }
}
