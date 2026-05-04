import SwiftUI

struct BookmarksBarView: View {
    @EnvironmentObject var state: BrowserState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(state.bookmarks) { b in
                    BookmarkPill(bookmark: b)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 30)
        .background(Color.primary.opacity(0.03))
    }
}

private struct BookmarkPill: View {
    @EnvironmentObject var state: BrowserState
    let bookmark: Bookmark
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(bookmark.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hover ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(bookmark.url)
        .contextMenu {
            Button("Open") { open() }
            Button("Open in New Tab") { openNewTab() }
            Divider()
            Button("Remove", role: .destructive) {
                state.removeBookmark(bookmark)
            }
        }
    }

    private func open() {
        guard let url = URL(string: bookmark.url),
              let tab = state.currentTab else { return }
        state.ensureLive(tab)
        tab.webView?.load(URLRequest(url: url))
    }

    private func openNewTab() {
        guard let url = URL(string: bookmark.url) else { return }
        state.newTab(url: url)
    }
}
