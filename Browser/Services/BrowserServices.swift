import SwiftUI
import AppKit
import WebKit
import Combine

/// App-wide shared services: one MCP server, one profile registry, one ad blocker, one memory saver.
/// Each NSWindow has its own `BrowserState`. They're registered here so cross-cutting concerns
/// (Memory Saver iterating tabs, MCP retargeting on focus, profile updates broadcast) work properly.
@MainActor
final class BrowserServices: ObservableObject {
    static let shared = BrowserServices()

    // MARK: - Shared model state

    @Published var profiles: [Profile]
    @Published var adBlockerEnabled: Bool
    @Published var memorySaverEnabled: Bool
    @Published var discardThresholdMinutes: Int
    @Published var mcpStatus: MCPServer.Status = .stopped
    @Published private(set) var mcpToken: String

    let profileManager = ProfileManager()
    let bookmarksManager = BookmarksManager()
    private(set) var contentRuleList: WKContentRuleList?

    private var mcpServer: MCPServer?
    private var browserTools: BrowserTools?
    private var memorySaverTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Window registry

    /// Currently focused window's state — MCP tools target this.
    weak var activeState: BrowserState?
    private var registeredStates: [WeakStateRef] = []
    private var stateByWindow: [ObjectIdentifier: WeakStateRef] = [:]

    /// All currently registered (alive) per-window states.
    var allStates: [BrowserState] {
        registeredStates.compactMap { $0.value }
    }

    private init() {
        profiles = profileManager.load()
        adBlockerEnabled = UserDefaults.standard.object(forKey: "adBlockerEnabled") as? Bool ?? true
        memorySaverEnabled = UserDefaults.standard.object(forKey: "memorySaverEnabled") as? Bool ?? true
        discardThresholdMinutes = max(1, UserDefaults.standard.object(forKey: "discardThresholdMinutes") as? Int ?? 10)

        if let saved = UserDefaults.standard.string(forKey: "mcpToken"), !saved.isEmpty {
            mcpToken = saved
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: "mcpToken")
            mcpToken = fresh
        }

        Task { await loadAdBlocker() }
        startMCPServer()
        startMemorySaverTask()
        observeMemoryPressure()
        observeKeyWindow()
    }

    // MARK: - Window registration

    func register(state: BrowserState) {
        registeredStates.removeAll { $0.value == nil }
        if !registeredStates.contains(where: { $0.value === state }) {
            registeredStates.append(WeakStateRef(state))
        }
        if activeState == nil { activeState = state }
    }

    func unregister(state: BrowserState) {
        registeredStates.removeAll { $0.value == nil || $0.value === state }
        stateByWindow = stateByWindow.filter { _, ref in ref.value !== state && ref.value != nil }
        if activeState === state {
            activeState = registeredStates.compactMap(\.value).first
        }
    }

    func bind(window: NSWindow, to state: BrowserState) {
        stateByWindow[ObjectIdentifier(window)] = WeakStateRef(state)
        if window.isKeyWindow {
            activeState = state
        }
    }

    private func observeKeyWindow() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                if let state = self.stateByWindow[ObjectIdentifier(window)]?.value {
                    self.activeState = state
                }
            }
        }
    }

    // MARK: - Profile mutations (broadcast to all windows)

    func addProfile(name: String, colorIndex: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let profile = Profile(name: trimmed.isEmpty ? "New Profile" : trimmed, colorIndex: colorIndex)
        profiles.append(profile)
        profileManager.save(profiles)
    }

    func renameProfile(_ profile: Profile, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        profiles[idx].name = trimmed
        profileManager.save(profiles)
    }

    func setProfileColor(_ profile: Profile, colorIndex: Int) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx].colorIndex = colorIndex
        profileManager.save(profiles)
    }

    func deleteProfile(_ profile: Profile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        profileManager.save(profiles)
        let dataStoreUUID = profile.dataStoreUUID
        Task {
            try? await WKWebsiteDataStore.remove(forIdentifier: dataStoreUUID)
        }
        bookmarksManager.deleteAllData(for: profile.id)
        // Any window currently on the deleted profile switches to first remaining.
        for state in allStates where state.currentProfileID == profile.id {
            if let next = profiles.first {
                state.switchProfile(to: next)
            }
        }
    }

    // MARK: - Cross-profile bookmark access

    /// Bookmarks for a specific profile (loaded fresh from disk).
    func bookmarks(forProfile profileID: UUID) -> [Bookmark] {
        bookmarksManager.load(for: profileID)
    }

    struct BookmarkWithProfile: Identifiable, Hashable {
        let bookmark: Bookmark
        let profile: Profile
        var id: String { "\(profile.id)-\(bookmark.id)" }
    }

    /// All bookmarks across all profiles, each annotated with its source profile.
    func allBookmarksWithProfile() -> [BookmarkWithProfile] {
        profiles.flatMap { profile in
            bookmarksManager.load(for: profile.id).map {
                BookmarkWithProfile(bookmark: $0, profile: profile)
            }
        }
    }

    func removeBookmark(_ bookmark: Bookmark, fromProfile profileID: UUID) {
        var bks = bookmarksManager.load(for: profileID)
        bks.removeAll { $0.id == bookmark.id }
        bookmarksManager.save(bks, for: profileID)
        broadcastBookmarksChanged(profileID: profileID)
    }

    func editBookmark(_ bookmark: Bookmark, inProfile profileID: UUID, title: String, url: String) {
        var bks = bookmarksManager.load(for: profileID)
        guard let idx = bks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let normalized = normalizedURL(url)
        guard !normalized.isEmpty else { return }
        bks[idx].title = trimmedTitle.isEmpty ? normalized : trimmedTitle
        bks[idx].url = normalized
        bookmarksManager.save(bks, for: profileID)
        broadcastBookmarksChanged(profileID: profileID)
    }

    private func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    /// Refresh `bookmarks` arrays of any open windows currently on the affected profile.
    private func broadcastBookmarksChanged(profileID: UUID) {
        let updated = bookmarksManager.load(for: profileID)
        for state in allStates where state.currentProfileID == profileID {
            state.bookmarks = updated
        }
    }

    // MARK: - Ad blocker (toggle broadcasts to all tabs in all windows)

    func toggleAdBlocker() {
        adBlockerEnabled.toggle()
        UserDefaults.standard.set(adBlockerEnabled, forKey: "adBlockerEnabled")
        applyAdBlockerToAllTabs()
        for state in allStates {
            state.currentTab?.webView?.reload()
        }
    }

    func applyAdBlockerToAllTabs() {
        guard let rules = contentRuleList else { return }
        for state in allStates {
            for tab in state.tabs {
                guard let ucc = tab.webView?.configuration.userContentController else { continue }
                if adBlockerEnabled {
                    ucc.add(rules)
                } else {
                    ucc.remove(rules)
                }
            }
        }
    }

    private func loadAdBlocker() async {
        do {
            let rules = try await AdBlocker.shared.loadRules()
            self.contentRuleList = rules
            if adBlockerEnabled {
                for state in allStates {
                    for tab in state.tabs {
                        tab.webView?.configuration.userContentController.add(rules)
                    }
                }
            }
        } catch {
            NSLog("Ad blocker compile failed: \(error.localizedDescription)")
        }
    }

    // MARK: - MCP

    private func startMCPServer() {
        let tools = BrowserTools(services: self)
        browserTools = tools
        let server = MCPServer(token: mcpToken, tools: tools)
        server.onStatusChange = { [weak self] status in
            self?.mcpStatus = status
        }
        server.start()
        mcpServer = server
    }

    func regenerateMCPToken() {
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "mcpToken")
        mcpToken = fresh
        mcpServer?.stop()
        startMCPServer()
    }

    var mcpURL: String {
        if case .listening(let port) = mcpStatus {
            return "http://localhost:\(port)/mcp"
        }
        return "http://localhost:9876/mcp"
    }

    // MARK: - Memory Saver (iterates tabs across all windows)

    func toggleMemorySaver() {
        memorySaverEnabled.toggle()
        UserDefaults.standard.set(memorySaverEnabled, forKey: "memorySaverEnabled")
    }

    func setDiscardThreshold(minutes: Int) {
        let clamped = max(1, min(120, minutes))
        discardThresholdMinutes = clamped
        UserDefaults.standard.set(clamped, forKey: "discardThresholdMinutes")
    }

    private func startMemorySaverTask() {
        memorySaverTask?.cancel()
        memorySaverTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await MainActor.run {
                    self?.discardIdleTabsAcrossWindows()
                }
            }
        }
    }

    private func discardIdleTabsAcrossWindows() {
        guard memorySaverEnabled else { return }
        let now = Date()
        let threshold = TimeInterval(discardThresholdMinutes * 60)
        var discarded = 0
        for state in allStates {
            for tab in state.tabs where tab.id != state.currentTabID && !tab.isDiscarded {
                if now.timeIntervalSince(tab.lastActivatedAt) > threshold {
                    tab.discard()
                    discarded += 1
                }
            }
        }
        if discarded > 0 {
            NSLog("Memory Saver: discarded \(discarded) idle tab(s) across \(allStates.count) window(s)")
        }
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleMemoryPressure(level: source.mask)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure(level: DispatchSource.MemoryPressureEvent) {
        var discarded = 0
        for state in allStates {
            for tab in state.tabs where tab.id != state.currentTabID && !tab.isDiscarded {
                tab.discard()
                discarded += 1
            }
        }
        NSLog("Memory pressure (\(level.rawValue)): emergency-discarded \(discarded) tab(s)")
    }
}

private final class WeakStateRef {
    weak var value: BrowserState?
    init(_ value: BrowserState) { self.value = value }
}
