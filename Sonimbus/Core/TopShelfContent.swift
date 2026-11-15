import Foundation
#if os(tvOS)
import OSLog
#endif

struct TopShelfLink: Equatable {
    enum Kind: String { case track, playlist }
    enum Action: String { case display, play }
    let kind: Kind
    let id: Int
    let accountID: Int
    let action: Action

    var url: URL {
        var components = URLComponents()
        components.scheme = "sonimbus"
        components.host = "top-shelf"
        components.path = "/\(kind.rawValue)/\(id)"
        components.queryItems = [
            URLQueryItem(name: "account", value: String(accountID)),
            URLQueryItem(name: "action", value: action.rawValue),
        ]
        return components.url!
    }

    init(kind: Kind, id: Int, accountID: Int, action: Action) {
        self.kind = kind
        self.id = id
        self.accountID = accountID
        self.action = action
    }

    init?(url: URL) {
        guard url.scheme == "sonimbus", url.host == "top-shelf",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.path.split(separator: "/")
        let query = components.queryItems ?? []
        guard path.count == 2, let kind = Kind(rawValue: String(path[0])),
              let id = Int(path[1]), id > 0,
              query.count == 2,
              let accountValue = query.first(where: { $0.name == "account" })?.value,
              let accountID = Int(accountValue), accountID > 0,
              let actionValue = query.first(where: { $0.name == "action" })?.value,
              let action = Action(rawValue: actionValue) else { return nil }
        self.init(kind: kind, id: id, accountID: accountID, action: action)
    }
}

/// Display metadata only. Authentication never leaves the application's Keychain.
struct TopShelfSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        let id: Int
        let title: String
        let imageURL: URL?
    }
    let accountID: Int
    let recentTracks: [Item]
    let playlists: [Item]
}

/// tvOS only permits shared file writes inside Library/Caches on physical devices.
/// The snapshot is rebuildable; the app republishes it if the system evicts it.
struct TopShelfSnapshotFile {
    let containerURL: URL

    private var fileURL: URL {
        containerURL.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
            .appendingPathComponent("top-shelf.json")
    }

    func read() throws -> TopShelfSnapshot? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(TopShelfSnapshot?.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func write(_ snapshot: TopShelfSnapshot?) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // An atomic empty value prevents the extension from reading the previous account.
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

#if os(tvOS)
enum TopShelfSnapshotStore {
    private static let log = Logger(subsystem: "com.svend.sonimbus", category: "TopShelf")

    private static var file: TopShelfSnapshotFile? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SonimbusAppGroup") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            log.error("Top Shelf shared container is unavailable")
            return nil
        }
        return TopShelfSnapshotFile(containerURL: container)
    }

    static func read() -> TopShelfSnapshot? {
        guard let file else { return nil }
        do {
            return try file.read()
        } catch {
            let error = error as NSError
            log.error("Top Shelf snapshot read failed: \(error.domain, privacy: .public) (\(error.code))")
            return nil
        }
    }

    @discardableResult
    static func write(_ snapshot: TopShelfSnapshot?) -> Bool {
        guard let file else { return false }
        do {
            try file.write(snapshot)
            return true
        } catch {
            let error = error as NSError
            log.error("Top Shelf snapshot write failed: \(error.domain, privacy: .public) (\(error.code))")
            return false
        }
    }
}
#endif
