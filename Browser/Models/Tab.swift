import Foundation
import WebKit

enum TabSource: String, Codable {
    case user
    case agent
}

final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var progress: Double = 0
    @Published var mobileMode: Bool = false
    @Published var source: TabSource = .user

    /// The active web view. `nil` when the tab has been discarded by Memory Saver.
    @Published var webView: WKWebView?

    /// Updated whenever this tab is shown. Used by Memory Saver to find idle tabs.
    @Published var lastActivatedAt: Date = Date()

    /// URL kept while the tab is discarded so we can restore it on reactivation.
    private var discardedURL: URL?

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    var isDiscarded: Bool { webView == nil }

    init(configuration: WKWebViewConfiguration) {
        let wv = Self.makeWebView(configuration: configuration, mobile: false)
        self.webView = wv
    }

    private static func makeWebView(configuration: WKWebViewConfiguration, mobile: Bool) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.customUserAgent = mobile ? Self.mobileUA : Self.desktopUA
        wv.isInspectable = true
        return wv
    }

    func setMobileMode(_ enabled: Bool, reload: Bool = true) {
        guard mobileMode != enabled else { return }
        mobileMode = enabled
        webView?.customUserAgent = enabled ? Self.mobileUA : Self.desktopUA
        if reload && webView?.url != nil {
            webView?.reload()
        }
    }

    func toggleMobileMode() {
        setMobileMode(!mobileMode)
    }

    /// Open the Web Inspector window for this tab using a private WebKit API.
    @discardableResult
    func showWebInspector() -> Bool {
        guard let wv = webView else { return false }
        wv.isInspectable = true
        let inspectorSel = NSSelectorFromString("_inspector")
        guard wv.responds(to: inspectorSel),
              let inspectorObj = wv.perform(inspectorSel)?.takeUnretainedValue() as? NSObject else {
            return false
        }
        let showSel = NSSelectorFromString("show")
        guard inspectorObj.responds(to: showSel) else { return false }
        inspectorObj.perform(showSel)
        return true
    }

    /// Free the WKWebView (and its WebContent process page) but keep title/URL/source so we can restore.
    func discard() {
        guard let wv = webView else { return }
        discardedURL = wv.url
        wv.stopLoading()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        webView = nil
    }

    /// Recreate the WKWebView and reload the previously-loaded URL.
    func reactivate(configuration: WKWebViewConfiguration) {
        guard webView == nil else { return }
        let wv = Self.makeWebView(configuration: configuration, mobile: mobileMode)
        webView = wv
        if let url = discardedURL {
            wv.load(URLRequest(url: url))
        }
        discardedURL = nil
    }
}
