import SwiftUI

struct CodeDetailView: View {

    let record: CodeRecord

    @State private var qrImage: Image?
    @State private var qrBitmap: CGImage?
    @State private var showPassword = false
    @State private var actionMessage: String?

    private let clipboard = Clipboard()
    private let generator = QRCodeGenerator()

    private var content: ScannedContent {
        ScannedContentParser().parse(record.value)
    }

    private var isQRCode: Bool {
        record.symbology.lowercased().contains("qr")
    }

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

                    if record.symbology != "QR code" {
                        Text("Scanned as \(record.symbology), shown here as a QR code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                details
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: content.icon)
                    Text(content.title)
                    Spacer()
                    Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                }
            }

            Section("Actions") {
                copyButtons

                if let actionMessage {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(content.title)
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

    @ViewBuilder
    private var details: some View {
        switch content {
        case .website(let url):
            row("Domain", url.host() ?? url.absoluteString)
            row("Address", url.absoluteString)

        case .wifi(let ssid, let password, let security, let isHidden):
            row("Network", ssid)
            if !password.isEmpty {
                HStack {
                    Text("Password")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(showPassword ? password : String(repeating: "•", count: max(password.count, 6)))
                        .textSelection(.enabled)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            row("Security", security)
            if isHidden { row("Hidden", "Yes") }

        case .contact(let name, let phone, let email, let organization):
            if !name.isEmpty { row("Name", name) }
            if !organization.isEmpty { row("Company", organization) }
            if !phone.isEmpty { row("Phone", phone) }
            if !email.isEmpty { row("Email", email) }

        case .email(let address, let subject, let body):
            row("To", address)
            if !subject.isEmpty { row("Subject", subject) }
            if !body.isEmpty { row("Message", body) }

        case .sms(let number, let message):
            row("Number", number)
            if !message.isEmpty { row("Message", message) }

        case .location(let latitude, let longitude):
            row("Latitude", String(latitude))
            row("Longitude", String(longitude))

        case .text(let text):
            Text(text)
                .textSelection(.enabled)
        }
    }

    private var copyButtons: some View {
        Group {
            if isQRCode, let qrBitmap {
                Button {
                    clipboard.copy(image: qrBitmap)
                    actionMessage = "QR code image copied."
                } label: {
                    Label("Copy QR image", systemImage: "photo.on.rectangle")
                }
            }

            Button {
                clipboard.copy(text: record.value)
                actionMessage = isQRCode ? "Text copied." : "Barcode number copied."
            } label: {
                Label(isQRCode ? "Copy text" : "Copy number", systemImage: "doc.on.doc")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func makeCode() {
        guard qrImage == nil,
              let image = generator.makeImage(from: record.value) else { return }
        qrBitmap = image
        qrImage = Image(decorative: image, scale: 1)
    }
}

#Preview {
    NavigationStack {
        CodeDetailView(record: CodeRecord(
            value: #"WIFI:T:WPA;S:Quby Cafe;P:latte\;123;H:true;;"#,
            kind: .scanned
        ))
    }
}
