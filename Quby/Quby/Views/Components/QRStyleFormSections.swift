import SwiftUI
import PhotosUI

struct QRStyleFormSections: View {

    @Bindable var viewModel: GeneratorViewModel
    @Binding var logoItem: PhotosPickerItem?

    var body: some View {
        colourSection
        shapeSection
        correctionSection
        logoSection
    }

    private var colourSection: some View {
        Section {
            QRPaletteAppearancePicker(selection: $viewModel.style.palette)
                .listRowInsets(platformPickerInsets)
                .listRowSeparator(.hidden)
                #if os(iOS)
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
                #endif
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Colour")
                Spacer(minLength: 8)
                Text(viewModel.style.palette.name)
                    .foregroundStyle(.secondary)
                    .fontWeight(.regular)
                    .textCase(nil)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.28), value: viewModel.style.palette.name)
            }
        } footer: {
            Text("Sets the foreground and background colours of your code.")
        }
    }

    private var shapeSection: some View {
        Section {
            QRModuleStyleAppearancePicker(selection: $viewModel.style.module)
                .listRowInsets(platformPickerInsets)
                .listRowSeparator(.hidden)
                #if os(iOS)
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
                #endif
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Shape")
                Spacer(minLength: 8)
                Text(viewModel.style.module.title)
                    .foregroundStyle(.secondary)
                    .fontWeight(.regular)
                    .textCase(nil)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.28), value: viewModel.style.module.title)
            }
        } footer: {
            Text("Changes how each module in the QR code is drawn.")
        }
    }

    private var correctionSection: some View {
        Section {
            Picker("Level", selection: $viewModel.style.correction) {
                ForEach(QRCorrection.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(viewModel.hasLogo)
            .opacity(viewModel.hasLogo ? 0.45 : 1)
        } header: {
            Text("Error correction")
        } footer: {
            if viewModel.hasLogo {
                Text("A logo needs the highest correction level, so it stays fixed while one is set.")
            } else {
                Text(viewModel.style.correction.detail)
            }
        }
    }

    private var logoSection: some View {
        Section {
            PhotosPicker(selection: $logoItem, matching: .images) {
                Label(viewModel.hasLogo ? "Change logo" : "Add logo", systemImage: "photo.badge.plus")
            }

            if viewModel.hasLogo {
                Button("Remove logo", role: .destructive) {
                    viewModel.removeLogo()
                    logoItem = nil
                }
            }
        } header: {
            Text("Logo")
        }
    }

    private var platformPickerInsets: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        #else
        EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        #endif
    }
}
