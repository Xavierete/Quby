import SwiftUI

enum TransientMessage {

    static func present(_ message: Binding<String?>, text: String, duration: Duration = .seconds(1.6)) {
        message.wrappedValue = text
        Task { @MainActor in
            try? await Task.sleep(for: duration)
            if message.wrappedValue == text { message.wrappedValue = nil }
        }
    }
}

struct TransientToastOverlay: View {

    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.opacity)
        }
    }
}
