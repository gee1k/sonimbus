import SwiftUI
import UIKit

private enum NowPlayingFocus: Hashable {
    case emptyReturn
    case immersive
    case fmDislike
    case info
    case favorite
    case moreActions
    case shuffle
    case previous
    case play
    case next
    case repeatMode
    case lyricsRetry
    case lyricsMode
    case queueMode
}

struct NowPlayingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus
    @Environment(PlayerService.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(ToastCenter.self) private var toast
    @Namespace private var focusScope
    let isActive: Bool
    let activationGeneration: Int
    let onDismiss: () -> Void
    @State private var interaction = NowPlayingInteractionState()
    @State private var detailPath: [AppRoute] = []
    @State private var lastSelectedDetailFocus: NowPlayingFocus?
    @State private var idleGeneration = 0
    @State private var expandsStage = false
    @State private var backgroundBreathes = false
    @State private var isInfoPresented = false
    @State private var modeFocusFallback: NowPlayingFocus?
    @FocusState private var focusedControl: NowPlayingFocus?
    @FocusState private var focusedQueueID: Int?

    var body: some View {
        NavigationStack(path: $detailPath) {
            ZStack {
                background
                if player.currentTrack == nil {
                    emptyPlayer
                } else {
                    if !interaction.showsControls {
                        immersiveSurface
                            .disabled(isInfoPresented)
                    }
                    VStack(spacing: 0) {
                        header
                        stage
                        if isInfoPresented, let track = player.currentTrack {
                            NowPlayingInfoPanel(
                                track: track,
                                duration: player.duration > 0 ? player.duration : track.duration,
                                playbackBadge: playbackBadgeText,
                                artists: navigableArtists,
                                album: navigableAlbum,
                                openArtist: { artist in
                                    isInfoPresented = false
                                    openDetail(.artist(artist.id), returningTo: .info)
                                },
                                openAlbum: { album in
                                    isInfoPresented = false
                                    openDetail(.album(album.id), returningTo: .info)
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            playbackChrome
                        }
                    }
                    .id(player.currentTrack?.id)
                    .padding(.horizontal, 76)
                    .padding(.vertical, 30)
                }
                toastOverlay
            }
            .navigationDestination(for: AppRoute.self, destination: detailDestination)
        }
        .environment(\.handlesNavigationExit, true)
        .focusScope(focusScope)
        .modifier(
            NowPlayingExitCommand(
                isActive: detailPath.isEmpty,
                action: handlePlayerExit
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: interaction.showsControls)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isInfoPresented)
        .task(id: activationGeneration) {
            await activatePlayerIfNeeded()
        }
        .task(id: player.currentTrack?.id) {
            await animateBackgroundIfNeeded()
        }
        .task(id: idleGeneration) {
            await hideControlsAfterIdleIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                stopDetailPlaybackIfNeeded()
                isInfoPresented = false
                modeFocusFallback = nil
                focusedControl = nil
                focusedQueueID = nil
                idleGeneration &+= 1
            }
        }
        .onChange(of: player.currentTrack?.id) { oldID, newID in
            guard isActive else { return }
            if oldID != newID, newID != nil {
                isInfoPresented = false
                interaction.showControls()
                if interaction.panel == .queue {
                    requestQueueFocus(newID)
                } else {
                    requestControlFocus(.play)
                }
                markInteraction()
            } else if newID == nil {
                focusedQueueID = nil
                requestEmptyPlayerFocus()
            }
        }
        .onChange(of: focusedControl) { _, focus in
            guard isActive, let focus else { return }
            if focus != modeFocusFallback {
                modeFocusFallback = nil
            }
            if focus != .immersive {
                markInteraction()
            }
        }
        .onChange(of: focusedQueueID) { _, trackID in
            if trackID != nil {
                modeFocusFallback = nil
            }
        }
        .onChange(of: player.isPlaying) { _, playing in
            if isActive, playing {
                markInteraction()
            }
        }
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
                .saturation(1.28)
                .contrast(1.06)
                .brightness(-0.05)
                .opacity(backgroundBreathes ? 0.43 : 0.32)
                .scaleEffect(backgroundBreathes ? 1.34 : 1.20)
                .offset(
                    x: backgroundBreathes ? 34 : -24,
                    y: backgroundBreathes ? 18 : -16
                )
                .ignoresSafeArea()
            }
            RadialGradient(
                colors: [Color.white.opacity(backgroundBreathes ? 0.055 : 0.025), Color.clear],
                center: backgroundBreathes ? .topTrailing : .bottomLeading,
                startRadius: 40,
                endRadius: 920
            )
            .blendMode(.screen)
            .ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.28), Color.black.opacity(0.57)],
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
        ZStack {
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

            VStack {
                Spacer()
                Button("返回", action: onDismiss)
                    .buttonStyle(TVPillButtonStyle())
                    .focused($focusedControl, equals: .emptyReturn)
                    .prefersDefaultFocus(true, in: focusScope)
                    .accessibilityHint("返回之前的标签页")
            }
            .padding(.bottom, 34)
        }
        .padding(76)
    }

    private var header: some View {
        HStack {
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
        .opacity(interaction.showsControls ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var immersiveSurface: some View {
        Button(action: handleImmersiveSelection) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NowPlayingImmersiveButtonStyle())
        .focused($focusedControl, equals: .immersive)
        .prefersDefaultFocus(!interaction.showsControls, in: focusScope)
        .onMoveCommand(perform: handleImmersiveMove)
        .accessibilityLabel("播放中")
        .accessibilityHint(
            interaction.chromeMode == .lyricsNavigation
                ? "上下选择歌词，点按跳转播放"
                : "点按显示控制"
        )
    }

    private var stage: some View {
        let showsLyrics = expandsStage && interaction.panel == .lyrics
        let showsQueue = expandsStage && interaction.panel == .queue
        return Group {
            if showsQueue {
                queuePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                HStack(alignment: .center, spacing: 70) {
                    artworkAndMetadata(size: showsLyrics ? 500 : 560)

                    if showsLyrics {
                        lyricsPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .focusSection()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(height: 650)
        .offset(y: interaction.showsControls ? 0 : 30)
        .scaleEffect(interaction.showsControls ? 1 : 1.018)
        .animation(
            reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.88),
            value: showsLyrics
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.30),
            value: showsQueue
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.45),
            value: interaction.showsControls
        )
    }

    private func artworkAndMetadata(size: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 14) {
            ArtworkView(url: player.currentTrack?.artworkURL, cornerRadius: 25)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.56), radius: 38, y: 20)

            Text(player.currentTrack?.name ?? "")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)

            metadataLinks
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: size)
    }

    @ViewBuilder
    private var metadataLinks: some View {
        let artistNames = player.currentTrack?.artistNames ?? ""
        if !artistNames.isEmpty, let album = navigableAlbum {
            (
                Text(artistNames).foregroundColor(.white.opacity(0.66))
                    + Text("  ·  ").foregroundColor(.white.opacity(0.34))
                    + Text(album.name).foregroundColor(.white.opacity(0.48))
            )
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        } else if !artistNames.isEmpty {
            Text(artistNames)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } else if let album = navigableAlbum {
            Text(album.name)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    @ViewBuilder
    private var songActions: some View {
        if let track = player.currentTrack {
            HStack(spacing: 10) {
                if interaction.panel == .queue, player.source != .personalFM {
                    Button(action: player.toggleShuffle) {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(NowPlayingActionButtonStyle(size: 62, active: player.shuffleEnabled))
                    .focused($focusedControl, equals: .shuffle)
                    .accessibilityLabel(player.shuffleEnabled ? "关闭随机播放" : "开启随机播放")
                    .disabled(!interaction.showsControls)

                    Button(action: player.cycleRepeat) {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    }
                    .buttonStyle(NowPlayingActionButtonStyle(size: 62, active: player.repeatMode != .off))
                    .focused($focusedControl, equals: .repeatMode)
                    .accessibilityLabel(repeatAccessibilityLabel)
                    .disabled(!interaction.showsControls)
                }

                if player.source == .personalFM {
                    Button {
                        player.dislikeCurrentFM()
                    } label: {
                        Image(systemName: "hand.thumbsdown.fill")
                    }
                    .buttonStyle(NowPlayingActionButtonStyle(size: 62))
                    .focused($focusedControl, equals: .fmDislike)
                    .disabled(!interaction.showsControls)
                    .accessibilityLabel("减少类似推荐并播放下一首")
                }

                Button {
                    Task { await account.toggleLike(track) }
                } label: {
                    Image(systemName: account.isLiked(track) ? "star.fill" : "star")
                }
                .buttonStyle(NowPlayingActionButtonStyle(size: 62, active: account.isLiked(track)))
                .focused($focusedControl, equals: .favorite)
                .disabled(!interaction.showsControls)
                .accessibilityLabel(account.isLiked(track) ? "取消喜欢" : "喜欢")

                moreActionsMenu(for: track)
            }
            .focusSection()
        }
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
            isEnabled: interaction.showsControls,
            focus: $focusedControl,
            openDetail: { openDetail($0, returningTo: .moreActions) }
        )
    }

    private var lyricsPanel: some View {
        let viewportHeight: CGFloat = interaction.showsControls ? 430 : 760

        return Group {
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
                    showsTranslatedLyrics: player.showsTranslatedLyrics,
                    selectedIndex: interaction.selectedLyricIndex,
                    viewportHeight: viewportHeight
                )
                .frame(height: viewportHeight)
                .offset(y: 200)
                .frame(height: 650, alignment: .top)
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
                    .disabled(!interaction.showsControls)
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
        .onAppear {
            guard interaction.panel == .queue else { return }
            requestQueueFocus()
        }
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
            }
        }
        .padding(.horizontal, 34)
        .frame(height: 72)
        .focusSection()
    }

    private var playbackChrome: some View {
        VStack(spacing: 7) {
            HStack {
                Spacer()
                songActions
            }
            .frame(height: 68)

            NowPlayingTimeline(
                isEnabled: interaction.showsControls,
                onSeek: { time in
                    player.seek(to: time)
                    markInteraction()
                },
                onFocusChange: { focused in
                    if focused {
                        modeFocusFallback = nil
                        markInteraction()
                    }
                }
            )

            HStack(spacing: 0) {
                songInfoButton

                transportControls

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        panelButton(.lyrics, symbol: "quote.bubble.fill", focus: .lyricsMode, label: "歌词")
                        panelButton(.queue, symbol: "list.bullet", focus: .queueMode, label: "播放队列")
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.11), in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1)
                    }
                    .focusSection()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 78)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
        .frame(height: 240)
        .opacity(interaction.showsControls ? 1 : 0)
        .allowsHitTesting(interaction.showsControls)
    }

    private var songInfoButton: some View {
        Button {
            focusedControl = nil
            focusedQueueID = nil
            isInfoPresented = true
            markInteraction()
        } label: {
            Text("信息")
        }
        .buttonStyle(NowPlayingInfoButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .focused($focusedControl, equals: .info)
        .disabled(!interaction.showsControls)
        .accessibilityLabel("查看歌曲信息")
    }

    private var transportControls: some View {
        HStack(spacing: 20) {
            Button {
                player.previous()
                markInteraction()
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 58))
            .focused($focusedControl, equals: .previous)
            .accessibilityLabel("上一首")
            .disabled(!player.canGoPrevious || !interaction.showsControls)

            Button {
                guard interaction.showsControls else { return }
                player.togglePlayPause()
                markInteraction()
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

            Button {
                player.next()
                markInteraction()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 58))
            .focused($focusedControl, equals: .next)
            .accessibilityLabel("下一首")
            .disabled(!player.canGoNext || !interaction.showsControls)
        }
        .frame(width: 238, height: 74)
        .focusSection()
    }

    private func panelButton(
        _ target: NowPlayingPanel,
        symbol: String,
        focus: NowPlayingFocus,
        label: String
    ) -> some View {
        let isActive = interaction.panel == target
        return Button {
            guard interaction.showsControls else { return }
            switch target {
            case .lyrics:
                interaction.toggleLyrics()
                expandsStage = interaction.panel == .lyrics
                modeFocusFallback = focus
            case .queue:
                if isActive {
                    interaction.toggleQueue()
                    expandsStage = interaction.panel != .artwork
                    modeFocusFallback = focus
                } else {
                    modeFocusFallback = nil
                    interaction.toggleQueue()
                    expandsStage = true
                    requestQueueFocus()
                }
            case .artwork:
                break
            }
            markInteraction()
        } label: { Image(systemName: symbol) }
        .buttonStyle(
            NowPlayingModeButtonStyle(
                size: 62,
                active: isActive,
                usesFocusFallback: modeFocusFallback == focus
            )
        )
        .focused($focusedControl, equals: focus)
        .overlay {
            if modeFocusFallback == focus {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(.white, in: Circle())
                    .scaleEffect(reduceMotion ? 1 : 1.08)
                    .shadow(color: .black.opacity(0.30), radius: 14, y: 7)
                    .allowsHitTesting(false)
            }
        }
        .disabled(!interaction.showsControls)
        .accessibilityLabel(isActive ? "隐藏\(label)" : "显示\(label)")
    }

    private func handleImmersiveSelection() {
        if let index = interaction.selectedLyricIndex,
           let lines = player.lyrics?.lines,
           lines.indices.contains(index) {
            player.seek(to: lines[index].time)
            interaction.clearLyricSelection()
        } else {
            showControls()
        }
        markInteraction()
    }

    private func handleImmersiveMove(_ direction: MoveCommandDirection) {
        guard interaction.chromeMode == .lyricsNavigation,
              interaction.panel == .lyrics,
              let lines = player.lyrics?.lines,
              !lines.isEmpty else {
            showControls()
            markInteraction()
            return
        }

        switch direction {
        case .up:
            interaction.moveLyricSelection(
                direction: -1,
                activeIndex: player.activeLyricIndex,
                lineCount: lines.count
            )
        case .down:
            interaction.moveLyricSelection(
                direction: 1,
                activeIndex: player.activeLyricIndex,
                lineCount: lines.count
            )
        case .left, .right:
            showControls()
        default:
            break
        }
        markInteraction()
    }

    private func requestControlFocus(_ target: NowPlayingFocus) {
        focusedQueueID = nil
        focusedControl = target
    }

    private func showControls() {
        interaction.showControls()
        focusedQueueID = nil
        focusedControl = nil
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
            guard interaction.panel == .queue else { return }
            focusedControl = nil
            focusedQueueID = target
            resetFocus(in: focusScope)
        }
    }

    private var initialControlFocus: NowPlayingFocus {
        guard player.currentTrack != nil else { return .emptyReturn }
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

    private func handlePlayerExit() {
        if isInfoPresented {
            closeInfoPanel()
            return
        }
        if interaction.handleBack(
            hasCurrentTrack: player.currentTrack != nil,
            allowsLyricsNavigation: hasNavigableLyrics
        ) == .handled {
            if interaction.panel == .queue {
                requestQueueFocus()
            } else if interaction.showsControls {
                requestControlFocus(.queueMode)
            } else {
                requestControlFocus(.immersive)
            }
            markInteraction()
        } else {
            onDismiss()
        }
    }

    private func popDetail() {
        guard let removedRoute = detailPath.popLast() else { return }
        if case .mv = removedRoute {
            MVPlaybackController.shared.stop()
        }
        if detailPath.isEmpty {
            restoreDetailFocus()
        }
    }

    private func restoreDetailFocus() {
        guard let focus = lastSelectedDetailFocus else { return }
        interaction.showControls()
        markInteraction()
        Task { @MainActor in
            await Task.yield()
            requestControlFocus(focus)
        }
    }

    private func openDetail(_ route: AppRoute, returningTo focus: NowPlayingFocus) {
        lastSelectedDetailFocus = focus
        detailPath.append(route)
    }

    @ViewBuilder
    private func detailDestination(_ route: AppRoute) -> some View {
        Group {
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
        .onExitCommand(perform: popDetail)
    }

    @MainActor
    private func activatePlayerIfNeeded() async {
        guard isActive else { return }
        stopDetailPlaybackIfNeeded()
        detailPath = []
        interaction.activate()
        expandsStage = reduceMotion && interaction.panel != .artwork
        isInfoPresented = false
        focusedQueueID = nil
        focusedControl = nil
        await Task.yield()
        guard !Task.isCancelled, isActive else { return }
        guard player.currentTrack != nil else {
            requestEmptyPlayerFocus()
            return
        }
        focusedControl = .play
        resetFocus(in: focusScope)
        markInteraction()
        guard interaction.panel != .artwork, !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled, isActive, interaction.panel != .artwork else { return }
        withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
            expandsStage = true
        }
    }

    @MainActor
    private func animateBackgroundIfNeeded() async {
        backgroundBreathes = false
        guard player.currentTrack?.artworkURL != nil, !reduceMotion else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
            backgroundBreathes = true
        }
    }

    @MainActor
    private func hideControlsAfterIdleIfNeeded() async {
        guard isActive,
              detailPath.isEmpty,
              interaction.showsControls,
              interaction.panel != .queue,
              !isInfoPresented,
              player.currentTrack != nil,
              player.isPlaying,
              focusedControl != .moreActions else { return }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled,
              isActive,
              detailPath.isEmpty,
              interaction.showsControls,
              interaction.panel != .queue,
              !isInfoPresented,
              player.isPlaying,
              focusedControl != .moreActions else { return }
        interaction.hideControlsForIdle()
        requestControlFocus(.immersive)
    }

    private func markInteraction() {
        idleGeneration &+= 1
    }

    private func requestEmptyPlayerFocus() {
        Task { @MainActor in
            await Task.yield()
            guard isActive, player.currentTrack == nil else { return }
            focusedControl = .emptyReturn
            resetFocus(in: focusScope)
        }
    }

    private func closeInfoPanel() {
        focusedControl = nil
        focusedQueueID = nil
        isInfoPresented = false
        markInteraction()
        Task { @MainActor in
            await Task.yield()
            guard interaction.showsControls, detailPath.isEmpty else { return }
            requestControlFocus(.info)
        }
    }

    private var playbackBadgeText: String? {
        if let source = player.alternativeSource {
            return "补全音源 · \(source)"
        }
        if player.isTrial {
            return "试听片段"
        }
        if let quality = player.servedQuality {
            return AudioQuality.displayName(for: quality)
        }
        return nil
    }

    private var hasNavigableLyrics: Bool {
        guard interaction.panel == .lyrics,
              let lines = player.lyrics?.lines else { return false }
        return !lines.isEmpty
    }

    private func stopDetailPlaybackIfNeeded() {
        if case .mv = detailPath.last {
            MVPlaybackController.shared.stop()
        }
    }
}

private struct NowPlayingExitCommand: ViewModifier {
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

private struct NowPlayingImmersiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private enum NowPlayingInfoFocus: Hashable {
    case artist(Int)
    case album
}

private struct NowPlayingInfoPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus

    let track: Track
    let duration: TimeInterval
    let playbackBadge: String?
    let artists: [ArtistRef]
    let album: AlbumRef?
    let openArtist: (ArtistRef) -> Void
    let openAlbum: (AlbumRef) -> Void

    @Namespace private var focusScope
    @FocusState private var focusedAction: NowPlayingInfoFocus?

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            ArtworkView(url: track.artworkURL, cornerRadius: 16)
                .frame(width: 158, height: 158)
                .shadow(color: .black.opacity(0.32), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 8) {
                Text(track.name)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(metadataSummary)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(DisplayFormatter.duration(duration))
                    .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))

                if let playbackBadge {
                    Text(playbackBadge)
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(.white.opacity(0.78))
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                if let album {
                    Button("前往专辑") {
                        openAlbum(album)
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .album)
                    .prefersDefaultFocus(preferredFocus == .album, in: focusScope)
                }

                if artists.count == 1, let artist = artists.first {
                    Button("前往艺人") {
                        openArtist(artist)
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .artist(artist.id))
                    .prefersDefaultFocus(preferredFocus == .artist(artist.id), in: focusScope)
                } else if artists.count > 1, let firstArtist = artists.first {
                    Menu {
                        ForEach(artists) { artist in
                            Button(artist.name) {
                                openArtist(artist)
                            }
                        }
                    } label: {
                        Text("前往艺人")
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .artist(firstArtist.id))
                    .prefersDefaultFocus(preferredFocus == .artist(firstArtist.id), in: focusScope)
                    .accessibilityLabel("选择要前往的艺人")
                }
            }
            .frame(width: 340)
            .focusSection()
        }
        .padding(.horizontal, 24)
        .frame(height: 240)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .focusScope(focusScope)
        .task {
            guard let preferredFocus else { return }
            focusedAction = preferredFocus
            await Task.yield()
            guard !Task.isCancelled else { return }
            resetFocus(in: focusScope)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focusedAction)
    }

    private var metadataSummary: String {
        let artist = track.artistNames
        let album = track.album.name
        if artist.isEmpty { return album }
        if album.isEmpty { return artist }
        return "\(artist) — \(album)"
    }

    private var preferredFocus: NowPlayingInfoFocus? {
        if album != nil {
            return .album
        }
        if let artist = artists.first {
            return .artist(artist.id)
        }
        return nil
    }
}

private struct NowPlayingSyncedLyrics: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PlayerService.self) private var player

    let lines: [LyricLine]
    let showsTranslatedLyrics: Bool
    let selectedIndex: Int?
    let viewportHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            lyricTrack(availableWidth: proxy.size.width)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: viewportHeight,
            maxHeight: viewportHeight,
            alignment: .topLeading
        )
    }

    private func lyricTrack(availableWidth: CGFloat) -> some View {
        let activeLyricIndex = player.activeLyricIndex
        let anchorIndex = validIndex(selectedIndex) ?? validIndex(activeLyricIndex) ?? 0
        let emphasizedIndex = validIndex(selectedIndex) ?? validIndex(activeLyricIndex) ?? anchorIndex
        let layouts = rowLayouts(availableWidth: availableWidth)
        let anchorOrigin = layouts[anchorIndex].originY
        let visibleIndices = viewportIndices(around: anchorIndex)

        return ZStack(alignment: .topLeading) {
            ForEach(visibleIndices, id: \.self) { index in
                let line = lines[index]
                let layout = layouts[index]
                let emphasized = index == emphasizedIndex
                let opacity = primaryOpacity(for: index - emphasizedIndex)

                lyricRow(
                    line,
                    selected: index == selectedIndex,
                    primaryOpacity: opacity
                )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: layout.metrics.height,
                        maxHeight: layout.metrics.height,
                        alignment: .topLeading
                    )
                    .offset(y: lyricAnchorY + layout.originY - anchorOrigin)
                    .zIndex(emphasized ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: viewportHeight, maxHeight: viewportHeight, alignment: .topLeading)
        .clipped()
        .mask(lyricViewportMask)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .smooth(duration: 0.56), value: anchorIndex)
        .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: showsTranslatedLyrics)
    }

    private func lyricRow(
        _ line: LyricLine,
        selected: Bool,
        primaryOpacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(
                    size: lyricFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, selected ? lyricSelectionBadgeClearance : 0)

            if showsTranslatedLyrics,
               let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(secondaryColor(primaryOpacity: primaryOpacity, emphasis: 0.78))
            } else if showsTranslatedLyrics,
                      let romaji = line.romaji, !romaji.isEmpty {
                Text(romaji)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(secondaryColor(primaryOpacity: primaryOpacity, emphasis: 0.54))
            }
        }
        .padding(.horizontal, lyricHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.white.opacity(primaryOpacity))
        .overlay(alignment: .topTrailing) {
            if selected {
                Text(DisplayFormatter.duration(line.time))
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())
                    .padding(.top, 12)
                    .padding(.trailing, 8)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.46), value: primaryOpacity)
        .accessibilityLabel(line.text.isEmpty ? "音乐间奏" : line.text)
        .accessibilityValue(DisplayFormatter.duration(line.time))
    }

    private var lyricViewportMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.025),
                .init(color: .black, location: 0.76),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func viewportIndices(around anchorIndex: Int) -> [Int] {
        let lowerBound = max(anchorIndex - 2, lines.startIndex)
        let upperBound = min(anchorIndex + 5, lines.index(before: lines.endIndex))
        return Array(lowerBound...upperBound)
    }

    private func rowLayouts(availableWidth: CGFloat) -> [RowLayout] {
        var nextOrigin: CGFloat = 0
        return lines.indices.map { index in
            let metrics = rowMetrics(
                for: lines[index],
                availableWidth: availableWidth,
                selected: index == selectedIndex
            )
            defer { nextOrigin += metrics.height + lyricRowSpacing }
            return RowLayout(originY: nextOrigin, metrics: metrics)
        }
    }

    private func rowMetrics(
        for line: LyricLine,
        availableWidth: CGFloat,
        selected: Bool
    ) -> RowMetrics {
        let lyricText = line.text.isEmpty ? "♪" : line.text
        let contentWidth = max(
            1,
            availableWidth
                - lyricHorizontalPadding * 2
                - (selected ? lyricSelectionBadgeClearance : 0)
        )
        let primaryHeight = measuredTextHeight(
            lyricText,
            font: roundedFont(size: lyricFontSize, weight: .bold),
            width: contentWidth
        )

        let supplemental: (text: String, font: UIFont)? = if showsTranslatedLyrics {
            if let translation = line.translation, !translation.isEmpty {
                (translation, roundedFont(size: 26, weight: .semibold))
            } else if let romaji = line.romaji, !romaji.isEmpty {
                (romaji, roundedFont(size: 24, weight: .semibold))
            } else {
                nil
            }
        } else {
            nil
        }
        let supplementalHeight = supplemental.map {
            lyricSupplementalSpacing
                + measuredTextHeight($0.text, font: $0.font, width: contentWidth)
        } ?? 0

        return RowMetrics(
            height: primaryHeight + supplementalHeight + lyricRowBottomBreathingRoom
        )
    }

    private var lyricAnchorY: CGFloat { 24 }
    private var lyricRowSpacing: CGFloat { 16 }
    private var lyricFontSize: CGFloat { 80 }
    private var lyricHorizontalPadding: CGFloat { 14 }
    private var lyricSelectionBadgeClearance: CGFloat { 92 }
    private var lyricSupplementalSpacing: CGFloat { 7 }
    private var lyricRowBottomBreathingRoom: CGFloat { 68 }

    private func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func measuredTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(max(font.lineHeight, bounds.height))
    }

    private func validIndex(_ index: Int?) -> Int? {
        guard let index, lines.indices.contains(index) else { return nil }
        return index
    }

    private func primaryOpacity(for distance: Int) -> Double {
        switch abs(distance) {
        case 0: 1
        case 1: 0.38
        case 2: 0.27
        case 3: 0.19
        default: 0.13
        }
    }

    private func secondaryColor(primaryOpacity: Double, emphasis: Double) -> Color {
        let opacity = primaryOpacity == 1
            ? emphasis
            : min(primaryOpacity, max(0.12, primaryOpacity * 0.82))
        return .white.opacity(opacity)
    }

    private struct RowLayout {
        let originY: CGFloat
        let metrics: RowMetrics
    }

    private struct RowMetrics {
        let height: CGFloat
    }
}

private struct NowPlayingTimeline: View {
    @Environment(PlayerService.self) private var player

    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onFocusChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 5) {
            TVSeekBar(
                progress: player.progress,
                duration: player.duration,
                isEnabled: isEnabled,
                onSeek: onSeek,
                onFocusChange: onFocusChange
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

private struct TVSeekBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFocused = false

    let progress: TimeInterval
    let duration: TimeInterval
    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onFocusChange: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ratio = duration > 0 ? min(max(progress / duration, 0), 1) : 0
            let trackHeight: CGFloat = isFocused ? 12 : 7
            let knobSize: CGFloat = isFocused ? 24 : 10
            let knobOffset = min(max(width * ratio - knobSize / 2, 0), max(width - knobSize, 0))

            ZStack {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(isFocused ? 0.34 : 0.22))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(isFocused ? Color.white : TVTheme.accent)
                        .frame(width: width * ratio, height: trackHeight)

                    Circle()
                        .fill(.white)
                        .frame(width: knobSize, height: knobSize)
                        .offset(x: knobOffset)
                }
                .frame(width: width, height: proxy.size.height)

                TVSeekControlView(
                    progress: progress,
                    duration: duration,
                    isEnabled: isEnabled,
                    isFocused: $isFocused,
                    onSeek: onSeek
                )
                .frame(width: width, height: 40)
            }
            .frame(width: width, height: proxy.size.height)
        }
        .frame(height: 32)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            onFocusChange(focused)
        }
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(DisplayFormatter.duration(progress)) / \(DisplayFormatter.duration(duration))")
        .accessibilityHint("左右轻扫可快退或快进十秒")
    }
}

private struct TVSeekControlView: UIViewRepresentable {
    let progress: TimeInterval
    let duration: TimeInterval
    let isEnabled: Bool
    @Binding var isFocused: Bool
    let onSeek: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> TVSeekControl {
        let control = TVSeekControl()
        control.focusDidChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.isFocused.wrappedValue = focused
        }
        return control
    }

    func updateUIView(_ control: TVSeekControl, context: Context) {
        context.coordinator.isFocused = $isFocused
        control.isEnabled = isEnabled && duration > 0
        control.seekBy = { offset in
            onSeek(min(max(progress + offset, 0), duration))
        }
        control.accessibilityLabel = "播放进度"
        control.accessibilityValue = "\(DisplayFormatter.duration(progress)) / \(DisplayFormatter.duration(duration))"
        control.accessibilityHint = "左右轻扫可快退或快进十秒"
    }

    final class Coordinator {
        var isFocused: Binding<Bool>

        init(isFocused: Binding<Bool>) {
            self.isFocused = isFocused
        }
    }
}

private final class TVSeekControl: UIControl {
    var seekBy: ((TimeInterval) -> Void)?
    var focusDidChange: ((Bool) -> Void)?

    override var canBecomeFocused: Bool { isEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self else { return }
            self.focusDidChange?(self.isFocused)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow:
                seekBy?(-10)
                handled = true
            case .rightArrow:
                seekBy?(10)
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func accessibilityIncrement() {
        seekBy?(10)
    }

    override func accessibilityDecrement() {
        seekBy?(-10)
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
    let isEnabled: Bool
    let focus: FocusState<NowPlayingFocus?>.Binding
    let openDetail: (AppRoute) -> Void

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
                    openDetail(.album(album.id))
                }
            }

            if artists.count == 1, let artist = artists.first {
                Button("查看歌手“\(artist.name)”") {
                    openDetail(.artist(artist.id))
                }
            } else if artists.count > 1 {
                Menu("查看歌手") {
                    ForEach(artists) { artist in
                        Button(artist.name) {
                            openDetail(.artist(artist.id))
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
        .buttonStyle(NowPlayingActionButtonStyle(size: 62))
        .focused(focus, equals: .moreActions)
        .disabled(!isEnabled)
        .accessibilityLabel("更多操作")
    }
}

private struct NowPlayingActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(isFocused ? Color.black : (active ? TVTheme.accent : Color.white.opacity(0.94)))
            .background {
                Circle().fill(isFocused ? Color.white : Color.white.opacity(active ? 0.17 : 0.11))
            }
            .overlay {
                Circle().stroke(Color.white.opacity(isFocused ? 0.92 : 0.09), lineWidth: isFocused ? 2.5 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.10 : (configuration.isPressed ? 0.95 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.36 : 0.10), radius: isFocused ? 16 : 7, y: 7)
            .opacity(isEnabled ? 1 : 0.32)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

private struct NowPlayingModeButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat
    var active: Bool
    var usesFocusFallback: Bool

    func makeBody(configuration: Configuration) -> some View {
        let showsFocus = isFocused || usesFocusFallback
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(showsFocus || active ? Color.black : Color.white.opacity(0.92))
            .background {
                Circle().fill(showsFocus || active ? Color.white : Color.clear)
            }
            .scaleEffect(showsFocus && !reduceMotion ? 1.08 : (configuration.isPressed ? 0.95 : 1))
            .shadow(color: .black.opacity(showsFocus ? 0.30 : 0), radius: 14, y: 7)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: showsFocus)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
    }
}

private struct NowPlayingInfoDestinationButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.90))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.13))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.92 : 0.08), lineWidth: isFocused ? 2 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.035 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

private struct NowPlayingInfoButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .padding(.horizontal, 18)
            .frame(height: 48)
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.86))
            .background(
                Capsule()
                    .fill(isFocused ? Color.white : Color.white.opacity(0.10))
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isFocused ? 0.9 : 0.12), lineWidth: 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .opacity(isEnabled ? 1 : 0.3)
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
