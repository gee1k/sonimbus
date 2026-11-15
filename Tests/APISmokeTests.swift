import Foundation
import Testing
@testable import SonimbusCore

@Test("网易云公开推荐、详情和扫码接口可访问")
func liveAPISmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["NETEASE_API_SMOKE"] == "1" else { return }

    print("Public API smoke: recommendations")
    let playlists = try await NeteaseAPI.personalizedPlaylists(limit: 2)
    #expect(!playlists.isEmpty)

    print("Public API smoke: playlist categories")
    let categories = try await NeteaseAPI.playlistCategories()
    #expect(categories.contains(where: { !$0.name.isEmpty }))

    print("Public API smoke: playlist detail")
    let detail = try await NeteaseAPI.playlist(id: playlists[0].id)
    #expect(!detail.playlist.name.isEmpty)
    #expect(!detail.playlist.tracks.isEmpty)

    print("Public API smoke: QR key")
    let key = try await NeteaseAPI.qrKey()
    #expect(key.count > 10)
    #expect(NeteaseAPI.qrLoginURL(key: key).contains(key))

    print("Public API smoke: search")
    let search = try await NeteaseAPI.search("晴天", type: .songs, limit: 2)
    let tracks = try #require(search.songs)
    let track = try #require(tracks.first)
    #expect(!track.name.isEmpty)

    print("Public API smoke: lyrics")
    let lyrics = try await NeteaseAPI.lyrics(id: track.id)
    #expect(lyrics.lrc?.lyric?.isEmpty == false)

    print("Public API smoke: song URL")
    let urls = try await NeteaseAPI.songURLs(ids: [track.id], level: "standard")
    #expect(urls.first?.id == track.id)

    print("Public API smoke: albums")
    let albums = try await NeteaseAPI.newAlbums(limit: 1)
    let album = try #require(albums.first)
    #expect(try await !NeteaseAPI.album(id: album.id).songs.isEmpty)

    print("Public API smoke: artists")
    let artists = try await NeteaseAPI.topArtists(limit: 1)
    let artist = try #require(artists.first)
    #expect(try await !NeteaseAPI.artist(id: artist.id).hotSongs.isEmpty)
    _ = try await NeteaseAPI.artistMVs(id: artist.id, limit: 1)

    print("Public API smoke: MVs")
    let mvs = try await NeteaseAPI.personalizedMVs(limit: 1)
    let mv = try #require(mvs.first)
    #expect(try await NeteaseAPI.latestMVs(limit: 12).count > 2)
    let mvDetail = try await NeteaseAPI.mvDetail(id: mv.id)
    #expect(!mvDetail.name.isEmpty)
    let mvStream = try await NeteaseAPI.mvURL(id: mv.id, resolution: 720)
    #expect(mvStream.id == mv.id)
    #expect(mvStream.streamURL != nil)
    #expect(try await NeteaseAPI.search(mv.name, type: .mvs, limit: 1).mvs != nil)
}

@Test("新版歌词接口可直接返回可解析内容")
func liveLyricV1SmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["NETEASE_API_SMOKE"] == "1" else { return }
    let data = try await NeteaseClient.shared.eapi(
        "/song/lyric/v1",
        ["id": 186016, "cp": false, "lv": 0, "kv": 0, "tv": 0, "rv": 0,
         "yv": 0, "ytv": 0, "yrv": 0]
    )
    let response = try NeteaseClient.shared.decoded(LyricResponse.self, from: data)
    #expect(LyricsParser.hasUsableLyrics(response))
    let lyrics = LyricsParser.parse(response)
    #expect(!lyrics.isEmpty)
    #expect(lyrics.lines.map(\.time) == lyrics.lines.map(\.time).sorted())
}

@Test("桌面设备身份的 eapi 歌曲详情和重试读取可访问")
func liveDesktopPlaybackSmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["NETEASE_API_SMOKE"] == "1" else { return }
    let detail = try await NeteaseAPI.songDetails(ids: [186016])
    #expect(detail.songs.first?.id == 186016)
    let urls = try await NeteaseAPI.songURLsRetrying(ids: [186016], level: "standard")
    #expect(urls.first?.id == 186016)
}
