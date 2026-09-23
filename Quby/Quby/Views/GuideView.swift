import SwiftUI

struct GuideSlide: Identifiable {
    let id: Int
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let badge: String
}

struct GuideView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private let slides: [GuideSlide] = [
        GuideSlide(
            id: 0,
            icon: "qrcode.viewfinder",
            color: .blue,
            title: "Instant Scanning",
            detail: "Read QR codes and all standard barcodes in real time with the camera, or decode images from your Photos library.",
            badge: "Camera & Photos"
        ),
        GuideSlide(
            id: 1,
            icon: "paintbrush",
            color: .purple,
            title: "Create & Style",
            detail: "Build codes for websites, contacts, Wi-Fi networks, and locations. Customise shapes, colour palettes, and center logos.",
            badge: "PNG, PDF & SVG"
        ),
        GuideSlide(
            id: 2,
            icon: "shield.lefthalf.filled",
            color: .orange,
            title: "Link Safety",
            detail: "Inspect destinations before opening. Quby alerts you to lookalike domains, unencrypted links, and hidden addresses.",
            badge: "Phishing Protection"
        ),
        GuideSlide(
            id: 3,
            icon: "lock.shield",
            color: .green,
            title: "Private & On-Device",
            detail: "Your history and generated codes stay entirely on this device. Search, filter, or export your data to CSV anytime.",
            badge: "Offline Storage"
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(iOS)
                TabView(selection: $currentStep) {
                    ForEach(slides) { slide in
                        slideView(for: slide)
                            .tag(slide.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.smooth, value: currentStep)
                #else
                slideView(for: slides[currentStep])
                    .id(currentStep)
                    .animation(.smooth, value: currentStep)
                #endif

                footerControls
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func slideView(for slide: GuideSlide) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(slide.color.opacity(0.12))
                    .frame(width: 120, height: 120)

                Image(systemName: slide.icon)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(slide.color)
            }

            Text(slide.badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(slide.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(slide.color.opacity(0.1), in: Capsule())

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(slide.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .padding()
    }

    private var footerButtonTitle: String {
        currentStep < slides.count - 1 ? "Next" : "Get started"
    }

    private var footerControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<slides.count, id: \.self) { index in
                    Capsule()
                        .fill(currentStep == index ? slides[currentStep].color : Color.gray.opacity(0.3))
                        .frame(width: currentStep == index ? 22 : 7, height: 7)
                        .animation(.smooth(duration: 0.25), value: currentStep)
                }
            }

            Button {
                if currentStep < slides.count - 1 {
                    withAnimation {
                        currentStep += 1
                    }
                } else {
                    dismiss()
                }
            } label: {
                Text(footerButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: footerButtonTitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    GuideView()
}
