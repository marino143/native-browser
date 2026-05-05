import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            AddressBarView()
            if state.showBookmarksBar && !state.bookmarks.isEmpty {
                BookmarksBarView()
                Divider().opacity(0.4)
            } else {
                Divider().opacity(0.4)
            }
            ZStack {
                if let tab = state.currentTab, tab.webView != nil {
                    WebView(tab: tab)
                        .id(tab.id)
                } else {
                    Color(NSColor.windowBackgroundColor)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            if let pending = state.pendingPasswordSave {
                PasswordSavePromptView(pending: pending)
                    .padding(.top, 32)  // sit below the tab bar / traffic-light row
                    .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.pendingPasswordSave)
        .sheet(isPresented: profileManagerBinding) {
            ProfileManagerView()
                .environmentObject(state)
        }
        .sheet(isPresented: claudeIntegrationBinding) {
            ClaudeIntegrationView()
                .environmentObject(state)
        }
        .sheet(isPresented: bookmarksManagerBinding) {
            BookmarksManagerView()
                .environmentObject(state)
        }
        .sheet(isPresented: passwordsManagerBinding) {
            PasswordsManagerView()
                .environmentObject(state)
        }
    }

    private var profileManagerBinding: Binding<Bool> {
        Binding(
            get: { state.showingProfileManager },
            set: { state.showingProfileManager = $0 }
        )
    }

    private var claudeIntegrationBinding: Binding<Bool> {
        Binding(
            get: { state.showingClaudeIntegration },
            set: { state.showingClaudeIntegration = $0 }
        )
    }

    private var bookmarksManagerBinding: Binding<Bool> {
        Binding(
            get: { state.showingBookmarksManager },
            set: { state.showingBookmarksManager = $0 }
        )
    }

    private var passwordsManagerBinding: Binding<Bool> {
        Binding(
            get: { state.showingPasswordsManager },
            set: { state.showingPasswordsManager = $0 }
        )
    }
}
