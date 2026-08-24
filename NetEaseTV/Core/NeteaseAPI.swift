import Foundation

enum NeteaseAPI {
    private static var client: NeteaseClient { .shared }

    private static func weapi<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        _ payload: [String: Any] = [:]
    ) async throws -> T {
        let data = try await client.weapi(path, payload)
        return try client.decoded(type, from: data)
    }

    private static func eapi<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        _ payload: [String: Any] = [:]
    ) async throws -> T {
        let data = try await client.eapi(path, payload)
        return try client.decoded(type, from: data)
    }

    struct CodeOnly: Decodable { let code: Int }

    // MARK: Authentication

    private struct QRKeyResponse: Decodable {
        let unikey: String
    }

    struct QRCheckResponse: Decodable {
        let code: Int
        let message: String?
        let nickname: String?
        let avatarUrl: String?
    }

    static func qrKey() async throws -> String {
        try await weapi(QRKeyResponse.self, "/login/qrcode/unikey", ["type": 1]).unikey
    }

    static func qrLoginURL(key: String) -> String {
        "https://music.163.com/login?codekey=\(key)"
    }

    static func qrCheck(key: String) async throws -> QRCheckResponse {
        let data = try await client.weapi("/login/qrcode/client/login", ["key": key, "type": 1])
        return try JSONDecoder().decode(QRCheckResponse.self, from: data)
    }

    static func logout() async {
        _ = try? await client.weapi("/logout", requestTimeout: 2)
    }

    static func refreshLogin() async throws {
        _ = try await client.weapi("/login/token/refresh")
    }

    private struct AccountResponse: Decodable {
        let profile: UserProfile?
    }

    static func account() async throws -> UserProfile? {
        try await weapi(AccountResponse.self, "/w/nuser/account/get").profile
    }

    private struct VIPInfoResponse: Decodable {
        let data: VIPMembership?
    }

    static func vipInfo(userID: Int) async throws -> VIPMembership? {
        try await weapi(
            VIPInfoResponse.self,
            "/music-vip-membership/front/vip/info",
            ["userId": userID]
        ).data
    }

    // MARK: Home and discovery

    private struct PersonalizedResponse: Decodable {
        let result: [PlaylistSummary]
    }

    static func personalizedPlaylists(limit: Int = 24) async throws -> [PlaylistSummary] {
        try await weapi(
            PersonalizedResponse.self,
            "/personalized/playlist",
            ["limit": limit, "total": true, "n": 1_000]
        ).result
    }

    private struct RecommendResourceResponse: Decodable {
        let recommend: [PlaylistSummary]
    }

    static func recommendedPlaylists() async throws -> [PlaylistSummary] {
        try await weapi(RecommendResourceResponse.self, "/v1/discovery/recommend/resource").recommend
    }

    private struct RecommendSongsResponse: Decodable {
        struct Body: Decodable { let dailySongs: [Track]? }
        let data: Body?
    }

    static func dailySongs() async throws -> [Track] {
        try await weapi(RecommendSongsResponse.self, "/v3/discovery/recommend/songs")
            .data?.dailySongs ?? []
    }

    private struct NewSongResponse: Decodable {
        struct Item: Decodable { let song: Track? }
        let result: [Item]
    }

    static func newSongs(limit: Int = 16) async throws -> [Track] {
        try await weapi(
            NewSongResponse.self,
            "/personalized/newsong",
            ["type": "recommend", "limit": limit, "areaId": 0]
        ).result.compactMap(\.song)
    }

    struct TopPlaylistResponse: Decodable {
        let playlists: [PlaylistSummary]
        let more: Bool?
    }

    static func topPlaylists(
        category: String = "全部",
        order: String = "hot",
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> TopPlaylistResponse {
        try await weapi(
            TopPlaylistResponse.self,
            "/playlist/list",
            ["cat": category, "order": order, "limit": limit, "offset": offset, "total": true]
        )
    }

    struct PlaylistCategory: Decodable, Hashable, Identifiable {
        let name: String
        let category: Int
        var id: String { name }
    }

    private struct PlaylistCatalogueResponse: Decodable {
        let sub: [PlaylistCategory]
    }

    static func playlistCategories() async throws -> [PlaylistCategory] {
        try await weapi(PlaylistCatalogueResponse.self, "/playlist/catalogue").sub
    }

    private struct ToplistResponse: Decodable { let list: [ToplistItem] }

    static func toplists() async throws -> [ToplistItem] {
        try await eapi(ToplistResponse.self, "/toplist").list
    }

    private struct NewAlbumsResponse: Decodable { let albums: [AlbumSummary] }

    static func newAlbums(limit: Int = 24) async throws -> [AlbumSummary] {
        try await weapi(
            NewAlbumsResponse.self,
            "/album/new",
            ["area": "ALL", "limit": limit, "offset": 0, "total": true]
        ).albums
    }

    private struct TopArtistsResponse: Decodable {
        struct Body: Decodable { let artists: [ArtistSummary] }
        let list: Body
    }

    static func topArtists(limit: Int = 24) async throws -> [ArtistSummary] {
        try await weapi(
            TopArtistsResponse.self,
            "/toplist/artist",
            ["type": 1, "limit": limit, "offset": 0, "total": true]
        ).list.artists
    }

    struct PlaylistCreateResponse: Decodable {
        let code: Int
        let id: Int?
    }

    @discardableResult
    static func createPlaylist(name: String, isPrivate: Bool) async throws -> Int? {
        try await weapi(
            PlaylistCreateResponse.self,
            "/playlist/create",
            ["name": name, "privacy": isPrivate ? 10 : 0, "type": "NORMAL"]
        ).id
    }

    static func deletePlaylist(id: Int) async throws {
        _ = try await weapi(CodeOnly.self, "/playlist/remove", ["ids": "[\(id)]"])
    }

    static func updatePlaylistName(id: Int, name: String) async throws {
        _ = try await weapi(CodeOnly.self, "/playlist/update/name", ["id": id, "name": name])
    }

    static func updatePlaylistDescription(id: Int, description: String) async throws {
        _ = try await weapi(CodeOnly.self, "/playlist/desc/update", ["id": id, "desc": description])
    }

    static func updatePlaylistCover(id: Int, imageID: String) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/playlist/cover/update",
            ["id": id, "coverImgId": imageID]
        )
    }

    static func playlistTracks(operation: String, playlistID: Int, trackIDs: [Int]) async throws {
        guard !trackIDs.isEmpty else { return }
        let ids = "[" + trackIDs.map(String.init).joined(separator: ",") + "]"
        let payload: [String: Any] = [
            "op": operation,
            "pid": playlistID,
            "trackIds": ids,
            "imme": "true",
        ]
        let data = try await client.weapi("/playlist/manipulate/tracks", payload)

        if operation == "add",
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["code"] as? Int == 512 {
            let doubled = "[" + (trackIDs + trackIDs).map(String.init).joined(separator: ",") + "]"
            let retry = try await client.weapi(
                "/playlist/manipulate/tracks",
                ["op": operation, "pid": playlistID, "trackIds": doubled, "imme": "true"]
            )
            _ = try client.decoded(CodeOnly.self, from: retry)
            return
        }

        _ = try client.decoded(CodeOnly.self, from: data)
    }

    // MARK: Details

    struct PlaylistDetailResponse: Decodable {
        let playlist: PlaylistDetail
        let privileges: [TrackPrivilege]?
    }

    static func playlist(id: Int) async throws -> PlaylistDetailResponse {
        let response = try await weapi(
            PlaylistDetailResponse.self,
            "/v6/playlist/detail",
            ["id": id, "n": 100_000, "s": 8]
        )
        guard response.playlist.tracks.count < response.playlist.trackIds.count else {
            return response
        }
        let known = Set(response.playlist.tracks.map(\.id))
        var missingIDs = Set<Int>()
        let missing = response.playlist.trackIds
            .map(\.id)
            .filter { !known.contains($0) && missingIDs.insert($0).inserted }
        guard !missing.isEmpty else { return response }
        guard let fetched = try? await songDetails(ids: missing) else { return response }
        let order = response.playlist.trackIds.enumerated().reduce(into: [Int: Int]()) { result, item in
            if result[item.element.id] == nil { result[item.element.id] = item.offset }
        }
        let combined = (response.playlist.tracks + fetched.songs)
            .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        let detail = PlaylistDetail(
            id: response.playlist.id,
            name: response.playlist.name,
            coverImgUrl: response.playlist.coverImgUrl,
            description: response.playlist.description,
            trackCount: response.playlist.trackCount,
            playCount: response.playlist.playCount,
            subscribedCount: response.playlist.subscribedCount,
            creator: response.playlist.creator,
            tracks: combined,
            trackIds: response.playlist.trackIds
        )
        return PlaylistDetailResponse(playlist: detail, privileges: response.privileges)
    }

    struct SongDetailResponse: Decodable {
        let songs: [Track]
        let privileges: [TrackPrivilege]?
    }

    static func songDetails(ids: [Int]) async throws -> SongDetailResponse {
        guard !ids.isEmpty else { return SongDetailResponse(songs: [], privileges: []) }
        var songs: [Track] = []
        var privileges: [TrackPrivilege] = []
        for chunk in ids.chunked(size: 500) {
            let objects = "[" + chunk.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
            let response = try await weapi(SongDetailResponse.self, "/v3/song/detail", ["c": objects])
            songs.append(contentsOf: response.songs)
            privileges.append(contentsOf: response.privileges ?? [])
        }
        return SongDetailResponse(songs: songs, privileges: privileges)
    }

    static func album(id: Int) async throws -> AlbumDetailResponse {
        try await weapi(AlbumDetailResponse.self, "/v1/album/\(id)")
    }

    struct ArtistResponse: Decodable {
        let artist: ArtistSummary
        let hotSongs: [Track]
    }

    struct ArtistAlbumsResponse: Decodable {
        let artist: ArtistSummary?
        let hotAlbums: [AlbumSummary]
        let more: Bool?
    }

    static func artist(id: Int) async throws -> ArtistResponse {
        try await weapi(ArtistResponse.self, "/v1/artist/\(id)")
    }

    static func artistAlbums(id: Int, limit: Int = 100, offset: Int = 0) async throws -> ArtistAlbumsResponse {
        try await weapi(
            ArtistAlbumsResponse.self,
            "/artist/albums/\(id)",
            ["limit": limit, "offset": offset, "total": true]
        )
    }

    private struct SimilarArtistsResponse: Decodable { let artists: [ArtistSummary] }

    static func similarArtists(id: Int) async throws -> [ArtistSummary] {
        try await weapi(SimilarArtistsResponse.self, "/discovery/simiArtist", ["artistid": id]).artists
    }

    // MARK: Playback

    private struct SongURLResponse: Decodable { let data: [SongURLData] }

    static func songURLs(ids: [Int], level: String = "lossless") async throws -> [SongURLData] {
        let ids = "[" + ids.map(String.init).joined(separator: ",") + "]"
        return try await eapi(
            SongURLResponse.self,
            "/song/enhance/player/url/v1",
            ["ids": ids, "level": level, "encodeType": "flac"]
        ).data
    }

    static func lyrics(id: Int) async throws -> LyricResponse {
        try await weapi(
            LyricResponse.self,
            "/song/lyric",
            ["id": id, "lv": -1, "kv": -1, "tv": -1, "rv": -1]
        )
    }

    private struct FMResponse: Decodable { let data: [Track]? }

    static func personalFM() async throws -> [Track] {
        try await weapi(FMResponse.self, "/v1/radio/get").data ?? []
    }

    private struct IntelligenceResponse: Decodable {
        struct Item: Decodable {
            let songInfo: Track?
            let id: Int?
        }

        let data: [Item]?
    }

    static func intelligenceList(songID: Int, playlistID: Int) async throws -> [Track] {
        try await weapi(
            IntelligenceResponse.self,
            "/playmode/intelligence/list",
            [
                "songId": songID,
                "type": "fromPlayOne",
                "playlistId": playlistID,
                "startMusicId": songID,
                "count": 1,
            ]
        ).data?.compactMap(\.songInfo) ?? []
    }

    // MARK: Search

    enum SearchType: Int, CaseIterable {
        case songs = 1
        case albums = 10
        case artists = 100
        case playlists = 1_000
    }

    struct SearchResult: Decodable {
        let songs: [Track]?
        let albums: [AlbumSummary]?
        let artists: [ArtistSummary]?
        let playlists: [PlaylistSummary]?
        let songCount: Int?
        let albumCount: Int?
        let artistCount: Int?
        let playlistCount: Int?
    }

    private struct SearchResponse: Decodable { let result: SearchResult? }

    static func search(
        _ keyword: String,
        type: SearchType,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> SearchResult {
        let response = try await eapi(
            SearchResponse.self,
            "/cloudsearch/pc",
            ["s": keyword, "type": type.rawValue, "limit": limit, "offset": offset, "total": true]
        )
        return response.result ?? SearchResult(
            songs: nil,
            albums: nil,
            artists: nil,
            playlists: nil,
            songCount: nil,
            albumCount: nil,
            artistCount: nil,
            playlistCount: nil
        )
    }

    private struct SearchDefaultResponse: Decodable {
        struct Body: Decodable {
            let showKeyword: String?
            let realkeyword: String?
        }

        let data: Body?
    }

    static func searchDefaultKeyword() async throws -> String? {
        let body = try await eapi(SearchDefaultResponse.self, "/search/defaultkeyword/get").data
        return body?.realkeyword ?? body?.showKeyword
    }

    // MARK: Library

    private struct UserPlaylistsResponse: Decodable { let playlist: [PlaylistSummary] }

    static func userPlaylists(userID: Int) async throws -> [PlaylistSummary] {
        try await weapi(
            UserPlaylistsResponse.self,
            "/user/playlist",
            ["uid": userID, "limit": 2_000, "offset": 0, "includeVideo": true]
        ).playlist
    }

    private struct LikedSongsResponse: Decodable { let ids: [Int] }

    static func likedSongIDs(userID: Int) async throws -> [Int] {
        try await weapi(LikedSongsResponse.self, "/song/like/get", ["uid": userID]).ids
    }

    static func likeSong(id: Int, like: Bool) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/radio/like?alg=itembased&trackId=\(id)&time=3",
            ["trackId": id, "like": like]
        )
    }

    private struct SublistResponse<Item: Decodable>: Decodable {
        let data: [Item]
    }

    static func likedAlbums(limit: Int = 500, offset: Int = 0) async throws -> [AlbumSummary] {
        try await weapi(
            SublistResponse<AlbumSummary>.self,
            "/album/sublist",
            ["limit": limit, "offset": offset, "total": true]
        ).data
    }

    static func likedArtists(limit: Int = 500, offset: Int = 0) async throws -> [ArtistSummary] {
        try await weapi(
            SublistResponse<ArtistSummary>.self,
            "/artist/sublist",
            ["limit": limit, "offset": offset, "total": true]
        ).data
    }

    static func subscribePlaylist(id: Int, subscribe: Bool) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/playlist/\(subscribe ? "subscribe" : "unsubscribe")",
            ["id": id]
        )
    }

    static func subscribeAlbum(id: Int, subscribe: Bool) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/album/\(subscribe ? "sub" : "unsub")",
            ["id": id]
        )
    }

    static func subscribeArtist(id: Int, subscribe: Bool) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/artist/\(subscribe ? "sub" : "unsub")",
            ["artistId": id, "artistIds": "[\(id)]"]
        )
    }

    private struct PlayRecordResponse: Decodable {
        let weekData: [PlayRecordItem]?
        let allData: [PlayRecordItem]?
    }

    static func playRecords(userID: Int, week: Bool) async throws -> [PlayRecordItem] {
        let response = try await weapi(
            PlayRecordResponse.self,
            "/v1/play/record",
            ["uid": userID, "type": week ? 1 : 0]
        )
        return (week ? response.weekData : response.allData) ?? []
    }

    struct CloudResponse: Decodable {
        let data: [CloudSongItem]?
        let hasMore: Bool?
        let size: Int64?
        let maxSize: Int64?

        private enum CodingKeys: String, CodingKey {
            case data, hasMore, size, maxSize
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try? container.decode([CloudSongItem].self, forKey: .data)
            hasMore = try? container.decode(Bool.self, forKey: .hasMore)
            size = (try? container.decode(Int64.self, forKey: .size))
                ?? (try? container.decode(String.self, forKey: .size)).flatMap(Int64.init)
            maxSize = (try? container.decode(Int64.self, forKey: .maxSize))
                ?? (try? container.decode(String.self, forKey: .maxSize)).flatMap(Int64.init)
        }
    }

    static func cloudSongs(limit: Int = 1_000, offset: Int = 0) async throws -> CloudResponse {
        try await weapi(
            CloudResponse.self,
            "/v1/cloud/get",
            ["limit": limit, "offset": offset]
        )
    }

    static func deleteCloudSong(id: Int) async throws {
        _ = try await weapi(CodeOnly.self, "/cloud/del", ["songIds": "[\(id)]"])
    }

    static func matchCloudSong(userID: Int, cloudSongID: Int, targetSongID: Int) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/cloud/user/song/match",
            ["userId": userID, "songId": cloudSongID, "adjustSongId": targetSongID]
        )
    }

    struct CloudUploadCheck: Decodable {
        let needUpload: Bool
        let songID: String

        private enum CodingKeys: String, CodingKey { case needUpload, songId }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            needUpload = (try? container.decode(Bool.self, forKey: .needUpload)) ?? true
            songID = container.losslessString(forKey: .songId) ?? "0"
        }
    }

    struct UploadToken: Decodable {
        struct Body: Decodable {
            let objectKey: String
            let token: String
            let resourceID: String
            let documentID: String?

            private enum CodingKeys: String, CodingKey {
                case objectKey, token, resourceId, docId
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                objectKey = try container.decode(String.self, forKey: .objectKey)
                token = try container.decode(String.self, forKey: .token)
                resourceID = container.losslessString(forKey: .resourceId) ?? ""
                documentID = container.losslessString(forKey: .docId)
            }
        }

        let result: Body
    }

    struct CloudInfoResponse: Decodable {
        let songID: String

        private enum CodingKeys: String, CodingKey { case songId }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            songID = container.losslessString(forKey: .songId) ?? "0"
        }
    }

    static func checkCloudUpload(md5: String, fileSize: Int64, bitrate: Int) async throws -> CloudUploadCheck {
        try await weapi(
            CloudUploadCheck.self,
            "/cloud/upload/check",
            [
                "bitrate": String(bitrate),
                "ext": "",
                "length": fileSize,
                "md5": md5,
                "songId": "0",
                "version": 1,
            ]
        )
    }

    static func allocateCloudUploadToken(
        md5: String,
        filename: String,
        fileExtension: String
    ) async throws -> UploadToken.Body {
        try await weapi(
            UploadToken.self,
            "/nos/token/alloc",
            [
                "bucket": "jd-musicrep-privatecloud-audio-public",
                "ext": fileExtension,
                "filename": filename,
                "local": false,
                "nos_product": 3,
                "type": "audio",
                "md5": md5,
            ]
        ).result
    }

    static func completeCloudUpload(
        songID: String,
        resourceID: String,
        md5: String,
        filename: String,
        song: String,
        artist: String,
        album: String,
        bitrate: Int
    ) async throws {
        let info = try await weapi(
            CloudInfoResponse.self,
            "/upload/cloud/info/v2",
            [
                "md5": md5,
                "songid": songID,
                "filename": filename,
                "song": song,
                "album": album,
                "artist": artist,
                "bitrate": String(bitrate),
                "resourceId": resourceID,
            ]
        )
        _ = try await weapi(CodeOnly.self, "/cloud/pub/v2", ["songid": info.songID])
    }

    static func allocatePlaylistImageToken(filename: String) async throws -> UploadToken.Body {
        try await weapi(
            UploadToken.self,
            "/nos/token/alloc",
            [
                "bucket": "yyimgs",
                "ext": "jpg",
                "filename": filename,
                "local": false,
                "nos_product": 0,
                "return_body": #"{"code":200,"size":"$(ObjectSize)"}"#,
                "type": "other",
            ]
        ).result
    }

    static func fmTrash(id: Int) async throws {
        _ = try await weapi(
            CodeOnly.self,
            "/radio/trash/add?alg=RT&songId=\(id)&time=25",
            ["songId": id]
        )
    }

    static func scrobble(trackID: Int, sourceID: Int, seconds: Int) async {
        let log: [[String: Any]] = [[
            "action": "play",
            "json": [
                "download": 0,
                "end": "playend",
                "id": trackID,
                "sourceId": String(sourceID),
                "time": seconds,
                "type": "song",
                "wifi": 0,
                "source": "list",
            ],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: log),
              let logs = String(data: data, encoding: .utf8) else { return }
        _ = try? await client.weapi("/feedback/weblog", ["logs": logs])
    }
}

private extension KeyedDecodingContainer {
    func losslessString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(format: "%.0f", value) }
        return nil
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
