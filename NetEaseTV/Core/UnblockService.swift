import CryptoKit
import Foundation

/// Resolves an alternate stream only after the account's NetEase playback URL
/// is unavailable or limited to a trial fragment. The provider protocol and
/// matching order are independently implemented from the references listed in
/// THIRD_PARTY_NOTICES.md.
enum UnblockService {
    struct Resolved: Sendable {
        let url: URL
        let source: String
    }

    static func resolve(_ track: Track) async -> Resolved? {
        if let url = await pyncmd(track) {
            return Resolved(url: url, source: "GD 音乐台")
        }
        guard !Task.isCancelled else { return nil }
        if let url = await kuwo(track) {
            return Resolved(url: url, source: "酷我音乐")
        }
        guard !Task.isCancelled else { return nil }
        if let url = await kugou(track) {
            return Resolved(url: url, source: "酷狗音乐")
        }
        return nil
    }

    static func preferredMatchIndex(durationsMS: [Int], targetDurationMS: Int) -> Int? {
        guard !durationsMS.isEmpty else { return nil }
        return durationsMS.prefix(5).firstIndex {
            $0 > 0 && abs($0 - targetDurationMS) < 5_000
        } ?? durationsMS.indices.first
    }

    private static func keyword(for track: Track) -> String {
        "\(track.name) \(track.artists.first?.name ?? "")"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func encoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func get(_ urlString: String, userAgent: String = "Mozilla/5.0") async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func secureURL(_ raw: String) -> URL? {
        URL(string: raw.replacingOccurrences(of: "http://", with: "https://"))
    }

    // MARK: GD Music API

    private static func pyncmd(_ track: Track) async -> URL? {
        let endpoint = "https://music-api.gdstudio.xyz/api.php?types=url&source=netease&id=\(track.id)&br=320"
        guard let data = await get(endpoint),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawURL = object["url"] as? String,
              !rawURL.isEmpty else { return nil }
        let bitrate = (object["br"] as? NSNumber)?.intValue
            ?? (object["br"] as? String).flatMap(Int.init)
            ?? 0
        guard bitrate > 0 else { return nil }
        return secureURL(rawURL)
    }

    // MARK: Kuwo

    private static func kuwo(_ track: Track) async -> URL? {
        let query = encoded(keyword(for: track))
        let endpoint = "https://search.kuwo.cn/r.s?correct=1&vipver=1&stype=comprehensive&encoding=utf8"
            + "&rformat=json&mobi=1&show_copyright_off=1&searchapi=6&all=\(query)"
        guard let data = await get(endpoint),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]], content.count > 1,
              let page = content[1]["musicpage"] as? [String: Any],
              let rawSongs = page["abslist"] as? [[String: Any]], !rawSongs.isEmpty else { return nil }

        let songs: [(id: String, durationMS: Int)] = rawSongs.compactMap { item in
            guard let musicID = item["MUSICRID"] as? String,
                  let id = musicID.components(separatedBy: "_").last,
                  !id.isEmpty else { return nil }
            let seconds = (item["DURATION"] as? NSNumber)?.intValue
                ?? (item["DURATION"] as? String).flatMap(Int.init)
                ?? 0
            return (id, seconds * 1_000)
        }
        guard let index = preferredMatchIndex(
            durationsMS: songs.map(\.durationMS),
            targetDurationMS: track.durationMS
        ) else { return nil }
        let convert = "https://antiserver.kuwo.cn/anti.s?type=convert_url&format=mp3&response=url"
            + "&rid=MUSIC_\(songs[index].id)"
        guard let data = await get(convert, userAgent: "okhttp/3.10.0"),
              let body = String(data: data, encoding: .utf8),
              let range = body.range(of: #"https?[^\s$\"]+"#, options: .regularExpression) else { return nil }
        return secureURL(String(body[range]))
    }

    // MARK: Kugou

    private static func kugou(_ track: Track) async -> URL? {
        let query = encoded(keyword(for: track))
        let endpoint = "https://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=\(query)&page=1&pagesize=10"
        guard let data = await get(endpoint),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = object["data"] as? [String: Any],
              let rawSongs = body["info"] as? [[String: Any]], !rawSongs.isEmpty else { return nil }

        let songs: [(hash: String, albumID: String, durationMS: Int)] = rawSongs.compactMap { item in
            guard let hash = item["hash"] as? String, !hash.isEmpty else { return nil }
            let albumID = (item["album_id"] as? String)
                ?? (item["album_id"] as? NSNumber).map(\.stringValue)
                ?? "0"
            let seconds = (item["duration"] as? NSNumber)?.intValue
                ?? (item["duration"] as? String).flatMap(Int.init)
                ?? 0
            return (hash, albumID, seconds * 1_000)
        }
        guard let index = preferredMatchIndex(
            durationsMS: songs.map(\.durationMS),
            targetDurationMS: track.durationMS
        ) else { return nil }
        let song = songs[index]
        let key = Insecure.MD5.hash(data: Data("\(song.hash)kgcloudv2".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let tracker = "https://trackercdn.kugou.com/i/v2/?key=\(key)&hash=\(song.hash)"
            + "&appid=1005&pid=2&cmd=25&behavior=play&album_id=\(song.albumID)"
        guard let data = await get(tracker),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rawURL = (object["url"] as? [String])?.first ?? (object["url"] as? String)
        guard let rawURL, !rawURL.isEmpty else { return nil }
        return secureURL(rawURL)
    }
}
