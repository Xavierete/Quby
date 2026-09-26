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

    /// When true, finishing (Get started / Done) marks the guide as seen.
    var markSeenOnFinish: Bool = false
    var onFinish: (() -> Void)? = nil

    private let slides: [GuideSlide] = [
        GuideSlide(
            id: 0,
            icon: "qrcode.viewfinder",
            color: .blue,
            title: "Scan in a snap",
            detail: "Point the camera at any QR or barcode, or pick a photo from your library. Quby reads it instantly and saves it to History when you want.",
            badge: "Camera & Photos"
        ),
        GuideSlide(
            id: 1,
            icon: "paintbrush",
            color: .purple,
            title: "Create & style",
            detail: "Make codes for websites, Wi‑Fi, contacts, email, SMS, locations, and plain text. Tune shapes, palettes, and a center logo, then share as PNG, PDF, or SVG.",
            badge: "PNG, PDF & SVG"
        ),
        GuideSlide(
            id: 2,
            icon: "sparkles",
            color: .mint,
            title: "Smart organization",
            detail: "On devices with Apple Intelligence, History can group your codes into clear sections with short titles—Travel, Home Wi‑Fi, Contacts, and more. Reorganize anytime from the Filter menu.",
            badge: "Apple Intelligence"
        ),
        GuideSlide(
            id: 3,
            icon: "shield.lefthalf.filled",
            color: .orange,
            title: "Safer links",
            detail: "Before you open a website, Quby flags lookalike domains, unencrypted http links, and other risky patterns so you can decide with context.",
            badge: "Link Safety"
        ),
        GuideSlide(
            id: 4,
            icon: "lock.shield",
            color: .green,
            title: "Private on this device",
            detail: "Scans and creations stay on your device. Search, filter, favorite, and export History as text, CSV, Excel, JSON, or PDF—with or without QR images.",
            badge: "On-Device"
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
                        finish()
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
                    finish()
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

    private func finish() {
        if markSeenOnFinish {
            onFinish?()
        }
        dismiss()
    }
}

#Preview {
    GuideView()
}
