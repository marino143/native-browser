import SwiftUI
import WebKit

struct WebView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var tab: Tab

    var body: some View {
        if tab.mobileMode {
            mobileLayout
        } else {
            WebViewBridge(tab: tab, state: state)
        }
    }

    private var mobileLayout: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .font(.system(size: 11))
                        Text("iPhone 14 Pro · 393 × 852")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                    let availableHeight = max(400, geo.size.height - 60)
                    let frameHeight = min(852, availableHeight)

                    WebViewBridge(tab: tab, state: state)
                        .frame(width: 393, height: frameHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 4)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct WebViewBridge: NSViewRepresentable {
    @ObservedObject var tab: Tab
    let state: BrowserState

    func makeNSView(context: Context) -> WKWebView {
        // Caller must only mount this when tab.webView != nil (ContentView enforces that).
        guard let wv = tab.webView else {
            return WKWebView()
        }
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.observe(webView: wv)
        if wv.url == nil && wv.backForwardList.currentItem == nil {
            wv.loadHTMLString(StartPage.html, baseURL: nil)
        }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab, state: state) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let tab: Tab
        weak var state: BrowserState?
        private var observers: [NSKeyValueObservation] = []

        init(tab: Tab, state: BrowserState) {
            self.tab = tab
            self.state = state
            super.init()
        }

        deinit { observers.forEach { $0.invalidate() } }

        func observe(webView: WKWebView) {
            observers.removeAll()
            observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                let v = wv.estimatedProgress
                Task { @MainActor in self?.tab.progress = v }
            })
            observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                let v = wv.title ?? ""
                Task { @MainActor in self?.tab.title = v.isEmpty ? "New Tab" : v }
            })
            observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                let v = wv.url?.absoluteString ?? ""
                Task { @MainActor in self?.tab.urlString = v }
            })
            observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                let v = wv.isLoading
                Task { @MainActor in self?.tab.isLoading = v }
            })
            observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                let v = wv.canGoBack
                Task { @MainActor in self?.tab.canGoBack = v }
            })
            observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                let v = wv.canGoForward
                Task { @MainActor in self?.tab.canGoForward = v }
            })
        }

        // MARK: - Open-in-new-tab routing
        //
        // Cmd+click       → background tab (don't steal focus)
        // Cmd+Shift+click → foreground tab
        // target=_blank /
        // window.open()   → foreground tab
        // Middle click    → background tab (mouse button 2 in WebKit)

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let modifiers = navigationAction.modifierFlags
            let isCmdClick = modifiers.contains(.command)
            let isMiddleClick = navigationAction.buttonNumber == 4

            // Only intercept primary-frame navigations that have a URL and are user-initiated.
            if let url = navigationAction.request.url,
               navigationAction.targetFrame?.isMainFrame == true,
               isCmdClick || isMiddleClick {
                decisionHandler(.cancel)
                let foreground = isCmdClick && modifiers.contains(.shift)
                let stateRef = state
                Task { @MainActor in
                    stateRef?.newTab(url: url, source: .user, selectNewTab: foreground)
                }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // target="_blank" or window.open() — open as a new tab in the same window.
            if let url = navigationAction.request.url {
                let modifiers = navigationAction.modifierFlags
                // If user Cmd+clicked a target=_blank link, keep it in the background.
                let foreground = !modifiers.contains(.command)
                let stateRef = state
                Task { @MainActor in
                    stateRef?.newTab(url: url, source: .user, selectNewTab: foreground)
                }
            }
            return nil
        }
    }
}

enum StartPage {
    static let html: String = """
    <!doctype html><html><head><meta charset='utf-8'>
    <meta name='viewport' content='width=device-width,initial-scale=1'>
    <title>New Tab</title>
    <style>
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    html, body { margin: 0; height: 100%; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
        display: flex; align-items: center; justify-content: center;
        background: linear-gradient(135deg, #0b1120 0%, #1e293b 100%);
        color: #e2e8f0;
        -webkit-font-smoothing: antialiased;
    }
    @media (prefers-color-scheme: light) {
        body { background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%); color: #0f172a; }
    }
    .wrap { text-align: center; max-width: 560px; padding: 32px; }
    h1 { font-size: 56px; margin: 0 0 6px 0; font-weight: 200; letter-spacing: -1.5px; }
    .accent { background: linear-gradient(135deg, #818cf8, #f472b6); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-weight: 500; }
    p.lead { opacity: 0.55; margin: 0 0 32px 0; font-size: 14px; letter-spacing: 0.3px; }
    .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-top: 12px; }
    a.tile {
        display: block; padding: 14px 16px; border-radius: 10px;
        background: rgba(255,255,255,0.04); text-decoration: none; color: inherit;
        border: 1px solid rgba(255,255,255,0.06); transition: all 0.15s ease;
    }
    a.tile:hover { background: rgba(255,255,255,0.08); transform: translateY(-1px); }
    @media (prefers-color-scheme: light) {
        a.tile { background: rgba(0,0,0,0.04); border-color: rgba(0,0,0,0.06); }
        a.tile:hover { background: rgba(0,0,0,0.07); }
    }
    .tile h3 { margin: 0 0 4px 0; font-size: 13px; font-weight: 600; }
    .tile p { margin: 0; font-size: 11px; opacity: 0.6; }
    .badges { display: flex; gap: 8px; justify-content: center; margin-top: 24px; flex-wrap: wrap; }
    .badge { font-size: 10px; padding: 4px 10px; border-radius: 12px; background: rgba(129,140,248,0.15); color: #a5b4fc; letter-spacing: 0.5px; }
    @media (prefers-color-scheme: light) { .badge { color: #4f46e5; background: rgba(79,70,229,0.1); } }
    </style></head>
    <body>
    <div class='wrap'>
        <h1>nat<span class='accent'>ive</span></h1>
        <p class='lead'>Apple Silicon · WebKit · Ad-blocked</p>
        <div class='grid'>
            <a class='tile' href='https://duckduckgo.com'><h3>DuckDuckGo</h3><p>Private search</p></a>
            <a class='tile' href='https://news.ycombinator.com'><h3>Hacker News</h3><p>Tech news</p></a>
            <a class='tile' href='https://github.com'><h3>GitHub</h3><p>Code</p></a>
            <a class='tile' href='https://en.wikipedia.org'><h3>Wikipedia</h3><p>Knowledge</p></a>
        </div>
        <div class='badges'>
            <span class='badge'>ARM64</span>
            <span class='badge'>WKWEBKIT</span>
            <span class='badge'>NO TRACKING</span>
        </div>
    </div>
    </body></html>
    """
}
