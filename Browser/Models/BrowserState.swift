import SwiftUI
import WebKit
import Combine

/// Per-window browser state. Tabs, current profile, current bookmarks list, UI sheets.
/// Shared resources (profiles list, MCP server, ad blocker, memory saver) live in `BrowserServices.shared`.
@MainActor
final class BrowserState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var currentTabID: UUID? {
        didSet { didChangeCurrentTab() }
    }
    @Published var currentProfileID: UUID
    @Published var bookmarks: [Bookmark] = []
    @Published var showBookmarksBar: Bool = true
    @Published var addressBarFocusToken: Int = 0
    @Published var showingProfileManager: Bool = false
    @Published var showingClaudeIntegration: Bool = false
    @Published var showingBookmarksManager: Bool = false
    @Published var showingPasswordsManager: Bool = false
    @Published var pendingPasswordSave: PendingPasswordSave?
    private(set) lazy var autofillBridge = AutofillBridge(state: self)

    var services: BrowserServices { .shared }

    var currentTab: Tab? {
        tabs.first { $0.id == currentTabID }
    }

    var currentProfile: Profile? {
        services.profiles.first { $0.id == currentProfileID }
    }

    init(profile: Profile? = nil) {
        let services = BrowserServices.shared
        let resolved: Profile
        if let profile = profile {
            resolved = profile
        } else {
            let savedID = UserDefaults.standard.string(forKey: "currentProfileID").flatMap(UUID.init(uuidString:))
            resolved = services.profiles.first(where: { $0.id == savedID })
                    ?? services.profiles.first!
        }
        currentProfileID = resolved.id
        services.bookmarksManager.migrateLegacyIfNeeded(toProfile: resolved.id)
        bookmarks = services.bookmarksManager.load(for: resolved.id)

        services.register(state: self)
        newTab()
    }

    // MARK: - Tab construction

    private func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: profile.dataStoreUUID)
    }

    private func makeConfig(for profile: Profile) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore(for: profile)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        if services.adBlockerEnabled, let rules = services.contentRuleList {
            config.userContentController.add(rules)
        }
        // Wire up password autofill: inject content script + register message handler.
        config.userContentController.addUserScript(AutofillBridge.userScript)
        config.userContentController.add(autofillBridge, name: AutofillBridge.messageName)
        return config
    }

    func savePendingPassword() {
        guard let pending = pendingPasswordSave else { return }
        PasswordStore.shared.save(
            host: pending.host,
            username: pending.username,
            password: pending.password,
            profileID: currentProfileID
        )
        pendingPasswordSave = nil
    }

    func dismissPendingPassword() {
        pendingPasswordSave = nil
    }

    func newTab(url: URL? = nil, source: TabSource = .user) {
        guard let profile = currentProfile else { return }
        let tab = Tab(configuration: makeConfig(for: profile))
        tab.source = source
        tab.lastActivatedAt = Date()
        tabs.append(tab)
        currentTabID = tab.id
        if let url = url {
            tab.webView?.load(URLRequest(url: url))
            tab.urlString = url.absoluteString
        }
    }

    func closeTab(_ tab: Tab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let wasCurrent = currentTabID == tab.id
        tabs.remove(at: idx)
        if tabs.isEmpty {
            newTab()
        } else if wasCurrent {
            currentTabID = tabs[max(0, idx - 1)].id
        }
    }

    func closeCurrentTab() {
        if let tab = currentTab { closeTab(tab) }
    }

    func reloadCurrentTab() {
        guard let tab = currentTab else { return }
        ensureLive(tab)
        tab.webView?.reload()
    }

    func navigate(to text: String, source: TabSource = .user) {
        guard let tab = currentTab else { return }
        ensureLive(tab)
        let url = resolveURL(from: text)
        tab.source = source
        tab.webView?.load(URLRequest(url: url))
    }

    func focusAddressBar() {
        addressBarFocusToken &+= 1
    }

    private func resolveURL(from text: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return URL(string: "https://duckduckgo.com")!
        }
        let looksLikeURL = !trimmed.contains(" ") &&
            (trimmed.contains(".") || trimmed.hasPrefix("localhost") || trimmed.hasPrefix("http"))
        if looksLikeURL {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
               let url = URL(string: trimmed) {
                return url
            }
            if let url = URL(string: "https://" + trimmed) {
                return url
            }
        }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(q)")!
    }

    // MARK: - Bookmarks

    func addBookmark() {
        guard let tab = currentTab,
              let url = tab.webView?.url else { return }
        let b = Bookmark(title: tab.title.isEmpty ? url.host ?? url.absoluteString : tab.title,
                         url: url.absoluteString)
        if !bookmarks.contains(where: { $0.url == b.url }) {
            bookmarks.append(b)
            services.bookmarksManager.save(bookmarks, for: currentProfileID)
        }
    }

    var currentBookmark: Bookmark? {
        guard let url = currentTab?.webView?.url?.absoluteString else { return nil }
        return bookmarks.first { $0.url == url }
    }

    func toggleBookmark() {
        if let existing = currentBookmark {
            removeBookmark(existing)
        } else {
            addBookmark()
        }
    }

    func removeBookmark(_ b: Bookmark) {
        bookmarks.removeAll { $0.id == b.id }
        services.bookmarksManager.save(bookmarks, for: currentProfileID)
    }

    func editBookmark(_ bookmark: Bookmark, title: String, url: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedURL = normalizedURL(url)
        guard !trimmedURL.isEmpty else { return }
        bookmarks[idx].title = trimmedTitle.isEmpty ? trimmedURL : trimmedTitle
        bookmarks[idx].url = trimmedURL
        services.bookmarksManager.save(bookmarks, for: currentProfileID)
    }

    func addBookmarkManually(title: String, url: String) {
        let normalized = normalizedURL(url)
        guard !normalized.isEmpty else { return }
        guard !bookmarks.contains(where: { $0.url == normalized }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let displayTitle: String
        if !trimmedTitle.isEmpty {
            displayTitle = trimmedTitle
        } else if let host = URL(string: normalized)?.host {
            displayTitle = host
        } else {
            displayTitle = normalized
        }
        bookmarks.append(Bookmark(title: displayTitle, url: normalized))
        services.bookmarksManager.save(bookmarks, for: currentProfileID)
    }

    private func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    func openBookmark(_ b: Bookmark, inNewTab: Bool = false) {
        guard let url = URL(string: b.url) else { return }
        if inNewTab {
            newTab(url: url)
        } else {
            guard let tab = currentTab else {
                newTab(url: url)
                return
            }
            ensureLive(tab)
            tab.webView?.load(URLRequest(url: url))
        }
    }

    func reorderBookmark(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < bookmarks.count else { return }
        guard destIndex >= 0, destIndex <= bookmarks.count else { return }
        let item = bookmarks.remove(at: sourceIndex)
        let target = destIndex > sourceIndex ? destIndex - 1 : destIndex
        bookmarks.insert(item, at: target)
        services.bookmarksManager.save(bookmarks, for: currentProfileID)
    }

    // MARK: - Profiles (per-window switch + delegate-mutations to services)

    func switchProfile(to profile: Profile) {
        guard profile.id != currentProfileID else { return }
        currentProfileID = profile.id
        UserDefaults.standard.set(profile.id.uuidString, forKey: "currentProfileID")
        bookmarks = services.bookmarksManager.load(for: profile.id)
        tabs.removeAll()
        currentTabID = nil
        newTab()
    }

    // MARK: - Memory Saver hooks

    func ensureLive(_ tab: Tab) {
        guard tab.isDiscarded, let profile = currentProfile else { return }
        tab.reactivate(configuration: makeConfig(for: profile))
    }

    private func didChangeCurrentTab() {
        guard let id = currentTabID, let tab = tabs.first(where: { $0.id == id }) else { return }
        ensureLive(tab)
        tab.lastActivatedAt = Date()
    }

    var discardedTabCount: Int {
        tabs.reduce(0) { $0 + ($1.isDiscarded ? 1 : 0) }
    }
}
