import Foundation
import Security

/// Apple Keychain wrapper for site credentials.
///
/// Items are stored as `kSecClassInternetPassword` scoped per profile via
/// `kSecAttrService = "native-browser-<profileUUID>"`. With
/// `kSecAttrSynchronizable = true` items sync via iCloud Keychain across
/// the user's other Apple devices — but only when the app is signed with a
/// real Apple Developer Team ID. Locally, the keychain still works fine
/// under ad-hoc signing.
@MainActor
final class PasswordStore {
    static let shared = PasswordStore()
    private init() {}

    private static func service(for profileID: UUID) -> String {
        "native-browser-\(profileID.uuidString)"
    }

    private static func normalizedHost(_ raw: String) -> String {
        var h = raw.lowercased()
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h
    }

    // MARK: - Save / update

    @discardableResult
    func save(host: String, username: String, password: String, profileID: UUID) -> Bool {
        let normalizedHost = Self.normalizedHost(host)
        guard !username.isEmpty, !password.isEmpty,
              let passwordData = password.data(using: .utf8) else { return false }
        let svc = Self.service(for: profileID)

        // Try update first.
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: svc,
            kSecAttrServer as String: normalizedHost,
            kSecAttrAccount as String: username,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: passwordData,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else {
            NSLog("Keychain update failed (\(updateStatus)) for \(normalizedHost)/\(username)")
            return false
        }

        // Otherwise add a new item.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: svc,
            kSecAttrServer as String: normalizedHost,
            kSecAttrAccount as String: username,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "\(normalizedHost) — \(username)",
            kSecValueData as String: passwordData,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("Keychain add failed (\(addStatus)) for \(normalizedHost)/\(username)")
            return false
        }
        return true
    }

    // MARK: - Read

    func credentials(forHost host: String, profileID: UUID) -> [PasswordCredential] {
        all(profileID: profileID).filter { $0.host == Self.normalizedHost(host) }
    }

    func all(profileID: UUID) -> [PasswordCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: Self.service(for: profileID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let array = result as? [[String: Any]] else { return [] }
        return array.compactMap { item -> PasswordCredential? in
            guard let host = item[kSecAttrServer as String] as? String,
                  let username = item[kSecAttrAccount as String] as? String else { return nil }
            return PasswordCredential(host: host, username: username, profileID: profileID)
        }
        .sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    /// Returns the password as plaintext string, or nil if not found.
    /// (No biometric gate yet; v2 will add Touch ID on reveal/copy.)
    func revealPassword(host: String, username: String, profileID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: Self.service(for: profileID),
            kSecAttrServer as String: Self.normalizedHost(host),
            kSecAttrAccount as String: username,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    func remove(host: String, username: String, profileID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: Self.service(for: profileID),
            kSecAttrServer as String: Self.normalizedHost(host),
            kSecAttrAccount as String: username,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Wipe all credentials for a profile (used when profile is deleted).
    func deleteAll(profileID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: Self.service(for: profileID),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct PasswordCredential: Identifiable, Hashable {
    let host: String
    let username: String
    let profileID: UUID
    var id: String { "\(profileID.uuidString)-\(host)-\(username)" }
}
