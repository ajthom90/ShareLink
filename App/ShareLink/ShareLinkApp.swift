import SwiftUI
import UIKit
import ShareLinkKit

@main
struct ShareLinkApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let configObserver: ManagedConfigObserver

    init() {
        AppGroup.defaults().set(UIDevice.current.model, forKey: AppGroup.deviceModelKey)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let model = AppModel(
            configStore: .shared(),
            credentials: KeychainCredentialStore(),
            domains: FileProviderDomainManager(),
            clientFactory: AMSMB2ClientFactory(),
            appVersion: "\(version) (\(build))"
        )
        _model = State(initialValue: model)
        configObserver = ManagedConfigObserver(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.start(managedConfig: Self.launchManagedConfig())
                    configObserver.start()
                }
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.appDidBecomeActive() }
            }
        }
    }

    private static func launchManagedConfig() -> [String: Any] {
        #if DEBUG
        // The observer reapplies this UserDefaults key after start. The demo dictionary
        // has to live there too, or that reapply replaces the example share with nothing.
        if demoManagedConfigEnabled {
            UserDefaults.standard.set(demoManagedConfig, forKey: ManagedConfigParser.managedConfigKey)
            return demoManagedConfig
        }
        if isDemoManagedDictionary(UserDefaults.standard.dictionary(forKey: ManagedConfigParser.managedConfigKey)) {
            UserDefaults.standard.removeObject(forKey: ManagedConfigParser.managedConfigKey)
        }
        #endif
        return UserDefaults.standard.dictionary(forKey: ManagedConfigParser.managedConfigKey) ?? [:]
    }

    #if DEBUG
    /// Simulator-only: `-SLDemoManagedConfig YES` shows a managed `example.com` share.
    private static var demoManagedConfigEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SLDemoManagedConfig") else { return false }
        let valueIndex = arguments.index(after: index)
        return arguments.indices.contains(valueIndex) && arguments[valueIndex] == "YES"
    }

    private static func isDemoManagedDictionary(_ dict: [String: Any]?) -> Bool {
        dict?["Host"] as? String == "files.example.com"
            && dict?["Share"] as? String == "Shared"
            && dict?["Username"] as? String == "jdoe"
    }

    private static var demoManagedConfig: [String: Any] {
        [
            "Host": "files.example.com",
            "Share": "Shared",
            "Path": "Finance",
            "DisplayName": "Finance",
            "Domain": "EXAMPLE",
            "Username": "jdoe",
            "SupportMessage": "Use your network password.",
        ]
    }
    #endif
}
