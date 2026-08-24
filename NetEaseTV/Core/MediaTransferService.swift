import CryptoKit
import Foundation
import UIKit

struct CloudUploadRequest: Sendable {
    let sourceURL: URL
    let songName: String
    let artist: String
    let album: String
}

enum MediaTransferError: LocalizedError {
    case invalidHTTPSURL
    case invalidResponse
    case unsupportedAudioFile
    case fileTooLarge
    case imageTooLarge
    case invalidImage
    case incompleteUploadToken
    case uploadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPSURL: "请输入可直接下载的 HTTPS 链接"
        case .invalidResponse: "下载地址返回了无效响应"
        case .unsupportedAudioFile: "仅支持 MP3、FLAC、M4A、AAC、WAV 和 OGG 音频"
        case .fileTooLarge: "单个音频文件不能超过 500 MB"
        case .imageTooLarge: "封面图片不能超过 20 MB"
        case .invalidImage: "链接内容不是可识别的图片"
        case .incompleteUploadToken: "网易云没有返回完整上传凭证"
        case .uploadFailed(let status): "文件上传失败（\(status)）"
        }
    }
}

enum MediaTransferService {
    private static let audioBucket = "jd-musicrep-privatecloud-audio-public"
    private static let imageBucket = "yyimgs"
    private static let supportedAudioExtensions = Set(["mp3", "flac", "m4a", "aac", "wav", "ogg"])

    static func uploadCloudTrack(_ request: CloudUploadRequest) async throws {
        try validateHTTPS(request.sourceURL)
        let (temporaryURL, response) = try await transferSession.download(from: request.sourceURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try validate(response)

        let suggested = response.suggestedFilename ?? request.sourceURL.lastPathComponent
        let filename = sanitizedFilename(suggested.isEmpty ? "cloud-track.mp3" : suggested)
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard supportedAudioExtensions.contains(fileExtension) else {
            throw MediaTransferError.unsupportedAudioFile
        }
        let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        guard fileSize > 0, fileSize <= 500 * 1_024 * 1_024 else {
            throw MediaTransferError.fileTooLarge
        }
        let md5 = try await Task.detached { try md5Hex(of: temporaryURL) }.value
        let bitrate = 999_000
        async let checkRequest = NeteaseAPI.checkCloudUpload(
            md5: md5,
            fileSize: fileSize,
            bitrate: bitrate
        )
        async let tokenRequest = NeteaseAPI.allocateCloudUploadToken(
            md5: md5,
            filename: uploadAllocationName(for: filename),
            fileExtension: fileExtension
        )
        let (check, token) = try await (checkRequest, tokenRequest)
        guard !token.resourceID.isEmpty, !token.objectKey.isEmpty, !token.token.isEmpty else {
            throw MediaTransferError.incompleteUploadToken
        }

        if check.needUpload {
            let uploadBase = try await cloudUploadBaseURL()
            let objectKey = encodedObjectKey(token.objectKey)
            guard let uploadURL = URL(
                string: "\(uploadBase)/\(audioBucket)/\(objectKey)?offset=0&complete=true&version=1.0"
            ) else { throw MediaTransferError.invalidResponse }
            try await upload(
                fileURL: temporaryURL,
                to: uploadURL,
                headers: [
                    "x-nos-token": token.token,
                    "Content-MD5": md5,
                    "Content-Type": mimeType(for: fileExtension),
                    "Content-Length": String(fileSize),
                ]
            )
        }

        let fallbackName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        try await NeteaseAPI.completeCloudUpload(
            songID: check.songID,
            resourceID: token.resourceID,
            md5: md5,
            filename: filename,
            song: nonempty(request.songName, fallback: fallbackName),
            artist: nonempty(request.artist, fallback: "未知艺术家"),
            album: nonempty(request.album, fallback: "未知专辑"),
            bitrate: bitrate
        )
    }

    static func updatePlaylistCover(playlistID: Int, sourceURL: URL) async throws {
        try validateHTTPS(sourceURL)
        let (data, response) = try await transferSession.data(from: sourceURL)
        try validate(response)
        guard data.count <= 20 * 1_024 * 1_024 else { throw MediaTransferError.imageTooLarge }
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw MediaTransferError.invalidImage
        }
        let filename = "playlist-\(playlistID)-\(UUID().uuidString).jpg"
        let token = try await NeteaseAPI.allocatePlaylistImageToken(filename: filename)
        guard let documentID = token.documentID,
              !documentID.isEmpty,
              !token.objectKey.isEmpty,
              !token.token.isEmpty else {
            throw MediaTransferError.incompleteUploadToken
        }
        let objectKey = encodedObjectKey(token.objectKey)
        guard let uploadURL = URL(
            string: "https://nosup-hz1.127.net/\(imageBucket)/\(objectKey)?offset=0&complete=true&version=1.0"
        ) else { throw MediaTransferError.invalidResponse }
        try await upload(
            data: jpeg,
            to: uploadURL,
            headers: ["x-nos-token": token.token, "Content-Type": "image/jpeg"]
        )
        try await NeteaseAPI.updatePlaylistCover(id: playlistID, imageID: documentID)
    }

    private static let transferSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private static func validateHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw MediaTransferError.invalidHTTPSURL
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MediaTransferError.invalidResponse
        }
    }

    private static func cloudUploadBaseURL() async throws -> String {
        struct LBSResponse: Decodable { let upload: [String] }
        guard let url = URL(
            string: "https://wanproxy.127.net/lbs?version=1.0&bucketname=\(audioBucket)"
        ) else { throw MediaTransferError.invalidResponse }
        let (data, response) = try await transferSession.data(from: url)
        try validate(response)
        guard let raw = try JSONDecoder().decode(LBSResponse.self, from: data).upload.first else {
            throw MediaTransferError.invalidResponse
        }
        return raw.replacingOccurrences(of: "http://", with: "https://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func upload(
        fileURL: URL,
        to url: URL,
        headers: [String: String]
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await transferSession.upload(for: request, fromFile: fileURL)
        try validateUpload(response)
    }

    private static func upload(
        data: Data,
        to url: URL,
        headers: [String: String]
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await transferSession.upload(for: request, from: data)
        try validateUpload(response)
    }

    private static func validateUpload(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MediaTransferError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MediaTransferError.uploadFailed(http.statusCode)
        }
    }

    private static func md5Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func encodedObjectKey(_ value: String) -> String {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        return encoded.replacingOccurrences(of: "/", with: "%2F")
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let cleaned = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "cloud-track.mp3" : cleaned
    }

    private static func uploadAllocationName(for filename: String) -> String {
        URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "_")
    }

    private static func nonempty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension {
        case "flac": "audio/flac"
        case "m4a": "audio/mp4"
        case "aac": "audio/aac"
        case "wav": "audio/wav"
        case "ogg": "audio/ogg"
        default: "audio/mpeg"
        }
    }
}
