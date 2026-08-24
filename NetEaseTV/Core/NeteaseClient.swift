import Foundation
import os.log

enum NeteaseAPIError: LocalizedError {
    case invalidResponse
    case http(Int)
    case business(code: Int, message: String?)
    case needLogin
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无效响应"
        case .http(let status):
            return "网络请求失败（\(status)）"
        case .business(let code, let message):
            return message ?? "接口请求失败（\(code)）"
        case .needLogin:
            return "需要先登录网易云音乐"
        case .decoding:
            return "数据格式暂时无法识别"
        }
    }
}

final class NeteaseClient: @unchecked Sendable {
    static let shared = NeteaseClient()

    private static let log = Logger(subsystem: "com.gee1k.neteasetv", category: "NeteaseAPI")
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    private let session: URLSession
    private let cookieLock = NSLock()
    private let cookiePersistenceLock = NSLock()
    private var cookies: [String: String] = [:]
    private var cookieGeneration = 0
    private let cookieFileURL: URL

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        session = URLSession(configuration: configuration)

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetEaseTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cookieFileURL = support.appendingPathComponent("cookies.json")
        if let data = try? Data(contentsOf: cookieFileURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            cookies = saved
        }
    }

    var isLoggedIn: Bool { cookie(named: "MUSIC_U") != nil }

    func cookie(named name: String) -> String? {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return cookies[name]
    }

    func setCookies(_ values: [String: String]) {
        cookieLock.lock()
        if let musicU = values["MUSIC_U"], !musicU.isEmpty, musicU != cookies["MUSIC_U"] {
            cookieGeneration &+= 1
        }
        for (key, value) in values where !value.isEmpty && value != "\"\"" {
            cookies[key] = value
        }
        cookieLock.unlock()
        persistCurrentCookies()
    }

    func clearAuthentication() {
        cookieLock.lock()
        cookies.removeAll(keepingCapacity: true)
        cookieGeneration &+= 1
        cookieLock.unlock()
        persistCurrentCookies()
    }

    func weapi(
        _ path: String,
        _ payload: [String: Any] = [:],
        requestTimeout: TimeInterval? = nil
    ) async throws -> Data {
        var body = payload
        body["csrf_token"] = cookie(named: "__csrf") ?? ""
        let json = try JSONSerialization.data(withJSONObject: body)
        let encrypted = NeteaseCrypto.weapi(payload: json)

        var fullPath = path
        if let csrf = cookie(named: "__csrf"), !csrf.isEmpty {
            fullPath += (path.contains("?") ? "&" : "?") + "csrf_token=\(csrf)"
        }
        guard let url = URL(string: "https://music.163.com/weapi\(fullPath)") else {
            throw NeteaseAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        prepare(&request)
        if let requestTimeout { request.timeoutInterval = requestTimeout }
        request.httpBody = Self.encodeForm(encrypted)
        return try await perform(request)
    }

    func eapi(_ path: String, _ payload: [String: Any] = [:]) async throws -> Data {
        let apiPath = "/api" + path
        var body = payload
        var header: [String: String] = [
            "os": "pc",
            "appver": "3.1.17",
            "osver": "Version 14.0",
            "deviceId": "netease-tv",
            "requestId": String(Int.random(in: 20_000_000...30_000_000)),
            "clientSign": "",
            "versioncode": "140",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "resolution": "1920x1080",
            "channel": "",
        ]
        if let musicU = cookie(named: "MUSIC_U") { header["MUSIC_U"] = musicU }
        if let csrf = cookie(named: "__csrf") { header["__csrf"] = csrf }
        body["header"] = header

        let json = try JSONSerialization.data(withJSONObject: body)
        let encrypted = NeteaseCrypto.eapi(apiPath: apiPath, payload: json)
        guard let url = URL(string: "https://interface.music.163.com/eapi\(path)") else {
            throw NeteaseAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        prepare(&request)
        request.httpBody = Self.encodeForm(encrypted)
        return try await perform(request)
    }

    func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = Self.businessCode(from: object["code"]),
           code != 200 {
            if code == 301 { throw NeteaseAPIError.needLogin }
            let message = (object["message"] as? String) ?? (object["msg"] as? String)
            throw NeteaseAPIError.business(code: code, message: message)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Self.log.error("Decode \(String(describing: type)) failed: \(error.localizedDescription)")
            throw NeteaseAPIError.decoding(String(describing: error))
        }
    }

    static func businessCode(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func prepare(_ request: inout URLRequest) {
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader(extra: ["os": "pc", "appver": "3.1.17"]), forHTTPHeaderField: "Cookie")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let requestCookieGeneration = currentCookieGeneration()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NeteaseAPIError.invalidResponse
        }
        if let url = request.url {
            absorbCookies(from: http, url: url, expectedGeneration: requestCookieGeneration)
        }
        guard (200..<300).contains(http.statusCode) else {
            Self.log.error("HTTP \(http.statusCode) at \(request.url?.path ?? "?")")
            throw NeteaseAPIError.http(http.statusCode)
        }
        return data
    }

    private func currentCookieGeneration() -> Int {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return cookieGeneration
    }

    private func cookieHeader(extra: [String: String]) -> String {
        cookieLock.lock()
        var values = cookies
        cookieLock.unlock()
        for (key, value) in extra where values[key] == nil { values[key] = value }
        return values.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func absorbCookies(from response: HTTPURLResponse, url: URL, expectedGeneration: Int) {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                fields[key] = value
            }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        let values = Self.cookieValues(from: parsed)
        guard !values.isEmpty else { return }
        cookieLock.lock()
        guard cookieGeneration == expectedGeneration else {
            cookieLock.unlock()
            return
        }
        if let musicU = values["MUSIC_U"], !musicU.isEmpty, musicU != cookies["MUSIC_U"] {
            cookieGeneration &+= 1
        }
        for (key, value) in values where !value.isEmpty && value != "\"\"" {
            cookies[key] = value
        }
        cookieLock.unlock()
        persistCurrentCookies()
    }

    static func cookieValues(from parsed: [HTTPCookie]) -> [String: String] {
        parsed.reduce(into: [:]) { values, cookie in
            values[cookie.name] = cookie.value
        }
    }

    private func persistCurrentCookies() {
        cookiePersistenceLock.lock()
        defer { cookiePersistenceLock.unlock() }
        cookieLock.lock()
        let snapshot = cookies
        cookieLock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: cookieFileURL, options: .atomic)
        }
    }

    private static func encodeForm(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
