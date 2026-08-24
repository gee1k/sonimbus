import Foundation
import Testing
@testable import NetEaseTVCore

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
