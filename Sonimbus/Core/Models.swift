import Foundation

enum AudioQuality: String, CaseIterable, Identifiable {
    case standard
    case higher
    case exhigh
    case lossless
    case hires

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "标准"
        case .higher: "较高"
        case .exhigh: "极高"
        case .lossless: "无损"
        case .hires: "高解析度无损"
        }
    }

    var fallbackLevels: [AudioQuality] {
        switch self {
        case .hires: [.hires, .lossless, .exhigh, .higher, .standard]
        case .lossless: [.lossless, .exhigh, .higher, .standard]
        case .exhigh: [.exhigh, .higher, .standard]
        case .higher: [.higher, .standard]
        case .standard: [.standard]
        }
    }

    static func displayName(for level: String) -> String {
        if let quality = AudioQuality(rawValue: level.lowercased()) {
            return quality.displayName
        }
        switch level.lowercased() {
        case "jyeffect": return "高清环绕声"
        case "sky": return "沉浸环绕声"
        case "jymaster": return "超清母带"
        case "dolby": return "杜比全景声"
        default: return "高品质"
        }
    }
}

enum RepeatMode: String, CaseIterable, Codable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

enum PlaybackQueuePolicy {
    static func deduplicated(_ tracks: [Track]) -> [Track] {
        var seen = Set<Int>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    static func nextIndex(after currentIndex: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        guard count > 0 else { return nil }
        let candidate = max(0, currentIndex + 1)
        if candidate < count { return candidate }
        return repeatMode == .all ? 0 : nil
    }
}

enum PlaybackIdlePolicy {
    static func shouldDisableTimer(isPlaying: Bool, isPreparingPlayback: Bool) -> Bool {
        isPlaying || isPreparingPlayback
    }
}

enum SongUnlockPolicy {
    static func visibleTracks(_ tracks: [Track], isEnabled: Bool) -> [Track] {
        guard !isEnabled else { return tracks }
        return tracks.filter { !$0.isPlaybackUnavailable }
    }
}

enum MVQueuePolicy {
    static func deduplicated(_ videos: [MVSummary]) -> [MVSummary] {
        var seen = Set<Int>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    static func adjacentIndex(from currentIndex: Int, count: Int, offset: Int) -> Int? {
        guard count > 1, offset != 0 else { return nil }
        guard (0..<count).contains(currentIndex) else {
            return offset > 0 ? 0 : count - 1
        }
        let candidate = (currentIndex + offset) % count
        return candidate >= 0 ? candidate : candidate + count
    }
}

struct ArtistRef: Codable, Hashable, Identifiable {
    let id: Int
    let name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? "未知歌手"
    }
}

struct AlbumRef: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?

    init(id: Int, name: String, picUrl: String?) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? container.decode(String.self, forKey: .picUrl)
    }
}

struct Track: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let artists: [ArtistRef]
    let album: AlbumRef
    let durationMS: Int
    let alias: [String]
    let translatedNames: [String]
    let fee: Int
    let noCopyright: Bool
    let embeddedPrivilege: TrackPrivilege?

    var artistNames: String { artists.map(\.name).joined(separator: " / ") }
    var duration: TimeInterval { TimeInterval(durationMS) / 1_000 }
    var subtitle: String? { translatedNames.first ?? alias.first }
    var artworkURL: URL? { album.picUrl.flatMap { ArtworkURL.make($0, size: 800) } }
    var isCopyrightUnavailable: Bool {
        noCopyright || (embeddedPrivilege?.st ?? 0) < 0
    }
    var isPlaybackUnavailable: Bool {
        isCopyrightUnavailable || embeddedPrivilege?.pl == 0
    }

    func applyingPrivilege(_ privilege: TrackPrivilege?) -> Track {
        guard let privilege else { return self }
        return Track(
            id: id,
            name: name,
            artists: artists,
            album: album,
            durationMS: durationMS,
            alias: alias,
            translatedNames: translatedNames,
            fee: fee,
            noCopyright: noCopyright,
            embeddedPrivilege: privilege
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, ar, artists, al, album, dt, duration, alia, alias, tns, fee
        case noCopyrightRcmd, privilege
    }

    init(
        id: Int,
        name: String,
        artists: [ArtistRef],
        album: AlbumRef,
        durationMS: Int,
        alias: [String] = [],
        translatedNames: [String] = [],
        fee: Int = 0,
        noCopyright: Bool = false,
        embeddedPrivilege: TrackPrivilege? = nil
    ) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.durationMS = durationMS
        self.alias = alias
        self.translatedNames = translatedNames
        self.fee = fee
        self.noCopyright = noCopyright
        self.embeddedPrivilege = embeddedPrivilege
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        artists = (try? container.decode([ArtistRef].self, forKey: .ar))
            ?? (try? container.decode([ArtistRef].self, forKey: .artists))
            ?? []
        album = (try? container.decode(AlbumRef.self, forKey: .al))
            ?? (try? container.decode(AlbumRef.self, forKey: .album))
            ?? AlbumRef(id: 0, name: "", picUrl: nil)
        durationMS = (try? container.decode(Int.self, forKey: .dt))
            ?? (try? container.decode(Int.self, forKey: .duration))
            ?? 0
        alias = (try? container.decode([String].self, forKey: .alia))
            ?? (try? container.decode([String].self, forKey: .alias))
            ?? []
        translatedNames = (try? container.decode([String].self, forKey: .tns)) ?? []
        fee = (try? container.decode(Int.self, forKey: .fee)) ?? 0
        if !container.contains(.noCopyrightRcmd)
            || (try? container.decodeNil(forKey: .noCopyrightRcmd)) == true {
            noCopyright = false
        } else if let value = try? container.decode(Bool.self, forKey: .noCopyrightRcmd) {
            noCopyright = value
        } else {
            noCopyright = true
        }
        embeddedPrivilege = try? container.decode(TrackPrivilege.self, forKey: .privilege)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(artists, forKey: .ar)
        try container.encode(album, forKey: .al)
        try container.encode(durationMS, forKey: .dt)
        try container.encode(alias, forKey: .alia)
        try container.encode(translatedNames, forKey: .tns)
        try container.encode(fee, forKey: .fee)
        if noCopyright { try container.encode(true, forKey: .noCopyrightRcmd) }
        try container.encodeIfPresent(embeddedPrivilege, forKey: .privilege)
    }
}

struct TrackPrivilege: Codable, Hashable {
    let id: Int
    let fee: Int?
    let pl: Int?
    let st: Int?
    let cs: Bool?
    let maxbr: Int?
}

struct UserProfile: Decodable, Hashable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    let backgroundUrl: String?
    let signature: String?
    let vipType: Int

    private enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl, backgroundUrl, signature, vipType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(Int.self, forKey: .userId)
        nickname = (try? container.decode(String.self, forKey: .nickname)) ?? "网易云用户"
        avatarUrl = try? container.decode(String.self, forKey: .avatarUrl)
        backgroundUrl = try? container.decode(String.self, forKey: .backgroundUrl)
        signature = try? container.decode(String.self, forKey: .signature)
        vipType = (try? container.decode(Int.self, forKey: .vipType)) ?? 0
    }
}

struct VIPMembership: Decodable, Hashable {
    let redVipLevel: Int?
    let redVipAnnualCount: Int?

    private enum CodingKeys: String, CodingKey {
        case redVipLevel, redVipAnnualCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        redVipLevel = (try? container.decode(Int.self, forKey: .redVipLevel))
            ?? (try? container.decode(String.self, forKey: .redVipLevel)).flatMap(Int.init)
        redVipAnnualCount = (try? container.decode(Int.self, forKey: .redVipAnnualCount))
            ?? (try? container.decode(String.self, forKey: .redVipAnnualCount)).flatMap(Int.init)
    }
}

struct PlaylistCreator: Decodable, Hashable {
    let userId: Int
    let nickname: String?
    let avatarUrl: String?
}

struct PlaylistSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let trackCount: Int
    let playCount: Int
    let subscribedCount: Int
    let creator: PlaylistCreator?
    let specialType: Int

    var artworkURL: URL? { coverImgUrl.flatMap { ArtworkURL.make($0, size: 800) } }
    var isLikedSongsList: Bool { specialType == 5 }

    private enum CodingKeys: String, CodingKey {
        case id, name, coverImgUrl, picUrl, description, trackCount, playCount, playcount
        case subscribedCount, creator, specialType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "未命名歌单"
        coverImgUrl = (try? container.decode(String.self, forKey: .coverImgUrl))
            ?? (try? container.decode(String.self, forKey: .picUrl))
        description = try? container.decode(String.self, forKey: .description)
        trackCount = (try? container.decode(Int.self, forKey: .trackCount)) ?? 0
        let numericPlayCount = (try? container.decode(Double.self, forKey: .playCount))
            ?? (try? container.decode(Double.self, forKey: .playcount))
        let stringPlayCount = (try? container.decode(String.self, forKey: .playCount)).flatMap(Double.init)
            ?? (try? container.decode(String.self, forKey: .playcount)).flatMap(Double.init)
        playCount = Int(max(0, numericPlayCount ?? stringPlayCount ?? 0))
        subscribedCount = (try? container.decode(Int.self, forKey: .subscribedCount)) ?? 0
        creator = try? container.decode(PlaylistCreator.self, forKey: .creator)
        specialType = (try? container.decode(Int.self, forKey: .specialType)) ?? 0
    }

    func replacingTrackCount(with value: Int) -> PlaylistSummary {
        PlaylistSummary(
            id: id,
            name: name,
            coverImgUrl: coverImgUrl,
            description: description,
            trackCount: max(0, value),
            playCount: playCount,
            subscribedCount: subscribedCount,
            creator: creator,
            specialType: specialType
        )
    }

    private init(
        id: Int,
        name: String,
        coverImgUrl: String?,
        description: String?,
        trackCount: Int,
        playCount: Int,
        subscribedCount: Int,
        creator: PlaylistCreator?,
        specialType: Int
    ) {
        self.id = id
        self.name = name
        self.coverImgUrl = coverImgUrl
        self.description = description
        self.trackCount = trackCount
        self.playCount = playCount
        self.subscribedCount = subscribedCount
        self.creator = creator
        self.specialType = specialType
    }
}

struct PlaylistDetail: Decodable, Hashable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let trackCount: Int
    let playCount: Int
    let subscribedCount: Int
    let creator: PlaylistCreator?
    let tracks: [Track]
    let trackIds: [TrackIDRef]

    var artworkURL: URL? { coverImgUrl.flatMap { ArtworkURL.make($0, size: 800) } }
}

struct TrackIDRef: Codable, Hashable {
    let id: Int
}

struct AlbumSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: ArtistRef?
    let artists: [ArtistRef]?
    let publishTime: Int64?
    let size: Int?
    let description: String?

    var artistNames: String {
        if let artist { return artist.name }
        return artists?.map(\.name).joined(separator: " / ") ?? ""
    }
    var artworkURL: URL? { picUrl.flatMap { ArtworkURL.make($0, size: 800) } }

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, artist, artists, publishTime, size, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "未命名专辑"
        picUrl = try? container.decode(String.self, forKey: .picUrl)
        artist = try? container.decode(ArtistRef.self, forKey: .artist)
        artists = try? container.decode([ArtistRef].self, forKey: .artists)
        publishTime = (try? container.decode(Int64.self, forKey: .publishTime))
            ?? (try? container.decode(Int.self, forKey: .publishTime)).map(Int64.init)
        size = try? container.decode(Int.self, forKey: .size)
        description = try? container.decode(String.self, forKey: .description)
    }
}

struct AlbumDetailResponse: Decodable {
    let album: AlbumSummary
    let songs: [Track]
}

struct ArtistSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let img1v1Url: String?
    let alias: [String]
    let albumSize: Int?
    let musicSize: Int?
    let briefDesc: String?

    var artworkURL: URL? {
        (picUrl ?? img1v1Url).flatMap { ArtworkURL.make($0, size: 800) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, img1v1Url, alias, albumSize, musicSize, briefDesc
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "未知歌手"
        picUrl = try? container.decode(String.self, forKey: .picUrl)
        img1v1Url = try? container.decode(String.self, forKey: .img1v1Url)
        alias = (try? container.decode([String].self, forKey: .alias)) ?? []
        albumSize = try? container.decode(Int.self, forKey: .albumSize)
        musicSize = try? container.decode(Int.self, forKey: .musicSize)
        briefDesc = try? container.decode(String.self, forKey: .briefDesc)
    }
}

struct MVSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let cover: String?
    let artists: [ArtistRef]
    let durationMS: Int
    let playCount: Int
    let briefDesc: String?
    let description: String?
    let publishTime: String?
    let bitrates: [String: Int]

    var artistNames: String { artists.map(\.name).joined(separator: " / ") }
    var duration: TimeInterval { TimeInterval(durationMS) / 1_000 }
    var artworkURL: URL? { cover.flatMap { ArtworkURL.make($0, width: 960, height: 540) } }
    var availableResolutions: [Int] {
        bitrates.keys.compactMap(Int.init).sorted(by: >)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, cover, picUrl, imgurl, imgurl16v9, coverUrl
        case artists, artistId, artistName, duration, playCount
        case briefDesc, desc, publishTime, brs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "未命名 MV"
        cover = (try? container.decode(String.self, forKey: .cover))
            ?? (try? container.decode(String.self, forKey: .picUrl))
            ?? (try? container.decode(String.self, forKey: .imgurl16v9))
            ?? (try? container.decode(String.self, forKey: .imgurl))
            ?? (try? container.decode(String.self, forKey: .coverUrl))
        let decodedArtists = (try? container.decode([ArtistRef].self, forKey: .artists)) ?? []
        if decodedArtists.isEmpty,
           let artistName = try? container.decode(String.self, forKey: .artistName) {
            let artistID = (try? container.decode(Int.self, forKey: .artistId)) ?? 0
            artists = [ArtistRef(id: artistID, name: artistName)]
        } else {
            artists = decodedArtists
        }
        durationMS = (try? container.decode(Int.self, forKey: .duration)) ?? 0
        playCount = (try? container.decode(Int.self, forKey: .playCount))
            ?? (try? container.decode(String.self, forKey: .playCount)).flatMap(Int.init)
            ?? 0
        briefDesc = try? container.decode(String.self, forKey: .briefDesc)
        description = try? container.decode(String.self, forKey: .desc)
        publishTime = try? container.decode(String.self, forKey: .publishTime)
        bitrates = (try? container.decode([String: Int].self, forKey: .brs)) ?? [:]
    }
}

struct MVURLData: Decodable, Hashable {
    let id: Int
    let url: String?
    let resolution: Int?
    let size: Int64?
    let code: Int?
    let expiresIn: Int?

    var streamURL: URL? {
        guard let url, !url.isEmpty else { return nil }
        return URL(string: url.replacingOccurrences(of: "http://", with: "https://"))
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, size, code
        case resolution = "r"
        case expiresIn = "expi"
    }
}

struct ToplistItem: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let updateFrequency: String?
    let description: String?
    let playCount: Int?

    var artworkURL: URL? { coverImgUrl.flatMap { ArtworkURL.make($0, size: 800) } }
}

struct LyricResponse: Decodable {
    struct Body: Decodable { let lyric: String? }

    let lrc: Body?
    let tlyric: Body?
    let romalrc: Body?
    let lyricUser: LyricContributor?
    let transUser: LyricContributor?
}

struct LyricContributor: Decodable {
    let nickname: String?
}

struct SongURLData: Decodable, Hashable {
    let id: Int
    let url: String?
    let br: Int?
    let size: Int64?
    let type: String?
    let level: String?
    let time: Int?
    let freeTrialInfo: FreeTrialInfo?
}

struct FreeTrialInfo: Codable, Hashable {
    let start: Int?
    let end: Int?
}

struct PlayRecordItem: Decodable, Hashable {
    let playCount: Int
    let score: Int
    let song: Track

    private enum CodingKeys: String, CodingKey {
        case playCount, score, song
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playCount = (try? container.decode(Int.self, forKey: .playCount)) ?? 0
        score = (try? container.decode(Int.self, forKey: .score)) ?? 0
        song = try container.decode(Track.self, forKey: .song)
    }
}

struct CloudSongItem: Decodable, Hashable, Identifiable {
    let songId: Int
    let songName: String?
    let artist: String?
    let fileSize: Int64
    let simpleSong: Track?

    var id: Int { songId }
    var playableTrack: Track? {
        if let simpleSong { return simpleSong }
        guard songId > 0 else { return nil }
        let resolvedName = songName
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "云盘歌曲"
        let artistName = artist
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"
        return Track(
            id: songId,
            name: resolvedName,
            artists: [ArtistRef(id: 0, name: artistName)],
            album: AlbumRef(id: 0, name: "音乐云盘", picUrl: nil),
            durationMS: 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case songId, songName, artist, fileSize, simpleSong, privateCloud
    }

    private struct PrivateCloud: Decodable {
        let songId: Int?
        let song: String?
        let artist: String?
        let fileSize: Int64?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try? container.decode(PrivateCloud.self, forKey: .privateCloud)
        simpleSong = try? container.decode(Track.self, forKey: .simpleSong)
        songId = (try? container.decode(Int.self, forKey: .songId))
            ?? nested?.songId ?? simpleSong?.id ?? 0
        songName = (try? container.decode(String.self, forKey: .songName))
            ?? nested?.song ?? simpleSong?.name
        artist = (try? container.decode(String.self, forKey: .artist)) ?? nested?.artist
        fileSize = (try? container.decode(Int64.self, forKey: .fileSize))
            ?? nested?.fileSize ?? 0
    }
}

enum ArtworkURL {
    static func make(_ raw: String, size: Int) -> URL? {
        make(raw, width: size, height: size)
    }

    static func make(_ raw: String, width: Int, height: Int) -> URL? {
        guard !raw.isEmpty else { return nil }
        let secure = raw.replacingOccurrences(of: "http://", with: "https://")
        let separator = secure.contains("?") ? "&" : "?"
        return URL(string: "\(secure)\(separator)param=\(width)y\(height)")
    }
}

enum DisplayFormatter {
    static func playCount(_ count: Int) -> String {
        switch count {
        case 100_000_000...:
            return compactUnit(Double(count) / 100_000_000, suffix: "亿")
        case 10_000...:
            return compactUnit(Double(count) / 10_000, suffix: "万")
        default:
            return "\(count)"
        }
    }

    private static func compactUnit(_ value: Double, suffix: String) -> String {
        let formatted = String(format: "%.1f", value)
        let compact = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        return "\(compact) \(suffix)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func year(_ milliseconds: Int64?) -> String? {
        guard let milliseconds else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        return String(Calendar.current.component(.year, from: date))
    }
}
