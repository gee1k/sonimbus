import AVFoundation
import AVKit
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
                    artworkURL: tracks.first?.artworkURL,
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

    private static let autoplayDefaultsKey = "mv.autoplay.enabled"

    private(set) var activeMVID: Int?
    private(set) var player: AVPlayer?
    private(set) var isPreparing = false
    private(set) var isPlaying = false
    private(set) var errorMessage: String?
    private(set) var servedResolution: Int?
    private(set) var queue: [MVSummary] = []
    private(set) var currentDetail: MVSummary?
    private(set) var currentQueueIndex: Int?
    private(set) var autoplayEnabled: Bool

    private weak var audioPlayer: PlayerService?
    private var requestGeneration = 0
    private var timeControlObservation: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoplayDefaultsKey) == nil {
            autoplayEnabled = true
        } else {
            autoplayEnabled = defaults.bool(forKey: Self.autoplayDefaultsKey)
        }
    }

    var canSkip: Bool { queue.count > 1 && currentQueueIndex != nil }

    var nextSummary: MVSummary? {
        adjacentSummary(offset: 1)
    }

    func configureQueue(_ videos: [MVSummary], startingAt mvID: Int) {
        let uniqueVideos = MVQueuePolicy.deduplicated(videos)
        guard let index = uniqueVideos.firstIndex(where: { $0.id == mvID }) else { return }
        queue = uniqueVideos
        currentQueueIndex = index
        currentDetail = uniqueVideos[index]
    }

    func enrichQueue(_ videos: [MVSummary], around detail: MVSummary) {
        guard queue.count <= 1, activeMVID == detail.id else { return }
        let uniqueVideos = MVQueuePolicy.deduplicated([detail] + videos)
        configureQueue(uniqueVideos, startingAt: detail.id)
        replaceCurrentSummary(with: detail)
    }

    func activate(mvID: Int) {
        guard activeMVID != mvID else { return }
        if let activeMVID,
           queue.contains(where: { $0.id == activeMVID }),
           queue.contains(where: { $0.id == mvID }) {
            return
        }
        resetPlayback()
        activeMVID = mvID
        if let index = queue.firstIndex(where: { $0.id == mvID }) {
            currentQueueIndex = index
            currentDetail = queue[index]
        } else {
            queue = []
            currentQueueIndex = nil
            currentDetail = nil
        }
    }

    func stop() {
        resetPlayback()
        activeMVID = nil
        queue = []
        currentDetail = nil
        currentQueueIndex = nil
    }

    func prepare(detail: MVSummary, audioPlayer: PlayerService) {
        if activeMVID != detail.id { activate(mvID: detail.id) }
        guard !isPreparing, player == nil else { return }
        self.audioPlayer = audioPlayer
        if let index = queue.firstIndex(where: { $0.id == detail.id }) {
            currentQueueIndex = index
            currentDetail = detail
            queue[index] = detail
        } else {
            configureQueue([detail], startingAt: detail.id)
        }
        beginPreparing(detail: detail)
    }

    func playNext(audioPlayer: PlayerService? = nil) {
        playAdjacent(offset: 1, audioPlayer: audioPlayer)
    }

    func playPrevious(audioPlayer: PlayerService? = nil) {
        if let currentTime = player?.currentTime().seconds,
           currentTime.isFinite,
           currentTime > 5 {
            player?.seek(to: .zero)
            player?.play()
            isPlaying = true
            return
        }
        playAdjacent(offset: -1, audioPlayer: audioPlayer)
    }

    func toggleAutoplay() {
        autoplayEnabled.toggle()
        UserDefaults.standard.set(autoplayEnabled, forKey: Self.autoplayDefaultsKey)
    }

    func toggle(audioPlayer: PlayerService) {
        guard let player else { return }
        self.audioPlayer = audioPlayer
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            pauseAudioIfNeeded()
            player.play()
            isPlaying = true
        }
    }

    func didReachEnd(item: AnyObject?) {
        guard item === player?.currentItem else { return }
        if autoplayEnabled, canSkip {
            playNext()
        } else {
            isPlaying = false
            player?.seek(to: .zero)
        }
    }

    private func beginPreparing(detail: MVSummary) {
        requestGeneration &+= 1
        let generation = requestGeneration
        isPreparing = true
        errorMessage = nil
        servedResolution = nil

        var seen = Set<Int>()
        let resolutions = (detail.availableResolutions.filter { $0 <= 1_080 } + [1_080, 720, 480, 240])
            .filter { seen.insert($0).inserted }
        let id = detail.id
        Task.detached(priority: .userInitiated) {
            let result = await Self.resolveStream(mvID: id, resolutions: resolutions)
            await MainActor.run {
                Self.shared.apply(result, detail: detail, generation: generation)
            }
        }
    }

    private func playAdjacent(offset: Int, audioPlayer: PlayerService?) {
        if let audioPlayer { self.audioPlayer = audioPlayer }
        guard let currentQueueIndex,
              let nextIndex = MVQueuePolicy.adjacentIndex(
                from: currentQueueIndex,
                count: queue.count,
                offset: offset
              ) else { return }
        playQueueItem(at: nextIndex)
    }

    private func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let summary = queue[index]
        resetPlayback(clearAudioPlayer: false)
        activeMVID = summary.id
        currentQueueIndex = index
        currentDetail = summary
        isPreparing = true
        errorMessage = nil
        let generation = requestGeneration

        Task { @MainActor [weak self] in
            let detail = (try? await NeteaseAPI.mvDetail(id: summary.id)) ?? summary
            guard let self,
                  requestGeneration == generation,
                  activeMVID == summary.id else { return }
            replaceCurrentSummary(with: detail)
            beginPreparing(detail: detail)
        }
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

    private func apply(_ result: StreamResult, detail: MVSummary, generation: Int) {
        guard activeMVID == detail.id, requestGeneration == generation else { return }
        isPreparing = false
        switch result {
        case .success(let url, let resolution):
            let item = AVPlayerItem(url: url)
            item.externalMetadata = Self.externalMetadata(for: detail)
            let videoPlayer = AVPlayer(playerItem: item)
            pauseAudioIfNeeded()
            player = videoPlayer
            servedResolution = resolution
            isPlaying = true
            timeControlObservation = videoPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
                Task { @MainActor in
                    guard Self.shared.player === player else { return }
                    Self.shared.isPlaying = player.timeControlStatus == .playing
                }
            }
            videoPlayer.play()
        case .failure(let message):
            errorMessage = message
        }
    }

    private func adjacentSummary(offset: Int) -> MVSummary? {
        guard let currentQueueIndex,
              let index = MVQueuePolicy.adjacentIndex(
                from: currentQueueIndex,
                count: queue.count,
                offset: offset
              ) else { return nil }
        return queue[index]
    }

    private func replaceCurrentSummary(with detail: MVSummary) {
        currentDetail = detail
        if let currentQueueIndex, queue.indices.contains(currentQueueIndex) {
            queue[currentQueueIndex] = detail
        }
    }

    private static func externalMetadata(for detail: MVSummary) -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = detail.name as NSString
        title.extendedLanguageTag = "zh-CN"
        metadata.append(title)

        if !detail.artistNames.isEmpty {
            let subtitle = AVMutableMetadataItem()
            subtitle.identifier = .iTunesMetadataTrackSubTitle
            subtitle.value = detail.artistNames as NSString
            subtitle.extendedLanguageTag = "zh-CN"
            metadata.append(subtitle)
        }
        return metadata
    }

    private func pauseAudioIfNeeded() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
        }
    }

    private func resetPlayback(clearAudioPlayer: Bool = true) {
        requestGeneration &+= 1
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        player?.pause()
        player = nil
        isPreparing = false
        isPlaying = false
        errorMessage = nil
        servedResolution = nil
        if clearAudioPlayer { audioPlayer = nil }
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
    @State private var showsFullscreenPlayer = false

    private var videoPlayer: AVPlayer? {
        mvPlayback.player
    }

    private var displayedDetail: MVSummary? {
        mvPlayback.currentDetail ?? detail
    }

    var body: some View {
        ZStack {
            if let detail = displayedDetail {
                ScrollView {
                    HStack(alignment: .top, spacing: 44) {
                        videoStageButton(detail)
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
                mvPlayback.stop()
                dismiss()
            }
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { mvPlayback.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            mvPlayback.didReachEnd(item: notification.object as AnyObject?)
        }
        .modifier(
            MVPlayPauseCommand(isActive: videoPlayer != nil) {
                mvPlayback.toggle(audioPlayer: audioPlayer)
            }
        )
        .fullScreenCover(isPresented: $showsFullscreenPlayer) {
            if let detail = displayedDetail {
                MVFullscreenPlayer(detail: detail) {
                    showsFullscreenPlayer = false
                }
            }
        }
    }

    @ViewBuilder
    private func videoStageButton(_ detail: MVSummary) -> some View {
        Button {
            openFullscreen(detail)
        } label: {
            ZStack(alignment: .bottomTrailing) {
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

                    if mvPlayback.isPreparing {
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

                Label(videoPlayer == nil ? "播放并全屏" : "进入全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.headline.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassPanel(cornerRadius: 18)
                    .padding(22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(MVVideoStageButtonStyle())
        .accessibilityLabel(videoPlayer == nil ? "播放 \(detail.name) 并进入全屏" : "全屏播放 \(detail.name)")
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

            HStack(spacing: 14) {
                Button {
                    if videoPlayer == nil {
                        openFullscreen(detail)
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

                if videoPlayer != nil {
                    Button {
                        showsFullscreenPlayer = true
                    } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
            }

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
                                mvPlayback.stop()
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
        mvPlayback.activate(mvID: mvID)
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let response = try await NeteaseAPI.mvDetail(id: mvID)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            detail = response
            mvPlayback.enrichQueue([], around: response)
            if mvPlayback.queue.count <= 1,
               let artistID = response.artists.first(where: { $0.id > 0 })?.id,
               let related = (try? await NeteaseAPI.artistMVs(id: artistID, limit: 50))?.mvs {
                guard generation == loadGeneration, !Task.isCancelled else { return }
                mvPlayback.enrichQueue(related, around: response)
            }
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

    private func openFullscreen(_ detail: MVSummary) {
        if videoPlayer == nil, !mvPlayback.isPreparing {
            mvPlayback.prepare(detail: detail, audioPlayer: audioPlayer)
        }
        showsFullscreenPlayer = true
    }

}

private struct MVFullscreenPlayer: View {
    private enum FallbackControl: Hashable {
        case retry
        case next
        case close
    }

    let detail: MVSummary
    let onClose: () -> Void

    @Environment(PlayerService.self) private var audioPlayer
    private let mvPlayback = MVPlaybackController.shared
    @FocusState private var focusedControl: FallbackControl?

    private var currentDetail: MVSummary {
        mvPlayback.currentDetail ?? detail
    }

    var body: some View {
        Group {
            if let player = mvPlayback.player {
                SystemMVPlayer(
                    player: player,
                    detail: currentDetail,
                    servedResolution: mvPlayback.servedResolution,
                    autoplayEnabled: mvPlayback.autoplayEnabled,
                    canSkip: mvPlayback.canSkip,
                    nextTitle: mvPlayback.nextSummary?.name,
                    onPrevious: { mvPlayback.playPrevious(audioPlayer: audioPlayer) },
                    onNext: { mvPlayback.playNext(audioPlayer: audioPlayer) },
                    onToggleAutoplay: mvPlayback.toggleAutoplay
                )
                    .ignoresSafeArea()
            } else if mvPlayback.isPreparing {
                ZStack {
                    Color.black
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在准备视频")
                            .font(.title2.bold())
                        Text(currentDetail.name)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .foregroundStyle(.white)
            } else if let errorMessage = mvPlayback.errorMessage {
                ZStack {
                    Color.black
                    VStack(spacing: 18) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("暂时无法播放")
                            .font(.title2.bold())
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 760)

                        HStack(spacing: 16) {
                            Button {
                                mvPlayback.prepare(detail: currentDetail, audioPlayer: audioPlayer)
                            } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(TVPillButtonStyle(prominent: true))
                            .focused($focusedControl, equals: .retry)

                            if mvPlayback.canSkip {
                                Button {
                                    mvPlayback.playNext(audioPlayer: audioPlayer)
                                } label: {
                                    Label("播放下一支", systemImage: "forward.end.fill")
                                }
                                .buttonStyle(TVPillButtonStyle())
                                .focused($focusedControl, equals: .next)
                            }

                            Button(action: onClose) {
                                Text("返回详情")
                            }
                            .buttonStyle(TVPillButtonStyle())
                            .focused($focusedControl, equals: .close)
                        }
                        .padding(.top, 10)
                    }
                }
                .foregroundStyle(.white)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .onAppear { focusedControl = .retry }
        .onExitCommand(perform: onClose)
    }
}

private struct SystemMVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let detail: MVSummary
    let servedResolution: Int?
    let autoplayEnabled: Bool
    let canSkip: Bool
    let nextTitle: String?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToggleAutoplay: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.view.backgroundColor = .black
        controller.showsPlaybackControls = true
        controller.playbackControlsIncludeTransportBar = true
        controller.playbackControlsIncludeInfoViews = true
        controller.transportBarIncludesTitleView = true
        controller.videoGravity = .resizeAspect
        configure(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        configure(controller)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }

    private func configure(_ controller: AVPlayerViewController) {
        if controller.player !== player {
            controller.player = player
        }

        var customItems: [UIMenuElement] = []
        if canSkip {
            customItems.append(
                UIAction(title: "上一支", image: UIImage(systemName: "backward.end.fill")) { _ in
                    onPrevious()
                }
            )
            customItems.append(
                UIAction(title: "下一支", image: UIImage(systemName: "forward.end.fill")) { _ in
                    onNext()
                }
            )
        }

        let autoplayAction = UIAction(
            title: autoplayEnabled ? "自动连播已开启" : "自动连播已关闭",
            image: UIImage(systemName: "infinity"),
            state: autoplayEnabled ? .on : .off
        ) { _ in
            onToggleAutoplay()
        }
        var queueItems: [UIMenuElement] = [autoplayAction]
        if let nextTitle, canSkip {
            queueItems.append(
                UIAction(title: "接下来：\(nextTitle)", attributes: [.disabled]) { _ in }
            )
        }
        if let servedResolution {
            queueItems.append(
                UIAction(title: "当前清晰度：\(servedResolution)p", attributes: [.disabled]) { _ in }
            )
        }
        customItems.append(
            UIMenu(
                title: "播放队列",
                image: UIImage(systemName: "rectangle.stack.fill"),
                children: queueItems
            )
        )
        controller.transportBarCustomMenuItems = customItems
    }
}

private struct MVVideoStageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(MVVideoStageFocusEffect(isPressed: configuration.isPressed))
    }
}

private struct MVVideoStageFocusEffect: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(isFocused ? .white : .white.opacity(0.12), lineWidth: isFocused ? 5 : 1)
            }
            .scaleEffect(isPressed ? 0.99 : (isFocused ? 1.018 : 1))
            .shadow(
                color: isFocused ? TVTheme.accent.opacity(0.38) : .black.opacity(0.42),
                radius: isFocused ? 42 : 34,
                y: 18
            )
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: isPressed)
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
                            MVCard(mv: mv, queue: relatedMVs)
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
