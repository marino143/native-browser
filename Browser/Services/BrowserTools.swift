import Foundation
import WebKit
import AppKit

@MainActor
final class BrowserTools {
    weak var services: BrowserServices?

    /// Returns the currently focused window's state. MCP tools target this.
    var state: BrowserState? { services?.activeState }

    init(services: BrowserServices) {
        self.services = services
    }

    // MARK: - Tool catalog (MCP tools/list)

    static let definitions: [[String: Any]] = [
        [
            "name": "browser_list_tabs",
            "description": "List all open tabs with their id, title, URL, and whether each is the active tab.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "additionalProperties": false
            ]
        ],
        [
            "name": "browser_get_active_tab",
            "description": "Get the currently active tab (id, title, URL, loading state).",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "additionalProperties": false
            ]
        ],
        [
            "name": "browser_navigate",
            "description": "Navigate the active tab (or a specific tab by id) to a URL. Search query if not URL-shaped.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL or search query"],
                    "tab_id": ["type": "string", "description": "Optional tab id (UUID); defaults to active tab"]
                ],
                "required": ["url"]
            ]
        ],
        [
            "name": "browser_new_tab",
            "description": "Open a new tab. If url is given, navigate it there immediately.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "Optional URL to load in the new tab"]
                ]
            ]
        ],
        [
            "name": "browser_close_tab",
            "description": "Close the tab with the given id.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "tab_id": ["type": "string", "description": "UUID of the tab to close"]
                ],
                "required": ["tab_id"]
            ]
        ],
        [
            "name": "browser_switch_tab",
            "description": "Make the tab with the given id the active tab.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "tab_id": ["type": "string"]
                ],
                "required": ["tab_id"]
            ]
        ],
        [
            "name": "browser_back",
            "description": "Go back in the active tab's history.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_forward",
            "description": "Go forward in the active tab's history.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_reload",
            "description": "Reload the active tab.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_get_page_text",
            "description": "Return the visible text content of the active tab (document.body.innerText). Truncated to ~50k chars.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_get_page_html",
            "description": "Return the full HTML of the active tab (document.documentElement.outerHTML). Truncated to ~200k chars.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_execute_js",
            "description": "Run arbitrary JavaScript in the active tab and return the result as a string. Useful for clicking, filling forms, scraping data, etc.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "code": ["type": "string", "description": "JavaScript expression or statements"]
                ],
                "required": ["code"]
            ]
        ],
        [
            "name": "browser_click",
            "description": "Click the first element matching a CSS selector in the active tab.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "selector": ["type": "string", "description": "CSS selector"]
                ],
                "required": ["selector"]
            ]
        ],
        [
            "name": "browser_fill",
            "description": "Set the value of the first input/textarea matching a CSS selector and fire input/change events.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "selector": ["type": "string"],
                    "text": ["type": "string"]
                ],
                "required": ["selector", "text"]
            ]
        ],
        [
            "name": "browser_screenshot",
            "description": "Take a PNG screenshot of the active tab's visible viewport. Returned as base64 image content.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_list_profiles",
            "description": "List all browser profiles and indicate which is active.",
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
        ],
        [
            "name": "browser_switch_profile",
            "description": "Switch to a profile by id or name. Closes all current tabs and opens a fresh tab in the new profile.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "profile": ["type": "string", "description": "Profile UUID or name (case-insensitive)"]
                ],
                "required": ["profile"]
            ]
        ],
        [
            "name": "browser_set_mobile_mode",
            "description": "Switch the active tab between mobile and desktop user-agent + viewport. Reloads the page so the site re-renders with the new UA.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "enabled": ["type": "boolean", "description": "true = iPhone UA + 393×852 viewport; false = desktop"]
                ],
                "required": ["enabled"]
            ]
        ]
    ]

    // MARK: - Dispatch

    func call(_ name: String, arguments: [String: Any]) async throws -> [[String: Any]] {
        guard let state = state else { throw MCPError.serverNotReady }
        switch name {
        case "browser_list_tabs":
            let tabs = state.tabs.map { tab in
                [
                    "id": tab.id.uuidString,
                    "title": tab.title,
                    "url": tab.urlString,
                    "active": tab.id == state.currentTabID,
                    "is_loading": tab.isLoading,
                    "is_discarded": tab.isDiscarded,
                    "source": tab.source.rawValue
                ] as [String: Any]
            }
            return jsonContent(["tabs": tabs])

        case "browser_get_active_tab":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            return jsonContent([
                "id": tab.id.uuidString,
                "title": tab.title,
                "url": tab.urlString,
                "is_loading": tab.isLoading,
                "is_discarded": tab.isDiscarded,
                "can_go_back": tab.canGoBack,
                "can_go_forward": tab.canGoForward,
                "source": tab.source.rawValue
            ])

        case "browser_navigate":
            guard let url = arguments["url"] as? String else { throw MCPError.invalidParams("url is required") }
            if let tabIDStr = arguments["tab_id"] as? String,
               let tabID = UUID(uuidString: tabIDStr) {
                if let tab = state.tabs.first(where: { $0.id == tabID }) {
                    state.currentTabID = tab.id
                }
            }
            state.navigate(to: url, source: .agent)
            return textContent("Navigating to: \(url)")

        case "browser_new_tab":
            let url = (arguments["url"] as? String).flatMap(URL.init(string:))
            state.newTab(url: url, source: .agent)
            if let tab = state.currentTab {
                return jsonContent(["id": tab.id.uuidString, "url": tab.urlString])
            }
            return textContent("Tab opened.")

        case "browser_close_tab":
            guard let idStr = arguments["tab_id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let tab = state.tabs.first(where: { $0.id == id }) else {
                throw MCPError.invalidParams("tab_id not found")
            }
            state.closeTab(tab)
            return textContent("Tab closed.")

        case "browser_switch_tab":
            guard let idStr = arguments["tab_id"] as? String,
                  let id = UUID(uuidString: idStr),
                  state.tabs.contains(where: { $0.id == id }) else {
                throw MCPError.invalidParams("tab_id not found")
            }
            state.currentTabID = id
            return textContent("Switched to tab \(idStr).")

        case "browser_back":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            try liveWebView(tab).goBack()
            return textContent("Went back.")

        case "browser_forward":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            try liveWebView(tab).goForward()
            return textContent("Went forward.")

        case "browser_reload":
            state.reloadCurrentTab()
            return textContent("Reloaded.")

        case "browser_get_page_text":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let raw = try await evaluate(on: wv, js: "document.body ? document.body.innerText : ''")
            let str = (raw as? String) ?? ""
            return textContent(truncate(str, to: 50_000))

        case "browser_get_page_html":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let raw = try await evaluate(on: wv, js: "document.documentElement.outerHTML")
            let str = (raw as? String) ?? ""
            return textContent(truncate(str, to: 200_000))

        case "browser_execute_js":
            guard let code = arguments["code"] as? String else {
                throw MCPError.invalidParams("code is required")
            }
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let raw = try await evaluate(on: wv, js: code)
            return textContent(stringify(raw))

        case "browser_click":
            guard let selector = arguments["selector"] as? String else {
                throw MCPError.invalidParams("selector is required")
            }
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let escaped = jsString(selector)
            let js = """
            (function(){
              var el = document.querySelector(\(escaped));
              if (!el) return {ok:false, error:'no element matched'};
              el.scrollIntoView({block:'center'});
              el.click();
              return {ok:true, tag: el.tagName, text: (el.innerText||'').slice(0,200)};
            })()
            """
            let raw = try await evaluate(on: wv, js: js)
            return textContent(stringify(raw))

        case "browser_fill":
            guard let selector = arguments["selector"] as? String,
                  let text = arguments["text"] as? String else {
                throw MCPError.invalidParams("selector and text are required")
            }
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let js = """
            (function(){
              var el = document.querySelector(\(jsString(selector)));
              if (!el) return {ok:false, error:'no element matched'};
              var setter = Object.getOwnPropertyDescriptor(el.__proto__, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
              if (setter && setter.set) setter.set.call(el, \(jsString(text))); else el.value = \(jsString(text));
              el.dispatchEvent(new Event('input', {bubbles:true}));
              el.dispatchEvent(new Event('change', {bubbles:true}));
              return {ok:true, tag: el.tagName};
            })()
            """
            let raw = try await evaluate(on: wv, js: js)
            return textContent(stringify(raw))

        case "browser_screenshot":
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            let wv = try liveWebView(tab)
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            let image = try await wv.takeSnapshot(configuration: config)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw MCPError.internalError("failed to encode screenshot")
            }
            return [[
                "type": "image",
                "data": png.base64EncodedString(),
                "mimeType": "image/png"
            ]]

        case "browser_list_profiles":
            let list = (services?.profiles ?? []).map { p in
                [
                    "id": p.id.uuidString,
                    "name": p.name,
                    "active": p.id == state.currentProfileID
                ] as [String: Any]
            }
            return jsonContent(["profiles": list])

        case "browser_switch_profile":
            guard let key = arguments["profile"] as? String else {
                throw MCPError.invalidParams("profile is required")
            }
            let target = services?.profiles.first(where: {
                $0.id.uuidString.lowercased() == key.lowercased() ||
                $0.name.lowercased() == key.lowercased()
            })
            guard let target = target else {
                throw MCPError.invalidParams("no profile matched '\(key)'")
            }
            state.switchProfile(to: target)
            return textContent("Switched to profile \(target.name).")

        case "browser_set_mobile_mode":
            guard let enabled = arguments["enabled"] as? Bool else {
                throw MCPError.invalidParams("enabled (boolean) is required")
            }
            guard let tab = state.currentTab else { throw MCPError.noActiveTab }
            tab.setMobileMode(enabled)
            return textContent(enabled ? "Switched to mobile (iPhone UA, 393×852)." : "Switched to desktop UA.")

        default:
            throw MCPError.methodNotFound(name)
        }
    }

    // MARK: - Helpers

    private func liveWebView(_ tab: Tab) throws -> WKWebView {
        state?.ensureLive(tab)
        guard let wv = tab.webView else {
            throw MCPError.internalError("tab is discarded and could not be reactivated")
        }
        return wv
    }

    private func evaluate(on webView: WKWebView, js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }

    private func jsonContent(_ obj: [String: Any]) -> [[String: Any]] {
        let json = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [["type": "text", "text": json]]
    }

    private func textContent(_ text: String) -> [[String: Any]] {
        [["type": "text", "text": text]]
    }

    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "null" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }

    private func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        return String(s.prefix(limit)) + "\n\n[…truncated, original length: \(s.count) chars]"
    }

    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
        let str = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // Strip the wrapping array brackets to leave just the quoted/escaped string
        return String(str.dropFirst().dropLast())
    }
}

enum MCPError: Error, CustomStringConvertible {
    case serverNotReady
    case noActiveTab
    case invalidParams(String)
    case methodNotFound(String)
    case internalError(String)

    var description: String {
        switch self {
        case .serverNotReady: return "Browser state not available"
        case .noActiveTab: return "No active tab"
        case .invalidParams(let m): return "Invalid params: \(m)"
        case .methodNotFound(let m): return "Method not found: \(m)"
        case .internalError(let m): return "Internal error: \(m)"
        }
    }
}
