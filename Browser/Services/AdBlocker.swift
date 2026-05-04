import Foundation
import WebKit

@MainActor
final class AdBlocker {
    static let shared = AdBlocker()

    private let identifier = "BrowserAdBlock-v1"

    func loadRules() async throws -> WKContentRuleList {
        if let existing = await fetch() {
            return existing
        }
        return try await compile()
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
