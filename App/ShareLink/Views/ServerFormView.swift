import SwiftUI
import ShareLinkKit

struct ServerFormView: View {
    var existing: ServerConfig?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var host: String
    @State private var port: String
    @State private var share: String
    @State private var path: String
    @State private var domain: String
    @State private var username: String
    @State private var password: String
    @State private var requireEncryption: Bool
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult?
    @State private var saveError: SMBError?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case displayName, host, port, share, path, domain, username, password
    }

    private enum TestResult {
        case success
        case failure(SMBError)
    }

    init(existing: ServerConfig?) {
        self.existing = existing
        _displayName = State(initialValue: existing?.displayName ?? "")
        _host = State(initialValue: existing?.host ?? "")
        _port = State(initialValue: String(existing?.port ?? 445))
        _share = State(initialValue: existing?.share ?? "")
        _path = State(initialValue: existing?.rootPath ?? "")
        _domain = State(initialValue: existing?.domain ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _password = State(initialValue: "")
        _requireEncryption = State(initialValue: existing?.requireEncryption ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Display Name", text: $displayName)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.next)
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .host)
                        .submitLabel(.next)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
                    TextField("Share", text: $share)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .share)
                        .submitLabel(.next)
                    TextField("Path", text: $path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .path)
                        .submitLabel(.next)
                    TextField("Domain", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .domain)
                        .submitLabel(.next)
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                } footer: {
                    if existing != nil {
                        Text("Leave the password blank to keep the saved password.")
                    }
                }

                Section {
                    Toggle("Require encryption", isOn: $requireEncryption)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isBusy || !canTest)
                    .accessibilityLabel("Test Connection")

                    if case .success = testResult {
                        Label("Connection succeeded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    if case .failure(let error) = testResult {
                        Text(error.userMessage)
                            .foregroundStyle(.red)
                    }
                    if let saveError {
                        Text(saveError.userMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isBusy || !canSave)
                    .accessibilityLabel("Save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onChange(of: port) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue { port = String(digits.prefix(5)) }
                testResult = nil
            }
            .onChange(of: host) { _, _ in testResult = nil }
            .onChange(of: share) { _, _ in testResult = nil }
            .onChange(of: path) { _, _ in testResult = nil }
            .onChange(of: domain) { _, _ in testResult = nil }
            .onChange(of: username) { _, _ in testResult = nil }
            .onChange(of: password) { _, _ in testResult = nil }
            .onChange(of: requireEncryption) { _, _ in testResult = nil }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var isBusy: Bool { isTesting || isSaving }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTest: Bool {
        canSave && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func draft() -> ServerConfig {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShare = share.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? ServerConfig.defaultDisplayName(host: trimmedHost, share: trimmedShare) : trimmedName
        let portNumber = Int(port) ?? 445
        return ServerConfig(
            id: existing?.id ?? ServerConfig.newUserID(),
            source: .user,
            displayName: name,
            host: trimmedHost,
            port: (1...65535).contains(portNumber) ? portNumber : 445,
            share: trimmedShare,
            rootPath: path.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            requireEncryption: requireEncryption
        )
    }

    private func testConnection() async {
        guard canTest, !isBusy else { return }
        isTesting = true
        testResult = nil
        saveError = nil
        defer { isTesting = false }
        let server = draft()
        if let error = await model.testConnection(server, username: server.username, password: password) {
            testResult = .failure(error)
        } else {
            testResult = .success
        }
    }

    private func save() async {
        guard canSave, !isBusy else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let server = draft()
        do {
            try await model.saveUserServer(server, username: server.username, password: password.isEmpty ? nil : password)
            dismiss()
        } catch let smb as SMBError {
            saveError = smb
        } catch {
            saveError = .other(error.localizedDescription)
        }
    }
}
