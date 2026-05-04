import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var state: BrowserState

    private var userTabs: [Tab] { state.tabs.filter { $0.source == .user } }
    private var agentTabs: [Tab] { state.tabs.filter { $0.source == .agent } }

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(userTabs) { tab in
                        TabItem(tab: tab)
                    }
                    if !userTabs.isEmpty && !agentTabs.isEmpty {
                        AgentDivider()
                    }
                    ForEach(agentTabs) { tab in
                        TabItem(tab: tab)
                    }
                }
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.18), value: state.tabs.map(\.id))
                .animation(.easeInOut(duration: 0.18), value: state.tabs.map(\.source))
            }
            Button(action: { state.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(.ultraThinMaterial)
    }
}

private struct AgentDivider: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.49, blue: 0.20),
                        Color(red: 0.85, green: 0.30, blue: 0.45)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 2, height: 18)
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                Text("CLAUDE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.49, blue: 0.20),
                    Color(red: 0.85, green: 0.30, blue: 0.45)
                ],
                startPoint: .leading, endPoint: .trailing
            ))
        }
        .padding(.horizontal, 4)
    }
}

struct TabItem: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var tab: Tab
    @State private var hover = false
    @State private var closeHover = false

    var isActive: Bool { state.currentTabID == tab.id }
    var isAgent: Bool { tab.source == .agent }

    var body: some View {
        HStack(spacing: 6) {
            leadingIcon
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(tab.isDiscarded ? 0.55 : 1.0)
                .italic(tab.isDiscarded)
            Spacer(minLength: 0)
            if hover || isActive {
                Button(action: { state.closeTab(tab) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 14, height: 14)
                        .background(
                            Circle().fill(closeHover ? Color.primary.opacity(0.18) : .clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHover = $0 }
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 200, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: isAgent ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { state.currentTabID = tab.id }
        .help(helpText)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if tab.isDiscarded {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: 12, height: 12)
        } else if tab.isLoading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
                .frame(width: 12, height: 12)
        } else if isAgent {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.49, blue: 0.20),
                        Color(red: 0.85, green: 0.30, blue: 0.45)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
        }
    }

    private var backgroundFill: Color {
        if isActive {
            return isAgent
                ? Color(red: 0.93, green: 0.49, blue: 0.20).opacity(0.18)
                : Color.primary.opacity(0.14)
        }
        if hover {
            return isAgent
                ? Color(red: 0.93, green: 0.49, blue: 0.20).opacity(0.10)
                : Color.primary.opacity(0.06)
        }
        return isAgent
            ? Color(red: 0.93, green: 0.49, blue: 0.20).opacity(0.05)
            : Color.clear
    }

    private var borderColor: Color {
        guard isAgent else { return .clear }
        return Color(red: 0.93, green: 0.49, blue: 0.20).opacity(isActive ? 0.4 : 0.2)
    }

    private var helpText: String {
        if tab.isDiscarded {
            return "Asleep — click to reload\n\(tab.urlString)"
        }
        if isAgent {
            return "Controlled by Claude — type in URL bar to reclaim\n\(tab.urlString)"
        }
        return tab.urlString
    }
}
