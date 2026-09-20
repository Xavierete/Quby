import SwiftUI
import PhotosUI

struct GeneratorView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var activeCreationType: QRType?
    @State private var showCameraScanner = false
    @State private var showPhotoPicker = false
    @State private var scanPhotoItem: PhotosPickerItem?
    @State private var contentWidth: CGFloat = 0

    private let gridSpacing: CGFloat = 12

    private var opensCameraInWindow: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    private var typeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }

    private var typeCardMetrics: TypeCardMetrics {
        TypeCardMetrics(containerWidth: contentWidth,
                        spacing: gridSpacing,
                        isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        GeometryReader { proxyGeometry in
            ScrollView {
                VStack(spacing: 24) {
                    typeButtons

                    Spacer(minLength: 24)

                    emptyResult
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 28)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxyGeometry.size.height, alignment: .top)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    contentWidth = width
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openCameraScanner()
                    } label: {
                        Label("Scan from camera", systemImage: "camera")
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Scan from photo", systemImage: "photo")
                    }
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(item: $activeCreationType) { type in
            QRCreationSheet(type: type)
                .presentationDragIndicator(.visible)
                .presentationSizing(.form)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $scanPhotoItem, matching: .images)
        .sheet(isPresented: $showCameraScanner) {
            NavigationStack {
                CameraScannerView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openCameraScanner() {
        if opensCameraInWindow {
            openWindow(id: QubyWindowID.cameraScanner)
        } else {
            showCameraScanner = true
        }
    }

    private var typeButtons: some View {
        let metrics = typeCardMetrics

        return LazyVGrid(columns: typeColumns, spacing: gridSpacing) {
            ForEach(QRType.allCases) { type in
                Button {
                    activeCreationType = type
                } label: {
                    VStack(spacing: metrics.contentSpacing) {
                        Image(systemName: type.icon)
                            .font(metrics.iconFont)
                        Text(type.title)
                            .font(metrics.titleFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.cardHeight)
                    .background(typeGradient(for: type).gradient,
                                in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func typeGradient(for type: QRType) -> Color {
        switch type {
        case .website: return .blue
        case .contact: return .purple
        case .wifi: return .cyan
        case .email: return .orange
        case .sms: return .green
        case .location: return .pink
        }
    }

    private var emptyResult: some View {
        ContentUnavailableView(
            "No code yet",
            systemImage: "qrcode",
            description: Text("Choose a type above to get started.")
        )
    }
}

private struct TypeCardMetrics {
    let containerWidth: CGFloat
    let spacing: CGFloat
    let isRegularWidth: Bool

    private var cardSide: CGFloat {
        guard containerWidth > 0 else { return isRegularWidth ? 140 : 108 }
        let side = (containerWidth - spacing * 2) / 3
        return max(96, side)
    }

    var cardHeight: CGFloat {
        if isRegularWidth {
            return max(120, min(cardSide * 0.78, 168))
        }
        return max(96, min(cardSide * 0.92, 128))
    }

    var contentSpacing: CGFloat {
        isRegularWidth ? 12 : 8
    }

    var cornerRadius: CGFloat { 26 }

    var iconFont: Font {
        if isRegularWidth || cardSide >= 140 {
            return .largeTitle.weight(.medium)
        }
        if cardSide >= 118 {
            return .title.weight(.medium)
        }
        return .title2.weight(.medium)
    }

    var titleFont: Font {
        if isRegularWidth || cardSide >= 140 {
            return .body.weight(.semibold)
        }
        if cardSide >= 118 {
            return .callout.weight(.semibold)
        }
        return .caption.weight(.semibold)
    }
}

#Preview {
    NavigationStack {
        GeneratorView()
    }
}
