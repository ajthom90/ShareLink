import Foundation
import ShareLinkKit

/// Watches `UserDefaults.didChangeNotification` on `.standard` and reapplies managed configuration.
@MainActor
final class ManagedConfigObserver {
    private var observer: NSObjectProtocol?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [model] _ in
            Task { @MainActor in
                let dict = UserDefaults.standard.dictionary(forKey: ManagedConfigParser.managedConfigKey) ?? [:]
                await model.applyManagedConfiguration(dict)
            }
        }
    }

    // Main-actor deinit: the observer token is not Sendable.
    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
