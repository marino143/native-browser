import SwiftUI

struct PasswordSavePromptView: View {
    @EnvironmentObject var state: BrowserState
    let pending: PendingPasswordSave
    @State private var revealPassword = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save password for ") + Text(pending.host).bold() + Text("?")
                HStack(spacing: 6) {
                    Text(pending.username)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(revealPassword ? pending.password : String(repeating: "•", count: min(pending.password.count, 12)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { revealPassword.toggle() }) {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12))

            Spacer()

            Button("Not Now") { state.dismissPendingPassword() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Save") { state.savePendingPassword() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .overlay(
            Rectangle()
                .fill(Color.yellow.opacity(0.4))
                .frame(height: 2),
            alignment: .top
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
