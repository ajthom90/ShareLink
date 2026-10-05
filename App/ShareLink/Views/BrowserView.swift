import SwiftUI
import ShareLinkKit

struct BrowserView: View {
    var serverID: String
    var path: String = ""
    var folderName: String? = nil
    var connectedClient: (any SMBClient)? = nil

    @Environment(AppModel.self) private var model

    @State private var browser: BrowserModel?
    @State private var activeClient: (any SMBClient)?
    @State private var connectError: SMBError?
    @State private var isConnecting = false
    @State private var search = ""
    @State private var busyPath: String?
    @State private var preview: LocalFile?
    @State private var shareItem: LocalFile?
    @State private var actionError: SMBError?

    private struct LocalFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            if isConnecting || (browser == nil && connectError == nil) {
                ProgressView("Loading")
            } else if let connectError, browser == nil {
                unavailable(connectError) {
                    Task { await start() }
                }
            } else if let browser {
                browserContent(browser)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Filter")
        .task { await start() }
        .sheet(item: $preview) { file in
            NavigationStack {
                QuickLookView(url: file.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(file.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { preview = nil }
                        }
                    }
            }
        }
        .sheet(item: $shareItem) { file in
            NavigationStack {
                ShareLink(item: file.url, preview: SharePreview(file.url.lastPathComponent)) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Share")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { shareItem = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Couldn't Complete That", isPresented: actionAlertPresented) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError?.userMessage ?? "")
        }
    }

    private var title: String {
        if let folderName, !folderName.isEmpty { return folderName }
        return model.servers.first { $0.id == serverID }?.displayName ?? "Browse"
    }

    private var actionAlertPresented: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }

    @ViewBuilder
    private func browserContent(_ browser: BrowserModel) -> some View {
        if let error = browser.error, browser.entries.isEmpty, !browser.isLoading {
            unavailable(error) {
                Task { await browser.load() }
            }
        } else if browser.isLoading && browser.entries.isEmpty {
            ProgressView("Loading")
        } else if filtered(browser.entries).isEmpty, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: search)
        } else if browser.entries.isEmpty {
            ContentUnavailableView("This Folder Is Empty", systemImage: "folder")
                .refreshable { await browser.load() }
        } else {
            List {
                if let error = browser.error {
                    Section {
                        Text(error.userMessage)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await browser.load() }
                        }
                    }
                }
                ForEach(filtered(browser.entries), id: \.path) { entry in
                    row(entry, browser: browser)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await browser.load() }
        }
    }

    @ViewBuilder
    private func row(_ entry: RemoteEntry, browser: BrowserModel) -> some View {
        if entry.isDirectory {
            NavigationLink {
                BrowserView(
                    serverID: serverID,
                    path: entry.path,
                    folderName: entry.name,
                    connectedClient: connectedClient ?? activeClient
                )
            } label: {
                entryLabel(entry)
            }
        } else {
            Button {
                Task { await open(entry, browser: browser) }
            } label: {
                entryLabel(entry)
            }
            .disabled(busyPath != nil)
            .swipeActions {
                Button {
                    Task { await share(entry, browser: browser) }
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .disabled(busyPath != nil)
            }
            .contextMenu {
                Button {
                    Task { await share(entry, browser: browser) }
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .disabled(busyPath != nil)
            }
        }
    }

    private func entryLabel(_ entry: RemoteEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .font(.body)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detailLine(entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busyPath == entry.path {
                ProgressView()
                    .accessibilityLabel("Working")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detailLine(_ entry: RemoteEntry) -> String {
        let date = entry.modified.formatted(date: .abbreviated, time: .shortened)
        guard !entry.isDirectory else { return date }
        return "\(Self.byteCount.string(fromByteCount: entry.size)) · \(date)"
    }

    private func filtered(_ entries: [RemoteEntry]) -> [RemoteEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(query) }
    }

    private func unavailable(_ error: SMBError, retry: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label("Couldn't Open This Folder", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.userMessage)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }

    private func start() async {
        guard browser == nil, !isConnecting else { return }
        let client: any SMBClient
        if let connectedClient {
            client = connectedClient
        } else {
            isConnecting = true
            connectError = nil
            defer { isConnecting = false }
            guard let made = model.makeBrowserClient(for: serverID) else {
                connectError = .authenticationFailed
                return
            }
            do {
                try await made.connect()
            } catch let smb as SMBError {
                connectError = smb
                return
            } catch {
                connectError = .other(error.localizedDescription)
                return
            }
            client = made
        }
        activeClient = client
        let browser = BrowserModel(client: client, path: path)
        self.browser = browser
        await browser.load()
    }

    private func open(_ entry: RemoteEntry, browser: BrowserModel) async {
        guard busyPath == nil else { return }
        busyPath = entry.path
        defer { busyPath = nil }
        do {
            preview = LocalFile(url: try await browser.download(entry))
        } catch let smb as SMBError {
            actionError = smb
        } catch {
            actionError = .other(error.localizedDescription)
        }
    }

    private func share(_ entry: RemoteEntry, browser: BrowserModel) async {
        guard busyPath == nil else { return }
        busyPath = entry.path
        defer { busyPath = nil }
        do {
            shareItem = LocalFile(url: try await browser.download(entry))
        } catch let smb as SMBError {
            actionError = smb
        } catch {
            actionError = .other(error.localizedDescription)
        }
    }
}
