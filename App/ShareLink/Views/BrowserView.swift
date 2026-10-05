import SwiftUI

/// Empty stand-in so server detail can link to a browser. Task 12 replaces this view.
struct BrowserView: View {
    var serverID: String

    var body: some View {
        Color.clear
            .accessibilityLabel("Browse")
            .navigationTitle("Browse")
    }
}
