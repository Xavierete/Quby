import SwiftUI

struct CodeDetailSheet: View {

    let record: CodeRecord
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            CodeDetailView(record: record)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onDone) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .accessibilityLabel("Done")
                    }
                }
        }
    }
}
