import SwiftUI
import ImageIO
import UIKit

struct CodeDetailView: View {

    let record: CodeRecord

    @State private var showPassword = false
    @State private var selectedPreviewPage: QRPreviewPage = .styled
    @State private var styledImage: Image?
    @State private var baseImage: Image?
    @State private var styledBitmap: CGImage?
    @State private var baseBitmap: CGImage?
    @State private var confirmOpen = false
    @State private var browserLink: BrowserLink?
    @State private var showOfflineAlert = false
    @State private var actionMessage: String?
    @State private var isWorking = false

    private let safety = LinkSafety()
    private let clipboard = Clipboard()
    private let generator = QRCodeGenerator()

    private var content: ScannedContent {
        ScannedContentParser().parse(record.value)
    }

    private var isQRCode: Bool {
        record.symbology.lowercased().contains("qr")
    }

    private var showsBothPreviews: Bool {
        styledBitmap != nil && baseBitmap != nil
    }

    private var visiblePreviewPages: [QRPreviewPage] {
        showsBothPreviews ? QRPreviewPage.allCases : [.base]
    }

    private var activeBitmap: CGImage? {
        switch selectedPreviewPage {
        case .styled: return styledBitmap ?? baseBitmap
        case .base: return baseBitmap
        }
    }

    var body: some View {
        List {
            Section {
                codePreview
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
                actions
                copyButtons

                if let actionMessage {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isQRCode {
                    Menu {
                        ShareLink(item: record.value) {
                            Label("Share text", systemImage: "text.alignleft")
                        }
                        if let activeBitmap, let png = generator.writePNG(activeBitmap, named: "QRCode") {
                            ShareLink(item: png) {
                                Label("PNG image", systemImage: "photo")
                            }
                        }
                        if selectedPreviewPage == .base || !showsBothPreviews {
                            if let pdf = generator.writePDF(from: record.value, named: "QRCode") {
                                ShareLink(item: pdf) {
                                    Label("PDF document", systemImage: "doc.text")
                                }
                            }
                            if let svg = generator.writeSVG(from: record.value, named: "QRCode") {
                                ShareLink(item: svg) {
                                    Label("SVG vector", systemImage: "curlybraces")
                                }
                            }
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: record.value) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
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
        .sheet(item: $browserLink) { link in
            WebBrowserSheet(url: link.url) { browserLink = nil }
                .presentationDragIndicator(.visible)
        }
        .alert("No connection", isPresented: $showOfflineAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your internet connection and try again.")
        }
    }

    @ViewBuilder
    private var codePreview: some View {
        VStack(spacing: 10) {
            if baseImage != nil || styledImage != nil {
                QRPreviewPager(
                    pages: visiblePreviewPages,
                    selection: $selectedPreviewPage,
                    side: 220,
                    image: previewImage(for:)
                )
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
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .onAppear {
            if !showsBothPreviews {
                selectedPreviewPage = .base
            }
        }
    }

    private func previewImage(for page: QRPreviewPage) -> Image {
        switch page {
        case .styled:
            return styledImage ?? baseImage ?? Image(systemName: "qrcode")
        case .base:
            return baseImage ?? Image(systemName: "qrcode")
        }
    }

    @ViewBuilder
    private var details: some View {
        switch content {
        case .website(let url):
            row("Domain", safety.host(of: url))
            row("Address", url.absoluteString)

            ForEach(safety.warnings(for: url)) { warning in
                Label {
                    Text(warning.message)
                        .font(.footnote)
                } icon: {
                    Image(systemName: warning.icon)
                        .foregroundStyle(.orange)
                }
            }

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

    @ViewBuilder
    private var actions: some View {
        switch content {
        case .website(let url):
            let warnings = safety.warnings(for: url)

            Button {
                if warnings.isEmpty {
                    openWebsite(url)
                } else {
                    confirmOpen = true
                }
            } label: {
                Label(warnings.isEmpty ? "Open link" : "Open link anyway",
                      systemImage: warnings.isEmpty ? "safari" : "exclamationmark.shield")
            }
            .foregroundStyle(warnings.isEmpty ? Color.accentColor : .orange)
            .confirmationDialog("Open \(safety.host(of: url))?",
                                isPresented: $confirmOpen,
                                titleVisibility: .visible) {
                Button("Open anyway", role: .destructive) {
                    openWebsite(url)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(warnings.map(\.message).joined(separator: "\n\n"))
            }

        case .contact(let name, let phone, let email, let organization):
            Button {
                run { await ContactSaver().save(name: name,
                                                phone: phone,
                                                email: email,
                                                organization: organization) }
            } label: {
                Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(isWorking)

            if !ProcessInfo.processInfo.isiOSAppOnMac, let url = link("tel:", phone) {
                Link(destination: url) { Label("Call", systemImage: "phone") }
            } else if ProcessInfo.processInfo.isiOSAppOnMac, !phone.isEmpty {
                Button {
                    clipboard.copy(text: phone)
                    actionMessage = "Number copied."
                } label: {
                    Label("Copy number", systemImage: "doc.on.doc")
                }
            }
            if let url = link("mailto:", email) {
                Link(destination: url) { Label("Send email", systemImage: "envelope") }
            }

        case .email(let address, _, _):
            if let url = URL(string: record.value) ?? link("mailto:", address) {
                Link(destination: url) { Label("Write email", systemImage: "envelope") }
            }

        case .sms(let number, let message):
            if ProcessInfo.processInfo.isiOSAppOnMac {
                Button {
                    clipboard.copy(text: message.isEmpty ? number : "\(number)\n\(message)")
                    actionMessage = "Copied."
                } label: {
                    Label("Copy number", systemImage: "doc.on.doc")
                }
            } else if let url = link("sms:", number) {
                Link(destination: url) { Label("Send message", systemImage: "message") }
            }

        case .location(let latitude, let longitude):
            if let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)") {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }
            }

        case .wifi(let ssid, let password, let security, let isHidden):
            if ProcessInfo.processInfo.isiOSAppOnMac {
                Button {
                    var lines = ["Network: \(ssid)", "Security: \(security)"]
                    if !password.isEmpty { lines.insert("Password: \(password)", at: 1) }
                    if isHidden { lines.append("Hidden: Yes") }
                    clipboard.copy(text: lines.joined(separator: "\n"))
                    actionMessage = "Wi‑Fi details copied."
                } label: {
                    Label("Copy network details", systemImage: "doc.on.doc")
                }
            } else {
                Button {
                    run { await WiFiJoiner().join(ssid: ssid,
                                                  password: password,
                                                  security: security,
                                                  isHidden: isHidden) }
                } label: {
                    Label("Join network", systemImage: "wifi")
                }
                .disabled(isWorking)
            }

        case .text:
            EmptyView()
        }
    }

    private var copyButtons: some View {
        Group {
            if isQRCode, let activeBitmap {
                Button {
                    clipboard.copy(image: activeBitmap)
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

    private func openWebsite(_ url: URL) {
        Task {
            await InAppBrowser.open(url, into: $browserLink, offlineAlert: $showOfflineAlert)
        }
    }

    private func run(_ work: @escaping () async -> String) {
        isWorking = true
        actionMessage = nil

        Task {
            let result = await work()
            actionMessage = result
            isWorking = false
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

    private func link(_ scheme: String, _ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        return URL(string: scheme + stripped)
    }

    private func makeCode() {
        if let data = record.styledImageData,
           let image = Self.makeCGImage(from: data) {
            styledBitmap = image
            styledImage = Image(decorative: image, scale: 1)
            selectedPreviewPage = .styled
        }

        if let data = record.baseImageData,
           let image = Self.makeCGImage(from: data) {
            baseBitmap = image
            baseImage = Image(decorative: image, scale: 1)
        } else if let image = generator.makeImage(from: record.value) {
            baseBitmap = image
            baseImage = Image(decorative: image, scale: 1)
        }

        if styledBitmap == nil {
            selectedPreviewPage = .base
        }
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        return UIImage(data: data)?.cgImage
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
