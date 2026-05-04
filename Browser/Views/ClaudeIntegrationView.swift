import SwiftUI

struct ClaudeIntegrationView: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var services = BrowserServices.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copiedCommand = false
    @State private var copiedToken = false
    @State private var copiedURL = false
    @State private var showRegenerateConfirm = false
    @State private var revealToken = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    setupCard
                    toolsCard
                    securityCard
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 600)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.49, blue: 0.20),
                            Color(red: 0.85, green: 0.30, blue: 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            Text("Claude Integration")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
            }
            Text("MCP server runs locally inside the browser. Claude clients connect over HTTP and call tools to control tabs, scrape pages, and run JavaScript on this browser.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Claude Code")
                .font(.system(size: 13, weight: .semibold))

            Text("Run this in your terminal:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(claudeMcpAddCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Button(action: copyCommand) {
                    Label(copiedCommand ? "Copied!" : "Copy command", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                }
                Spacer()
            }

            Divider().padding(.vertical, 6)

            Text("Or configure manually")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                Text("URL:").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                Text(services.mcpURL)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(action: copyURL) {
                    Image(systemName: copiedURL ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("Token:").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                Text(revealToken ? services.mcpToken : maskedToken)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Button(action: { revealToken.toggle() }) {
                    Image(systemName: revealToken ? "eye.slash" : "eye").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: copyToken) {
                    Image(systemName: copiedToken ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            Text("Header: `Authorization: Bearer <token>`")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available tools (\(BrowserTools.definitions.count))")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(BrowserTools.definitions.indices, id: \.self) { idx in
                    let def = BrowserTools.definitions[idx]
                    let name = def["name"] as? String ?? "?"
                    let desc = def["description"] as? String ?? ""
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text(desc)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Security")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("The server only accepts connections from localhost. Anyone on this Mac who has the token can fully control your browser (read pages, run JavaScript, click around). Don't paste the token into untrusted apps.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack {
                Button(role: .destructive) {
                    showRegenerateConfirm = true
                } label: {
                    Label("Regenerate token", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                Spacer()
            }
            .confirmationDialog(
                "Regenerate token?",
                isPresented: $showRegenerateConfirm,
                titleVisibility: .visible
            ) {
                Button("Regenerate", role: .destructive) {
                    services.regenerateMCPToken()
                    revealToken = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All currently connected Claude clients will need to be reconnected with the new token.")
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch services.mcpStatus {
        case .listening: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch services.mcpStatus {
        case .listening(let port): return "Listening on localhost:\(port)"
        case .stopped: return "Stopped"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var maskedToken: String {
        let t = services.mcpToken
        guard t.count > 8 else { return String(repeating: "•", count: t.count) }
        return String(t.prefix(4)) + String(repeating: "•", count: t.count - 8) + String(t.suffix(4))
    }

    private var claudeMcpAddCommand: String {
        "claude mcp add native-browser --transport http \(services.mcpURL) --header \"Authorization: Bearer \(services.mcpToken)\""
    }

    private func copyCommand() {
        copy(claudeMcpAddCommand)
        copiedCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCommand = false }
    }

    private func copyURL() {
        copy(services.mcpURL)
        copiedURL = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedURL = false }
    }

    private func copyToken() {
        copy(services.mcpToken)
        copiedToken = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedToken = false }
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
