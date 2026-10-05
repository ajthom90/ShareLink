import SwiftUI
import ShareLinkKit

struct ServerRow: View {
    let server: ServerConfig
    let status: ServerStatus

    /// Symbol slots scale with Dynamic Type but stay in the row so the name can wrap.
    @ScaledMetric(relativeTo: .body) private var iconSide = 22
    @ScaledMetric(relativeTo: .caption) private var statusSide = 10

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            symbol("server.rack", side: iconSide)
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
            // idealWidth keeps the title from collapsing to a few characters at accessibility sizes.
            .frame(minWidth: 0, idealWidth: 4000, maxWidth: .infinity, alignment: .leading)

            if server.isManaged {
                symbol("lock.fill", side: iconSide)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Managed")
            }

            symbol("circle.fill", side: statusSide)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("server.status")
        .accessibilityValue(statusLabel)
    }

    private func symbol(_ name: String, side: CGFloat) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
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
