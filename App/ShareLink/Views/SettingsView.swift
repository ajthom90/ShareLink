import SwiftUI

/// Empty stand-in so the settings sheet has a destination. Task 12 replaces this view.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {}
                .navigationTitle("Settings")
        }
    }
}
