import Foundation
import Testing
@testable import NetEaseTVCore

@Test("灰歌补全优先匹配前五项中时长接近的歌曲")
func matchesAlternativeTrackByDuration() {
    #expect(
        UnblockService.preferredMatchIndex(
            durationsMS: [180_000, 203_100, 202_000, 203_500, 203_900, 203_000],
            targetDurationMS: 204_000
        ) == 1
    )
    #expect(
        UnblockService.preferredMatchIndex(
            durationsMS: [120_000, 130_000, 140_000],
            targetDurationMS: 200_000
        ) == nil
    )
    #expect(UnblockService.preferredMatchIndex(durationsMS: [], targetDurationMS: 200_000) == nil)
    #expect(UnblockService.streamDurationIsPlausible(269.4, target: 269))
    #expect(!UnblockService.streamDurationIsPlausible(11.31, target: 269))
    #expect(UnblockService.automaticRetrySources == ["波点音乐"])
    #expect(!UnblockService.automaticRetrySources.contains("GD 音乐台"))
    #expect(!UnblockService.automaticRetrySources.contains("酷我音乐"))
    #expect(!UnblockService.automaticRetrySources.contains("酷狗音乐"))
}

@Test("歌曲解锁关闭后隐藏不可用歌曲")
func filtersUnavailableTracksWhenSongUnlockIsOff() throws {
    let playable = try JSONDecoder().decode(
        Track.self,
        from: Data(#"{"id":1,"name":"可播放","ar":[],"al":{"id":0,"name":""},"dt":1000,"privilege":{"id":1,"st":0,"pl":320000}}"#.utf8)
    )
    let unavailable = try JSONDecoder().decode(
        Track.self,
        from: Data(#"{"id":2,"name":"不可用","ar":[],"al":{"id":0,"name":""},"dt":1000,"privilege":{"id":2,"st":-200,"pl":0}}"#.utf8)
    )

    #expect(SongUnlockPolicy.visibleTracks([playable, unavailable], isEnabled: true).map(\.id) == [1, 2])
    #expect(SongUnlockPolicy.visibleTracks([playable, unavailable], isEnabled: false).map(\.id) == [1])
}

@Test("云盘上传接口兼容字符串与数字 ID")
func decodesCloudUploadResponses() throws {
    let check = try JSONDecoder().decode(
        NeteaseAPI.CloudUploadCheck.self,
        from: Data(#"{"needUpload":false,"songId":42}"#.utf8)
    )
    let token = try JSONDecoder().decode(
        NeteaseAPI.UploadToken.self,
        from: Data(#"{"result":{"objectKey":"a/b.mp3","token":"token","resourceId":123,"docId":"456"}}"#.utf8)
    )
    let info = try JSONDecoder().decode(
        NeteaseAPI.CloudInfoResponse.self,
        from: Data(#"{"songId":"789"}"#.utf8)
    )

    #expect(!check.needUpload)
    #expect(check.songID == "42")
    #expect(token.result.resourceID == "123")
    #expect(token.result.documentID == "456")
    #expect(info.songID == "789")
}

@Test("歌曲模型兼容新版和旧版字段")
func decodesTrackShapes() throws {
    let modern = Data(#"{"id":1,"name":"现代","ar":[{"id":2,"name":"歌手"}],"al":{"id":3,"name":"专辑","picUrl":"http://example.com/a.jpg"},"dt":123456,"alia":[],"tns":["Modern"],"noCopyrightRcmd":{"type":1}}"#.utf8)
    let legacy = Data(#"{"id":4,"name":"旧版","artists":[{"id":5,"name":"Artist"}],"album":{"id":6,"name":"Album"},"duration":654321,"alias":["别名"]}"#.utf8)
    let explicitlyPlayable = Data(#"{"id":7,"name":"可播放","ar":[],"al":{"id":0,"name":""},"dt":1000,"noCopyrightRcmd":false}"#.utf8)
    let unavailable = Data(#"{"id":8,"name":"灰歌","ar":[],"al":{"id":0,"name":""},"dt":269000,"privilege":{"id":8,"st":-200,"pl":0}}"#.utf8)

    let first = try JSONDecoder().decode(Track.self, from: modern)
    let second = try JSONDecoder().decode(Track.self, from: legacy)
    let third = try JSONDecoder().decode(Track.self, from: explicitlyPlayable)
    let fourth = try JSONDecoder().decode(Track.self, from: unavailable)

    #expect(first.artistNames == "歌手")
    #expect(first.durationMS == 123456)
    #expect(first.artworkURL?.scheme == "https")
    #expect(first.noCopyright)
    #expect(try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(first)).noCopyright)
    #expect(second.album.name == "Album")
    #expect(second.subtitle == "别名")
    #expect(!third.noCopyright)
    #expect(fourth.isCopyrightUnavailable)
    #expect(fourth.isPlaybackUnavailable)
}

@Test("歌手完整曲库兼容数字 more 字段")
func decodesArtistSongCatalog() throws {
    let response = try JSONDecoder().decode(
        NeteaseAPI.ArtistSongsResponse.self,
        from: Data(#"{"songs":[],"more":1}"#.utf8)
    )

    #expect(response.songs.isEmpty)
    #expect(response.hasMore)
}

@Test("播放次数与时长格式适合电视 UI")
func formatsValues() {
    #expect(DisplayFormatter.playCount(12_340) == "1.2 万")
    #expect(DisplayFormatter.playCount(20_000) == "2 万")
    #expect(DisplayFormatter.playCount(230_000_000) == "2.3 亿")
    #expect(DisplayFormatter.playCount(25_000_000_000) == "250 亿")
    #expect(DisplayFormatter.duration(61.9) == "1:01")
}

@Test("推荐歌单兼容不同播放次数字段")
func decodesRecommendedPlaylistPlayCount() throws {
    let lowercase = Data(#"{"id":1,"name":"专属推荐","picUrl":"http://example.com/a.jpg","playcount":1234567}"#.utf8)
    let decimal = Data(#"{"id":2,"name":"热门推荐","coverImgUrl":"http://example.com/b.jpg","playCount":9876.0}"#.utf8)

    let first = try JSONDecoder().decode(PlaylistSummary.self, from: lowercase)
    let second = try JSONDecoder().decode(PlaylistSummary.self, from: decimal)

    #expect(first.playCount == 1_234_567)
    #expect(second.playCount == 9_876)
    #expect(first.replacingTrackCount(with: 8).trackCount == 8)
    #expect(first.replacingTrackCount(with: -1).trackCount == 0)
}

@Test("歌单列表与详情复用同一封面地址")
func reusesPlaylistArtworkURLAcrossScreens() throws {
    let coverURL = "http://example.com/playlist.jpg"
    let summary = try JSONDecoder().decode(
        PlaylistSummary.self,
        from: Data(#"{"id":1,"name":"歌单","coverImgUrl":"http://example.com/playlist.jpg"}"#.utf8)
    )
    let detail = try JSONDecoder().decode(
        PlaylistDetail.self,
        from: Data(#"{"id":1,"name":"歌单","coverImgUrl":"http://example.com/playlist.jpg","trackCount":0,"playCount":0,"subscribedCount":0,"tracks":[],"trackIds":[]}"#.utf8)
    )

    #expect(summary.coverImgUrl == coverURL)
    #expect(summary.artworkURL == detail.artworkURL)
    #expect(summary.artworkURL?.absoluteString == "https://example.com/playlist.jpg?param=800y800")
}

@Test("播放音质使用中文标识")
func formatsAudioQuality() {
    #expect(AudioQuality.displayName(for: "lossless") == "无损")
    #expect(AudioQuality.displayName(for: "hires") == "高解析度无损")
    #expect(AudioQuality.displayName(for: "sky") == "沉浸环绕声")
    #expect(AudioQuality.displayName(for: "jymaster") == "超清母带")
    #expect(AudioQuality.displayName(for: "future-level") == "高品质")
    #expect(AudioQuality.hires.fallbackLevels == [.hires, .lossless, .exhigh, .higher, .standard])
    #expect(AudioQuality.lossless.fallbackLevels == [.lossless, .exhigh, .higher, .standard])
    #expect(AudioQuality.standard.fallbackLevels == [.standard])
}

@Test("云盘歌曲兼容嵌套元数据和字符串容量")
func decodesCloudSongShapes() throws {
    let data = Data(#"{"songId":9,"privateCloud":{"songId":9,"song":"云端歌曲","artist":"歌手","fileSize":1234},"simpleSong":{"id":9,"name":"云端歌曲","ar":[{"id":2,"name":"歌手"}],"al":{"id":3,"name":"专辑"},"dt":180000}}"#.utf8)

    let item = try JSONDecoder().decode(CloudSongItem.self, from: data)

    #expect(item.id == 9)
    #expect(item.songName == "云端歌曲")
    #expect(item.fileSize == 1_234)
    #expect(item.simpleSong?.duration == 180)
}

@Test("旧云盘条目缺少 simpleSong 时仍可播放")
func buildsFallbackCloudTrack() throws {
    let data = Data(#"{"privateCloud":{"songId":88,"song":"旧云盘歌曲","artist":"本地歌手","fileSize":4321}}"#.utf8)

    let item = try JSONDecoder().decode(CloudSongItem.self, from: data)
    let track = try #require(item.playableTrack)

    #expect(track.id == 88)
    #expect(track.name == "旧云盘歌曲")
    #expect(track.artistNames == "本地歌手")
    #expect(track.album.name == "音乐云盘")
}

@Test("账号播放记录缺少统计字段时仍可解码")
func decodesPlayRecordDefaults() throws {
    let data = Data(#"{"song":{"id":10,"name":"记录歌曲","ar":[],"al":{"id":0,"name":""},"dt":120000}}"#.utf8)

    let item = try JSONDecoder().decode(PlayRecordItem.self, from: data)

    #expect(item.playCount == 0)
    #expect(item.score == 0)
    #expect(item.song.id == 10)
}

@Test("会员信息兼容数字与字符串等级")
func decodesVIPMembership() throws {
    let numeric = Data(#"{"redVipLevel":7,"redVipAnnualCount":1}"#.utf8)
    let string = Data(#"{"redVipLevel":"5","redVipAnnualCount":"0"}"#.utf8)

    let first = try JSONDecoder().decode(VIPMembership.self, from: numeric)
    let second = try JSONDecoder().decode(VIPMembership.self, from: string)

    #expect(first.redVipLevel == 7)
    #expect(first.redVipAnnualCount == 1)
    #expect(second.redVipLevel == 5)
    #expect(second.redVipAnnualCount == 0)
}

@Test("播放队列边界遵循循环模式")
func resolvesNextQueueIndex() {
    #expect(PlaybackQueuePolicy.nextIndex(after: 1, count: 4, repeatMode: .off) == 2)
    #expect(PlaybackQueuePolicy.nextIndex(after: 3, count: 4, repeatMode: .off) == nil)
    #expect(PlaybackQueuePolicy.nextIndex(after: 3, count: 4, repeatMode: .one) == nil)
    #expect(PlaybackQueuePolicy.nextIndex(after: 3, count: 4, repeatMode: .all) == 0)
    #expect(PlaybackQueuePolicy.nextIndex(after: -1, count: 4, repeatMode: .off) == 0)
    #expect(PlaybackQueuePolicy.nextIndex(after: 0, count: 0, repeatMode: .all) == nil)
}

@Test("播放队列按歌曲 ID 保留首次出现顺序")
func deduplicatesPlaybackQueue() {
    let album = AlbumRef(id: 1, name: "专辑", picUrl: nil)
    let artist = ArtistRef(id: 2, name: "歌手")
    let first = Track(id: 10, name: "第一首", artists: [artist], album: album, durationMS: 1_000)
    let duplicate = Track(id: 10, name: "重复项", artists: [artist], album: album, durationMS: 1_000)
    let second = Track(id: 20, name: "第二首", artists: [artist], album: album, durationMS: 1_000)

    #expect(PlaybackQueuePolicy.deduplicated([first, duplicate, second]).map(\.name) == ["第一首", "第二首"])
}

@Test("MV 连播队列去重并首尾循环")
func resolvesMVQueueOrder() throws {
    let first = try JSONDecoder().decode(
        MVSummary.self,
        from: Data(#"{"id":1,"name":"第一支","artistName":"歌手"}"#.utf8)
    )
    let duplicate = try JSONDecoder().decode(
        MVSummary.self,
        from: Data(#"{"id":1,"name":"重复项","artistName":"歌手"}"#.utf8)
    )
    let second = try JSONDecoder().decode(
        MVSummary.self,
        from: Data(#"{"id":2,"name":"第二支","artistName":"歌手"}"#.utf8)
    )

    #expect(MVQueuePolicy.deduplicated([first, duplicate, second]).map(\.name) == ["第一支", "第二支"])
    #expect(MVQueuePolicy.adjacentIndex(from: 0, count: 2, offset: 1) == 1)
    #expect(MVQueuePolicy.adjacentIndex(from: 1, count: 2, offset: 1) == 0)
    #expect(MVQueuePolicy.adjacentIndex(from: 0, count: 2, offset: -1) == 1)
    #expect(MVQueuePolicy.adjacentIndex(from: 0, count: 1, offset: 1) == nil)
}

@Test("MV 模型兼容推荐、详情与播放地址字段")
func decodesMVShapes() throws {
    let summaryData = Data(#"{"id":77,"name":"现场 MV","picUrl":"http://example.com/mv.jpg","artistId":9,"artistName":"歌手","duration":245000,"playCount":"12345","brs":{"480":1,"1080":1}}"#.utf8)
    let urlData = Data(#"{"id":77,"url":"http://example.com/video.mp4","r":1080,"size":1024,"code":200,"expi":1200}"#.utf8)

    let summary = try JSONDecoder().decode(MVSummary.self, from: summaryData)
    let stream = try JSONDecoder().decode(MVURLData.self, from: urlData)

    #expect(summary.name == "现场 MV")
    #expect(summary.artistNames == "歌手")
    #expect(summary.duration == 245)
    #expect(summary.playCount == 12_345)
    #expect(summary.availableResolutions == [1_080, 480])
    #expect(summary.artworkURL?.absoluteString.contains("param=960y540") == true)
    #expect(stream.streamURL?.scheme == "https")
    #expect(stream.resolution == 1_080)
    #expect(stream.expiresIn == 1_200)
}
