import SwiftUI
import UIKit
import ShareLinkKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false
    @State private var isCopying = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Source Code", destination: URL(string: "https://github.com/ajthom90/ShareLink")!)
                    Link("Report an Issue", destination: URL(string: "https://github.com/ajthom90/ShareLink/issues")!)
                }

                Section {
                    Button {
                        copyDiagnostics()
                    } label: {
                        if isCopying {
                            ProgressView()
                        } else {
                            Label("Copy Diagnostics", systemImage: "doc.on.clipboard")
                        }
                    }
                    .disabled(isCopying)
                    .accessibilityLabel("Copy Diagnostics")

                    NavigationLink("Acknowledgements", value: "acknowledgements")
                } header: {
                    Text("Support")
                } footer: {
                    Text("ShareLink is free and open source under the MIT License. It includes libsmb2 and AMSMB2 under the GNU LGPL 2.1.")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: String.self) { _ in
                AcknowledgementsView()
            }
            .alert("Diagnostics Copied", isPresented: $copied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A redacted diagnostics report is on the clipboard.")
            }
            .task {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-SLDemoPresent"),
                   arguments.indices.contains(arguments.index(after: index)),
                   arguments[arguments.index(after: index)] == "acknowledgements" {
                    path.append("acknowledgements")
                }
                #endif
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }

    private func copyDiagnostics() {
        isCopying = true
        defer { isCopying = false }
        let report = Diagnostics.report(
            servers: model.servers,
            statuses: model.statuses,
            issues: model.configIssues,
            appVersion: appVersion,
            logTail: DiagnosticLog.tail(200)
        )
        UIPasteboard.general.string = report
        copied = true
    }
}
