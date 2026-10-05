import FileProvider
import ShareLinkKit

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let engine: ProviderEngine?

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let serverID = domain.identifier.rawValue
        if let server = ConfigStore.shared().server(id: serverID),
           let store = try? MetadataStore(directory: AppGroup.domainDirectory(for: serverID)) {
            let connection = ConnectionProvider(
                server: server,
                credentials: KeychainCredentialStore(),
                factory: AMSMB2ClientFactory()
            )
            // NSFileProviderManager is not Sendable. The signal runs on the engine's executor.
            nonisolated(unsafe) let manager = NSFileProviderManager(for: domain)
            // UIDevice is main-actor-only; the app stores the model name in App Group defaults.
            let deviceName = AppGroup.defaults().string(forKey: AppGroup.deviceModelKey) ?? "iOS"
            engine = ProviderEngine(
                server: server,
                store: store,
                connection: connection,
                deviceName: deviceName,
                signalWorkingSet: { manager?.signalEnumerator(for: .workingSet) { _ in } }
            )
        } else {
            engine = nil
            DiagnosticLog.append("provider: no configuration for domain")
        }
        super.init()
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        guard let engine else {
            completionHandler(nil, NSFileProviderError(.notAuthenticated))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 100)
        nonisolated(unsafe) let completion = completionHandler
        let task = Task {
            do {
                let item = try await engine.item(for: identifier)
                completion(item, nil)
            } catch {
                completion(nil, providerReportedError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        guard let engine else {
            completionHandler(nil, nil, NSFileProviderError(.notAuthenticated))
            return Progress()
        }
        let directory: URL
        do {
            guard let manager = NSFileProviderManager(for: domain) else {
                completionHandler(nil, nil, NSFileProviderError(.cannotSynchronize))
                return Progress()
            }
            directory = try manager.temporaryDirectoryURL()
        } catch {
            completionHandler(nil, nil, NSFileProviderError(.cannotSynchronize))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 100)
        nonisolated(unsafe) let completion = completionHandler
        let task = Task {
            do {
                let (url, item) = try await engine.fetchContents(for: itemIdentifier, into: directory, progress: progress)
                completion(url, item, nil)
            } catch {
                completion(nil, nil, providerReportedError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        guard let engine else {
            completionHandler(nil, [], false, NSFileProviderError(.notAuthenticated))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 100)
        nonisolated(unsafe) let completion = completionHandler
        nonisolated(unsafe) let template = itemTemplate
        let mayAlreadyExist = options.contains(.mayAlreadyExist)
        let task = Task {
            do {
                let item = try await engine.createItem(
                    template: template,
                    fields: fields,
                    contents: url,
                    mayAlreadyExist: mayAlreadyExist,
                    progress: progress
                )
                completion(item, [], false, nil)
            } catch {
                completion(nil, [], false, providerReportedError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        guard let engine else {
            completionHandler(nil, [], false, NSFileProviderError(.notAuthenticated))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 100)
        nonisolated(unsafe) let completion = completionHandler
        nonisolated(unsafe) let template = item
        nonisolated(unsafe) let baseVersion = version
        let task = Task {
            do {
                let updated = try await engine.modifyItem(
                    template,
                    baseVersion: baseVersion,
                    changedFields: changedFields,
                    contents: newContents,
                    progress: progress
                )
                completion(updated, [], false, nil)
            } catch {
                completion(nil, [], false, providerReportedError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping ((any Error)?) -> Void) -> Progress {
        guard let engine else {
            completionHandler(NSFileProviderError(.notAuthenticated))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 100)
        nonisolated(unsafe) let completion = completionHandler
        let task = Task {
            do {
                try await engine.deleteItem(identifier)
                completion(nil)
            } catch {
                completion(providerReportedError(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let engine else { throw NSFileProviderError(.notAuthenticated) }
        return FileProviderEnumerator(container: containerItemIdentifier, engine: engine)
    }
}

/// Task cancellation surfaces as `CancellationError`. File Provider expects `NSUserCancelledError`.
func providerReportedError(_ error: any Error) -> NSError {
    if error is CancellationError {
        return CocoaError(.userCancelled) as NSError
    }
    return FileProviderErrors.nsError(for: error)
}
