import SwiftUI
import ImageIO

struct CodeDetailView: View {

    private enum DetailAction: Hashable {
        case copyImage
        case copyText
        case copyPhone
        case copySMS
        case copyWifi
        case saveContact
        case joinWifi
    }

    let record: CodeRecord
    var animateContentReveal: Bool = false

    @State private var showPassword = false
    @State private var selectedPreviewPage: QRPreviewPage = .styled
    @State private var styledImage: Image?
    @State private var baseImage: Image?
    @State private var styledBitmap: CGImage?
    @State private var baseBitmap: CGImage?
    @State private var confirmOpen = false
    @State private var browserLink: BrowserLink?
    @State private var showOfflineAlert = false
    @State private var confirmedAction: DetailAction?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var feedbackResetTask: Task<Void, Never>?
    @State private var isContentReady = false

    private let safety = LinkSafety()
    private let clipboard = Clipboard()
    private let generator = QRCodeGenerator()

    private var isLoadingContent: Bool {
        animateContentReveal && !isContentReady
    }

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

    private var sharePDFURL: URL? {
        if selectedPreviewPage == .styled, let activeBitmap {
            return generator.writePDF(activeBitmap, named: "QRCode")
        }
        if let url = generator.writePDF(from: record.value, named: "QRCode") {
            return url
        }
        if let activeBitmap {
            return generator.writePDF(activeBitmap, named: "QRCode")
        }
        return nil
    }

    private var shareSVGURL: URL? {
        if selectedPreviewPage == .styled, let activeBitmap {
            return generator.writeSVG(activeBitmap, named: "QRCode")
        }
        if let url = generator.writeSVG(from: record.value, named: "QRCode") {
            return url
        }
        if let activeBitmap {
            return generator.writeSVG(activeBitmap, named: "QRCode")
        }
        return nil
    }

    private var runsOnMac: Bool {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        Form {
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
                        .foregroundStyle(.secondary)
                }
            }

            if isContentReady || !animateContentReveal {
                Section("Actions") {
                    actions
                    copyButtons

                    if let errorMessage {
                        Text(errorMessage)
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
                            if let pdf = sharePDFURL {
                                ShareLink(item: pdf) {
                                    Label("PDF document", systemImage: "doc.text")
                                }
                            }
                            if let svg = shareSVGURL {
                                ShareLink(item: svg) {
                                    Label("SVG vector", systemImage: "curlybraces")
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .animation(.smooth(duration: 0.7), value: isContentReady)
        .navigationTitle(content.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: PlatformToolbar.trailing) {
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
        .task { await revealContent() }
        .sheet(item: $browserLink) { link in
            WebBrowserSheet(url: link.url) { browserLink = nil }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
        }
        .alert("No connection", isPresented: $showOfflineAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your internet connection and try again.")
        }
    }

    @ViewBuilder
    private var codePreview: some View {
        VStack(spacing: 12) {
            #if os(macOS)
            macCodePreview
            #else
            iosCodePreview
            #endif

            if record.symbology != "QR code" {
                Text("Scanned as \(record.symbology), shown here as a QR code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        #if os(macOS)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        #else
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        #endif
        .listRowBackground(Color.clear)
        .onAppear {
            if !showsBothPreviews {
                selectedPreviewPage = .base
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macCodePreview: some View {
        if baseImage != nil || styledImage != nil {
            if showsBothPreviews {
                Picker("Preview", selection: $selectedPreviewPage) {
                    ForEach(visiblePreviewPages) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }

            previewImage(for: selectedPreviewPage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityLabel(selectedPreviewPage.title)
        } else {
            ProgressView()
                .frame(height: 220)
        }
    }
    #endif

    #if !os(macOS)
    @ViewBuilder
    private var iosCodePreview: some View {
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
    }
    #endif

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

            if isContentReady || !animateContentReveal {
                ForEach(safety.warnings(for: url)) { warning in
                    Label {
                        Text(warning.message)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: warning.icon)
                            .foregroundStyle(.orange)
                    }
                }
            }

        case .wifi(let ssid, let password, let security, let isHidden):
            row("Network", ssid)
            if !password.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text("Password")
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                    LoadingShimmerText(
                        text: showPassword
                            ? password
                            : String(repeating: "•", count: max(password.count, 6)),
                        isLoading: isLoadingContent,
                        multilineTextAlignment: .trailing
                    )
                    .selectableWhenReady(isContentReady || !animateContentReveal)
                    if isContentReady || !animateContentReveal {
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye" : "eye.slash")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
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
            LoadingShimmerText(
                text: text,
                isLoading: isLoadingContent,
                multilineTextAlignment: .leading
            )
            .selectableWhenReady(isContentReady || !animateContentReveal)
        }

        ForEach(extraContextFields) { field in
            row(field.label, field.value)
        }
    }

    private var extraContextFields: [ScanContextField] {
        let known = knownDetailValues
        return record.nearbyContext.filter { field in
            let normalized = field.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !known.contains(normalized)
        }
    }

    private var knownDetailValues: Set<String> {
        var values: Set<String> = [record.value.lowercased()]
        switch content {
        case .website(let url):
            values.insert(url.absoluteString.lowercased())
            values.insert(safety.host(of: url).lowercased())
        case .wifi(let ssid, let password, let security, _):
            values.formUnion([ssid, password, security].map { $0.lowercased() })
        case .contact(let name, let phone, let email, let organization):
            values.formUnion([name, phone, email, organization].map { $0.lowercased() })
        case .email(let address, let subject, let body):
            values.formUnion([address, subject, body].map { $0.lowercased() })
        case .sms(let number, let message):
            values.formUnion([number, message].map { $0.lowercased() })
        case .location(let latitude, let longitude):
            values.formUnion([String(latitude), String(longitude)].map { $0.lowercased() })
        case .text(let text):
            values.insert(text.lowercased())
        }
        return values.filter { !$0.isEmpty }
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
                run(.saveContact,
                    succeedsIf: { $0.hasPrefix("Saved") }) {
                    await ContactSaver().save(name: name,
                                             phone: phone,
                                             email: email,
                                             organization: organization)
                }
            } label: {
                feedbackLabel(
                    idle: ("Add to Contacts", "person.crop.circle.badge.plus"),
                    done: ("Saved", "checkmark.circle"),
                    action: .saveContact
                )
            }
            .disabled(isWorking)
            .animation(.snappy, value: confirmedAction)

            if !runsOnMac, let url = link("tel:", phone) {
                Link(destination: url) { Label("Call", systemImage: "phone") }
            } else if runsOnMac, !phone.isEmpty {
                Button {
                    clipboard.copy(text: phone)
                    confirm(.copyPhone)
                } label: {
                    feedbackLabel(
                        idle: ("Copy number", "doc.on.doc"),
                        done: ("Copied", "checkmark"),
                        action: .copyPhone
                    )
                }
                .animation(.snappy, value: confirmedAction)
            }
            if let url = link("mailto:", email) {
                Link(destination: url) { Label("Send email", systemImage: "envelope") }
            }

        case .email(let address, _, _):
            if let url = URL(string: record.value) ?? link("mailto:", address) {
                Link(destination: url) { Label("Write email", systemImage: "envelope") }
            }

        case .sms(let number, let message):
            if runsOnMac {
                Button {
                    clipboard.copy(text: message.isEmpty ? number : "\(number)\n\(message)")
                    confirm(.copySMS)
                } label: {
                    feedbackLabel(
                        idle: ("Copy number", "doc.on.doc"),
                        done: ("Copied", "checkmark"),
                        action: .copySMS
                    )
                }
                .animation(.snappy, value: confirmedAction)
            } else if let url = link("sms:", number) {
                Link(destination: url) { Label("Send message", systemImage: "message") }
            }

        case .location(let latitude, let longitude):
            if let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)") {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }
            }

        case .wifi(let ssid, let password, let security, let isHidden):
            if runsOnMac {
                Button {
                    var lines = ["Network: \(ssid)", "Security: \(security)"]
                    if !password.isEmpty { lines.insert("Password: \(password)", at: 1) }
                    if isHidden { lines.append("Hidden: Yes") }
                    clipboard.copy(text: lines.joined(separator: "\n"))
                    confirm(.copyWifi)
                } label: {
                    feedbackLabel(
                        idle: ("Copy network details", "doc.on.doc"),
                        done: ("Copied", "checkmark"),
                        action: .copyWifi
                    )
                }
                .animation(.snappy, value: confirmedAction)
            } else {
                Button {
                    run(.joinWifi,
                        succeedsIf: {
                            $0.hasPrefix("Joining") || $0.hasPrefix("Already connected")
                        }) {
                        await WiFiJoiner().join(ssid: ssid,
                                                password: password,
                                                security: security,
                                                isHidden: isHidden)
                    }
                } label: {
                    feedbackLabel(
                        idle: ("Join network", "wifi"),
                        done: ("Joined", "checkmark"),
                        action: .joinWifi
                    )
                }
                .disabled(isWorking)
                .animation(.snappy, value: confirmedAction)
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
                    confirm(.copyImage)
                } label: {
                    feedbackLabel(
                        idle: ("Copy QR image", "photo.on.rectangle"),
                        done: ("Copied", "checkmark"),
                        action: .copyImage
                    )
                }
                .animation(.snappy, value: confirmedAction)
            }

            Button {
                clipboard.copy(text: record.value)
                confirm(.copyText)
            } label: {
                feedbackLabel(
                    idle: (isQRCode ? "Copy text" : "Copy number", "doc.on.doc"),
                    done: ("Copied", "checkmark"),
                    action: .copyText
                )
            }
            .animation(.snappy, value: confirmedAction)
        }
    }

    private func openWebsite(_ url: URL) {
        Task {
            await InAppBrowser.open(url, into: $browserLink, offlineAlert: $showOfflineAlert)
        }
    }

    @ViewBuilder
    private func feedbackLabel(
        idle: (title: String, systemImage: String),
        done: (title: String, systemImage: String),
        action: DetailAction
    ) -> some View {
        let isDone = confirmedAction == action
        Label {
            Text(isDone ? done.title : idle.title)
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: isDone ? done.systemImage : idle.systemImage)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func confirm(_ action: DetailAction) {
        errorMessage = nil
        withAnimation(.snappy) {
            confirmedAction = action
        }
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                if confirmedAction == action {
                    confirmedAction = nil
                }
            }
        }
    }

    private func run(
        _ action: DetailAction,
        succeedsIf: @escaping (String) -> Bool,
        work: @escaping () async -> String
    ) {
        isWorking = true
        errorMessage = nil

        Task {
            let result = await work()
            isWorking = false
            if succeedsIf(result) {
                confirm(action)
            } else {
                confirmedAction = nil
                errorMessage = result
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            LoadingShimmerText(
                text: value,
                isLoading: isLoadingContent,
                multilineTextAlignment: .trailing
            )
            .selectableWhenReady(isContentReady || !animateContentReveal)
        }
    }

    private func revealContent() async {
        if animateContentReveal {
            isContentReady = false
            // Build the QR early, keep shimmering a bit longer, then ease into the real text.
            await Task.yield()
            makeCode()
            try? await Task.sleep(for: .milliseconds(1450))
            withAnimation(.smooth(duration: 0.95)) {
                isContentReady = true
            }
        } else {
            makeCode()
            isContentReady = true
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

#Preview("Reveal") {
    NavigationStack {
        CodeDetailView(
            record: CodeRecord(
                value: #"WIFI:T:WPA;S:Quby Cafe;P:latte\;123;H:true;;"#,
                kind: .scanned
            ),
            animateContentReveal: true
        )
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

private extension View {
    @ViewBuilder
    func selectableWhenReady(_ ready: Bool) -> some View {
        if ready {
            textSelection(.enabled)
        } else {
            self
        }
    }
}
