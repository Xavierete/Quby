import SwiftUI
import PhotosUI

struct QRCreationSheet: View {

    private enum Field: Hashable {
        case website
        case contactName, contactPhone, contactEmail, contactOrganization
        case wifiSSID, wifiPasswordSecure, wifiPasswordPlain
        case emailAddress, emailSubject, emailBody
        case smsNumber, smsMessage
        case latitude, longitude
    }

    let type: QRType
    @Bindable var viewModel: GeneratorViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showPassword = false
    @State private var logoItem: PhotosPickerItem?
    @State private var didPasteWebsite = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                fieldsSection
                QRStyleFormSections(viewModel: viewModel, logoItem: $logoItem)
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(type.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        focusedField = nil
                        viewModel.generate(queueDetailsIfEnabled: true)
                        dismiss()
                    } label: {
                        Text("Create QR code")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(viewModel.canGenerate ? .green : .gray)
                    .foregroundStyle(Color.white)
                    .disabled(!viewModel.canGenerate)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { viewModel.type = type }
            .onChange(of: viewModel.input.wifiSecurity) { _, _ in resetTyping() }
            .onChange(of: logoItem) { _, newItem in
                Task {
                    guard let newItem else {
                        await MainActor.run { viewModel.removeLogo() }
                        return
                    }

                    guard let picked = try? await newItem.loadTransferable(type: PickedImageData.self) else {
                        await MainActor.run { logoItem = nil }
                        return
                    }

                    await MainActor.run {
                        viewModel.setLogo(picked.data)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        Section {
            switch type {
            case .website:
                websiteField

            case .contact:
                TextField("Name", text: $viewModel.input.contactName)
                    .focused($focusedField, equals: .contactName)
                TextField("Phone", text: $viewModel.input.contactPhone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .contactPhone)
                TextField("Email", text: $viewModel.input.contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .contactEmail)
                TextField("Company (optional)", text: $viewModel.input.contactOrganization)
                    .focused($focusedField, equals: .contactOrganization)

            case .wifi:
                TextField("Network name (SSID)", text: $viewModel.input.wifiSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .wifiSSID)

                if viewModel.input.wifiSecurity != .open {
                    passwordField
                }

                Picker("Security", selection: $viewModel.input.wifiSecurity) {
                    ForEach(WiFiSecurity.allCases) { security in
                        Text(security.title).tag(security)
                    }
                }

                Toggle("Hidden network", isOn: $viewModel.input.wifiHidden)

            case .email:
                TextField("Email address", text: $viewModel.input.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .emailAddress)
                TextField("Subject (optional)", text: $viewModel.input.emailSubject)
                    .focused($focusedField, equals: .emailSubject)
                TextField("Message (optional)", text: $viewModel.input.emailBody, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .emailBody)

            case .sms:
                TextField("Phone number", text: $viewModel.input.smsNumber)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .smsNumber)
                TextField("Message (optional)", text: $viewModel.input.smsMessage, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .smsMessage)

            case .location:
                TextField("Latitude", text: $viewModel.input.latitude)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .latitude)
                TextField("Longitude", text: $viewModel.input.longitude)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .longitude)
            }
        } header: {
            Text("Details")
        }
    }

    private var websiteField: some View {
        HStack(spacing: 8) {
            TextField("Website address", text: $viewModel.input.website)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focusedField, equals: .website)

            Button {
                guard let pasted = Clipboard().pasteText() else { return }
                viewModel.input.website = pasted
                focusedField = .website
                withAnimation {
                    didPasteWebsite = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation {
                        didPasteWebsite = false
                    }
                }
            } label: {
                Image(systemName: didPasteWebsite ? "checkmark" : "doc.on.clipboard")
                    .foregroundStyle(didPasteWebsite ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didPasteWebsite ? "Pasted" : "Paste from clipboard")
        }
    }

    private var passwordField: some View {
        HStack(spacing: 8) {
            ZStack {
                SecureField("Password", text: $viewModel.input.wifiPassword)
                    .focused($focusedField, equals: .wifiPasswordSecure)
                    .opacity(showPassword ? 0 : 1)
                    .allowsHitTesting(!showPassword)

                TextField("Password", text: $viewModel.input.wifiPassword)
                    .focused($focusedField, equals: .wifiPasswordPlain)
                    .opacity(showPassword ? 1 : 0)
                    .allowsHitTesting(showPassword)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                let wasTyping = isTypingPassword
                withAnimation {
                    showPassword.toggle()
                }
                if wasTyping { focusedField = activePasswordField }
            } label: {
                Image(systemName: showPassword ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
    }

    private var activePasswordField: Field {
        showPassword ? .wifiPasswordPlain : .wifiPasswordSecure
    }

    private var isTypingPassword: Bool {
        focusedField == .wifiPasswordSecure || focusedField == .wifiPasswordPlain
    }

    private func resetTyping() {
        focusedField = nil
        showPassword = false
    }
}
