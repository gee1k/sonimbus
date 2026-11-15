import Foundation
import Testing
@testable import SonimbusCore

private func profile(_ id: Int, name: String) throws -> UserProfile {
    let data = try JSONSerialization.data(withJSONObject: ["userId": id, "nickname": name])
    return try JSONDecoder().decode(UserProfile.self, from: data)
}

@Test("保存多个账号、更新同一账号和移除账号互不覆盖")
func savedAccountsStayIndependent() throws {
    var archive = SavedAccountArchive()
    let first = try profile(1, name: "甲")
    let second = try profile(2, name: "乙")
    archive.remember(profile: first, cookies: ["MUSIC_U": "first", "__csrf": "first-csrf"])
    archive.remember(profile: second, cookies: ["MUSIC_U": "second"])
    archive.remember(profile: first, cookies: ["MUSIC_U": "refreshed"])
    let restored = try JSONDecoder().decode(SavedAccountArchive.self, from: JSONEncoder().encode(archive))
    #expect(restored.sessions.count == 2)
    #expect(restored.session(userID: 1)?.cookies == ["MUSIC_U": "refreshed"])
    #expect(restored.session(userID: 2)?.cookies == ["MUSIC_U": "second"])
    archive.remove(userID: 1)
    #expect(archive.sessions.map(\.profile.userId) == [2])
}

@Test("未完成扫码不会保存为空账号或污染当前登录")
func pendingSignInIsIsolated() throws {
    let active = NeteaseClient()
    active.setCookies(["MUSIC_U": "active", "__csrf": "old-csrf"])
    let pending = NeteaseClient()
    pending.setCookies(["MUSIC_U": "pending"])
    #expect(active.cookie(named: "MUSIC_U") == "active")
    pending.clearAuthentication()
    #expect(active.isLoggedIn)
    var archive = SavedAccountArchive()
    archive.remember(profile: try profile(1, name: "未登录"), cookies: [:])
    #expect(archive.sessions.isEmpty)
    active.replaceAuthentication(with: ["MUSIC_U": "new-account"])
    #expect(active.cookie(named: "__csrf") == nil)
    #expect(active.cookie(named: "MUSIC_U") == "new-account")
}

private actor DelayedRequestGate {
    var pending: DelayedAccountProtocol?
    func receive(_ request: DelayedAccountProtocol) { pending = request }
    func take() -> DelayedAccountProtocol? {
        defer { pending = nil }
        return pending
    }
}

private final class DelayedAccountProtocol: URLProtocol, @unchecked Sendable {
    static let gate = DelayedRequestGate()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Task { await Self.gate.receive(self) } }
    override func stopLoading() {}

    func finish() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Set-Cookie": "MUSIC_U=late-old-token; Path=/; Domain=music.163.com"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"code\":200}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Test("旧账号迟到的响应既不能返回数据，也不能覆盖新账号 Cookie")
func lateAccountResponseIsDiscarded() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DelayedAccountProtocol.self]
    let client = NeteaseClient(configuration: configuration)
    client.replaceAuthentication(with: ["MUSIC_U": "first", "__csrf": "first-csrf"])
    let request = Task { try await client.weapi("/account-isolation-test") }
    defer { request.cancel() }
    var pending: DelayedAccountProtocol?
    for _ in 0..<100 {
        pending = await DelayedAccountProtocol.gate.take()
        if pending != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let response = try #require(pending)
    #expect(response.request.value(forHTTPHeaderField: "Cookie")?.contains("MUSIC_U=first") == true)
    client.replaceAuthentication(with: ["MUSIC_U": "second"])
    response.finish()
    do {
        _ = try await request.value
        Issue.record("切换账号后不应返回旧请求的数据")
    } catch is CancellationError {} catch { throw error }
    #expect(client.authenticationCookies() == ["MUSIC_U": "second"])
}
