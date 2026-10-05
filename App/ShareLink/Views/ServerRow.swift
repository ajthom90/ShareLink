import SwiftUI
import ShareLinkKit

struct ServerRow: View {
    let server: ServerConfig
    let status: ServerStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "server.rack")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(server.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if server.isManaged {
                Image(systemName: "lock.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Managed")
            }

            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusLabel)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch status {
        case .signedIn: "Signed in"
        case .needsSignIn: "Sign-in required"
        case .error: "Error"
        }
    }

    private var statusColor: Color {
        switch status {
        case .signedIn: .green
        case .needsSignIn: .orange
        case .error: .red
        }
    }
}

#if DEBUG
#Preview("Rows") {
    let server = PreviewData.financeServer()
    let mine = ServerConfig(
        id: "user-preview",
        source: .user,
        displayName: "Quarterly Reports and Board Materials",
        host: "nas.example.com",
        share: "Home",
        rootPath: "Documents/Finance"
    )
    List {
        ServerRow(server: server, status: .needsSignIn)
        ServerRow(server: server, status: .signedIn)
        ServerRow(server: server, status: .error("The server can't be reached. Check your network connection."))
        ServerRow(server: mine, status: .signedIn)
    }
    .listStyle(.sidebar)
    .environment(PreviewData.model(servers: [server, mine]))
}
#endif
