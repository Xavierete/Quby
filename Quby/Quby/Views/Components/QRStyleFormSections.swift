import SwiftUI

struct QRStyleFormSections: View {

    @Bindable var viewModel: GeneratorViewModel

    var body: some View {
        colourSection
        shapeSection
        correctionSection
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
                    Button {
                        viewModel.style.correction = level
                    } label: {
                        Text(level.title)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(viewModel.style.correction == level
                                        ? Color.accentColor : Color.gray.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(viewModel.style.correction == level
                                             ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(viewModel.style.correction.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Error correction")
        }
    }
}
