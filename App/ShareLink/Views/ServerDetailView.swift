import SwiftUI
import ShareLinkKit

struct ServerDetailView: View {
    let server: ServerConfig

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var isOpeningFiles = false
    @State private var isSigningOut = false
    @State private var isRemoving = false
    @State private var confirmSignOut = false
    @State private var confirmRemove = false
    @State private var showingEdit = false
    @State private var openFailed = false

    private var status: ServerStatus { model.status(for: server.id) }
    private var isSignedIn: Bool { status == .signedIn }
    private var isBusy: Bool { isOpeningFiles || isSigningOut || isRemoving }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: statusTitle)
                if case .error(let message) = status {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Host", value: server.host)
                LabeledContent("Share", value: server.share)
                LabeledContent("Path", value: server.rootPath.isEmpty ? "None" : server.rootPath)
                LabeledContent("Domain", value: server.domain.isEmpty ? "None" : server.domain)
                LabeledContent("Port", value: String(server.port))
                LabeledContent("Encryption", value: server.requireEncryption ? "Required" : "Not Required")
            } header: {
                Text("Connection")
            } footer: {
                if server.isManaged {
                    Text("This server is managed by your organization.")
                }
            }

            Section {
                Button {
                    Task { await openInFiles() }
                } label: {
                    if isOpeningFiles {
                        ProgressView()
                    } else {
                        Label("Open in Files", systemImage: "folder")
                    }
                }
                .disabled(!isSignedIn || isBusy)
                .accessibilityLabel("Open in Files")

                NavigationLink {
                    BrowserView(serverID: server.id)
                } label: {
                    Label("Browse", systemImage: "list.bullet")
                }
                .disabled(!isSignedIn)

                if status == .signedIn {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        if isSigningOut {
                            ProgressView()
                        } else {
                            Text("Sign Out")
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("Sign Out")
                } else {
                    Button {
                        model.signInRequest = server
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle")
                    }
                    .disabled(isBusy)
                }

                if server.source == .user {
                    Button("Edit") { showingEdit = true }
                        .disabled(isBusy)
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        if isRemoving {
                            ProgressView()
                        } else {
                            Text("Remove Server")
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("Remove Server")
                }
            } footer: {
                if !isSignedIn {
                    Text("Sign in to open this server in Files.")
                }
            }
        }
        .navigationTitle(server.displayName)
        .confirmationDialog("Sign Out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ShareLink removes the saved password and downloaded files for this server.")
        }
        .confirmationDialog("Remove Server?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Server", role: .destructive) {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the server from ShareLink and the Files app.")
        }
        .sheet(isPresented: $showingEdit) {
            ServerFormView(existing: server)
        }
        .alert("Can't Open in Files", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Files location isn't available yet.")
        }
    }

    private var statusTitle: String {
        switch status {
        case .signedIn: "Signed in"
        case .needsSignIn: "Sign-in required"
        case .error: "Error"
        }
    }

    private func openInFiles() async {
        guard !isBusy else { return }
        isOpeningFiles = true
        defer { isOpeningFiles = false }
        guard let url = await model.openInFilesURL(for: server.id) else {
            openFailed = true
            return
        }
        openURL(url)
    }

    private func signOut() async {
        guard !isBusy else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await model.signOut(serverID: server.id)
    }

    private func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        await model.removeUserServer(id: server.id)
    }
}
