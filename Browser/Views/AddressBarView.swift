import SwiftUI

struct AddressBarView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            navButtons
            urlField
            trailingButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onAppear { syncFromTab() }
        .onChange(of: state.currentTabID) { syncFromTab() }
        .onChange(of: state.currentTab?.urlString) { syncFromTab() }
        .onChange(of: state.addressBarFocusToken) {
            focused = true
        }
    }

    private var navButtons: some View {
        HStack(spacing: 2) {
            iconButton("chevron.left",
                       enabled: state.currentTab?.canGoBack ?? false) {
                state.currentTab?.webView?.goBack()
            }
            iconButton("chevron.right",
                       enabled: state.currentTab?.canGoForward ?? false) {
                state.currentTab?.webView?.goForward()
            }
            iconButton(state.currentTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                       enabled: true) {
                if state.currentTab?.isLoading == true {
                    state.currentTab?.webView?.stopLoading()
                } else {
                    state.reloadCurrentTab()
                }
            }
        }
    }

    private var urlField: some View {
        HStack(spacing: 6) {
            Image(systemName: secureIcon)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Search DuckDuckGo or enter address", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { state.navigate(to: text) }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        DispatchQueue.main.async {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                editor.selectAll(nil)
                            }
                        }
                    }
                }
            if state.currentTab?.isLoading == true {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14)
            }
            if hasSavedPassword {
                Menu {
                    ForEach(savedCredentials, id: \.id) { cred in
                        Button {
                            autofill(cred)
                        } label: {
                            Label(cred.username, systemImage: "person.crop.circle")
                        }
                    }
                    Divider()
                    Button("Manage Passwords…") { state.showingPasswordsManager = true }
                        .keyboardShortcut(";", modifiers: [.command, .option])
                } label: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Saved password — click to autofill")
            }
            Button(action: { state.toggleBookmark() }) {
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(isBookmarked ? Color.yellow : .secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(state.currentTab?.webView?.url == nil)
            .help(isBookmarked ? "Remove bookmark (Cmd+D)" : "Add bookmark (Cmd+D)")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    private var trailingButtons: some View {
        HStack(spacing: 4) {
            ProfileMenuView()
            Button(action: { services.toggleAdBlocker() }) {
                Image(systemName: services.adBlockerEnabled ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(services.adBlockerEnabled ? Color.green : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(services.adBlockerEnabled ? "Ad blocker: ON" : "Ad blocker: OFF")
            Button(action: { state.showingClaudeIntegration = true }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(claudeIconStyle)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Claude Integration (Cmd+Shift+C)")
            Button(action: { state.currentTab?.toggleMobileMode() }) {
                Image(systemName: state.currentTab?.mobileMode == true ? "iphone" : "macbook")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.currentTab?.mobileMode == true ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.currentTab?.mobileMode == true ? "Switch to desktop (Cmd+Shift+M)" : "Switch to mobile (Cmd+Shift+M)")
            Menu {
                Button(state.showBookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar") {
                    state.showBookmarksBar.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("All Bookmarks…") { state.showingBookmarksManager = true }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                if state.currentTab?.webView?.url != nil {
                    Button(state.currentBookmark != nil ? "Remove Bookmark" : "Bookmark This Page") {
                        state.toggleBookmark()
                    }
                    .keyboardShortcut("d", modifiers: .command)
                }
                if !state.bookmarks.isEmpty {
                    Divider()
                    Section(state.currentProfile.map { "Bookmarks · \($0.name)" } ?? "Bookmarks") {
                        ForEach(state.bookmarks.prefix(20)) { b in
                            Button {
                                state.openBookmark(b)
                            } label: {
                                Label(b.title.isEmpty ? b.url : b.title, systemImage: "globe")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: state.showBookmarksBar ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.showBookmarksBar ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Bookmarks menu")
        }
    }

    private func iconButton(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .opacity(enabled ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var secureIcon: String {
        guard let url = state.currentTab?.webView?.url else { return "magnifyingglass" }
        if url.scheme == "https" { return "lock.fill" }
        if url.scheme == "http" { return "exclamationmark.triangle" }
        return "magnifyingglass"
    }

    private var claudeIconStyle: AnyShapeStyle {
        if case .listening = services.mcpStatus {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.49, blue: 0.20),
                    Color(red: 0.85, green: 0.30, blue: 0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(Color.secondary)
    }

    private var isBookmarked: Bool {
        guard let url = state.currentTab?.webView?.url?.absoluteString else { return false }
        return state.bookmarks.contains { $0.url == url }
    }

    private var savedCredentials: [PasswordCredential] {
        guard let host = state.currentTab?.webView?.url?.host else { return [] }
        return PasswordStore.shared.credentials(forHost: host, profileID: state.currentProfileID)
    }

    private var hasSavedPassword: Bool { !savedCredentials.isEmpty }

    private func autofill(_ cred: PasswordCredential) {
        guard let webView = state.currentTab?.webView,
              let password = PasswordStore.shared.revealPassword(
                host: cred.host, username: cred.username, profileID: state.currentProfileID
              ) else { return }
        let escapedUser = cred.username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let js = "window.__nativeAutofillFill(\"\(escapedUser)\", \"\(escapedPass)\");"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func syncFromTab() {
        if !focused {
            text = state.currentTab?.urlString ?? ""
        }
    }
}
