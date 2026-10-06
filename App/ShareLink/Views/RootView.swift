import SwiftUI
import ShareLinkKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: String?
    @State private var showingAdd = false
    @State private var showingSettings = false
    /// Compact width only. Regular width forces `.all` so iPadOS 17 portrait
    /// does not collapse the server list behind "Show Sidebar".
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    /// iPhone push. `List(selection:)` does not navigate on compact width, and a
    /// `NavigationLink` label collapses under the largest accessibility sizes.
    @State private var compactDetailID: String?

    /// Regular width (iPad portrait and landscape) keeps the sidebar beside the
    /// detail. Compact width keeps the system's stack and does not lock visibility.
    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        if horizontalSizeClass == .regular {
            return .constant(.all)
        }
        return $columnVisibility
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
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
            selectFirstServerIfNeeded()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            selectFirstServerIfNeeded()
        }
        .onAppear { selectFirstServerIfNeeded() }
        .task { await applyDemoPresentation() }
    }

    /// Regular width opens the first managed server, then the first user server,
    /// so launch is never an empty "Select a server" placeholder. That placeholder
    /// stays as the detail fallback when nothing can be selected.
    private func selectFirstServerIfNeeded() {
        guard horizontalSizeClass == .regular else { return }
        if let selection, model.servers.contains(where: { $0.id == selection }) { return }
        selection = managedServers.first?.id ?? userServers.first?.id
    }

    /// DEBUG-only screenshot hooks. `-SLDemoPresent` is addServer, settings, or acknowledgements.
    /// `-SLDemoSelect YES` selects the first server so compact width shows its detail.
    private func applyDemoPresentation() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-SLDemoPresent"),
           arguments.indices.contains(arguments.index(after: index)) {
            switch arguments[arguments.index(after: index)] {
            case "addServer":
                showingAdd = true
            case "settings", "acknowledgements":
                showingSettings = true
            default:
                break
            }
        }
        let select = Self.flag("SLDemoSelect", in: arguments)
        let dismissSignIn = select || Self.flag("SLDemoDismissSignIn", in: arguments)
        if dismissSignIn {
            // `start` assigns the sign-in sheet after domain reconciliation, so wait for that write.
            for _ in 0..<80 where model.signInRequest == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if select {
                selection = model.servers.first?.id
                compactDetailID = selection
            }
            model.signInRequest = nil
        }
        #endif
    }

    #if DEBUG
    private static func flag(_ name: String, in arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-\(name)") else { return false }
        let valueIndex = arguments.index(after: index)
        return arguments.indices.contains(valueIndex) && arguments[valueIndex] == "YES"
    }
    #endif

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
        Group {
            if horizontalSizeClass == .compact {
                // Sidebar rows collapse to a narrow column at the largest accessibility sizes.
                List { serverSections }
                    .listStyle(.insetGrouped)
                    .navigationDestination(isPresented: compactDetailPresented) {
                        if let compactDetailID,
                           let server = model.servers.first(where: { $0.id == compactDetailID }) {
                            ServerDetailView(server: server)
                        }
                    }
            } else {
                List(selection: $selection) { serverSections }
                    .listStyle(.sidebar)
            }
        }
    }

    private var compactDetailPresented: Binding<Bool> {
        Binding(
            get: { compactDetailID != nil },
            set: { if !$0 { compactDetailID = nil } }
        )
    }

    @ViewBuilder
    private var serverSections: some View {
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

    @ViewBuilder
    private func row(_ server: ServerConfig) -> some View {
        let status = model.status(for: server.id)
        if horizontalSizeClass == .compact {
            Button {
                selection = server.id
                compactDetailID = server.id
            } label: {
                ServerRow(server: server, status: status)
            }
            .buttonStyle(.plain)
        } else {
            ServerRow(server: server, status: status)
                .tag(server.id)
        }
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

