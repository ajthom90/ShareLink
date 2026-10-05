import FileProvider
import ShareLinkKit

struct FileProviderDomainManager: DomainManaging {
    func domains() async throws -> [DomainInfo] {
        try await NSFileProviderManager.domains().map {
            DomainInfo(id: $0.identifier.rawValue, displayName: $0.displayName)
        }
    }

    func addOrUpdate(id: String, displayName: String) async throws {
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: displayName)
        try await NSFileProviderManager.add(domain)
    }

    func remove(id: String) async throws {
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "")
        // FILEPROVIDER_API_AVAILABILITY_V4_0_IOS is API_AVAILABLE(ios(16.0)). Checked against the iOS 27 SDK.
        if #available(iOS 16.0, *) {
            _ = try await NSFileProviderManager.remove(domain, mode: .removeAll)
        } else {
            try await NSFileProviderManager.remove(domain)
        }
    }

    private func manager(_ id: String) async -> NSFileProviderManager? {
        guard let domain = try? await NSFileProviderManager.domains().first(where: { $0.identifier.rawValue == id }) else {
            return nil
        }
        return NSFileProviderManager(for: domain)
    }

    func signalWorkingSet(id: String) async {
        try? await manager(id)?.signalEnumerator(for: .workingSet)
    }

    func evictAll(id: String) async {
        try? await manager(id)?.evictItem(identifier: .rootContainer)
    }

    func userVisibleRootURL(id: String) async -> URL? {
        try? await manager(id)?.getUserVisibleURL(for: .rootContainer)
    }
}
