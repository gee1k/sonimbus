import SwiftUI

private enum NowPlayingFocus: Hashable {
    case close
    case fmDislike
    case artist(Int)
    case album
    case favorite
    case moreActions
    case seek
    case shuffle
    case previous
    case play
    case next
    case repeatMode
    case lyricsRetry
    case lyricsMode
    case queueMode
}

private enum NowPlayingDetailDestination: Identifiable {
    case artist(ArtistRef)
    case album(AlbumRef)

    var id: String {
        switch self {
        case .artist(let artist): "artist-\(artist.id)"
        case .album(let album): "album-\(album.id)"
        }
    }
}

struct NowPlayingView: View {
    private enum Panel {
        case lyrics
        case queue
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus
    @Environment(PlayerService.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(ToastCenter.self) private var toast
    @Namespace private var focusScope
    let onClose: () -> Void
    @State private var panel: Panel?
    @State private var panelBeforeQueue: Panel?
    @State private var selectedDetail: NowPlayingDetailDestination?
    @State private var isDetailPlayerPresented = false
    @State private var detailPath = NavigationPath()
    @State private var lastSelectedDetailFocus: NowPlayingFocus?
    @State private var acceptsPanelActivation = false
    @State private var controlsReady = false
    @FocusState private var focusedControl: NowPlayingFocus?
    @FocusState private var focusedQueueID: Int?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        _panel = State(initialValue: .lyrics)
    }

    var body: some View {
        ZStack {
            background
            if let selectedDetail {
                detailCover(selectedDetail)
                    .zIndex(2)
            } else if player.currentTrack == nil {
                emptyPlayer
            } else {
                VStack(spacing: 0) {
                    header
                    stage
                    playbackChrome
                }
                .padding(.horizontal, 76)
                .padding(.vertical, 30)
            }
            toastOverlay
        }
        .focusScope(focusScope)
        .focusSection()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .onAppear {
            acceptsPanelActivation = false
            controlsReady = false
            focusedControl = initialControlFocus
        }
        .task {
            // The full-screen transition can finish its tvOS focus handoff after onAppear.
            // Keep every earlier control disabled while focus is handed to Play,
            // so a shortcut-origin presentation cannot fall through to Close.
            // Ignore the Return key-up that presented this player. Without this
            // short gate it can immediately toggle the newly focused control.
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            focusedControl = nil
            await Task.yield()
            focusedControl = initialControlFocus
            await Task.yield()
            resetFocus(in: focusScope)
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            acceptsPanelActivation = true
            controlsReady = true
        }
        .onChange(of: player.currentTrack?.id) { oldID, newID in
            if oldID != newID, newID != nil {
                if panel == .queue {
                    requestQueueFocus(newID)
                } else {
                    requestControlFocus(.play)
                }
            } else if newID == nil {
                requestControlFocus(.close)
            }
        }
        .onChange(of: selectedDetail?.id) { oldID, newID in
            if oldID == nil, newID != nil {
                detailPath = NavigationPath()
            } else if oldID != nil, newID == nil {
                detailCoverDidDismiss()
            }
        }
        .onExitCommand(perform: handleExitCommand)
    }

    private var background: some View {
        ZStack {
            TVBackground(tint: TVTheme.magenta)
            if let url = player.currentTrack?.artworkURL {
                CachedRemoteImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .blur(radius: 100)
                .opacity(0.34)
                .scaleEffect(1.25)
                .ignoresSafeArea()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.12), Color.black.opacity(0.34), Color.black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toast.current {
            Text(toast.text)
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .glassPanel(cornerRadius: 22)
                .padding(.bottom, 48)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(3)
        }
    }

    private var emptyPlayer: some View {
        VStack(spacing: 30) {
            Button { closePlayer() } label: {
                Label("返回", systemImage: "chevron.down")
            }
            .buttonStyle(TVPillButtonStyle())
            .focused($focusedControl, equals: .close)
            .prefersDefaultFocus(player.currentTrack == nil, in: focusScope)

            if player.isLoadingPersonalFM {
                VStack(spacing: 22) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在为你挑选音乐…")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("私人 FM 会根据你的听歌偏好持续更新。")
                        .font(.title3)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if player.source == .personalFM {
                EmptyStateView(
                    title: "私人 FM 暂时没有新推荐",
                    message: "稍后回到首页再试一次。",
                    symbol: "dot.radiowaves.left.and.right"
                )
            } else {
                EmptyStateView(
                    title: "还没有正在播放的音乐",
                    message: "从歌曲、专辑或歌单中选择一首开始播放。",
                    symbol: "music.note"
                )
            }
        }
        .padding(76)
    }

    private var header: some View {
        HStack {
            Button { closePlayer() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 54, prominent: true))
            .focused($focusedControl, equals: .close)
            .disabled(!controlsReady)
            .accessibilityLabel("返回")

            Spacer()

            if let source = player.alternativeSource {
                Text("补全音源 · \(source)")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(TVTheme.amber.opacity(0.20), in: Capsule())
                    .foregroundStyle(TVTheme.amber)
            } else if player.isTrial {
                Text("试听片段")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(TVTheme.accent.opacity(0.22), in: Capsule())
                    .foregroundStyle(TVTheme.accent)
            } else if let quality = player.servedQuality {
                Text(AudioQuality.displayName(for: quality))
                    .font(.caption2.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(height: 56)
        .focusSection()
    }

    private var stage: some View {
        Group {
            if let panel {
                HStack(alignment: .center, spacing: 82) {
                    artworkAndMetadata(size: 430)
                    Group {
                        switch panel {
                        case .lyrics: lyricsPanel
                        case .queue: queuePanel
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusSection()
                }
            } else {
                artworkAndMetadata(size: 500)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(height: 640)
    }

    private func artworkAndMetadata(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ArtworkView(url: player.currentTrack?.artworkURL, cornerRadius: 25)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.56), radius: 38, y: 20)

            HStack(alignment: .center, spacing: 14) {
                Text(player.currentTrack?.name ?? "")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if let track = player.currentTrack {
                    HStack(spacing: 6) {
                        if player.source == .personalFM {
                            Button {
                                player.dislikeCurrentFM()
                            } label: {
                                Image(systemName: "hand.thumbsdown.fill")
                            }
                            .buttonStyle(TVPlaybackButtonStyle(size: 54))
                            .focused($focusedControl, equals: .fmDislike)
                            .disabled(!controlsReady)
                            .accessibilityLabel("减少类似推荐并播放下一首")
                        }

                        Button {
                            Task { await account.toggleLike(track) }
                        } label: {
                            Image(systemName: account.isLiked(track) ? "heart.fill" : "heart")
                        }
                        .buttonStyle(TVPlaybackButtonStyle(size: 54, active: account.isLiked(track)))
                        .focused($focusedControl, equals: .favorite)
                        .disabled(!controlsReady)
                        .accessibilityLabel(account.isLiked(track) ? "取消喜欢" : "喜欢")

                        moreActionsMenu(for: track)
                    }
                }
            }
            .focusSection()

            if !navigableArtists.isEmpty || navigableAlbum != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(navigableArtists) { artist in
                            Button {
                                lastSelectedDetailFocus = .artist(artist.id)
                                selectedDetail = .artist(artist)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(artist.name)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                            }
                            .buttonStyle(NowPlayingArtistButtonStyle())
                            .focused($focusedControl, equals: .artist(artist.id))
                            .disabled(!controlsReady)
                            .accessibilityLabel("查看歌手\(artist.name)")
                        }

                        if let album = navigableAlbum {
                            Button {
                                lastSelectedDetailFocus = .album
                                selectedDetail = .album(album)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.stack")
                                        .font(.caption.bold())
                                    Text(album.name)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                            }
                            .buttonStyle(NowPlayingArtistButtonStyle())
                            .focused($focusedControl, equals: .album)
                            .disabled(!controlsReady)
                            .accessibilityLabel("查看专辑\(album.name)")
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 6)
                }
                .frame(height: 52)
                .focusSection()
            } else if let artistNames = player.currentTrack?.artistNames, !artistNames.isEmpty {
                Text(artistNames)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .frame(width: size)
    }

    private func moreActionsMenu(for track: Track) -> some View {
        NowPlayingMoreActionsMenu(
            track: track,
            isLiked: account.isLiked(track),
            ownedPlaylists: account.ownedPlaylists,
            likedSongsPlaylistID: account.likedSongsPlaylist?.id,
            sourcePlaylistID: player.source.playlistID,
            album: navigableAlbum,
            artists: navigableArtists,
            controlsReady: controlsReady,
            focus: $focusedControl,
            selectedDetail: $selectedDetail,
            lastSelectedDetailFocus: $lastSelectedDetailFocus
        )
    }

    private var lyricsPanel: some View {
        Group {
            if player.lyrics?.isInstrumental == true, player.lyrics?.lines.isEmpty == true {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 68, weight: .medium))
                    Text("纯音乐，请欣赏")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white.opacity(0.76))
            } else if let lines = player.lyrics?.lines, !lines.isEmpty {
                NowPlayingSyncedLyrics(
                    lines: lines,
                    showsTranslatedLyrics: player.showsTranslatedLyrics
                )
            } else if player.isLoadingLyrics {
                VStack(alignment: .leading, spacing: 20) {
                    ProgressView().controlSize(.large)
                    Text("正在载入歌词…")
                        .font(.title2.bold())
                    Text("稍等片刻，歌词会自动同步到当前进度。")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = player.lyricsErrorMessage {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(errorMessage)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("歌曲仍可正常播放，你可以立即重试。")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.48))
                    Button {
                        player.retryLyrics()
                    } label: {
                        Label("重试歌词", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(TVPillButtonStyle(prominent: true))
                    .focused($focusedControl, equals: .lyricsRetry)
                    .disabled(!controlsReady)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                    Text("这首歌暂无歌词")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("你仍然可以继续欣赏音乐。")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            queueHeader

            Group {
                if player.playbackQueue.isEmpty {
                    EmptyStateView(
                        title: "当前队列为空",
                        message: "私人 FM 会按播放进度持续加入歌曲。",
                        symbol: "text.line.first.and.arrowtriangle.forward"
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .center, spacing: 30) {
                                ForEach(Array(player.playbackQueue.enumerated()), id: \.element.id) { index, track in
                                    Button {
                                        player.playTrack(track)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ArtworkView(url: track.artworkURL, cornerRadius: 20)
                                                .frame(width: 235, height: 235)
                                            Text(track.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(track.artistNames)
                                                .font(.caption)
                                                .opacity(0.58)
                                                .lineLimit(1)
                                            HStack(spacing: 7) {
                                                Text("\(index + 1)")
                                                if player.currentTrack?.id == track.id {
                                                    Circle().fill(TVTheme.accent).frame(width: 6, height: 6)
                                                    Text("正在播放")
                                                }
                                            }
                                            .font(.caption2.bold().monospacedDigit())
                                            .opacity(0.54)
                                        }
                                        .frame(width: 235, alignment: .leading)
                                    }
                                    .buttonStyle(NowPlayingQueueCardStyle(isCurrent: player.currentTrack?.id == track.id))
                                    .focused($focusedQueueID, equals: track.id)
                                    .contextMenu {
                                        if player.currentTrack?.id != track.id {
                                            Button("从播放队列移除", role: .destructive) {
                                                player.removeFromQueue(track)
                                            }
                                        }
                                    }
                                    .id(track.id)
                                }
                            }
                            .padding(.horizontal, 34)
                            .padding(.vertical, 42)
                        }
                        .onAppear {
                            guard let currentID = player.currentTrack?.id else { return }
                            proxy.scrollTo(currentID, anchor: .center)
                        }
                        .onChange(of: player.currentTrack?.id) { _, currentID in
                            guard let currentID else { return }
                            if reduceMotion {
                                proxy.scrollTo(currentID, anchor: .center)
                            } else {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    proxy.scrollTo(currentID, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .focusSection()
        .onAppear { requestQueueFocus() }
    }

    private var queueHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("待播放")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(player.playbackQueue.count) 首歌曲")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            if player.source == .personalFM {
                Label("私人 FM 自动续播", systemImage: "infinity")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: Capsule())
            } else {
                HStack(spacing: 8) {
                    Button(action: player.toggleShuffle) {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(TVPlaybackButtonStyle(size: 54, active: player.shuffleEnabled))
                    .focused($focusedControl, equals: .shuffle)
                    .accessibilityLabel(player.shuffleEnabled ? "关闭随机播放" : "开启随机播放")
                    .disabled(!controlsReady)

                    Button(action: player.cycleRepeat) {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    }
                    .buttonStyle(TVPlaybackButtonStyle(size: 54, active: player.repeatMode != .off))
                    .focused($focusedControl, equals: .repeatMode)
                    .accessibilityLabel(repeatAccessibilityLabel)
                    .disabled(!controlsReady)
                }
            }
        }
        .padding(.horizontal, 34)
        .frame(height: 72)
        .focusSection()
    }

    private var playbackChrome: some View {
        VStack(spacing: 5) {
            NowPlayingTimeline(
                isEnabled: controlsReady,
                focus: $focusedControl,
                onMove: moveTimeline
            )

            ZStack {
                HStack {
                    Spacer()

                    HStack(spacing: 8) {
                        panelButton(.lyrics, symbol: "quote.bubble.fill", focus: .lyricsMode, label: "歌词")
                        panelButton(.queue, symbol: "list.bullet", focus: .queueMode, label: "播放队列")
                    }
                    .focusSection()
                }

                HStack(spacing: 16) {
                    Button(action: player.previous) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(TVPlaybackButtonStyle(size: 58))
                    .focused($focusedControl, equals: .previous)
                    .accessibilityLabel("上一首")
                    .disabled(!player.canGoPrevious || !controlsReady)

                    Button {
                        guard controlsReady else { return }
                        player.togglePlayPause()
                    } label: {
                        Group {
                            if player.isBuffering {
                                ProgressView()
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(TVPlaybackButtonStyle(size: 66, prominent: true))
                    .focused($focusedControl, equals: .play)
                    .prefersDefaultFocus(initialControlFocus == .play, in: focusScope)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                    Button(action: player.next) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(TVPlaybackButtonStyle(size: 58))
                    .focused($focusedControl, equals: .next)
                    .accessibilityLabel("下一首")
                    .disabled(!player.canGoNext || !controlsReady)
                }
                .focusSection()
            }
            .frame(height: 72)
        }
        .padding(.top, 26)
        .padding(.horizontal, 4)
        .frame(height: 190)
    }

    private func panelButton(
        _ target: Panel,
        symbol: String,
        focus: NowPlayingFocus,
        label: String
    ) -> some View {
        let isActive = panel == target
        return Button {
            guard acceptsPanelActivation else { return }
            switch target {
            case .lyrics:
                panel = isActive ? nil : .lyrics
                requestControlFocus(focus)
            case .queue:
                if isActive {
                    restorePanelAfterQueue()
                } else {
                    panelBeforeQueue = panel
                    panel = .queue
                }
            }
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: symbol)
                if isActive {
                    Circle()
                        .fill(TVTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(y: 1)
                }
            }
        }
        .buttonStyle(TVPlaybackButtonStyle(size: 62, active: isActive))
        .focused($focusedControl, equals: focus)
        .disabled(!controlsReady && focus != initialControlFocus)
        .prefersDefaultFocus(focus == initialControlFocus, in: focusScope)
        .accessibilityLabel(isActive ? "隐藏\(label)" : "显示\(label)")
    }

    private func moveTimeline(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            player.seek(to: player.progress - 10)
        case .right:
            player.seek(to: player.progress + 10)
        default:
            break
        }
    }

    private func requestControlFocus(_ target: NowPlayingFocus) {
        focusedQueueID = nil
        focusedControl = target
    }

    private func requestQueueFocus(_ requestedTrackID: Int? = nil) {
        let currentTrackID = player.currentTrack.flatMap { currentTrack in
            player.playbackQueue.contains(where: { $0.id == currentTrack.id }) ? currentTrack.id : nil
        }
        let target = requestedTrackID
            .flatMap { requestedID in
                player.playbackQueue.contains(where: { $0.id == requestedID }) ? requestedID : nil
            }
            ?? currentTrackID
            ?? player.playbackQueue.first?.id
        guard let target else {
            requestControlFocus(.queueMode)
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard panel == .queue else { return }
            focusedControl = nil
            focusedQueueID = target
        }
    }

    private var initialControlFocus: NowPlayingFocus {
        guard player.currentTrack != nil else { return .close }
        return .play
    }

    private var repeatAccessibilityLabel: String {
        switch player.repeatMode {
        case .off: "循环播放已关闭"
        case .all: "列表循环已开启"
        case .one: "单曲循环已开启"
        }
    }

    private var navigableArtists: [ArtistRef] {
        var seen = Set<Int>()
        return (player.currentTrack?.artists ?? []).filter {
            $0.id > 0 && seen.insert($0.id).inserted
        }
    }

    private var navigableAlbum: AlbumRef? {
        guard let album = player.currentTrack?.album,
              album.id > 0,
              !album.name.isEmpty else { return nil }
        return album
    }

    private func closePlayer() {
        onClose()
    }

    private func handleExitCommand() {
        // Menu is a distinct command from the Select key that presents this view,
        // so it is safe—and feels much more responsive—to honor it immediately.
        guard selectedDetail == nil else { return }
        if panel == .queue {
            restorePanelAfterQueue()
        } else {
            closePlayer()
        }
    }

    private func restorePanelAfterQueue() {
        panel = panelBeforeQueue
        panelBeforeQueue = nil
        requestControlFocus(.queueMode)
    }

    @ViewBuilder
    private func detailCover(_ destination: NowPlayingDetailDestination) -> some View {
        NavigationStack(path: $detailPath) {
            Group {
                switch destination {
                case .artist(let artist): ArtistDetailView(artistID: artist.id)
                case .album(let album): AlbumDetailView(albumID: album.id)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .playlist(let id): PlaylistDetailView(playlistID: id)
                case .album(let id): AlbumDetailView(albumID: id)
                case .artist(let id): ArtistDetailView(artistID: id)
                case .mv(let id): MVDetailView(mvID: id)
                case .dailySongs: DailySongsView()
                case .recents: RecentPlaysView()
                case .cloud: CloudMusicView()
                case .settings: PlaybackSettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .fullScreenCover(isPresented: $isDetailPlayerPresented) {
            NowPlayingView {
                isDetailPlayerPresented = false
            }
        }
        .environment(\.openNowPlaying, {
            isDetailPlayerPresented = true
        })
        .onExitCommand {
            if detailPath.isEmpty {
                selectedDetail = nil
            } else {
                detailPath.removeLast()
            }
        }
    }

    private func detailCoverDidDismiss() {
        isDetailPlayerPresented = false
        detailPath = NavigationPath()
        restoreDetailFocus()
    }

    private func restoreDetailFocus() {
        guard let focus = lastSelectedDetailFocus else { return }
        Task { @MainActor in
            await Task.yield()
            requestControlFocus(focus)
        }
    }
}

private struct NowPlayingSyncedLyrics: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PlayerService.self) private var player

    let lines: [LyricLine]
    let showsTranslatedLyrics: Bool

    var body: some View {
        let activeLyricIndex = player.activeLyricIndex
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 34) {
                    Color.clear.frame(height: 210)
                    ForEach(lines) { line in
                        let active = line.id == activeLyricIndex
                        VStack(alignment: .leading, spacing: 9) {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(
                                    size: active ? 48 : 36,
                                    weight: active ? .bold : .semibold,
                                    design: .rounded
                                ))
                            if showsTranslatedLyrics,
                               let translation = line.translation, !translation.isEmpty {
                                Text(translation)
                                    .font(.system(size: active ? 25 : 21, weight: .semibold, design: .rounded))
                                    .foregroundStyle(secondaryColor(active: active, emphasis: 0.78))
                            }
                            if showsTranslatedLyrics,
                               let romaji = line.romaji, !romaji.isEmpty {
                                Text(romaji)
                                    .font(.headline)
                                    .foregroundStyle(secondaryColor(active: active, emphasis: 0.54))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(active ? Color.white : Color.white.opacity(0.30))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: active)
                        .accessibilityLabel(line.text.isEmpty ? "音乐间奏" : line.text)
                        .accessibilityValue(DisplayFormatter.duration(line.time))
                        .id(line.id)
                    }
                    Color.clear.frame(height: 230)
                }
            }
            .scrollDisabled(true)
            .allowsHitTesting(false)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.17),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                guard let index = player.activeLyricIndex else { return }
                proxy.scrollTo(index, anchor: .center)
            }
            .onChange(of: player.activeLyricIndex) { _, index in
                guard let index else { return }
                if reduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.42)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func secondaryColor(active: Bool, emphasis: Double) -> Color {
        .white.opacity(active ? emphasis : max(0.24, emphasis * 0.42))
    }
}

private struct NowPlayingTimeline: View {
    @Environment(PlayerService.self) private var player

    let isEnabled: Bool
    let focus: FocusState<NowPlayingFocus?>.Binding
    let onMove: (MoveCommandDirection) -> Void

    var body: some View {
        VStack(spacing: 5) {
            TVSeekBar(
                progress: player.progress,
                duration: player.duration,
                isEnabled: isEnabled,
                focus: focus,
                onMove: onMove
            )

            HStack {
                Text(DisplayFormatter.duration(player.progress))
                Spacer()
                Text("−" + DisplayFormatter.duration(max(player.duration - player.progress, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.54))
        }
    }
}

private struct NowPlayingMoreActionsMenu: View {
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    let track: Track
    let isLiked: Bool
    let ownedPlaylists: [PlaylistSummary]
    let likedSongsPlaylistID: Int?
    let sourcePlaylistID: Int?
    let album: AlbumRef?
    let artists: [ArtistRef]
    let controlsReady: Bool
    let focus: FocusState<NowPlayingFocus?>.Binding
    @Binding var selectedDetail: NowPlayingDetailDestination?
    @Binding var lastSelectedDetailFocus: NowPlayingFocus?

    var body: some View {
        Menu {
            Button(isLiked ? "取消喜欢" : "喜欢") {
                Task { await account.toggleLike(track) }
            }

            if !ownedPlaylists.isEmpty {
                Menu("添加到歌单") {
                    ForEach(ownedPlaylists) { playlist in
                        Button(playlist.name) {
                            Task { await account.add(track, to: playlist) }
                        }
                    }
                }
            }

            if let sourcePlaylistID,
               sourcePlaylistID == likedSongsPlaylistID,
               !track.noCopyright {
                Button("从这首开启心动模式") {
                    player.startIntelligence(from: track, playlistID: sourcePlaylistID)
                }
            }

            if album != nil || !artists.isEmpty {
                Divider()
            }

            if let album {
                Button("查看专辑《\(album.name)》") {
                    openDetail(.album(album))
                }
            }

            if artists.count == 1, let artist = artists.first {
                Button("查看歌手“\(artist.name)”") {
                    openDetail(.artist(artist))
                }
            } else if artists.count > 1 {
                Menu("查看歌手") {
                    ForEach(artists) { artist in
                        Button(artist.name) {
                            openDetail(.artist(artist))
                        }
                    }
                }
            }

            if let sourcePlaylistID,
               let playlist = ownedPlaylists.first(where: { $0.id == sourcePlaylistID }) {
                Divider()
                Button("从《\(playlist.name)》中移除", role: .destructive) {
                    Task { await account.remove(track, from: playlist) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(TVPlaybackButtonStyle(size: 54))
        .focused(focus, equals: .moreActions)
        .disabled(!controlsReady)
        .accessibilityLabel("更多操作")
    }

    private func openDetail(_ destination: NowPlayingDetailDestination) {
        lastSelectedDetailFocus = .moreActions
        selectedDetail = destination
    }
}

private struct NowPlayingArtistButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.62))
            .background(
                Capsule()
                    .fill(isFocused ? Color.white : Color.white.opacity(0.08))
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isFocused ? 0.95 : 0.12), lineWidth: isFocused ? 2 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

private struct NowPlayingQueueCardStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(14)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(isCurrent ? 0.12 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        isFocused ? Color.white : (isCurrent ? TVTheme.accent.opacity(0.72) : Color.white.opacity(0.08)),
                        lineWidth: isFocused || isCurrent ? 3 : 1
                    )
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.055 : (configuration.isPressed ? 0.98 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.46 : 0.12), radius: isFocused ? 28 : 10, y: isFocused ? 14 : 5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

private struct TVSeekBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: TimeInterval
    let duration: TimeInterval
    let isEnabled: Bool
    let focus: FocusState<NowPlayingFocus?>.Binding
    let onMove: (MoveCommandDirection) -> Void

    var body: some View {
        let isFocused = focus.wrappedValue == .seek
        GeometryReader { proxy in
            let ratio = duration > 0 ? min(max(progress / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(isFocused ? 0.34 : 0.22))
                Capsule()
                    .fill(isFocused ? Color.white : TVTheme.accent)
                    .frame(width: proxy.size.width * ratio)
                Circle()
                    .fill(.white)
                    .frame(width: isFocused ? 24 : 10, height: isFocused ? 24 : 10)
                    .offset(x: max(0, proxy.size.width * ratio - (isFocused ? 12 : 5)))
                    .shadow(color: .black.opacity(0.42), radius: 6)
            }
            .frame(height: isFocused ? 12 : 7)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 34)
        .contentShape(Rectangle())
        .focusable(isEnabled)
        .focused(focus, equals: .seek)
        .onMoveCommand(perform: onMove)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(DisplayFormatter.duration(progress)) / \(DisplayFormatter.duration(duration))")
        .accessibilityHint("左右轻扫可快退或快进十秒")
    }
}
