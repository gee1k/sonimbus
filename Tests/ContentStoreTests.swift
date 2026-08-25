import Foundation
import Testing
@testable import SonimbusCore

@MainActor
@Test("内容缓存在有效期内复用且版本变化时重新载入")
func contentCacheCachesByRevision() async throws {
    var requestCount = 0
    let cache = ContentCache<ContentStore.PlaylistKey, PlaylistDetail>(lifetime: 300)
    let loader: ContentCache<ContentStore.PlaylistKey, PlaylistDetail>.Loader = { key in
        requestCount += 1
        return try makePlaylistDetail(id: key.playlistID, name: "第 \(requestCount) 次载入")
    }
    let originalKey = ContentStore.PlaylistKey(playlistID: 42, userID: 7, revision: 0)

    let first = try await cache.load(for: originalKey, loader: loader)
    let cached = try await cache.load(for: originalKey, loader: loader)

    #expect(first.name == "第 1 次载入")
    #expect(cached.name == first.name)
    #expect(requestCount == 1)

    let refreshedKey = ContentStore.PlaylistKey(playlistID: 42, userID: 7, revision: 1)
    #expect(cache.value(for: refreshedKey) == nil)
    #expect(cache.latest { $0.playlistID == 42 && $0.userID == 7 }?.name == first.name)

    let refreshed = try await cache.load(for: refreshedKey, loader: loader)
    #expect(refreshed.name == "第 2 次载入")
    #expect(requestCount == 2)
}

@MainActor
@Test("内容缓存过期后重新载入")
func contentCacheExpiresEntries() async throws {
    var currentDate = Date(timeIntervalSince1970: 1_000)
    var requestCount = 0
    let cache = ContentCache<Int, String>(
        lifetime: 300,
        now: { currentDate }
    )

    _ = try await cache.load(for: 42) { _ in
        requestCount += 1
        return "第 \(requestCount) 次载入"
    }
    currentDate.addTimeInterval(301)

    #expect(cache.value(for: 42) == nil)
    let refreshed = try await cache.load(for: 42) { _ in
        requestCount += 1
        return "第 \(requestCount) 次载入"
    }
    #expect(refreshed == "第 2 次载入")
    #expect(requestCount == 2)
}

@MainActor
@Test("内容缓存按账号隔离")
func contentCacheSeparatesAccounts() async throws {
    let cache = ContentCache<ContentStore.PlaylistKey, PlaylistDetail>(lifetime: 300)
    let firstAccountKey = ContentStore.PlaylistKey(playlistID: 42, userID: 7, revision: 0)

    _ = try await cache.load(for: firstAccountKey) { key in
        try makePlaylistDetail(id: key.playlistID, name: "我的歌单")
    }

    #expect(cache.latest { $0.playlistID == 42 && $0.userID == 7 }?.name == "我的歌单")
    #expect(cache.latest { $0.playlistID == 42 && $0.userID == 8 } == nil)
    #expect(cache.latest { $0.playlistID == 42 && $0.userID == nil } == nil)
}

@MainActor
@Test("显式刷新会更新缓存而不是复用旧内容")
func contentCacheRefreshesOnDemand() async throws {
    var requestCount = 0
    let cache = ContentCache<Int, String>(lifetime: 300)
    let loader: ContentCache<Int, String>.Loader = { _ in
        requestCount += 1
        return "版本 \(requestCount)"
    }

    #expect(try await cache.load(for: 1, loader: loader) == "版本 1")
    #expect(try await cache.refresh(for: 1, loader: loader) == "版本 2")
    #expect(cache.value(for: 1) == "版本 2")
    #expect(requestCount == 2)
}

private func makePlaylistDetail(id: Int, name: String) throws -> PlaylistDetail {
    let data = try JSONSerialization.data(withJSONObject: [
        "id": id,
        "name": name,
        "coverImgUrl": "https://example.com/cover.jpg",
        "description": "测试歌单",
        "trackCount": 0,
        "playCount": 0,
        "subscribedCount": 0,
        "tracks": [],
        "trackIds": [],
    ])
    return try JSONDecoder().decode(PlaylistDetail.self, from: data)
}
