import Foundation

final class BookmarksManager {
    private static let baseDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Browser", isDirectory: true)
    }()

    private func url(for profileID: UUID) -> URL {
        let dir = Self.baseDir
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }

    func load(for profileID: UUID) -> [Bookmark] {
        let path = url(for: profileID)
        guard let data = try? Data(contentsOf: path) else { return [] }
        return (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    func save(_ bookmarks: [Bookmark], for profileID: UUID) {
        let path = url(for: profileID)
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: path, options: .atomic)
        } catch {
            NSLog("Bookmarks save failed: \(error.localizedDescription)")
        }
    }

    func deleteAllData(for profileID: UUID) {
        let dir = Self.baseDir
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Migrate legacy single-profile bookmarks.json into a profile folder.
    /// Runs once: if legacy file exists and target profile has no bookmarks file yet, copy it across.
    func migrateLegacyIfNeeded(toProfile profileID: UUID) {
        let legacy = Self.baseDir.appendingPathComponent("bookmarks.json")
        let target = url(for: profileID)
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try? FileManager.default.copyItem(at: legacy, to: target)
    }
}
