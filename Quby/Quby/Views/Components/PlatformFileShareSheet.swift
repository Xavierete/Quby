import SwiftUI

#if os(iOS)
import UIKit

/// Presents the system share sheet on iOS (`UIActivityViewController`) from the
/// topmost visible view controller so it rises as a native bottom sheet.
///
/// Presents at most once per URL until the user dismisses the sheet — parent
/// re-renders (e.g. hiding export progress) must not open a second copy.
struct PlatformFileShareSheet: UIViewControllerRepresentable {
    let url: URL?
    @Binding var isPresented: Bool
    /// Called once the share sheet has been presented.
    var onPresented: (() -> Void)? = nil

    /// Survives representable remounts so a second sheet cannot open for the same file.
    private static var lockedURL: URL?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onPresented = onPresented
        context.coordinator.isPresented = $isPresented

        guard isPresented, let url else { return }

        // Already presented (or presenting) this file — ignore parent re-renders.
        if context.coordinator.activeURL == url { return }
        if context.coordinator.isPresenting { return }
        if Self.lockedURL == url { return }

        let presenter = topMostViewController(from: controller) ?? controller
        // Another share sheet is already on screen.
        if presenter.presentedViewController is UIActivityViewController { return }

        Self.lockedURL = url
        context.coordinator.activeURL = url
        context.coordinator.isPresenting = true

        let coordinator = context.coordinator
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                Self.lockedURL = nil
                coordinator.activeURL = nil
                coordinator.isPresenting = false
                coordinator.isPresented.wrappedValue = false
            }
        }

        if UIDevice.current.userInterfaceIdiom == .pad,
           let popover = activity.popoverPresentationController {
            let view = presenter.view!
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.maxY - 24,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        DispatchQueue.main.async {
            guard Self.lockedURL == url else { return }
            // Already showing a share sheet — keep the lock until that one dismisses.
            if presenter.presentedViewController is UIActivityViewController { return }
            guard presenter.presentedViewController == nil else {
                Self.lockedURL = nil
                coordinator.activeURL = nil
                coordinator.isPresenting = false
                return
            }
            presenter.present(activity, animated: true) {
                coordinator.onPresented?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPresented: onPresented)
    }

    /// Walks up from any VC to the frontmost presented controller in its window.
    private func topMostViewController(from start: UIViewController) -> UIViewController? {
        var root = start
        if let window = start.view.window {
            root = window.rootViewController ?? start
        } else if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let key = scene.windows.first(where: \.isKeyWindow) {
            root = key.rootViewController ?? start
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    final class Coordinator {
        var isPresented: Binding<Bool>
        var activeURL: URL?
        var onPresented: (() -> Void)?
        var isPresenting = false

        init(isPresented: Binding<Bool>, onPresented: (() -> Void)?) {
            self.isPresented = isPresented
            self.onPresented = onPresented
        }
    }
}

#elseif os(macOS)
import AppKit

/// Presents the system sharing picker on Mac (`NSSharingServicePicker`).
///
/// The picker must be retained while visible, and anchored to a real window view —
/// a zero-size SwiftUI-only host often fails silently on macOS.
struct PlatformFileShareSheet: NSViewRepresentable {
    let url: URL?
    @Binding var isPresented: Bool
    /// Called right after the sharing picker menu is shown.
    var onPresented: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.setFrameSize(NSSize(width: 1, height: 1))
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPresented = onPresented

        guard isPresented, let url else {
            context.coordinator.clear()
            return
        }
        guard context.coordinator.presentedURL != url else { return }
        context.coordinator.presentedURL = url

        DispatchQueue.main.async {
            context.coordinator.present(url: url, from: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPresented: onPresented)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        @Binding var isPresented: Bool
        var presentedURL: URL?
        var onPresented: (() -> Void)?
        /// Strong reference — releasing early dismisses the menu immediately.
        var picker: NSSharingServicePicker?

        init(isPresented: Binding<Bool>, onPresented: (() -> Void)?) {
            _isPresented = isPresented
            self.onPresented = onPresented
        }

        func present(url: URL, from host: NSView) {
            guard picker == nil else { return }

            let picker = NSSharingServicePicker(items: [url])
            picker.delegate = self
            self.picker = picker

            let anchor = host.window?.contentView ?? NSApp.keyWindow?.contentView ?? host
            let rect: NSRect
            if anchor === host {
                rect = host.bounds
            } else {
                rect = NSRect(
                    x: anchor.bounds.maxX - 36,
                    y: anchor.bounds.maxY - 36,
                    width: 1,
                    height: 1
                )
            }
            picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
            onPresented?()
        }

        func clear() {
            picker = nil
            presentedURL = nil
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            isPresented = false
            clear()
        }
    }
}
#endif
