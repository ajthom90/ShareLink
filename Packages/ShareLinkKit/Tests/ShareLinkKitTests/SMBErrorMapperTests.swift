import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct SMBErrorMapperTests {
    func posix(_ code: POSIXErrorCode, _ desc: String) -> POSIXError {
        POSIXError(code, userInfo: [NSLocalizedDescriptionKey: desc])
    }
    @Test func logonFailureIsAuth() {
        let e = posix(.ECONNREFUSED, "Error code ECONNREFUSED: Session setup failed with (0xc000006d) STATUS_LOGON_FAILURE.")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .authenticationFailed)
    }
    @Test func refusedTCPIsUnreachable() {
        let e = posix(.ECONNREFUSED, "Error code ECONNREFUSED: Connect failed with errno : Connection refused(61)")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .serverUnreachable)
    }
    @Test func accessDeniedDuringConnectIsAuthAfterIsPermission() {
        let e = posix(.EACCES, "Error code EACCES: Session setup failed with (0xc0000072) STATUS_ACCOUNT_DISABLED")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .authenticationFailed)
        #expect(SMBErrorMapper.map(posix(.EACCES, "STATUS_ACCESS_DENIED"), duringConnect: false) == .permissionDenied)
    }
    @Test func otherCodes() {
        #expect(SMBErrorMapper.map(posix(.ENOENT, "x"), duringConnect: false) == .notFound)
        #expect(SMBErrorMapper.map(posix(.EEXIST, "x"), duringConnect: false) == .alreadyExists)
        #expect(SMBErrorMapper.map(posix(.ENOTEMPTY, "x"), duringConnect: false) == .notEmpty)
        #expect(SMBErrorMapper.map(posix(.ETXTBSY, "x"), duringConnect: false) == .fileInUse)
        #expect(SMBErrorMapper.map(posix(.EDEADLK, "x"), duringConnect: false) == .fileInUse)
        #expect(SMBErrorMapper.map(posix(.ENOSPC, "x"), duringConnect: false) == .noSpace)
        for c in [POSIXErrorCode.ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .ECONNRESET, .ENOTCONN, .EPIPE] {
            #expect(SMBErrorMapper.map(posix(c, "x"), duringConnect: false) == .serverUnreachable)
        }
        #expect(SMBErrorMapper.map(CancellationError(), duringConnect: false) == .cancelled)
        #expect(SMBErrorMapper.map(SMBError.notFound, duringConnect: false) == .notFound)
    }
    @Test func encryptionRequiredButUnsupported() {
        let e = posix(.EINVAL, "Error code EINVAL: Server does not support encryption")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .encryptionUnsupported)
    }
}
