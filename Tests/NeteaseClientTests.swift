import Foundation
import Testing
@testable import SonimbusCore

@Test
func decodesBusinessCodeShapes() {
    #expect(NeteaseClient.businessCode(from: 200) == 200)
    #expect(NeteaseClient.businessCode(from: NSNumber(value: 301)) == 301)
    #expect(NeteaseClient.businessCode(from: "512") == 512)
    #expect(NeteaseClient.businessCode(from: nil) == nil)
}

@Test("登录响应包含同名 Cookie 时使用最后一个值")
func duplicateResponseCookiesDoNotCrash() throws {
    let first = try #require(HTTPCookie(properties: [
        .domain: ".music.163.com",
        .path: "/",
        .name: "MUSIC_U",
        .value: "old-token",
    ]))
    let second = try #require(HTTPCookie(properties: [
        .domain: "music.163.com",
        .path: "/weapi",
        .name: "MUSIC_U",
        .value: "new-token",
    ]))
    let csrf = try #require(HTTPCookie(properties: [
        .domain: ".music.163.com",
        .path: "/",
        .name: "__csrf",
        .value: "csrf-token",
    ]))

    let values = NeteaseClient.cookieValues(from: [first, csrf, second])

    #expect(values["MUSIC_U"] == "new-token")
    #expect(values["__csrf"] == "csrf-token")
    #expect(values.count == 2)
}

@Test("登录 Cookie 可以完整归档并恢复")
func authenticationCookiesRoundTrip() throws {
    let cookies = [
        "MUSIC_U": "music-token",
        "__csrf": "csrf-token",
        "NMTID": "device-token",
    ]

    let data = try #require(AuthenticationCookieArchive.encode(cookies))

    #expect(AuthenticationCookieArchive.decode(data) == cookies)
    #expect(AuthenticationCookieArchive.decode(Data("invalid".utf8)) == nil)
}

@Test("播放上报区分最近播放与听歌计数并保留来源")
func playbackLogsMatchUpstreamContract() throws {
    let start = try #require(NeteaseAPI.playbackLog(trackID: 123, sourceID: 456, seconds: nil).first)
    let finish = try #require(NeteaseAPI.playbackLog(trackID: 123, sourceID: 456, seconds: 30).first)
    #expect(start["action"] as? String == "startplay")
    #expect(finish["action"] as? String == "play")
    let startBody = try #require(start["json"] as? [String: Any])
    let finishBody = try #require(finish["json"] as? [String: Any])
    #expect(startBody["id"] as? Int == 123)
    #expect(startBody["content"] as? String == "id=456")
    #expect(startBody["mainsiteWeb"] as? String == "1")
    #expect(startBody["time"] == nil)
    #expect(finishBody["sourceId"] as? String == "456")
    #expect(finishBody["time"] as? Int == 30)
    #expect(finishBody["end"] as? String == "playend")
    #expect(JSONSerialization.isValidJSONObject([start, finish]))
}

@Test("单次 Cookie 覆盖保留认证和设备令牌且不污染后续请求")
func requestCookieOverridesAreScoped() {
    let cookies = ["MUSIC_U": "test-token", "NMTID": "server-device", "os": "pc"]
    let extra = ["os": "pc", "appver": "3.1.17"]
    let overridden = NeteaseClient.cookieHeader(cookies: cookies, extra: extra, overrides: ["os": "osx"])
    #expect(overridden.contains("os=osx"))
    #expect(overridden.contains("MUSIC_U=test-token"))
    #expect(overridden.contains("NMTID=server-device"))
    #expect(NeteaseClient.cookieHeader(cookies: cookies, extra: extra, overrides: [:]).contains("os=pc"))
}

@Test("设备身份按安装持久保存，损坏值自动更换")
func persistentDesktopIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = NeteaseClient.loadDeviceID(in: directory)
    #expect(first.count == 52)
    #expect(first.allSatisfy { $0.isHexDigit })
    #expect(NeteaseClient.loadDeviceID(in: directory) == first)
    try Data("netease-tv".utf8).write(to: directory.appendingPathComponent("device-id"))
    let repaired = NeteaseClient.loadDeviceID(in: directory)
    #expect(repaired != first)
    #expect(NeteaseClient.loadDeviceID(in: directory) == repaired)
    let header = NeteaseClient.desktopHeader(deviceID: repaired)
    let cookie = NeteaseClient.cookieHeader(cookies: ["deviceId": "stale", "MUSIC_U": "test"], extra: header, overrides: header)
    #expect(cookie.contains("deviceId=\(repaired)"))
    #expect(cookie.contains("MUSIC_U=test"))
}

@Test("最近播放保留服务端时间顺序、去重且跳过无效记录")
func recentSongResponseKeepsChronologicalOrder() throws {
    let json = #"{"data":{"list":[{"data":{"id":20,"name":"new"}},{"data":null},{"data":{"id":10,"name":"old"}},null,{"data":{"id":20,"name":"duplicate"}},{"data":{"id":0}}]}}"#
    let response = try JSONDecoder().decode(NeteaseAPI.RecentSongsResponse.self, from: Data(json.utf8))
    #expect(response.records.map(\.song.id) == [20, 10])
    #expect(response.records.first?.song.name == "new")
}

@Test("暂时断连只重试一次；业务拒绝和离线不重试")
func playbackReadRetryIsBounded() async throws {
    var attempts = 0
    let value = try await PlaybackRequestRetry.run(delay: .zero) {
        attempts += 1
        if attempts == 1 { throw URLError(.networkConnectionLost) }
        return 42
    }
    #expect(value == 42)
    #expect(attempts == 2)
    for error: Error in [URLError(.timedOut), NeteaseAPIError.http(503), URLError(.notConnectedToInternet), NeteaseAPIError.business(code: 301, message: nil), CancellationError()] {
        attempts = 0
        do {
            let _: Int = try await PlaybackRequestRetry.run(delay: .zero) {
                attempts += 1
                throw error
            }
            Issue.record("Expected failure")
        } catch { }
        #expect(attempts == (PlaybackRequestRetry.isTransient(error) ? 2 : 1))
    }
}

@Test("取消等待中的播放请求不会发送重试")
func cancelledPlaybackReadDoesNotRetry() async throws {
    let task = Task {
        try await PlaybackRequestRetry.run(delay: .seconds(10)) { () -> Int in
            throw URLError(.timedOut)
        }
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch { #expect(error is CancellationError) }
}

@Test("CDN 只切换官方音频主机，保留路径签名并记住短期故障")
func officialCDNFailoverIsScopedAndExpires() throws {
    let original = try #require(URL(string: "https://m801.music.126.net/abc/file.flac?token=a%2Bb"))
    let twin = try #require(PlaybackCDNPolicy.alternate(for: original))
    #expect(twin.absoluteString == "https://m801c.music.126.net/abc/file.flac?token=a%2Bb")
    #expect(PlaybackCDNPolicy.alternate(for: twin) == original)
    for raw in ["https://m801.music.126.net.evil.com/a", "https://other.example/a", "https://music.163.com/a", "https://m.music.126.net/a", "http://m801.music.126.net/a"] {
        #expect(PlaybackCDNPolicy.alternate(for: URL(string: raw)!) == nil)
    }
    var policy = PlaybackCDNPolicy()
    let wrapped = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: URLError(.cannotFindHost)])
    #expect(policy.failover(from: original, error: wrapped, now: 10) == twin)
    #expect(policy.preferred(original, now: 11) == twin)
    #expect(policy.preferred(original, now: 611) == original)
    #expect(policy.failover(from: twin, error: wrapped, now: 12) == nil)
    policy.markReachable(original)
    #expect(policy.preferred(original, now: 13) == original)
    #expect(policy.failover(from: original, error: NeteaseAPIError.http(403), now: 14) == nil)
}
