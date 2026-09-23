import SwiftUI

enum PlatformKeyboard {
    case phone
    case email
    case url
    case numbersAndPunctuation
}

extension View {
    @ViewBuilder
    func platformKeyboard(_ kind: PlatformKeyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .phone:
            keyboardType(.phonePad)
        case .email:
            keyboardType(.emailAddress)
        case .url:
            keyboardType(.URL)
        case .numbersAndPunctuation:
            keyboardType(.numbersAndPunctuation)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformAutocapitalizationNever() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
