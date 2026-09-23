import SwiftUI

struct CodeDetailSheet: View {

    let record: CodeRecord
    var animateContentReveal: Bool = false
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            CodeDetailView(record: record, animateContentReveal: animateContentReveal)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        #if os(macOS)
                        Button("Done", action: onDone)
                            .keyboardShortcut(.defaultAction)
                        #else
                        Button(action: onDone) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .accessibilityLabel("Done")
                        #endif
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 460)
        #endif
    }
}
