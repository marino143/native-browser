import SwiftUI

struct PasswordsManagerView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @Environment(\.dismiss) private var dismiss

    /// nil = "All Profiles"; otherwise specific profile UUID.
    @State private var filter: UUID? = nil
    @State private var initialized = false
    @State private var searchText: String = ""
    @State private var newHost: String = ""
    @State private var newUsername: String = ""
    @State private var newPassword: String = ""

    fileprivate struct Entry: Identifiable, Hashable {
        let credential: PasswordCredential
        let profile: Profile
        var id: String { credential.id }
    }

    private var entries: [Entry] {
        let raw: [Entry]
        if let filterID = filter {
            guard let p = services.profiles.first(where: { $0.id == filterID }) else { return [] }
            raw = PasswordStore.shared.all(profileID: filterID).map { Entry(credential: $0, profile: p) }
        } else {
            raw = services.profiles.flatMap { p in
                PasswordStore.shared.all(profileID: p.id).map { Entry(credential: $0, profile: p) }
            }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return raw }
        return raw.filter {
            $0.credential.host.lowercased().contains(q) ||
            $0.credential.username.lowercased().contains(q) ||
            $0.profile.name.lowercased().contains(q)
        }
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
        .frame(width: 640, height: 620)
        .onAppear {
            if !initialized {
                filter = state.currentProfileID
                initialized = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.yellow)
            Text("Passwords")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { filter = nil } label: {
                    if filter == nil {
                        Label("All profiles", systemImage: "checkmark")
                    } else { Text("All profiles") }
                }
                Divider()
                ForEach(services.profiles) { profile in
                    Button { filter = profile.id } label: {
                        if filter == profile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else { Text(profile.name) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let id = filter, let p = services.profiles.first(where: { $0.id == id }) {
                        Circle().fill(p.color).frame(width: 10, height: 10)
                        Text(p.name)
                    } else {
                        Image(systemName: "square.grid.2x2").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("All profiles")
                    }
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search by site or username", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Text("\(entries.count)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            if entries.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(entries) { e in
                        PasswordRow(entry: e, showProfileBadge: filter == nil)
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No passwords yet" : "No matches for '\(searchText)'")
                .font(.system(size: 13, weight: .medium))
            if searchText.isEmpty {
                Text("Log in on a site and click 'Save' on the prompt, or add one manually below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
                    Text(p.name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                TextField("site.com", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                TextField("username", text: $newUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                SecureField("password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty
                              || newUsername.trimmingCharacters(in: .whitespaces).isEmpty
                              || newPassword.isEmpty
                              || addTargetProfile == nil)
            }
        }
        .padding(14)
    }

    private var addTargetProfile: Profile? {
        if let id = filter { return services.profiles.first(where: { $0.id == id }) }
        return state.currentProfile
    }

    private func add() {
        guard let target = addTargetProfile else { return }
        let host = newHost.trimmingCharacters(in: .whitespaces)
        let user = newUsername.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty, !newPassword.isEmpty else { return }
        PasswordStore.shared.save(host: host, username: user, password: newPassword, profileID: target.id)
        newHost = ""
        newUsername = ""
        newPassword = ""
    }
}

private struct PasswordRow: View {
    @EnvironmentObject var state: BrowserState
    let entry: PasswordsManagerView.Entry
    let showProfileBadge: Bool
    @State private var revealedPassword: String?
    @State private var copied: Bool = false
    @State private var showDeleteConfirm = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.05))
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.credential.host)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.credential.username)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let pw = revealedPassword {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(pw)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showProfileBadge {
                HStack(spacing: 4) {
                    Circle().fill(entry.profile.color).frame(width: 7, height: 7)
                    Text(entry.profile.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(entry.profile.color.opacity(0.10)))
            }

            if hover || revealedPassword != nil || copied {
                Button(action: toggleReveal) {
                    Image(systemName: revealedPassword == nil ? "eye" : "eye.slash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(revealedPassword == nil ? "Show password" : "Hide password")

                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Copy password")

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete from \(entry.profile.name)")
                .confirmationDialog(
                    "Delete password for '\(entry.credential.host)' (\(entry.profile.name))?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        PasswordStore.shared.remove(
                            host: entry.credential.host,
                            username: entry.credential.username,
                            profileID: entry.profile.id
                        )
                    }
                    Button("Cancel", role: .cancel) {}
                }
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

    private func toggleReveal() {
        if revealedPassword == nil {
            revealedPassword = PasswordStore.shared.revealPassword(
                host: entry.credential.host,
                username: entry.credential.username,
                profileID: entry.profile.id
            )
        } else {
            revealedPassword = nil
        }
    }

    private func copy() {
        guard let pw = PasswordStore.shared.revealPassword(
            host: entry.credential.host,
            username: entry.credential.username,
            profileID: entry.profile.id
        ) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(pw, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
