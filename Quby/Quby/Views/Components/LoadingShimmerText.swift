import SwiftUI

/// Text that shows Spot-style letter shimmer + wave while `isLoading` is true.
/// During loading it shows a short status phrase; when ready it shows `text` fully, multiline.
struct LoadingShimmerText: View {

    let text: String
    var isLoading: Bool = false
    var font: Font = .body
    var multilineTextAlignment: TextAlignment = .trailing
    var baseColor: Color = .primary
    var lineLimit: Int? = nil
    var loadingText: String = "Analyzing"

    @State private var shimmerPhase: CGFloat = 0
    @State private var wavePhase: CGFloat = 0

    private var displayedText: String {
        isLoading ? loadingText : text
    }

    var body: some View {
        Text(displayedText)
            .font(font)
            .foregroundStyle(textForeground)
            .multilineTextAlignment(multilineTextAlignment)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: textAlignment)
            .contentTransition(.numericText())
            .overlay {
                if isLoading {
                    textWave
                        .mask {
                            Text(displayedText)
                                .font(font)
                                .multilineTextAlignment(multilineTextAlignment)
                                .lineLimit(lineLimit)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: textAlignment)
                        }
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .animation(.smooth(duration: 0.7), value: displayedText)
            .animation(.smooth(duration: 0.85), value: isLoading)
            .onAppear {
                if isLoading { startLoadingEffects() }
            }
            .onChange(of: isLoading) { _, loading in
                if loading {
                    startLoadingEffects()
                } else {
                    stopLoadingEffects()
                }
            }
            .onDisappear {
                stopLoadingEffects()
            }
            .accessibilityValue(isLoading ? displayedText : text)
    }

    private var textAlignment: Alignment {
        switch multilineTextAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        @unknown default: return .trailing
        }
    }

    private var textForeground: AnyShapeStyle {
        if isLoading {
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        baseColor.opacity(0.34),
                        baseColor.opacity(0.34),
                        baseColor.opacity(0.55),
                        baseColor.opacity(1.0),
                        baseColor.opacity(0.55),
                        baseColor.opacity(0.34),
                        baseColor.opacity(0.34)
                    ],
                    startPoint: UnitPoint(x: shimmerPhase - 0.55, y: 0.5),
                    endPoint: UnitPoint(x: shimmerPhase + 0.55, y: 0.5)
                )
            )
        } else {
            AnyShapeStyle(baseColor)
        }
    }

    private var textWave: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let band = width * 0.38
            let travel = width + band * 2
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: baseColor.opacity(0.08), location: 0.22),
                    .init(color: baseColor.opacity(0.35), location: 0.38),
                    .init(color: Color.white.opacity(0.78), location: 0.5),
                    .init(color: baseColor.opacity(0.35), location: 0.62),
                    .init(color: baseColor.opacity(0.08), location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band, height: geo.size.height)
            .offset(x: -band + travel * wavePhase)
        }
    }

    private func startLoadingEffects() {
        shimmerPhase = -0.4
        wavePhase = 0
        withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.4
        }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            wavePhase = 1
        }
    }

    private func stopLoadingEffects() {
        shimmerPhase = 0
        wavePhase = 0
    }
}
