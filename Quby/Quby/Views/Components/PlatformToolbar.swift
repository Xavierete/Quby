import SwiftUI

enum PlatformToolbar {
    static var leading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var trailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }

    static var bottomAction: ToolbarItemPlacement {
        #if os(macOS)
        .confirmationAction
        #else
        .bottomBar
        #endif
    }
}
