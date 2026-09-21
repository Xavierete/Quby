import SwiftUI

struct ScanCapsuleButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.blue.gradient))
        }
        .buttonStyle(.plain)
    }
}
