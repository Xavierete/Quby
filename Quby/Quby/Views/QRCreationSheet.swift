import SwiftUI

struct QRCreationSheet: View {

    let type: QRType

    @Environment(\.dismiss) private var dismiss

    @State private var website = ""
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var contactOrganization = ""
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var wifiSecurity = "WPA/WPA2"
    @State private var wifiHidden = false
    @State private var showPassword = false
    @State private var emailAddress = ""
    @State private var emailSubject = ""
    @State private var emailBody = ""
    @State private var smsNumber = ""
    @State private var smsMessage = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var correction = "M"
    @State private var paletteName = "Classic"
    @State private var moduleName = "Square"

    var body: some View {
        NavigationStack {
            Form {
                fieldsSection

                Section {
                    Text(paletteName)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Sets the foreground and background colours of your code.")
                }

                Section {
                    Text(moduleName)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Shape")
                } footer: {
                    Text("Changes how each module in the QR code is drawn.")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(["L", "M", "Q", "H"], id: \.self) { level in
                            Button {
                                correction = level
                            } label: {
                                Text(level)
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(correction == level
                                                ? Color.accentColor : Color.gray.opacity(0.12),
                                                in: Capsule())
                                    .foregroundStyle(correction == level
                                                     ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Error correction")
                }

                Section {
                    Button {
                    } label: {
                        Label("Add logo", systemImage: "photo.circle")
                    }
                } header: {
                    Text("Logo")
                }
            }
            .navigationTitle(type.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Create QR code")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var fieldsSection: some View {
        Section {
            switch type {
            case .website:
                TextField("Website address", text: $website)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

            case .contact:
                TextField("Name", text: $contactName)
                TextField("Phone", text: $contactPhone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Company (optional)", text: $contactOrganization)

            case .wifi:
                TextField("Network name (SSID)", text: $wifiSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if wifiSecurity != "None" {
                    if showPassword {
                        TextField("Password", text: $wifiPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Password", text: $wifiPassword)
                    }

                    Toggle("Show password", isOn: $showPassword)
                }

                Picker("Security", selection: $wifiSecurity) {
                    Text("WPA/WPA2").tag("WPA/WPA2")
                    Text("WEP").tag("WEP")
                    Text("None").tag("None")
                }

                Toggle("Hidden network", isOn: $wifiHidden)

            case .email:
                TextField("Email address", text: $emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Subject (optional)", text: $emailSubject)
                TextField("Message (optional)", text: $emailBody, axis: .vertical)
                    .lineLimit(3...6)

            case .sms:
                TextField("Phone number", text: $smsNumber)
                    .keyboardType(.phonePad)
                TextField("Message (optional)", text: $smsMessage, axis: .vertical)
                    .lineLimit(3...6)

            case .location:
                TextField("Latitude", text: $latitude)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $longitude)
                    .keyboardType(.numbersAndPunctuation)
            }
        } header: {
            Text("Details")
        }
    }
}

#Preview {
    QRCreationSheet(type: .website)
}
