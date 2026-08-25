import Foundation
import SwiftUI
import UIKit

private actor RemoteImageRepository {
    static let shared = RemoteImageRepository()

    private let memoryCache: NSCache<NSURL, NSData>
    private let responseCache: URLCache
    private let session: URLSession
    private var inFlight: [URL: Task<Data, Error>] = [:]

    private init() {
        let memoryCache = NSCache<NSURL, NSData>()
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
        self.memoryCache = memoryCache

        let responseCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "netease-tv-artwork"
        )
        self.responseCache = responseCache

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = responseCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached as Data
        }
        if let existing = inFlight[url] {
            return try await existing.value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        let task = Task<Data, Error> { [responseCache, session] in
            if let cached = responseCache.cachedResponse(for: request) {
                return cached.data
            }

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard !data.isEmpty else { throw URLError(.zeroByteResource) }
            responseCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
                for: request
            )
            return data
        }
        inFlight[url] = task

        do {
            let data = try await task.value
            memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            inFlight[url] = nil
            return data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }
}

@MainActor
private final class DecodedRemoteImageCache {
    static let shared = DecodedRemoteImageCache()

    private let cache: NSCache<NSURL, UIImage>

    private init() {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 160 * 1_024 * 1_024
        self.cache = cache
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: url as NSURL, cost: max(1, Int(pixels * 4)))
    }
}

struct CachedRemoteImage<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    let content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty
    @State private var loadedURL: URL?

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(resolvedPhase)
            .task(id: url) {
                await load()
            }
    }

    @MainActor
    private var resolvedPhase: AsyncImagePhase {
        guard let url else { return .empty }
        if let image = DecodedRemoteImageCache.shared.image(for: url) {
            return .success(Image(uiImage: image))
        }
        return loadedURL == url ? phase : .empty
    }

    @MainActor
    private func load() async {
        guard let url else {
            loadedURL = nil
            phase = .empty
            return
        }
        loadedURL = url
        if let image = DecodedRemoteImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: image))
            return
        }

        phase = .empty
        do {
            let data = try await RemoteImageRepository.shared.data(for: url)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            DecodedRemoteImageCache.shared.insert(image, for: url)
            if reduceMotion {
                phase = .success(Image(uiImage: image))
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    phase = .success(Image(uiImage: image))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failure(error)
        }
    }
}

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 20
    var symbol = "music.note"

    var body: some View {
        GeometryReader { geometry in
            CachedRemoteImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    placeholder.overlay {
                        if url != nil {
                            ProgressView().tint(.white.opacity(0.75))
                        }
                    }
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [TVTheme.magenta.opacity(0.85), Color.indigo.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct MembershipStatusBadge: View {
    let label: String
    let isVIP: Bool
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            Image(systemName: isVIP ? "crown.fill" : "person.fill")
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: compact ? 16 : 18, weight: .semibold, design: .rounded))
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isVIP ? TVTheme.amber : Color.white.opacity(0.66))
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 4 : 6)
        .background((isVIP ? TVTheme.amber : Color.white).opacity(isVIP ? 0.14 : 0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke((isVIP ? TVTheme.amber : Color.white).opacity(isVIP ? 0.46 : 0.14), lineWidth: 1)
        }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(TVTheme.secondaryText)
            }
        }
        .padding(.horizontal, TVTheme.horizontalPadding)
    }
}

struct PlaylistCard: View {
    let playlist: PlaylistSummary
    var width: CGFloat = 265

    var body: some View {
        NavigationLink(value: AppRoute.playlist(playlist.id)) {
            VStack(alignment: .leading, spacing: 13) {
                ArtworkView(url: playlist.artworkURL)
                    .frame(width: width, height: width)
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text(DisplayFormatter.playCount(playlist.playCount))
                }
                .font(.caption)
                .opacity(0.62)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

struct AlbumCard: View {
    let album: AlbumSummary
    var width: CGFloat = 250

    var body: some View {
        NavigationLink(value: AppRoute.album(album.id)) {
            VStack(alignment: .leading, spacing: 12) {
                ArtworkView(url: album.artworkURL)
                    .frame(width: width, height: width)
                Text(album.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([album.artistNames, DisplayFormatter.year(album.publishTime)].compactMap { value in
                    value?.isEmpty == false ? value : nil
                }.joined(separator: " · "))
                    .font(.caption)
                    .opacity(0.62)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

struct ArtistCard: View {
    let artist: ArtistSummary
    var size: CGFloat = 220

    var body: some View {
        NavigationLink(value: AppRoute.artist(artist.id)) {
            VStack(spacing: 14) {
                ArtworkView(url: artist.artworkURL, cornerRadius: size / 2, symbol: "person.wave.2")
                    .frame(width: size, height: size)
                Text(artist.name)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
            }
            .frame(width: size)
        }
        .buttonStyle(TVCardButtonStyle(cornerRadius: 28))
    }
}

struct MVCard: View {
    let mv: MVSummary
    var width: CGFloat = 360
    var queue: [MVSummary] = []

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        NavigationLink(value: AppRoute.mv(mv.id)) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    ArtworkView(url: mv.artworkURL, cornerRadius: 18, symbol: "play.rectangle.fill")
                        .frame(width: width, height: height)
                    Circle()
                        .fill(.black.opacity(0.56))
                        .frame(width: 58, height: 58)
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .offset(x: 2)
                }
                Text(mv.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !mv.artistNames.isEmpty {
                        Text(mv.artistNames)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if mv.playCount > 0 {
                        Label(DisplayFormatter.playCount(mv.playCount), systemImage: "play.fill")
                    }
                    if mv.durationMS > 0 {
                        Text(DisplayFormatter.duration(mv.duration))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .opacity(0.62)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(TVCardButtonStyle(cornerRadius: 22))
        .simultaneousGesture(TapGesture().onEnded {
            MVPlaybackController.shared.configureQueue(queue.isEmpty ? [mv] : queue, startingAt: mv.id)
        })
    }
}

struct TrackCard: View {
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(\.nowPlayingFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.nowPlayingFocusRestorationID) private var focusRestorationID
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    let track: Track
    let tracks: [Track]
    let source: PlaySource
    var width: CGFloat = 250
    var focusBinding: FocusState<AnyHashable?>.Binding? = nil

    var body: some View {
        Button {
            player.play(tracks, source: source, startingAt: track)
            presentNowPlaying()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ArtworkView(url: track.artworkURL)
                    .frame(width: width, height: width)
                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artistNames)
                    .font(.caption)
                    .opacity(0.62)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(TVCardButtonStyle())
        .modifier(OptionalTrackFocus(target: AnyHashable(track.id), binding: focusBinding))
        .task(id: focusRestorationGeneration) { restoreFocusIfNeeded() }
        .contextMenu {
            Button("下一首播放") { player.playNext(track) }
            Button("添加到队列") { player.addToQueue(track) }
            if let playlistID = source.playlistID,
               playlistID == account.likedSongsPlaylist?.id,
               !track.noCopyright {
                Button("从这首开启心动模式") {
                    player.startIntelligence(from: track, playlistID: playlistID) {
                        presentNowPlaying()
                    }
                }
            }
            if !account.ownedPlaylists.isEmpty {
                Menu("添加到歌单") {
                    ForEach(account.ownedPlaylists) { playlist in
                        Button(playlist.name) {
                            Task { await account.add(track, to: playlist) }
                        }
                    }
                }
            }
            Button(account.isLiked(track) ? "取消喜欢" : "喜欢") {
                Task { await account.toggleLike(track) }
            }
        }
    }

    private func presentNowPlaying() {
        openNowPlaying?(AnyHashable(track.id))
    }

    @MainActor
    private func restoreFocusIfNeeded() {
        let target = AnyHashable(track.id)
        guard focusRestorationID == target, let focusBinding else { return }
        focusBinding.wrappedValue = target
    }
}

struct TrackRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(\.nowPlayingFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.nowPlayingFocusRestorationID) private var focusRestorationID
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    let track: Track
    let index: Int
    let tracks: [Track]
    let source: PlaySource
    var cloudMatchAction: (() -> Void)?
    var cloudDeleteAction: (() -> Void)?
    var focusBinding: FocusState<AnyHashable?>.Binding? = nil

    var body: some View {
        Button {
            player.play(tracks, source: source, startingAt: track)
            presentNowPlaying()
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    if player.currentTrack?.id == track.id && player.isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(TVTheme.accent)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    } else {
                        Text("\(index + 1)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .opacity(0.62)
                    }
                }
                .font(.system(size: 27, weight: .medium, design: .rounded).monospacedDigit())
                .frame(width: 56)

                ArtworkView(url: track.artworkURL, cornerRadius: 10)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        Text(track.name)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if track.fee == 1 {
                            Text("VIP")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(TVTheme.accent)
                                .overlay(Capsule().stroke(TVTheme.accent.opacity(0.7)))
                        }
                        if track.isPlaybackUnavailable {
                            Text(track.isCopyrightUnavailable ? "无版权" : "不可用")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(Color.gray)
                                .overlay(Capsule().stroke(Color.gray.opacity(0.58)))
                        }
                    }
                    Text(track.artistNames + (track.album.name.isEmpty ? "" : " · \(track.album.name)"))
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .opacity(0.62)
                        .lineLimit(1)
                }
                Spacer()
                Text(DisplayFormatter.duration(track.duration))
                    .font(.system(size: 24, weight: .regular, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .opacity(0.62)
            }
            .padding(.horizontal, 18)
            .frame(height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackRowButtonStyle())
        .modifier(OptionalTrackFocus(target: AnyHashable(track.id), binding: focusBinding))
        .task(id: focusRestorationGeneration) { restoreFocusIfNeeded() }
        .contextMenu {
            Button("立即播放") {
                player.play(tracks, source: source, startingAt: track)
                presentNowPlaying()
            }
            Button("下一首播放") { player.playNext(track) }
            Button("添加到队列") { player.addToQueue(track) }
            if let playlistID = source.playlistID,
               playlistID == account.likedSongsPlaylist?.id,
               !track.noCopyright {
                Button("从这首开启心动模式") {
                    player.startIntelligence(from: track, playlistID: playlistID) {
                        presentNowPlaying()
                    }
                }
            }
            if !account.ownedPlaylists.isEmpty {
                Menu("添加到歌单") {
                    ForEach(account.ownedPlaylists) { playlist in
                        Button(playlist.name) {
                            Task { await account.add(track, to: playlist) }
                        }
                    }
                }
            }
            Button(account.isLiked(track) ? "取消喜欢" : "喜欢") {
                Task { await account.toggleLike(track) }
            }
            if let playlistID = source.playlistID,
               let playlist = account.ownedPlaylists.first(where: { $0.id == playlistID }) {
                Button("从《\(playlist.name)》中移除", role: .destructive) {
                    Task { await account.remove(track, from: playlist) }
                }
            }
            if let cloudMatchAction {
                Button("匹配网易云歌曲", systemImage: "link") { cloudMatchAction() }
            }
            if let cloudDeleteAction {
                Button("从云盘删除", systemImage: "trash", role: .destructive) {
                    cloudDeleteAction()
                }
            }
        }
    }

    private func presentNowPlaying() {
        openNowPlaying?(AnyHashable(track.id))
    }

    @MainActor
    private func restoreFocusIfNeeded() {
        let target = AnyHashable(track.id)
        guard focusRestorationID == target, let focusBinding else { return }
        focusBinding.wrappedValue = target
    }
}

private struct OptionalTrackFocus: ViewModifier {
    let target: AnyHashable
    let binding: FocusState<AnyHashable?>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let binding {
            content.focused(binding, equals: target)
        } else {
            content
        }
    }
}

struct TrackRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Color.white : TVTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.95 : 0.08), lineWidth: isFocused ? 3 : 1)
            }
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .scaleEffect(isFocused && !reduceMotion ? 1.015 : (configuration.isPressed ? 0.99 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 18, y: 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

struct HorizontalShelf<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 34) {
                    content
                }
                .padding(.horizontal, TVTheme.horizontalPadding)
                .padding(.vertical, 24)
            }
        }
        .focusSection()
    }
}

enum AppRoute: Hashable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
    case mv(Int)
    case dailySongs
    case recents
    case cloud
    case settings
}
