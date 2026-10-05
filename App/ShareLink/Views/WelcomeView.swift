import SwiftUI
import ShareLinkKit

struct WelcomeView: View {
    var hasServers: Bool
    var onAddServer: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if hasServers {
                ContentUnavailableView("Select a server", systemImage: "server.rack")
            } else if model.allowUserServers {
                ContentUnavailableView {
                    Label("Welcome to ShareLink", systemImage: "externaldrive.connected.to.line.below")
                } description: {
                    Text("Connect to SMB file shares and open documents from the Files app.")
                } actions: {
                    Button("Add Server", action: onAddServer)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Welcome to ShareLink", systemImage: "externaldrive.connected.to.line.below")
                } description: {
                    Text("Your organization hasn't configured any shares yet.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Welcome") {
    NavigationStack {
        WelcomeView(hasServers: false, onAddServer: {})
    }
    .environment(PreviewData.model())
}

#Preview("No shares from organization") {
    NavigationStack {
        WelcomeView(hasServers: false, onAddServer: {})
    }
    .environment(PreviewData.model(allowUserServers: false))
}

#Preview("Select a server") {
    WelcomeView(hasServers: true, onAddServer: {})
        .environment(PreviewData.model())
}
#endif
