import Foundation
import os.log
import Security

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

enum AuthenticationCookieArchive {
    static func encode(_ cookies: [String: String]) -> Data? {
        try? JSONEncoder().encode(cookies)
    }

    static func decode(_ data: Data) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: data)
    }
}

enum AuthenticationCookieKeychain {
    private static let log = Logger(
        subsystem: "com.svend.sonimbus",
        category: "CredentialStorage"
    )
    private static let service = "com.svend.sonimbus.netease-authentication"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String = "cookies") -> Data? {
        var readQuery = query(account: account)
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, account: String = "cookies") -> Bool {
        let query = query(account: account)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else {
            log.error("Keychain update failed with status \(updateStatus)")
            return false
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Keychain add failed with status \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    static func remove(account: String = "cookies") {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}

final class NeteaseClient: @unchecked Sendable {
    static let shared = NeteaseClient(persistsAuthentication: true, configuration: .default)

    private static let log = Logger(subsystem: "com.svend.sonimbus", category: "NeteaseAPI")
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    private let session: URLSession
    private let cookieLock = NSLock()
    private let cookiePersistenceLock = NSLock()
    private var cookies: [String: String] = [:]
    private var cookieGeneration = 0
    private let cookieFileURL: URL
    private let persistsAuthentication: Bool
    private var authenticationGeneration = 0

    // QR sign-in uses an isolated, in-memory client until the user confirms login.
    init(persistsAuthentication: Bool = false, configuration: URLSessionConfiguration = .ephemeral) {
        self.persistsAuthentication = persistsAuthentication
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        session = URLSession(configuration: configuration)

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let support = applicationSupport
            .appendingPathComponent("Sonimbus", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cookieFileURL = support.appendingPathComponent("cookies.json")

        guard persistsAuthentication else { return }
        let keychainCookies = AuthenticationCookieKeychain.read()
            .flatMap(AuthenticationCookieArchive.decode)
        let fileCookies = (try? Data(contentsOf: cookieFileURL))
            .flatMap(AuthenticationCookieArchive.decode)
        cookies = keychainCookies ?? fileCookies ?? [:]
        if !cookies.isEmpty { persistCurrentCookies() }
    }

    var isLoggedIn: Bool { cookie(named: "MUSIC_U") != nil }

    func cookie(named name: String) -> String? {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return cookies[name]
    }

    func setCookies(_ values: [String: String]) {
        cookieLock.lock()
        var didChange = false
        if let musicU = values["MUSIC_U"], !musicU.isEmpty, musicU != cookies["MUSIC_U"] {
            cookieGeneration &+= 1
        }
        for (key, value) in values
        where !value.isEmpty && value != "\"\"" && value != cookies[key] {
            cookies[key] = value
            didChange = true
        }
        cookieLock.unlock()
        if didChange { persistCurrentCookies() }
    }

    func authenticationCookies() -> [String: String] {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return cookies
    }

    func replaceAuthentication(with values: [String: String]) {
        cookieLock.lock()
        cookies = values
        cookieGeneration &+= 1
        authenticationGeneration &+= 1
        cookieLock.unlock()
        persistCurrentCookies()
    }

    func clearAuthentication() {
        replaceAuthentication(with: [:])
    }

    private struct RequestAuthentication {
        let cookies: [String: String]
        let cookieGeneration: Int
        let generation: Int
    }

    private func requestAuthentication() -> RequestAuthentication {
        cookieLock.lock()
        defer { cookieLock.unlock() }
        return RequestAuthentication(cookies: cookies, cookieGeneration: cookieGeneration,
                                     generation: authenticationGeneration)
    }

    func weapi(
        _ path: String,
        _ payload: [String: Any] = [:],
        requestTimeout: TimeInterval? = nil
    ) async throws -> Data {
        let authentication = requestAuthentication()
        var body = payload
        body["csrf_token"] = authentication.cookies["__csrf"] ?? ""
        let json = try JSONSerialization.data(withJSONObject: body)
        let encrypted = NeteaseCrypto.weapi(payload: json)

        var fullPath = path
        if let csrf = authentication.cookies["__csrf"], !csrf.isEmpty {
            fullPath += (path.contains("?") ? "&" : "?") + "csrf_token=\(csrf)"
        }
        guard let url = URL(string: "https://music.163.com/weapi\(fullPath)") else {
            throw NeteaseAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        prepare(&request, cookies: authentication.cookies)
        if let requestTimeout { request.timeoutInterval = requestTimeout }
        request.httpBody = Self.encodeForm(encrypted)
        return try await perform(request, authentication: authentication)
    }

    func eapi(
        _ path: String,
        _ payload: [String: Any] = [:],
        cookieOverrides: [String: String] = [:]
    ) async throws -> Data {
        let authentication = requestAuthentication()
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
        if let musicU = authentication.cookies["MUSIC_U"] { header["MUSIC_U"] = musicU }
        if let csrf = authentication.cookies["__csrf"] { header["__csrf"] = csrf }
        if let nmtid = authentication.cookies["NMTID"], !nmtid.isEmpty { header["NMTID"] = nmtid }
        header.merge(cookieOverrides) { _, override in override }
        body["header"] = header

        let json = try JSONSerialization.data(withJSONObject: body)
        let encrypted = NeteaseCrypto.eapi(apiPath: apiPath, payload: json)
        guard let url = URL(string: "https://interface.music.163.com/eapi\(path)") else {
            throw NeteaseAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        prepare(&request, cookies: authentication.cookies, cookieOverrides: cookieOverrides)
        request.httpBody = Self.encodeForm(encrypted)
        return try await perform(request, authentication: authentication)
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

    private func prepare(_ request: inout URLRequest, cookies: [String: String], cookieOverrides: [String: String] = [:]) {
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.cookieHeader(cookies: cookies, extra: ["os": "pc", "appver": "3.1.17"], overrides: cookieOverrides), forHTTPHeaderField: "Cookie")
    }

    private func perform(_ request: URLRequest, authentication: RequestAuthentication) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard authentication.generation == requestAuthentication().generation else {
            throw CancellationError()
        }
        guard let http = response as? HTTPURLResponse else {
            throw NeteaseAPIError.invalidResponse
        }
        if let url = request.url {
            absorbCookies(from: http, url: url, expectedGeneration: authentication.cookieGeneration)
        }
        guard (200..<300).contains(http.statusCode) else {
            Self.log.error("HTTP \(http.statusCode) at \(request.url?.path ?? "?")")
            throw NeteaseAPIError.http(http.statusCode)
        }
        return data
    }

    static func cookieHeader(
        cookies: [String: String], extra: [String: String], overrides: [String: String]
    ) -> String {
        var values = cookies
        for (key, value) in extra where values[key] == nil { values[key] = value }
        values.merge(overrides) { _, override in override }
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
        var didChange = false
        if let musicU = values["MUSIC_U"], !musicU.isEmpty, musicU != cookies["MUSIC_U"] {
            cookieGeneration &+= 1
        }
        for (key, value) in values
        where !value.isEmpty && value != "\"\"" && value != cookies[key] {
            cookies[key] = value
            didChange = true
        }
        cookieLock.unlock()
        if didChange { persistCurrentCookies() }
    }

    static func cookieValues(from parsed: [HTTPCookie]) -> [String: String] {
        parsed.reduce(into: [:]) { values, cookie in
            values[cookie.name] = cookie.value
        }
    }

    private func persistCurrentCookies() {
        guard persistsAuthentication else { return }
        cookiePersistenceLock.lock()
        defer { cookiePersistenceLock.unlock() }
        cookieLock.lock()
        let snapshot = cookies
        cookieLock.unlock()

        if snapshot.isEmpty {
            AuthenticationCookieKeychain.remove()
            try? FileManager.default.removeItem(at: cookieFileURL)
            return
        }

        guard let data = AuthenticationCookieArchive.encode(snapshot) else { return }
        if AuthenticationCookieKeychain.write(data) {
            try? FileManager.default.removeItem(at: cookieFileURL)
        } else {
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
