import SwiftUI

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
                PageDotControl(
                    numberOfPages: pages.count,
                    currentPage: currentPageIndex
                )
                .frame(height: 26)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("QR preview page")
                .accessibilityValue("Page \((pages.firstIndex(of: selection) ?? 0) + 1) of \(pages.count)")
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

/// SwiftUI stand-in for the system prominent page control (works on iOS and Mac).
private struct PageDotControl: View {

    let numberOfPages: Int
    @Binding var currentPage: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(index == currentPage ? 1 : 0.25))
                    .frame(width: 7, height: 7)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        currentPage = index
                    }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
