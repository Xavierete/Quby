import SwiftUI

struct CodeDetailSheet: View {

    let record: CodeRecord
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            CodeDetailView(record: record)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
    }
}
