import Foundation
import Testing
@testable import SonimbusCore

@Test("Top Shelf 播放与详情链接保留账号和内容身份")
func topShelfLinksRoundTrip() {
    for kind in [TopShelfLink.Kind.playlist, .track] {
        for action in [TopShelfLink.Action.display, .play] {
            let link = TopShelfLink(kind: kind, id: 42, accountID: 7, action: action)
            #expect(TopShelfLink(url: link.url) == link)
        }
    }
}

@Test("无效或缺少账号的外部链接不触发播放")
func invalidTopShelfLinksAreIgnored() throws {
    for value in [
        "https://top-shelf/track/42?account=7&action=play",
        "sonimbus://top-shelf/track/42?action=play",
        "sonimbus://top-shelf/track/-1?account=7&action=play",
        "sonimbus://top-shelf/track/42?account=0&action=play",
        "sonimbus://top-shelf/artist/42?account=7&action=play",
        "sonimbus://top-shelf/track/42?account=7&account=8&action=play",
    ] {
        #expect(TopShelfLink(url: try #require(URL(string: value))) == nil)
    }
}

@Test("主屏幕快照仅包含展示内容并可供扩展恢复")
func topShelfSnapshotRoundTrip() throws {
    let snapshot = TopShelfSnapshot(accountID: 7,
        recentTracks: [.init(id: 42, title: "歌曲", imageURL: URL(string: "https://example.com/art.jpg"))],
        playlists: [.init(id: 8, title: "我喜欢的音乐", imageURL: nil)])
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(TopShelfSnapshot.self, from: data) == snapshot)
    let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(keys.keys) == ["accountID", "recentTracks", "playlists"])
}

@Test("主程序写入的缓存可供独立扩展读取，清空后不再暴露旧账号")
func topShelfSharedCacheLifecycle() throws {
    let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: container) }
    let publisher = TopShelfSnapshotFile(containerURL: container)
    let extensionReader = TopShelfSnapshotFile(containerURL: container)
    #expect(try extensionReader.read() == nil)

    let first = TopShelfSnapshot(accountID: 7, recentTracks: [],
                                playlists: [.init(id: 8, title: "歌单", imageURL: nil)])
    try publisher.write(first)
    #expect(try extensionReader.read() == first)
    try publisher.write(nil)
    #expect(try extensionReader.read() == nil)

    let second = TopShelfSnapshot(accountID: 9, recentTracks: [], playlists: [])
    try publisher.write(second)
    #expect(try extensionReader.read() == second)
}

@Test("tvOS 清理共享缓存后可重新发布 Top Shelf")
func topShelfCacheRecoversAfterEviction() throws {
    let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: container) }
    let store = TopShelfSnapshotFile(containerURL: container)
    let snapshot = TopShelfSnapshot(accountID: 7, recentTracks: [], playlists: [])
    try store.write(snapshot)
    let caches = container.appendingPathComponent("Library/Caches", isDirectory: true)
    try FileManager.default.removeItem(at: caches)
    #expect(try store.read() == nil)
    try store.write(snapshot)
    #expect(try store.read() == snapshot)
}
