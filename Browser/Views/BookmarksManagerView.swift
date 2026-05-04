import SwiftUI

struct BookmarksManagerView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @Environment(\.dismiss) private var dismiss

    /// nil = "All Profiles" filter; otherwise a specific profile UUID.
    @State private var filter: UUID? = nil
    @State private var initializedFilter = false
    @State private var searchText: String = ""
    @State private var newTitle: String = ""
    @State private var newURL: String = ""

    private var displayed: [BrowserServices.BookmarkWithProfile] {
        let all: [BrowserServices.BookmarkWithProfile]
        if let filterID = filter {
            let profile = services.profiles.first(where: { $0.id == filterID })
            if let profile = profile {
                all = services.bookmarks(forProfile: filterID).map {
                    BrowserServices.BookmarkWithProfile(bookmark: $0, profile: profile)
                }
            } else {
                all = []
            }
        } else {
            all = services.allBookmarksWithProfile()
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.bookmark.title.lowercased().contains(q) ||
            $0.bookmark.url.lowercased().contains(q)
        }
    }

    private var totalForCurrentFilter: Int {
        if let filterID = filter {
            return services.bookmarks(forProfile: filterID).count
        }
        return services.profiles.reduce(0) { $0 + services.bookmarks(forProfile: $1.id).count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider().opacity(0.4)
            list
            Divider()
            addRow
        }
        .frame(width: 620, height: 620)
        .onAppear {
            if !initializedFilter {
                filter = state.currentProfileID
                initializedFilter = true
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.yellow)
                Text("Bookmarks")
                    .font(.headline)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            // Profile filter
            Menu {
                Button {
                    filter = nil
                } label: {
                    if filter == nil {
                        Label("All profiles", systemImage: "checkmark")
                    } else {
                        Text("All profiles")
                    }
                }
                Divider()
                ForEach(services.profiles) { profile in
                    Button {
                        filter = profile.id
                    } label: {
                        if filter == profile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let filterID = filter, let p = services.profiles.first(where: { $0.id == filterID }) {
                        Circle().fill(p.color).frame(width: 10, height: 10)
                        Text(p.name)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("All profiles")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Search bookmarks", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )

            Text("\(displayed.count) of \(totalForCurrentFilter)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            if totalForCurrentFilter == 0 {
                emptyState
            } else if displayed.isEmpty {
                Text("No bookmarks match '\(searchText)'")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(40)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(displayed) { item in
                        BookmarkRow(
                            entry: item,
                            showProfileBadge: filter == nil
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No bookmarks")
                .font(.system(size: 13, weight: .medium))
            Text("Add one below, or visit a page and press Cmd+D / click ★ in the address bar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(50)
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Add to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let p = addTargetProfile {
                    Circle().fill(p.color).frame(width: 8, height: 8)
                    Text(p.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                TextField("Title (optional)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("URL or domain", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty || addTargetProfile == nil)
            }
        }
        .padding(14)
    }

    /// When filter == specific profile, add into that profile.
    /// When filter == "All", add into the current window's profile.
    private var addTargetProfile: Profile? {
        if let filterID = filter {
            return services.profiles.first(where: { $0.id == filterID })
        }
        return state.currentProfile
    }

    private func add() {
        let url = newURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, let target = addTargetProfile else { return }
        if target.id == state.currentProfileID {
            state.addBookmarkManually(title: newTitle, url: url)
        } else {
            // Add to a different profile via services
            let normalized = normalizedURL(url)
            let trimmedTitle = newTitle.trimmingCharacters(in: .whitespaces)
            let displayTitle: String
            if !trimmedTitle.isEmpty {
                displayTitle = trimmedTitle
            } else if let host = URL(string: normalized)?.host {
                displayTitle = host
            } else {
                displayTitle = normalized
            }
            var bks = services.bookmarks(forProfile: target.id)
            guard !bks.contains(where: { $0.url == normalized }) else { return }
            bks.append(Bookmark(title: displayTitle, url: normalized))
            services.bookmarksManager.save(bks, for: target.id)
        }
        newTitle = ""
        newURL = ""
    }

    private func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://" + trimmed
    }
}

private struct BookmarkRow: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    let entry: BrowserServices.BookmarkWithProfile
    let showProfileBadge: Bool

    @State private var isEditing = false
    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var hover = false
    @State private var showDeleteConfirm = false

    var bookmark: Bookmark { entry.bookmark }
    var profile: Profile { entry.profile }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.05))
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

            if isEditing {
                editingFields
            } else {
                displayFields
            }

            Spacer(minLength: 8)

            if !isEditing {
                if showProfileBadge {
                    profileBadge
                }
                actions
            } else {
                Button("Save") { commitEdit() }
                    .controlSize(.small)
                Button("Cancel") { isEditing = false }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hover ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        )
        .onHover { hover = $0 }
    }

    private var displayFields: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bookmark.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(bookmark.url)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
    }

    private var editingFields: some View {
        VStack(spacing: 4) {
            TextField("Title", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            TextField("URL", text: $editURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(commitEdit)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(profile.color).frame(width: 7, height: 7)
            Text(profile.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(profile.color.opacity(0.10))
        )
    }

    @ViewBuilder
    private var actions: some View {
        if hover {
            Button(action: open) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Open in current tab")

            Button(action: openNewTab) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Open in new tab")

            Button(action: startEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Edit")

            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete from \(profile.name)")
            .confirmationDialog(
                "Delete bookmark from '\(profile.name)'?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    services.removeBookmark(bookmark, fromProfile: profile.id)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func open() {
        guard let url = URL(string: bookmark.url) else { return }
        state.openBookmark(bookmark)
        _ = url
    }

    private func openNewTab() {
        state.openBookmark(bookmark, inNewTab: true)
    }

    private func startEdit() {
        editTitle = bookmark.title
        editURL = bookmark.url
        isEditing = true
    }

    private func commitEdit() {
        services.editBookmark(bookmark, inProfile: profile.id, title: editTitle, url: editURL)
        isEditing = false
    }
}
