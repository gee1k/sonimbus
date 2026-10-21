import Foundation
import Observation

@MainActor
@Observable
final class ContentCache<Key: Hashable, Value> {
    typealias Loader = (Key) async throws -> Value

    private struct Entry {
        let value: Value
        let loadedAt: Date
    }

    @ObservationIgnored private let lifetime: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: [Key: Task<Value, Error>] = [:]
    private var entries: [Key: Entry] = [:]
    private var generation = 0

    init(
        lifetime: TimeInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.lifetime = lifetime
        self.now = now
    }

    func value(for key: Key) -> Value? {
        guard let entry = entries[key], isFresh(entry, at: now()) else { return nil }
        return entry.value
    }

    func latest(where predicate: (Key) -> Bool) -> Value? {
        let currentDate = now()
        return entries
            .filter { key, entry in
                predicate(key) && isFresh(entry, at: currentDate)
            }
            .max { $0.value.loadedAt < $1.value.loadedAt }?
            .value.value
    }

    func load(for key: Key, loader: @escaping Loader) async throws -> Value {
        if let cached = value(for: key) { return cached }
        return try await request(for: key, loader: loader)
    }

    func refresh(for key: Key, loader: @escaping Loader) async throws -> Value {
        try await request(for: key, loader: loader)
    }

    func removeAll() {
        generation &+= 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        entries.removeAll()
    }

    private func request(for key: Key, loader: @escaping Loader) async throws -> Value {
        if let existing = inFlight[key] {
            let requestGeneration = generation
            let value = try await existing.value
            guard generation == requestGeneration else { throw CancellationError() }
            return value
        }

        removeExpiredEntries(at: now())
        let requestGeneration = generation
        let task = Task { try await loader(key) }
        inFlight[key] = task
        defer { if generation == requestGeneration { inFlight[key] = nil } }

        let value = try await task.value
        guard generation == requestGeneration else { throw CancellationError() }
        entries[key] = Entry(value: value, loadedAt: now())
        return value
    }

    private func isFresh(_ entry: Entry, at date: Date) -> Bool {
        date.timeIntervalSince(entry.loadedAt) < lifetime
    }

    private func removeExpiredEntries(at date: Date) {
        entries = entries.filter { isFresh($0.value, at: date) }
    }
}

@MainActor
@Observable
final class ContentStore {
    struct PlaylistKey: Hashable {
        let playlistID: Int
        let userID: Int?
        let revision: Int
    }

    struct DailySongsKey: Hashable {
        let userID: Int
        let day: Int

        static func current(
            userID: Int,
            now: Date = .now,
            calendar: Calendar = .current
        ) -> Self {
            Self(
                userID: userID,
                day: Int(calendar.startOfDay(for: now).timeIntervalSince1970)
            )
        }
    }

    struct PlayRecordsKey: Hashable {
        let userID: Int
        let weekOnly: Bool
    }

    struct ArtistDetailContent {
        let response: NeteaseAPI.ArtistResponse
        let albums: [AlbumSummary]
        let mvs: [MVSummary]
        let similarArtists: [ArtistSummary]
    }

    struct MVDetailContent {
        let detail: MVSummary
        let relatedMVs: [MVSummary]
    }

    let playlists = ContentCache<PlaylistKey, PlaylistDetail>(lifetime: 5 * 60)
    let albums = ContentCache<Int, AlbumDetailResponse>(lifetime: 10 * 60)
    let artists = ContentCache<Int, ArtistDetailContent>(lifetime: 10 * 60)
    let mvs = ContentCache<Int, MVDetailContent>(lifetime: 10 * 60)
    let dailySongs = ContentCache<DailySongsKey, [Track]>(lifetime: 24 * 60 * 60)
    let playRecords = ContentCache<PlayRecordsKey, [PlayRecordItem]>(lifetime: 2 * 60)
    let cloudMusic = ContentCache<Int, NeteaseAPI.CloudResponse>(lifetime: 2 * 60)

    func removeAll() {
        playlists.removeAll()
        albums.removeAll()
        artists.removeAll()
        mvs.removeAll()
        dailySongs.removeAll()
        playRecords.removeAll()
        cloudMusic.removeAll()
    }
}
