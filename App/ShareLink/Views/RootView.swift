import SwiftUI
import ShareLinkKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: String?
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $model.signInRequest) { server in
            SignInView(server: server)
        }
        .sheet(isPresented: $showingAdd) {
            ServerFormView(existing: nil)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: model.servers.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }

    private var managedServers: [ServerConfig] { model.servers.filter(\.isManaged) }
    private var userServers: [ServerConfig] { model.servers.filter { !$0.isManaged } }

    private var showsWelcomeInSidebar: Bool {
        model.servers.isEmpty && horizontalSizeClass == .compact
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if showsWelcomeInSidebar {
                WelcomeView(hasServers: false, onAddServer: { showingAdd = true })
            } else {
                serverList
            }
        }
        .navigationTitle(showsWelcomeInSidebar ? "ShareLink" : "Servers")
        .toolbar { sidebarToolbar }
    }

    private var serverList: some View {
        List(selection: $selection) {
            if !managedServers.isEmpty {
                Section("Managed by your organization") {
                    ForEach(managedServers) { server in
                        row(server)
                    }
                }
            }
            if !userServers.isEmpty {
                Section("My Servers") {
                    ForEach(userServers) { server in
                        row(server)
                    }
                }
            }
            if !model.configIssues.isEmpty {
                Section("Configuration") {
                    ForEach(Array(model.configIssues.enumerated()), id: \.offset) { _, issue in
                        Text(issue)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ server: ServerConfig) -> some View {
        ServerRow(server: server, status: model.status(for: server.id))
            .tag(server.id)
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        if model.allowUserServers {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected = model.servers.first(where: { $0.id == selection }) {
            ServerDetailView(server: selected)
        } else {
            WelcomeView(hasServers: !model.servers.isEmpty, onAddServer: { showingAdd = true })
        }
    }
}
