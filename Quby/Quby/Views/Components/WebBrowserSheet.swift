import SwiftUI
import WebKit

struct BrowserLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

enum InAppBrowser {

    /// Opens WebKit only when the device is online; otherwise flips `showOfflineAlert`.
    @MainActor
    static func open(_ url: URL,
                     into link: Binding<BrowserLink?>,
                     offlineAlert: Binding<Bool>) async {
        if await NetworkReachability.isOnline() {
            link.wrappedValue = BrowserLink(url: url)
        } else {
            offlineAlert.wrappedValue = true
        }
    }
}

struct WebBrowserSheet: View {

    let url: URL
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                if loadFailed {
                    offlineUnavailableView
                } else {
                    WebKitView(
                        url: url,
                        isLoading: $isLoading,
                        loadFailed: $loadFailed
                    )

                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(browserBackground.opacity(0.92))
                            .accessibilityLabel("Loading")
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(browserBackground)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(url.host() ?? "Website")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: PlatformToolbar.trailing) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in Safari")
                }
            }
        }
    }

    private var browserBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    private var offlineUnavailableView: some View {
        ContentUnavailableView {
            Label("No connection", systemImage: "wifi.slash")
        } description: {
            Text("Check your internet connection and try again.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(macOS)
private struct WebKitView: NSViewRepresentable {

    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> WebKitCoordinator {
        WebKitCoordinator(isLoading: $isLoading, loadFailed: $loadFailed)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(to: webView)
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.isLoading = $isLoading
        context.coordinator.loadFailed = $loadFailed
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: WebKitCoordinator) {
        coordinator.detach(from: webView)
    }
}
#else
private struct WebKitView: UIViewRepresentable {

    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadFailed: Bool

    func makeCoordinator() -> WebKitCoordinator {
        WebKitCoordinator(isLoading: $isLoading, loadFailed: $loadFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(to: webView)
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.isLoading = $isLoading
        context.coordinator.loadFailed = $loadFailed
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: WebKitCoordinator) {
        coordinator.detach(from: webView)
    }
}
#endif

private final class WebKitCoordinator: NSObject, WKNavigationDelegate {
    var isLoading: Binding<Bool>
    var loadFailed: Binding<Bool>

    /// After the first paint, never show the blocking spinner again
    /// (subframe / SPA navigations keep WKWebView.isLoading busy).
    private var hasPresentedContent = false
    private var timeoutTask: Task<Void, Never>?
    private weak var webView: WKWebView?

    init(isLoading: Binding<Bool>, loadFailed: Binding<Bool>) {
        self.isLoading = isLoading
        self.loadFailed = loadFailed
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func detach(from webView: WKWebView) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.navigationDelegate = nil
        webView.stopLoading()
        self.webView = nil
    }

    func load(_ url: URL, in webView: WKWebView) {
        hasPresentedContent = false
        setLoading(true)
        setFailed(false)
        scheduleTimeout()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if !hasPresentedContent {
            setLoading(true)
            setFailed(false)
            scheduleTimeout()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        markContentPresented()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markContentPresented()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error, webView: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error, webView: webView)
    }

    private func markContentPresented() {
        hasPresentedContent = true
        timeoutTask?.cancel()
        timeoutTask = nil
        setLoading(false)
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            guard !self.hasPresentedContent else {
                self.setLoading(false)
                return
            }

            if let webView = self.webView {
                webView.stopLoading()
            }
            self.setLoading(false)
            self.setFailed(true)
        }
    }

    private func handleLoadFailure(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        if hasPresentedContent {
            setLoading(false)
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        setLoading(false)
        setFailed(true)
    }

    private func setLoading(_ value: Bool) {
        Task { @MainActor in
            if isLoading.wrappedValue != value {
                isLoading.wrappedValue = value
            }
        }
    }

    private func setFailed(_ value: Bool) {
        Task { @MainActor in
            if loadFailed.wrappedValue != value {
                loadFailed.wrappedValue = value
            }
        }
    }
}
