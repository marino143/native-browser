import SwiftUI

struct ProfileMenuView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Section("Switch Profile (this window)") {
                ForEach(services.profiles) { profile in
                    Button {
                        state.switchProfile(to: profile)
                    } label: {
                        if profile.id == state.currentProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
            Section("Open in New Window") {
                ForEach(services.profiles) { profile in
                    Button {
                        openWindow(id: "browser-window-profile", value: profile.id)
                    } label: {
                        Label(profile.name, systemImage: "macwindow.badge.plus")
                    }
                }
            }
            Divider()
            Button("Manage Profiles…") {
                state.showingProfileManager = true
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
        } label: {
            ProfileBadge(profile: state.currentProfile)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ProfileBadge: View {
    let profile: Profile?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(profile?.color ?? Color.gray)
                Text(profile?.initial ?? "?")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            Text(profile?.name ?? "—")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder((profile?.color ?? .gray).opacity(0.3), lineWidth: 1)
        )
    }
}
