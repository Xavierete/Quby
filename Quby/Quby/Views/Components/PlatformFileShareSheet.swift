import SwiftUI

#if os(iOS)
import UIKit

/// Hosts and presents the system share sheet (`UIActivityViewController`).
struct PlatformFileShareSheet: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var onPresented: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onPresented = onPresented

        if isPresented {
            guard controller.presentedViewController == nil,
                  context.coordinator.presentedURL != url else { return }

            context.coordinator.presentedURL = url

            let coordinator = context.coordinator
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                Task { @MainActor in
                    coordinator.presentedURL = nil
                    coordinator.isPresented = false
                }
            }

            if let popover = activity.popoverPresentationController {
                popover.sourceView = controller.view
                popover.sourceRect = CGRect(
                    x: controller.view.bounds.midX,
                    y: controller.view.bounds.minY + 8,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }

            controller.present(activity, animated: true)
            coordinator.onPresented?()
        } else if controller.presentedViewController != nil {
            controller.dismiss(animated: true)
            context.coordinator.presentedURL = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPresented: onPresented)
    }

    final class Coordinator {
        @Binding var isPresented: Bool
        var presentedURL: URL?
        var onPresented: (() -> Void)?

        init(isPresented: Binding<Bool>, onPresented: (() -> Void)?) {
            _isPresented = isPresented
            self.onPresented = onPresented
        }
    }
}

#elseif os(macOS)
import AppKit

/// Presents the system sharing picker (`NSSharingServicePicker`).
/// The picker must be retained for the duration of the menu, and anchored to a
/// real window view — a zero-size SwiftUI background host is unreliable on Mac.
struct PlatformFileShareSheet: NSViewRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var onPresented: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.setFrameSize(NSSize(width: 1, height: 1))
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPresented = onPresented

        guard isPresented else {
            context.coordinator.clear()
            return
        }
        guard context.coordinator.presentedURL != url else { return }
        context.coordinator.presentedURL = url

        // Defer so the host is in a window hierarchy before showing the picker.
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
        /// Keep the picker alive while the menu is visible.
        var picker: NSSharingServicePicker?

        init(isPresented: Binding<Bool>, onPresented: (() -> Void)?) {
            _isPresented = isPresented
            self.onPresented = onPresented
        }

        func present(url: URL, from host: NSView) {
            let picker = NSSharingServicePicker(items: [url])
            picker.delegate = self
            self.picker = picker

            let anchor = host.window?.contentView ?? NSApp.keyWindow?.contentView ?? host
            let rect: NSRect
            if anchor === host {
                rect = host.bounds
            } else {
                // Near the trailing/top toolbar area — visible and hittable.
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
