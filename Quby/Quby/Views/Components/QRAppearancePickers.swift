import SwiftUI

private enum AppearancePickerMetrics {
    static let visibleCards: CGFloat = 3
    static let peekAmount: CGFloat = 32
    static let spacing: CGFloat = 10
    static let outerPadding: CGFloat = 12
    static let previewScale: CGFloat = 0.80
    static let previewCornerRadius: CGFloat = 10
    static let selectionStrokeWidth: CGFloat = 3
    static let sectionSafetyMargin: CGFloat = 4

    static func previewSide(for viewportWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 0 else { return 80 }
        let fullSide = (viewportWidth - spacing * visibleCards - peekAmount) / visibleCards
        return fullSide * previewScale
    }

    static func innerPadding(for side: CGFloat) -> CGFloat {
        min(6, max(4, side * 0.06))
    }

    static func innerPreviewShape(for side: CGFloat) -> RoundedRectangle {
        let padding = innerPadding(for: side)
        let radius = max(4, previewCornerRadius - padding * 0.4)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
    }
}

private struct AppearancePickerLayout<Option: Identifiable & Hashable, Preview: View>: View {

    @Binding var selection: Option
    let options: [Option]
    let accessibilityLabel: (Option) -> String
    @ViewBuilder let preview: (Option, Bool, CGFloat) -> Preview

    @State private var viewportWidth: CGFloat = 0

    private var previewSide: CGFloat {
        AppearancePickerMetrics.previewSide(for: viewportWidth)
    }

    private var tileExtent: CGFloat {
        previewSide + AppearancePickerMetrics.sectionSafetyMargin * 2
    }

    var body: some View {
        Color.clear
            .frame(height: tileExtent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                viewportWidth = width
            }
            .overlay {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: AppearancePickerMetrics.spacing) {
                            ForEach(options) { option in
                                let isSelected = selection == option

                                Button {
                                    selection = option
                                } label: {
                                    preview(option, isSelected, previewSide)
                                }
                                .buttonStyle(.plain)
                                .id(option)
                                .accessibilityLabel(accessibilityLabel(option))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .safeAreaPadding(.horizontal, 0)
                    .padding(AppearancePickerMetrics.outerPadding)
                    .scrollEdgeEffectHidden(true, for: .all)
                    .onAppear { scrollToSelection(using: proxy) }
                    .onChange(of: selection) { scrollToSelection(using: proxy) }
                    .onChange(of: viewportWidth) { scrollToSelection(using: proxy) }
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        guard viewportWidth > 0 else { return }
        withAnimation(.snappy(duration: 0.28)) {
            proxy.scrollTo(selection, anchor: .center)
        }
    }
}

private struct AppearancePreviewCard<Content: View>: View {

    let isSelected: Bool
    let side: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        let inset = AppearancePickerMetrics.innerPadding(for: side)
        let innerShape = AppearancePickerMetrics.innerPreviewShape(for: side)
        let safety = AppearancePickerMetrics.sectionSafetyMargin
        let stroke = AppearancePickerMetrics.selectionStrokeWidth

        content()
            .clipShape(innerShape)
            .padding(inset)
            .frame(width: side, height: side)
            .overlay {
                AppearancePickerMetrics.previewShape.strokeBorder(
                    Color.primary,
                    lineWidth: isSelected ? stroke : 0
                )
            }
            .padding(safety)
            .frame(width: side + safety * 2, height: side + safety * 2)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

struct QRPaletteAppearancePicker: View {

    @Binding var selection: QRPalette

    var body: some View {
        AppearancePickerLayout(
            selection: $selection,
            options: QRPalette.all,
            accessibilityLabel: { $0.name }
        ) { palette, isSelected, side in
            AppearancePreviewCard(isSelected: isSelected, side: side) {
                QRPalettePreviewContent(palette: palette)
            }
        }
    }
}

struct QRModuleStyleAppearancePicker: View {

    @Binding var selection: QRModuleStyle

    var body: some View {
        AppearancePickerLayout(
            selection: $selection,
            options: QRModuleStyle.allCases,
            accessibilityLabel: { $0.title }
        ) { module, isSelected, side in
            AppearancePreviewCard(isSelected: isSelected, side: side) {
                QRModuleStylePreviewContent(module: module)
            }
        }
    }
}

private struct QRPalettePreviewContent: View {

    let palette: QRPalette

    private let pattern = [[true, true, false], [true, false, true], [false, true, true]]

    var body: some View {
        Rectangle()
            .fill(color(palette.background))
            .overlay {
                miniGrid(foreground: color(palette.foreground))
            }
    }

    private func color(_ stored: CodeColor) -> Color {
        Color(red: stored.red, green: stored.green, blue: stored.blue)
    }

    @ViewBuilder
    private func miniGrid(foreground: Color) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        Rectangle()
                            .fill(foreground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(pattern[row][column] ? 1 : 0)
                    }
                }
            }
        }
        .padding(6)
    }
}

private struct QRModuleStylePreviewContent: View {

    let module: QRModuleStyle

    private let pattern = [[true, true, false], [true, false, true], [false, true, true]]

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { column in
                                Group {
                                    switch module {
                                    case .square:
                                        Rectangle()
                                            .fill(Color(uiColor: .label))
                                    case .rounded:
                                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                            .fill(Color(uiColor: .label))
                                    case .dots:
                                        Circle()
                                            .fill(Color(uiColor: .label))
                                    case .diamond:
                                        Diamond()
                                            .fill(Color(uiColor: .label))
                                            .padding(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(pattern[row][column] ? 1 : 0)
                            }
                        }
                    }
                }
                .padding(6)
            }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
