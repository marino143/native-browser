import SwiftUI
import AppKit

@main
struct BrowserApp: App {
    @ObservedObject private var services = BrowserServices.shared

    var body: some Scene {
        // Default window (Cmd+N or app launch).
        WindowGroup(id: "browser-window") {
            BrowserWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { BrowserCommands() }

        // Profile-specific windows opened via openWindow(id: "browser-window-profile", value: profile.id)
        WindowGroup(id: "browser-window-profile", for: UUID.self) { $profileID in
            BrowserWindow(initialProfileID: profileID)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// One browser window: own state, own tabs, own profile context.
struct BrowserWindow: View {
    @StateObject private var state: BrowserState

    init(initialProfileID: UUID? = nil) {
        let services = BrowserServices.shared
        let profile = services.profiles.first(where: { $0.id == initialProfileID })
                  ?? services.profiles.first!
        _state = StateObject(wrappedValue: BrowserState(profile: profile))
    }

    var body: some View {
        ContentView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .frame(minWidth: 900, minHeight: 560)
            .focusedSceneValue(\.activeBrowserState, state)
            .background(WindowAccessor { window in
                BrowserServices.shared.bind(window: window, to: state)
            })
            .onDisappear {
                BrowserServices.shared.unregister(state: state)
            }
    }
}

/// Lets us reach the underlying NSWindow so we can map it to its BrowserState.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

// MARK: - Focused state plumbing (commands → focused window's state)

private struct ActiveBrowserStateKey: FocusedValueKey {
    typealias Value = BrowserState
}

extension FocusedValues {
    var activeBrowserState: BrowserState? {
        get { self[ActiveBrowserStateKey.self] }
        set { self[ActiveBrowserStateKey.self] = newValue }
    }
}

// MARK: - App-wide commands

struct BrowserCommands: Commands {
    @FocusedValue(\.activeBrowserState) private var state
    @ObservedObject private var services = BrowserServices.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { state?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(state == nil)
            Button("New Window") { openWindow(id: "browser-window") }
                .keyboardShortcut("n", modifiers: .command)
            Button("Close Tab") { state?.closeCurrentTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(state == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Reload") { state?.reloadCurrentTab() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state == nil)
            Button("Toggle Bookmarks Bar") { state?.showBookmarksBar.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(state == nil)
            Button(state?.currentBookmark != nil ? "Remove Bookmark" : "Bookmark This Page") {
                state?.toggleBookmark()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(state?.currentTab?.webView?.url == nil)
            Button("Bookmarks…") { state?.showingBookmarksManager = true }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(state == nil)
            Button(services.adBlockerEnabled ? "Disable Ad Blocker" : "Enable Ad Blocker") {
                services.toggleAdBlocker()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Focus Address Bar") { state?.focusAddressBar() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(state == nil)
            Button(state?.currentTab?.mobileMode == true ? "Switch to Desktop View" : "Switch to Mobile View") {
                state?.currentTab?.toggleMobileMode()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(state?.currentTab == nil)
            Button("Open Web Inspector") {
                if let tab = state?.currentTab, !tab.showWebInspector() {
                    let alert = NSAlert()
                    alert.messageText = "Web Inspector unavailable"
                    alert.informativeText = "Inline inspector couldn't open. Right-click anywhere on the page → Inspect Element, or open Safari → Develop menu → Native → \(tab.title)."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(state?.currentTab == nil)
            Divider()
            Button(services.memorySaverEnabled
                   ? "Disable Memory Saver"
                   : "Enable Memory Saver (\(services.discardThresholdMinutes) min idle)") {
                services.toggleMemorySaver()
            }
            Menu("Discard idle tabs after") {
                ForEach([1, 5, 10, 15, 30, 60], id: \.self) { mins in
                    Button {
                        services.setDiscardThreshold(minutes: mins)
                    } label: {
                        if services.discardThresholdMinutes == mins {
                            Label("\(mins) min", systemImage: "checkmark")
                        } else {
                            Text("\(mins) min")
                        }
                    }
                }
            }
            Divider()
            Button("Claude Integration…") { state?.showingClaudeIntegration = true }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(state == nil)
            Button("Manage Profiles…") { state?.showingProfileManager = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(state == nil)
            Menu("Open Profile in New Window") {
                ForEach(services.profiles) { profile in
                    Button {
                        openWindow(id: "browser-window-profile", value: profile.id)
                    } label: {
                        Label(profile.name, systemImage: "macwindow.badge.plus")
                    }
                }
            }
        }
    }
}
