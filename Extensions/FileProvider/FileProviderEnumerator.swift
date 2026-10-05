import FileProvider
import ShareLinkKit

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let engine: ProviderEngine

    init(container: NSFileProviderItemIdentifier, engine: ProviderEngine) {
        self.container = container
        self.engine = engine
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        nonisolated(unsafe) let observer = observer
        let raw = page.rawValue
        // The initial-page constants are imported as NSData, not as NSFileProviderPage.
        let isInitial = raw == NSFileProviderPage.initialPageSortedByName as Data
            || raw == NSFileProviderPage.initialPageSortedByDate as Data
        let container = self.container
        let engine = self.engine
        Task {
            do {
                let (items, next) = try await engine.enumerateItems(in: container, page: isInitial ? nil : raw)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: next.map { NSFileProviderPage(rawValue: $0) })
            } catch {
                observer.finishEnumeratingWithError(providerReportedError(error))
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        nonisolated(unsafe) let observer = observer
        let container = self.container
        let engine = self.engine
        Task {
            do {
                let batch = try await engine.changes(in: container, since: anchor)
                if !batch.updated.isEmpty { observer.didUpdate(batch.updated) }
                if !batch.deleted.isEmpty { observer.didDeleteItems(withIdentifiers: batch.deleted) }
                observer.finishEnumeratingChanges(upTo: batch.anchor, moreComing: batch.moreComing)
            } catch {
                observer.finishEnumeratingWithError(providerReportedError(error))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        nonisolated(unsafe) let completion = completionHandler
        let engine = self.engine
        Task { completion(try? await engine.currentAnchor()) }
    }
}
