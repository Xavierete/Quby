import SwiftUI
import PhotosUI

struct QRStyleFormSections: View {

    @Bindable var viewModel: GeneratorViewModel
    @Binding var logoItem: PhotosPickerItem?
    @Namespace private var correctionNamespace

    var body: some View {
        colourSection
        shapeSection
        correctionSection
        logoSection
    }

    private var colourSection: some View {
        Section {
            QRPaletteAppearancePicker(selection: $viewModel.style.palette)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
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
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }

    private var shapeSection: some View {
        Section {
            QRModuleStyleAppearancePicker(selection: $viewModel.style.module)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
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
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }

    private var correctionSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(QRCorrection.allCases) { level in
                    let isSelected = viewModel.style.correction == level

                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            viewModel.style.correction = level
                        }
                    } label: {
                        Text(level.title)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "correctionSelection", in: correctionNamespace)
                                } else {
                                    Capsule()
                                        .fill(Color.gray.opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .opacity(viewModel.hasLogo ? 0.4 : 1)
            .disabled(viewModel.hasLogo)

            Text(viewModel.hasLogo
                 ? "A logo needs the highest correction level, so it stays fixed while one is set."
                 : viewModel.style.correction.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.snappy(duration: 0.28), value: viewModel.hasLogo ? "logo" : viewModel.style.correction.rawValue)
        } header: {
            Text("Error correction")
        } footer: {
            Text("Adds spare data so a damaged or partly covered code can still be read.")
                .font(.footnote)
                .foregroundStyle(.primary)
        }
    }

    private var logoSection: some View {
        Section {
            PhotosPicker(selection: $logoItem, matching: .images) {
                Label(viewModel.hasLogo ? "Change logo" : "Add logo", systemImage: "photo.circle")
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
}
