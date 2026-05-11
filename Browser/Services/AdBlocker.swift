import Foundation
import WebKit

@MainActor
final class AdBlocker {
    static let shared = AdBlocker()

    /// Bump this when BlockerRules.json materially changes so users pick up
    /// the new rules instead of the cached compiled list.
    private let identifier = "BrowserAdBlock-v2"

    func loadRules() async throws -> WKContentRuleList {
        await purgeOldVersions()
        if let existing = await fetch() {
            return existing
        }
        return try await compile()
    }

    /// Drop any previously-compiled rule lists from older versions so the
    /// WKContentRuleListStore doesn't keep them on disk forever.
    private func purgeOldVersions() async {
        guard let store = WKContentRuleListStore.default() else { return }
        let current = identifier
        let identifiers: [String] = await withCheckedContinuation { cont in
            store.getAvailableContentRuleListIdentifiers { ids in
                cont.resume(returning: ids ?? [])
            }
        }
        for id in identifiers where id != current && id.hasPrefix("BrowserAdBlock-") {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.removeContentRuleList(forIdentifier: id) { _ in cont.resume() }
            }
        }
    }

    private func fetch() async -> WKContentRuleList? {
        await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                cont.resume(returning: list)
            }
        }
    }

    private func compile() async throws -> WKContentRuleList {
        let json = BlockerRules.json
        return try await withCheckedThrowingContinuation { cont in
            WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { list, error in
                if let list = list {
                    cont.resume(returning: list)
                } else {
                    cont.resume(throwing: error ?? NSError(
                        domain: "AdBlocker",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown compile failure"]
                    ))
                }
            }
        }
    }
}
