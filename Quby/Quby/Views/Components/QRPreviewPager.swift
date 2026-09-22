import SwiftUI
import UIKit

struct QRPreviewPager: View {

    let pages: [QRPreviewPage]
    @Binding var selection: QRPreviewPage
    let side: CGFloat
    let image: (QRPreviewPage) -> Image

    private let pageSpacing: CGFloat = 16

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let showsPeek = pages.count > 1
                // Large enough peek so the neighbor QR is clearly visible.
                let horizontalInset = showsPeek
                    ? max(56, min(geo.size.width * 0.24, 88))
                    : 0
                let pageWidth = max(120, geo.size.width - horizontalInset * 2)
                let imageSide = min(side, pageWidth)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: pageSpacing) {
                        ForEach(pages) { page in
                            image(page)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: imageSide, height: imageSide)
                                .frame(width: pageWidth, height: side)
                                .scrollTransition(.animated, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                        .opacity(phase.isIdentity ? 1 : 0.82)
                                }
                                .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                // Only our peek inset — don't stack system safe-area margins on top.
                .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
                .safeAreaPadding(.horizontal, 0)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: selectionBinding)
                .scrollClipDisabled(showsPeek)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .frame(height: side)
            // Bleed past parent padding / list safe-area lines so peeks aren't clipped.
            .padding(.horizontal, pages.count > 1 ? -8 : 0)

            if pages.count > 1 {
                NativePageControl(
                    numberOfPages: pages.count,
                    currentPage: currentPageIndex
                )
                .frame(height: 26)
                .accessibilityLabel("QR preview page")
            }
        }
    }

    private var selectionBinding: Binding<QRPreviewPage?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    private var currentPageIndex: Binding<Int> {
        Binding(
            get: {
                pages.firstIndex(of: selection) ?? 0
            },
            set: { index in
                guard pages.indices.contains(index) else { return }
                selection = pages[index]
            }
        )
    }
}

/// Native `UIPageControl` with the system prominent background pill.
private struct NativePageControl: UIViewRepresentable {

    let numberOfPages: Int
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.hidesForSinglePage = true
        control.allowsContinuousInteraction = true
        control.addTarget(context.coordinator,
                          action: #selector(Coordinator.valueChanged(_:)),
                          for: .valueChanged)
        control.setContentHuggingPriority(.required, for: .vertical)
        control.setContentCompressionResistancePriority(.required, for: .vertical)
        applyAppearance(to: control)
        control.numberOfPages = numberOfPages
        control.currentPage = currentPage
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.currentPage = $currentPage
        applyAppearance(to: control)

        if control.numberOfPages != numberOfPages {
            control.numberOfPages = numberOfPages
        }
        if control.currentPage != currentPage {
            control.currentPage = currentPage
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    private func applyAppearance(to control: UIPageControl) {
        control.backgroundStyle = .prominent
        control.currentPageIndicatorTintColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
        control.pageIndicatorTintColor = UIColor { traits in
            let base: UIColor = traits.userInterfaceStyle == .dark ? .white : .black
            return base.withAlphaComponent(0.25)
        }
    }

    final class Coordinator: NSObject {
        var currentPage: Binding<Int>

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        @objc func valueChanged(_ sender: UIPageControl) {
            currentPage.wrappedValue = sender.currentPage
        }
    }
}
