import SwiftUI
import ShareLinkKit

struct SignInView: View {
    let server: ServerConfig

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: SMBError?
    @State private var detent: PresentationDetent = .large
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username
        case password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server", value: server.displayName)
                    LabeledContent("Location") {
                        Text(server.summary)
                            .multilineTextAlignment(.trailing)
                    }
                    if !server.domain.isEmpty {
                        Text("Domain: \(server.domain)")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if !model.supportMessage.isEmpty {
                        Text(model.supportMessage)
                    }
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(server.usernameLocked || isWorking)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .disabled(isWorking)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }

                if let error {
                    Section {
                        Text(message(for: error))
                            .foregroundStyle(.red)
                        if showsAdministratorHint(for: error) {
                            Text("If the problem continues, contact your IT administrator.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(isWorking || !canSubmit)
                    .accessibilityLabel("Sign In")
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(SignInSheetDetents(horizontalSizeClass: horizontalSizeClass, detent: $detent))
        .interactiveDismissDisabled(isWorking)
        .task {
            if username.isEmpty {
                username = model.savedUsername(for: server.id) ?? server.username
            }
            // The sheet needs a moment before the password field can take focus.
            try? await Task.sleep(for: .milliseconds(400))
            focusedField = username.isEmpty ? .username : .password
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func message(for error: SMBError) -> String {
        if case .authenticationFailed = error {
            return "Couldn't sign in. Check your username and password."
        }
        return error.userMessage
    }

    private func showsAdministratorHint(for error: SMBError) -> Bool {
        if case .authenticationFailed = error { return server.isManaged }
        return false
    }

    private func submit() async {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await model.signIn(
                serverID: server.id,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            dismiss()
        } catch let smb as SMBError {
            error = smb
        } catch {
            self.error = .other(error.localizedDescription)
        }
    }
}

/// Medium and large detents on iPhone. The sheet opens at large so the password field and Sign In stay on screen.
private struct SignInSheetDetents: ViewModifier {
    var horizontalSizeClass: UserInterfaceSizeClass?
    @Binding var detent: PresentationDetent

    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Sign in") {
    let server = PreviewData.financeServer()
    SignInView(server: server)
        .environment(PreviewData.model(
            supportMessage: "Use your network password.",
            servers: [server]
        ))
}
#endif
