import Foundation

/// The archive is stored in the Keychain; only profiles are exposed to the UI.
struct SavedAccountSession: Codable {
    let profile: UserProfile
    let cookies: [String: String]
}

struct SavedAccountArchive: Codable {
    private(set) var sessions: [SavedAccountSession] = []

    mutating func remember(profile: UserProfile, cookies: [String: String]) {
        guard let token = cookies["MUSIC_U"], !token.isEmpty else { return }
        let session = SavedAccountSession(profile: profile, cookies: cookies)
        if let index = sessions.firstIndex(where: { $0.profile.userId == profile.userId }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    mutating func remove(userID: Int) {
        sessions.removeAll { $0.profile.userId == userID }
    }

    func session(userID: Int) -> SavedAccountSession? {
        sessions.first { $0.profile.userId == userID }
    }
}

enum SavedAccountStorage {
    private static let key = "saved-accounts-v1"

    static func read() -> SavedAccountArchive {
        guard let data = AuthenticationCookieKeychain.read(account: key),
              let archive = try? JSONDecoder().decode(SavedAccountArchive.self, from: data) else {
            return SavedAccountArchive()
        }
        return archive
    }

    static func write(_ archive: SavedAccountArchive) throws {
        let data = try JSONEncoder().encode(archive)
        guard AuthenticationCookieKeychain.write(data, account: key) else {
            throw StorageError.unavailable
        }
    }

    private enum StorageError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法将账号安全保存到钥匙串，请稍后重试" }
    }
}
