import Foundation

final class ProfileManager {
    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Browser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }()

    func load() -> [Profile] {
        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data),
              !profiles.isEmpty else {
            return [Profile(name: "Osobno", colorIndex: 0)]
        }
        return profiles
    }

    func save(_ profiles: [Profile]) {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Profiles save failed: \(error.localizedDescription)")
        }
    }
}
