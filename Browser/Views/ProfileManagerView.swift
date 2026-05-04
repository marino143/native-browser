import SwiftUI

struct ProfileManagerView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newProfileName: String = ""
    @State private var newProfileColorIndex: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            addRow
        }
        .frame(width: 480, height: 520)
    }

    private var header: some View {
        HStack {
            Text("Profiles")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(services.profiles) { profile in
                    ProfileRow(profile: profile)
                }
            }
            .padding(12)
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Name (e.g. Klijent 1)", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                ColorSwatchPicker(colorIndex: $newProfileColorIndex)
                Button("Add") { add() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private func add() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        services.addProfile(name: name, colorIndex: newProfileColorIndex)
        newProfileName = ""
        newProfileColorIndex = (newProfileColorIndex + 1) % Profile.palette.count
    }
}

private struct ProfileRow: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    let profile: Profile
    @State private var isRenaming = false
    @State private var draftName: String = ""
    @State private var showDeleteConfirm = false

    var isCurrent: Bool { profile.id == state.currentProfileID }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(profile.color)
                Text(profile.initial)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            if isRenaming {
                TextField("", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .onSubmit(commitRename)
                Button("Save") { commitRename() }
                    .controlSize(.small)
                Button("Cancel") { isRenaming = false }
                    .controlSize(.small)
            } else {
                Text(profile.name)
                    .font(.system(size: 13))
                if isCurrent {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(profile.color.opacity(0.18)))
                        .foregroundStyle(profile.color)
                }
            }

            Spacer()

            if !isRenaming {
                ColorSwatchPicker(colorIndex: Binding(
                    get: { profile.colorIndex },
                    set: { services.setProfileColor(profile, colorIndex: $0) }
                ))
                Button(action: startRename) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Rename")

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .foregroundStyle(services.profiles.count > 1 ? Color.red : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(services.profiles.count <= 1)
                .help(services.profiles.count > 1 ? "Delete" : "Can't delete last profile")
                .confirmationDialog(
                    "Delete profile '\(profile.name)'?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        services.deleteProfile(profile)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Cookies, history, cache, and bookmarks for this profile will be permanently deleted.")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? profile.color.opacity(0.10) : Color.primary.opacity(0.04))
        )
    }

    private func startRename() {
        draftName = profile.name
        isRenaming = true
    }

    private func commitRename() {
        services.renameProfile(profile, to: draftName)
        isRenaming = false
    }
}

private struct ColorSwatchPicker: View {
    @Binding var colorIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Profile.palette.count, id: \.self) { idx in
                Circle()
                    .fill(Profile.palette[idx])
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(idx == colorIndex ? 0.7 : 0), lineWidth: 2)
                    )
                    .contentShape(Circle())
                    .onTapGesture { colorIndex = idx }
            }
        }
    }
}
