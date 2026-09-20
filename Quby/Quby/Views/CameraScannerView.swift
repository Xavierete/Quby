import SwiftUI

struct CameraScannerView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isTorchOn = false

    private var isPresentedInWindow: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                placeholder("Starting camera…", icon: "camera")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)

                Text("Point the camera at a QR code or barcode")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Scan from camera")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    closeScanner()
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isTorchOn.toggle()
                } label: {
                    Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isTorchOn ? Color.yellow : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.gray)
                }
                .disabled(true)
            }
        }
    }

    private func closeScanner() {
        if isPresentedInWindow {
            dismissWindow(id: QubyWindowID.cameraScanner)
        } else {
            dismiss()
        }
    }

    private func placeholder(_ message: String, icon: String) -> some View {
        ZStack {
            Color.gray.opacity(0.2)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.largeTitle)
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Camera") {
    NavigationStack {
        CameraScannerView()
    }
}
