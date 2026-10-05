import SwiftUI
import ShareLinkKit

struct AcknowledgementsView: View {
    private let items = Acknowledgements.all()

    var body: some View {
        List(items) { item in
            NavigationLink {
                ScrollView {
                    Text(item.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                LabeledContent(item.name, value: item.license)
            }
        }
        .navigationTitle("Acknowledgements")
        .listStyle(.insetGrouped)
    }
}
