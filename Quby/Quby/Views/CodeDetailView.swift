import SwiftUI

struct CodeDetailView: View {

    let record: CodeRecord

    @State private var qrImage: Image?

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    if let qrImage {
                        qrImage
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                    } else {
                        ProgressView()
                            .frame(height: 220)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text(record.value)

                Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .foregroundStyle(.secondary)
            } header: {
                Text("Details")
            }
        }
        .navigationTitle("Details")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    record.isFavorite.toggle()
                } label: {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(record.isFavorite ? AnyShapeStyle(.yellow.gradient) : AnyShapeStyle(.primary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(record.isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        .task { makeCode() }
    }

    private func makeCode() {
        guard qrImage == nil,
              let image = QRCodeGenerator().makeImage(from: record.value) else { return }
        qrImage = Image(decorative: image, scale: 1)
    }
}

#Preview {
    NavigationStack {
        CodeDetailView(record: CodeRecord(value: "https://example.com", kind: .created))
    }
}
