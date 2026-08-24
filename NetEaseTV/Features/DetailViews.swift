import AVFoundation
import SwiftUI
import UIKit

struct DailySongsView: View {
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if !tracks.isEmpty {
                TrackCollectionView(
                    title: "每日歌曲推荐",
                    subtitle: "为你推荐",
                    description: "根据你的音乐口味生成，每天更新。",
                    artworkURL: nil,
                    metadata: "每天更新 · \(tracks.count) 首歌曲",
                    tracks: tracks,
                    source: .daily
                )
            } else if isLoading {
                LoadStateView(title: "正在生成今日推荐")
            } else {
                LoadStateView(title: "暂时无法载入每日推荐", message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .background(TVBackground(tint: TVTheme.magenta))
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let result = try await NeteaseAPI.dailySongs()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            tracks = result
            if tracks.isEmpty {
                errorMessage = "今天还没有可播放的推荐歌曲"
            }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

struct PlaylistDetailView: View {
    let playlistID: Int

    @Environment(AccountStore.self) private var account
    @State private var detail: PlaylistDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0
    @State private var showEditor = false

    var body: some View {
        Group {
            if let detail {
                TrackCollectionView(
                    title: detail.name,
                    subtitle: detail.creator?.nickname,
                    description: detail.description,
                    artworkURL: detail.artworkURL,
                    metadata: "\(detail.trackCount) 首歌曲 · \(DisplayFormatter.playCount(detail.playCount)) 次播放",
                    tracks: detail.tracks,
                    source: .playlist(detail.id),
                    collectionActionTitle: playlistActionTitle(for: detail),
                    collectionActionSymbol: account.containsPlaylist(id: detail.id) ? "minus" : "plus",
                    collectionAction: canManageSubscription(detail) ? {
                        Task { await account.togglePlaylistSubscription(id: detail.id, name: detail.name) }
                    } : nil,
                    managementActionTitle: account.ownsPlaylist(id: detail.id) ? "编辑资料" : nil,
                    managementActionSymbol: "pencil",
                    managementAction: account.ownsPlaylist(id: detail.id) ? {
                        showEditor = true
                    } : nil
                )
            } else if isLoading {
                LoadStateView(title: "正在载入歌单")
            } else {
                LoadStateView(title: "无法打开歌单", message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .background(TVBackground(tint: TVTheme.accent))
        .task(id: account.playlistRevision) { await load() }
        .fullScreenCover(isPresented: $showEditor) {
            if let detail {
                PlaylistEditView(detail: detail)
            }
        }
    }

    private func canManageSubscription(_ detail: PlaylistDetail) -> Bool {
        account.isLoggedIn
            && detail.creator?.userId != account.profile?.userId
            && account.likedSongsPlaylist?.id != detail.id
    }

    private func playlistActionTitle(for detail: PlaylistDetail) -> String? {
        guard canManageSubscription(detail) else { return nil }
        return account.containsPlaylist(id: detail.id) ? "取消收藏" : "收藏歌单"
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let result = try await NeteaseAPI.playlist(id: playlistID).playlist
            guard generation == loadGeneration, !Task.isCancelled else { return }
            detail = result
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

struct AlbumDetailView: View {
    let albumID: Int

    @Environment(AccountStore.self) private var account
    @State private var response: AlbumDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if let response {
                TrackCollectionView(
                    title: response.album.name,
                    subtitle: response.album.artistNames,
                    description: response.album.description,
                    artworkURL: response.album.artworkURL,
                    metadata: [DisplayFormatter.year(response.album.publishTime), "\(response.songs.count) 首歌曲"]
                        .compactMap { $0 }.joined(separator: " · "),
                    tracks: response.songs,
                    source: .album(response.album.id),
                    collectionActionTitle: account.isAlbumLiked(response.album) ? "取消收藏" : "收藏专辑",
                    collectionActionSymbol: account.isAlbumLiked(response.album) ? "minus" : "plus",
                    collectionAction: account.isLoggedIn ? {
                        Task { await account.toggleAlbum(response.album) }
                    } : nil
                )
            } else if isLoading {
                LoadStateView(title: "正在载入专辑")
            } else {
                LoadStateView(title: "无法打开专辑", message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .background(TVBackground(tint: .purple))
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let result = try await NeteaseAPI.album(id: albumID)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            response = result
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

struct ArtistDetailView: View {
    let artistID: Int

    @Environment(AccountStore.self) private var account
    @State private var response: NeteaseAPI.ArtistResponse?
    @State private var albums: [AlbumSummary] = []
    @State private var mvs: [MVSummary] = []
    @State private var similarArtists: [ArtistSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if let response {
                TrackCollectionView(
                    title: response.artist.name,
                    subtitle: response.artist.alias.first,
                    description: response.artist.briefDesc,
                    artworkURL: response.artist.artworkURL,
                    metadata: [
                        "热门歌曲 · \(response.hotSongs.count) 首",
                        "\(albums.count) 张专辑",
                        mvs.isEmpty ? nil : "\(mvs.count) 支 MV",
                    ].compactMap { $0 }.joined(separator: " · "),
                    tracks: response.hotSongs,
                    source: .artist(response.artist.id),
                    circularArtwork: true,
                    collectionActionTitle: account.isArtistLiked(response.artist) ? "取消关注" : "关注歌手",
                    collectionActionSymbol: account.isArtistLiked(response.artist) ? "minus" : "plus",
                    collectionAction: account.isLoggedIn ? {
                        Task { await account.toggleArtist(response.artist) }
                    } : nil,
                    relatedAlbums: albums,
                    relatedMVs: mvs,
                    relatedArtists: similarArtists
                )
            } else if isLoading {
                LoadStateView(title: "正在载入歌手")
            } else {
                LoadStateView(title: "无法打开歌手", message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .background(TVBackground(tint: .blue))
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        async let albumRequest = try? NeteaseAPI.artistAlbums(id: artistID)
        async let mvRequest = try? NeteaseAPI.artistMVs(id: artistID)
        async let similarRequest = try? NeteaseAPI.similarArtists(id: artistID)
        do {
            let detail = try await NeteaseAPI.artist(id: artistID)
            let albumResult = (await albumRequest)?.hotAlbums ?? []
            let mvResult = (await mvRequest)?.mvs ?? []
            let artistResult = await similarRequest ?? []
            guard generation == loadGeneration, !Task.isCancelled else { return }
            albums = albumResult
            mvs = mvResult
            similarArtists = artistResult
            response = detail
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

@MainActor
@Observable
final class MVPlaybackController {
    private enum StreamResult: Sendable {
        case success(URL, Int)
        case failure(String)
    }

    static let shared = MVPlaybackController()

    private(set) var activeMVID: Int?
    private(set) var player: AVPlayer?
    private(set) var isPreparing = false
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    private(set) var servedResolution: Int?

    private weak var audioPlayer: PlayerService?
    private var requestGeneration = 0

    func activate(mvID: Int) {
        guard activeMVID != mvID else { return }
        resetPlayback()
        activeMVID = mvID
    }

    func stop(mvID: Int) {
        guard activeMVID == mvID else { return }
        resetPlayback()
        activeMVID = nil
    }

    func prepare(detail: MVSummary, audioPlayer: PlayerService) {
        guard activeMVID == detail.id, !isPreparing else { return }
        self.audioPlayer = audioPlayer
        requestGeneration &+= 1
        let generation = requestGeneration
        isPreparing = true
        errorMessage = nil

        var seen = Set<Int>()
        let resolutions = (detail.availableResolutions.filter { $0 <= 1_080 } + [1_080, 720, 480, 240])
            .filter { seen.insert($0).inserted }
        let id = detail.id
        Task.detached(priority: .userInitiated) {
            let result = await Self.resolveStream(mvID: id, resolutions: resolutions)
            await MainActor.run {
                Self.shared.apply(result, mvID: id, generation: generation)
            }
        }
    }

    func toggle(audioPlayer: PlayerService) {
        guard let player else { return }
        self.audioPlayer = audioPlayer
        if isPlaying {
            player.pause()
        } else {
            pauseAudioIfNeeded()
            player.play()
        }
        isPlaying.toggle()
    }

    func didReachEnd(item: AnyObject?) {
        guard item === player?.currentItem else { return }
        isPlaying = false
        player?.seek(to: .zero)
    }

    nonisolated private static func resolveStream(mvID: Int, resolutions: [Int]) async -> StreamResult {
        var lastErrorMessage: String?
        for resolution in resolutions {
            do {
                let response = try await NeteaseAPI.mvURL(id: mvID, resolution: resolution)
                if let url = response.streamURL {
                    return .success(url, response.resolution ?? resolution)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        return .failure(lastErrorMessage ?? "当前 MV 暂时没有可用的播放地址")
    }

    private func apply(_ result: StreamResult, mvID: Int, generation: Int) {
        guard activeMVID == mvID, requestGeneration == generation else { return }
        isPreparing = false
        switch result {
        case .success(let url, let resolution):
            let videoPlayer = AVPlayer(url: url)
            pauseAudioIfNeeded()
            player = videoPlayer
            servedResolution = resolution
            isPlaying = true
            videoPlayer.play()
        case .failure(let message):
            errorMessage = message
        }
    }

    private func pauseAudioIfNeeded() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
        }
    }

    private func resetPlayback() {
        requestGeneration &+= 1
        player?.pause()
        player = nil
        isPreparing = false
        isPlaying = false
        errorMessage = nil
        servedResolution = nil
        audioPlayer = nil
    }
}

struct MVDetailView: View {
    let mvID: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.handlesNavigationExit) private var handlesNavigationExit
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerService.self) private var audioPlayer
    private let mvPlayback = MVPlaybackController.shared
    @State private var detail: MVSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    private var videoPlayer: AVPlayer? {
        mvPlayback.activeMVID == mvID ? mvPlayback.player : nil
    }

    var body: some View {
        ZStack {
            if let detail {
                ScrollView {
                    HStack(alignment: .top, spacing: 44) {
                        videoStage(detail)
                            .frame(width: 1_080, height: 608)

                        metadataPanel(detail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, TVTheme.horizontalPadding)
                    .padding(.top, 40)
                    .padding(.bottom, 80)
                }
            } else if isLoading {
                LoadStateView(title: "正在载入音乐视频")
            } else {
                LoadStateView(title: "无法打开音乐视频", message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .background(TVBackground(tint: TVTheme.magenta))
        .task(id: mvID) { await load() }
        .onAppear { mvPlayback.activate(mvID: mvID) }
        .modifier(
            MVExitCommand(isActive: !handlesNavigationExit) {
                mvPlayback.stop(mvID: mvID)
                dismiss()
            }
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { mvPlayback.stop(mvID: mvID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            mvPlayback.didReachEnd(item: notification.object as AnyObject?)
        }
        .modifier(
            MVPlayPauseCommand(isActive: videoPlayer != nil) {
                mvPlayback.toggle(audioPlayer: audioPlayer)
            }
        )
    }

    @ViewBuilder
    private func videoStage(_ detail: MVSummary) -> some View {
        ZStack {
            if let videoPlayer {
                InlineMVPlayer(player: videoPlayer)
                    .background(.black)
            } else {
                ArtworkView(url: detail.artworkURL, cornerRadius: 28, symbol: "play.rectangle.fill")
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
            }

            if mvPlayback.activeMVID == mvID, mvPlayback.isPreparing {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在准备视频")
                        .font(.headline)
                }
                .padding(28)
                .glassPanel(cornerRadius: 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 34, y: 18)
        .accessibilityLabel("\(detail.name) 视频")
    }

    private func metadataPanel(_ detail: MVSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("音乐视频")
                .font(.subheadline.bold())
                .tracking(1.4)
                .foregroundStyle(TVTheme.accent)

            Text(detail.name)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .lineLimit(3)
                .minimumScaleFactor(0.72)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    if detail.durationMS > 0 {
                        Label(DisplayFormatter.duration(detail.duration), systemImage: "clock")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if detail.playCount > 0 {
                        Label(DisplayFormatter.playCount(detail.playCount), systemImage: "play.fill")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                if let publishTime = detail.publishTime, !publishTime.isEmpty {
                    Label(publishTime, systemImage: "calendar")
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.headline)
            .foregroundStyle(TVTheme.secondaryText)

            Button {
                if videoPlayer == nil {
                    mvPlayback.prepare(detail: detail, audioPlayer: audioPlayer)
                } else {
                    mvPlayback.toggle(audioPlayer: audioPlayer)
                }
            } label: {
                if mvPlayback.isPreparing {
                    Label("正在准备", systemImage: "hourglass")
                } else {
                    Label(
                        videoPlayer == nil ? "播放 MV" : (mvPlayback.isPlaying ? "暂停" : "继续播放"),
                        systemImage: videoPlayer == nil ? "play.fill" : (mvPlayback.isPlaying ? "pause.fill" : "play.fill")
                    )
                }
            }
            .buttonStyle(TVPillButtonStyle(prominent: true))
            .disabled(mvPlayback.isPreparing)

            if let servedResolution = mvPlayback.servedResolution {
                Label("\(servedResolution)p", systemImage: "tv")
                    .font(.subheadline.bold())
                    .foregroundStyle(TVTheme.secondaryText)
            }

            if !detail.artists.isEmpty {
                HStack(spacing: 10) {
                    ForEach(detail.artists.prefix(3)) { artist in
                        if artist.id > 0 {
                            NavigationLink(value: AppRoute.artist(artist.id)) {
                                Text(artist.name)
                            }
                            .buttonStyle(TVPillButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded {
                                mvPlayback.stop(mvID: mvID)
                            })
                        } else {
                            Text(artist.name)
                                .font(.headline)
                                .foregroundStyle(TVTheme.secondaryText)
                        }
                    }
                }
            }

            if let videoErrorMessage = mvPlayback.errorMessage {
                Label(videoErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let description = displayDescription(detail) {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(8)
                    .lineSpacing(5)
            }

            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let response = try await NeteaseAPI.mvDetail(id: mvID)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            detail = response
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            detail = nil
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    private func displayDescription(_ detail: MVSummary) -> String? {
        [detail.description, detail.briefDesc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

}

private struct MVPlayPauseCommand: ViewModifier {
    let isActive: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.onPlayPauseCommand(perform: action)
        } else {
            content
        }
    }
}

private struct MVExitCommand: ViewModifier {
    let isActive: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.onExitCommand(perform: action)
        } else {
            content
        }
    }
}

private final class InlineMVPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct InlineMVPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> InlineMVPlayerView {
        let view = InlineMVPlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: InlineMVPlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: InlineMVPlayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

private struct TrackCollectionView: View {
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(\.navigationFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.navigationFocusRestorationRoute) private var focusRestorationRoute
    let title: String
    let subtitle: String?
    let description: String?
    let artworkURL: URL?
    let metadata: String
    let tracks: [Track]
    let source: PlaySource
    var circularArtwork = false
    var collectionActionTitle: String?
    var collectionActionSymbol = "plus"
    var collectionAction: (() -> Void)?
    var managementActionTitle: String?
    var managementActionSymbol = "ellipsis"
    var managementAction: (() -> Void)?
    var relatedAlbums: [AlbumSummary] = []
    var relatedMVs: [MVSummary] = []
    var relatedArtists: [ArtistSummary] = []

    @Environment(PlayerService.self) private var player
    @Environment(AccountStore.self) private var account
    @State private var lastFocusedRoute: AppRoute?
    @FocusState private var focusedRoute: AppRoute?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                HStack(alignment: .bottom, spacing: 42) {
                    ArtworkView(
                        url: artworkURL,
                        cornerRadius: circularArtwork ? 165 : 26,
                        symbol: circularArtwork ? "person.wave.2.fill" : "music.note"
                    )
                    .frame(width: 330, height: 330)
                    .shadow(color: .black.opacity(0.38), radius: 30, y: 16)

                    VStack(alignment: .leading, spacing: 16) {
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle.uppercased())
                                .font(.subheadline.bold())
                                .tracking(1.3)
                                .foregroundStyle(TVTheme.accent)
                                .lineLimit(1)
                        }
                        Text(title)
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .lineLimit(2)
                        Text(metadata)
                            .font(.headline)
                            .foregroundStyle(TVTheme.secondaryText)
                            .lineLimit(1)
                        if let description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(3)
                                .lineSpacing(5)
                                .frame(maxWidth: 900, alignment: .leading)
                        }
                        HStack(spacing: 18) {
                            Button {
                                player.play(tracks, source: source)
                                openNowPlaying?()
                            } label: {
                                Label("播放", systemImage: "play.fill")
                            }
                            .buttonStyle(TVPillButtonStyle(prominent: true))
                            .disabled(tracks.isEmpty)

                            Button {
                                player.playShuffled(tracks, source: source)
                                openNowPlaying?()
                            } label: {
                                Label("随机播放", systemImage: "shuffle")
                            }
                            .buttonStyle(TVPillButtonStyle())
                            .disabled(tracks.isEmpty)

                            if let playlistID = source.playlistID,
                               playlistID == account.likedSongsPlaylist?.id,
                               let first = tracks.first(where: { !$0.noCopyright }) {
                                Button {
                                    player.startIntelligence(from: first, playlistID: playlistID) {
                                        openNowPlaying?()
                                    }
                                } label: {
                                    Label("心动模式", systemImage: "heart.fill")
                                }
                                .buttonStyle(TVPillButtonStyle())
                            }

                            if let collectionActionTitle, let collectionAction {
                                Button(action: collectionAction) {
                                    Label(collectionActionTitle, systemImage: collectionActionSymbol)
                                }
                                .buttonStyle(TVPillButtonStyle())
                            }

                            if let managementActionTitle, let managementAction {
                                Button(action: managementAction) {
                                    Label(managementActionTitle, systemImage: managementActionSymbol)
                                }
                                .buttonStyle(TVPillButtonStyle())
                            }

                        }
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    Spacer()
                }
                .focusSection()
                .padding(.horizontal, TVTheme.horizontalPadding)
                .padding(.top, 34)

                if tracks.isEmpty {
                    EmptyStateView(
                        title: "暂无可播放歌曲",
                        message: "内容可能受版权或地区限制。",
                        symbol: "music.note.slash"
                    )
                    .frame(height: 260)
                    .padding(.horizontal, TVTheme.horizontalPadding)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                index: index,
                                tracks: tracks,
                                source: source
                            )
                        }
                    }
                    .padding(.horizontal, TVTheme.horizontalPadding)
                    .padding(.bottom, 80)
                    .focusSection()
                }

                if !relatedAlbums.isEmpty {
                    HorizontalShelf(title: "专辑", subtitle: "完整作品目录") {
                        ForEach(relatedAlbums) { album in
                            AlbumCard(album: album)
                                .focused($focusedRoute, equals: .album(album.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .album(album.id)
                                })
                        }
                    }
                }

                if !relatedMVs.isEmpty {
                    HorizontalShelf(title: "音乐视频", subtitle: "来自这位歌手的 MV") {
                        ForEach(relatedMVs) { mv in
                            MVCard(mv: mv)
                                .focused($focusedRoute, equals: .mv(mv.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .mv(mv.id)
                                })
                        }
                    }
                }

                if !relatedArtists.isEmpty {
                    HorizontalShelf(title: "相似歌手") {
                        ForEach(relatedArtists) { artist in
                            ArtistCard(artist: artist)
                                .focused($focusedRoute, equals: .artist(artist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .artist(artist.id)
                                })
                        }
                    }
                }
            }
        }
        .onChange(of: focusedRoute) { _, route in
            if let route { lastFocusedRoute = route }
        }
        .task(id: focusRestorationGeneration) { await restoreNavigationFocus() }
    }

    @MainActor
    private func restoreNavigationFocus() async {
        guard let route = focusRestorationRoute ?? lastFocusedRoute else { return }
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        lastFocusedRoute = route
        focusedRoute = route
    }
}
