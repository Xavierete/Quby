import SwiftUI

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
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                fieldsSection
                QRStyleFormSections(viewModel: viewModel)
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
                        viewModel.generate()
                        dismiss()
                    } label: {
                        Text("Create QR code")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.canGenerate)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { viewModel.type = type }
            .onChange(of: viewModel.input.wifiSecurity) { _, _ in resetTyping() }
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        Section {
            switch type {
            case .website:
                TextField("Website address", text: $viewModel.input.website)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .website)

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
                showPassword.toggle()
                if wasTyping { focusedField = activePasswordField }
            } label: {
                Image(systemName: showPassword ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
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
