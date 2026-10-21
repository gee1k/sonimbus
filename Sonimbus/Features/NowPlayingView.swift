import SwiftUI
import UIKit

private enum NowPlayingFocus: Hashable {
    case emptyReturn
    case emptyResume
    case emptyFM
    case immersive
    case fmDislike
    case intelligence
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
    case queue
}

struct NowPlayingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus
    @Environment(PlayerService.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(ToastCenter.self) private var toast
    @Environment(\.openRouteFromNowPlaying) private var openRouteFromNowPlaying
    @Namespace private var focusScope
    let isActive: Bool
    let activationGeneration: Int
    let onDismiss: () -> Void
    @State private var interaction = NowPlayingInteractionState()
    @State private var idleGeneration = 0
    @State private var expandsStage = false
    @State private var backgroundBreathes = false
    @State private var isInfoPresented = false
    @State private var isMorePresented = false
    @State private var queueFocusRequest: PlaybackQueueFocusRequest?
    @State private var queueFocusGeneration = 0
    @State private var requestedControlFocus: NowPlayingFocus? = .play
    @State private var isTimelineFocusEnabled = true
    @State private var modeFocusFallback: NowPlayingFocus?
    @State private var pendingPlaybackFocusTrackID: Int?
    @FocusState private var focusedControl: NowPlayingFocus?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("now-playing-page")
                .allowsHitTesting(false)
            background
            if player.currentTrack == nil {
                emptyPlayer
            } else {
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
                                openDetail(.artist(artist.id))
                            },
                            openAlbum: { album in
                                isInfoPresented = false
                                openDetail(.album(album.id))
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        playbackChrome
                            .task(id: pendingPlaybackFocusTrackID) {
                                await fulfillPendingPlaybackFocus()
                            }
                    }
                }
                .disabled(isMorePresented)
                .padding(.horizontal, 76)
                .padding(.vertical, 22)
                // An input overlay stays registered and unobscured while the
                // controls animate, so consecutive remote presses remain valid.
                immersiveSurface
                    .disabled(interaction.showsControls || isInfoPresented || isMorePresented)
                    .allowsHitTesting(!interaction.showsControls && !isInfoPresented && !isMorePresented)
                    .accessibilityHidden(interaction.showsControls)
                    .opacity(interaction.showsControls ? 0 : 1)
                    .transaction { $0.animation = nil }
            }
            toastOverlay
            if isMorePresented, let track = player.currentTrack {
                NowPlayingMoreActionsPanel(track: track, isLiked: account.isLiked(track),
                                           ownedPlaylists: account.ownedPlaylists,
                                           sourcePlaylistID: player.source.playlistID,
                                           album: navigableAlbum, artists: navigableArtists,
                                           close: closeMoreActions, openDetail: { route in
                                               isMorePresented = false
                                               openDetail(route)
                                           })
                    .transition(.opacity)
            }
        }
        .focusScope(focusScope)
        .modifier(
            NowPlayingExitCommand(
                isActive: true,
                action: handlePlayerExit
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: interaction.showsControls)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isInfoPresented)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isMorePresented)
        .task(id: activationGeneration) {
            await activatePlayerIfNeeded()
        }
        .task(id: player.currentTrack?.id) {
            await animateBackgroundIfNeeded()
            await expandStageIfNeeded()
        }
        .task(id: idleGeneration) {
            await hideControlsAfterIdleIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                isInfoPresented = false
                isMorePresented = false
                modeFocusFallback = nil
                focusedControl = nil
                idleGeneration &+= 1
            }
        }
        .onChange(of: player.currentTrack?.id) { oldID, newID in
            guard isActive else { return }
            if oldID != newID, let newID {
                isInfoPresented = false
                interaction.clearLyricSelection()
                // Keep the view identity, current control and immersive mode when
                // a song changes. Only an empty-to-playing transition needs focus.
                if oldID == nil {
                    interaction.showControls()
                    pendingPlaybackFocusTrackID = newID
                }
                markInteraction()
            } else if newID == nil {
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                if player.isLoadingPersonalFM {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: player.source == .personalFM ? "dot.radiowaves.left.and.right" : "music.note")
                        .font(.system(size: 96, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .frame(width: 320, height: 320)
            .shadow(color: .black.opacity(0.34), radius: 30, y: 16)

            Text(emptyTitle)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .padding(.top, 46)

            Text(emptyMessage)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(TVTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            HStack(spacing: 24) {
                if !player.isLoadingPersonalFM {
                    if player.source != .personalFM, !player.recentTracks.isEmpty {
                        Button {
                            player.play(player.recentTracks, source: .recent)
                        } label: {
                            Label("播放最近听过", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: emptyPrimaryFocus == .emptyResume))
                        .focused($focusedControl, equals: .emptyResume)
                        .prefersDefaultFocus(emptyPrimaryFocus == .emptyResume, in: focusScope)
                    }

                    if account.isLoggedIn {
                        Button {
                            player.startPersonalFM()
                        } label: {
                            Label(
                                player.source == .personalFM ? "重试私人 FM" : "私人 FM",
                                systemImage: "dot.radiowaves.left.and.right"
                            )
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: emptyPrimaryFocus == .emptyFM))
                        .focused($focusedControl, equals: .emptyFM)
                        .prefersDefaultFocus(emptyPrimaryFocus == .emptyFM, in: focusScope)
                    }
                }

                Button(action: onDismiss) {
                    Label("返回", systemImage: "chevron.backward")
                }
                .buttonStyle(TVPillButtonStyle())
                .focused($focusedControl, equals: .emptyReturn)
                .prefersDefaultFocus(emptyPrimaryFocus == .emptyReturn, in: focusScope)
                .accessibilityLabel("返回")
                .accessibilityHint("返回之前的标签页")
            }
            .labelStyle(.titleAndIcon)
            .padding(.top, 52)
            .focusSection()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(76)
    }

    private var emptyTitle: String {
        if player.isLoadingPersonalFM { return "正在为你挑选音乐…" }
        if player.source == .personalFM { return "私人 FM 暂时没有新推荐" }
        return "未在播放"
    }

    private var emptyMessage: String {
        if player.isLoadingPersonalFM { return "私人 FM 会根据你的听歌偏好持续更新。" }
        if player.source == .personalFM { return "稍后再试一次，或先从资料库挑一首歌。" }
        return "从歌单、专辑或推荐中选择一首歌开始播放。"
    }

    private var emptyPrimaryFocus: NowPlayingFocus {
        guard !player.isLoadingPersonalFM else { return .emptyReturn }
        if player.source != .personalFM, !player.recentTracks.isEmpty { return .emptyResume }
        if account.isLoggedIn { return .emptyFM }
        return .emptyReturn
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
        .frame(height: 44)
        .opacity(interaction.showsControls ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var immersiveSurface: some View {
        ImmersivePlaybackControl(onSelect: handleImmersiveSelection,
                                 onMove: handleImmersiveMove, onSkip: handleImmersiveSkip,
                                 onFocusReleased: { restoreControlsAfterNativeFocus(.play) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focused($focusedControl, equals: .immersive)
        .prefersDefaultFocus(!interaction.showsControls, in: focusScope)
        .accessibilityLabel("播放中")
        .accessibilityHint(
            interaction.chromeMode == .lyricsNavigation
                ? "上下选择歌词，点按跳转播放"
                : "点按显示控制，长按左键上一首，长按右键下一首"
        )
    }

    private var stage: some View {
        let showsLyrics = expandsStage && interaction.contentPanel == .lyrics
        let showsQueue = expandsStage && interaction.panel == .queue
        return ZStack {
            HStack(alignment: .center, spacing: 70) {
                artworkAndMetadata(size: showsLyrics ? 500 : 520)

                if showsLyrics {
                    lyricsPanel
                        .accessibilityIdentifier("now-playing-lyrics-panel")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focusSection()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(showsQueue ? 0 : 1)
            .disabled(showsQueue)
            .accessibilityHidden(showsQueue)
            if showsQueue {
                queuePanel
                    .accessibilityIdentifier("now-playing-queue-panel")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(height: stageHeight)
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

    private var stageHeight: CGFloat { 700 }

    private func artworkAndMetadata(size: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 0) {
            ArtworkView(url: player.currentTrack?.artworkURL, cornerRadius: 26)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.52), radius: 40, y: 22)

            VStack(spacing: 6) {
                Text(player.currentTrack?.name ?? "")
                    .accessibilityIdentifier("now-playing-track-title")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let artistNames = player.currentTrack?.artistNames, !artistNames.isEmpty {
                    Text(artistNames)
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let album = navigableAlbum {
                    Text(album.name)
                        .font(.system(size: 25, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
        .frame(width: size + 120)
    }

    @ViewBuilder
    private var songActions: some View {
        if let track = player.currentTrack {
            HStack(spacing: 10) {
                songInfoButton

                Button {
                    Task { await account.toggleLike(track) }
                } label: {
                    Image(systemName: account.isLiked(track) ? "star.fill" : "star")
                }
                .buttonStyle(NowPlayingGlyphButtonStyle(active: account.isLiked(track)))
                .focused($focusedControl, equals: .favorite)
                .prefersDefaultFocus(requestedControlFocus == .favorite, in: focusScope)
                .disabled(!interaction.showsControls)
                .accessibilityLabel(account.isLiked(track) ? "取消喜欢" : "喜欢")

                if player.source == .personalFM {
                    Button {
                        player.dislikeCurrentFM()
                    } label: {
                        Image(systemName: "hand.thumbsdown")
                    }
                    .buttonStyle(NowPlayingGlyphButtonStyle())
                    .focused($focusedControl, equals: .fmDislike)
                    .prefersDefaultFocus(requestedControlFocus == .fmDislike, in: focusScope)
                    .disabled(!interaction.showsControls)
                    .accessibilityLabel("减少类似推荐并播放下一首")
                } else if let playlistID = intelligencePlaylistID {
                    Button {
                        toggleIntelligence(from: track, playlistID: playlistID)
                    } label: {
                        if player.isLoadingIntelligence {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: player.isIntelligenceActive ? "bolt.heart.fill" : "bolt.heart")
                        }
                    }
                    .buttonStyle(NowPlayingGlyphButtonStyle(active: player.isIntelligenceActive))
                    .focused($focusedControl, equals: .intelligence)
                    .prefersDefaultFocus(requestedControlFocus == .intelligence, in: focusScope)
                    .disabled(!interaction.showsControls)
                    .accessibilityLabel(player.isLoadingIntelligence ? "取消开启心动模式" :
                                            (player.isIntelligenceActive ? "退出心动模式" : "从这首开启心动模式"))
                }

                moreActionsMenu(for: track)
            }
            .nowPlayingControlGroup()
            .focusSection()
        }
    }

    private func moreActionsMenu(for track: Track) -> some View {
        Button {
            isMorePresented = true
            markInteraction()
        } label: { Image(systemName: "ellipsis") }
        .buttonStyle(NowPlayingGlyphButtonStyle())
        .focused($focusedControl, equals: .moreActions)
        .prefersDefaultFocus(requestedControlFocus == .moreActions, in: focusScope)
        .disabled(!interaction.showsControls)
        .accessibilityLabel("更多操作")
    }

    private var lyricsPanel: some View {
        let viewportHeight: CGFloat = interaction.showsControls ? 480 : 680
        let verticalOffset: CGFloat = 150

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
                .offset(y: verticalOffset)
                .frame(height: stageHeight, alignment: .top)
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
                    .prefersDefaultFocus(requestedControlFocus == .lyricsRetry, in: focusScope)
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
            if player.playbackQueue.isEmpty {
                EmptyStateView(title: "当前队列为空", message: "私人 FM 会按播放进度持续加入歌曲。",
                               symbol: "text.line.first.and.arrowtriangle.forward")
            } else {
                PlaybackQueueView(tracks: player.playbackQueue,
                                  currentID: player.currentTrack?.id,
                                  focusRequest: queueFocusRequest,
                                  onSelect: { player.playTrack($0) },
                                  onRemove: { player.removeFromQueue($0) },
                                  onFocusReleased: { restoreControlsAfterNativeFocus(.queueMode) })
                    .focused($focusedControl, equals: .queue)
                    .prefersDefaultFocus(requestedControlFocus == .queue, in: focusScope)
            }
        }
        .focusSection()
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
        VStack(spacing: 16) {
            NowPlayingTimeline(
                isEnabled: interaction.showsControls && isTimelineFocusEnabled,
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
                songActions
                    .frame(maxWidth: .infinity, alignment: .leading)

                transportControls

                HStack(spacing: 12) {
                    panelButton(.lyrics, symbol: "quote.bubble.fill", focus: .lyricsMode, label: "歌词")
                    panelButton(.queue, symbol: "list.bullet", focus: .queueMode, label: "播放队列")
                }
                .nowPlayingControlGroup()
                .focusSection()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 84)
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .frame(height: 180)
        .opacity(interaction.showsControls ? 1 : 0)
        .allowsHitTesting(interaction.showsControls)
    }

    private var songInfoButton: some View {
        Button {
            focusedControl = nil
                isInfoPresented = true
            markInteraction()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(NowPlayingGlyphButtonStyle())
        .focused($focusedControl, equals: .info)
        .prefersDefaultFocus(requestedControlFocus == .info, in: focusScope)
        .disabled(!interaction.showsControls)
        .accessibilityLabel("查看歌曲信息")
    }

    private var transportControls: some View {
        HStack(spacing: 22) {
            if player.source != .personalFM {
                Button {
                    player.toggleShuffle()
                    markInteraction()
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(TVPlaybackButtonStyle(size: 54, active: player.shuffleEnabled))
                .focused($focusedControl, equals: .shuffle)
                .prefersDefaultFocus(requestedControlFocus == .shuffle, in: focusScope)
                .accessibilityLabel(player.shuffleEnabled ? "关闭随机播放" : "开启随机播放")
                .disabled(!interaction.showsControls)
            }

            Button {
                player.previous()
                markInteraction()
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 60))
            .focused($focusedControl, equals: .previous)
            .prefersDefaultFocus(requestedControlFocus == .previous, in: focusScope)
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
                .frame(width: 36, height: 36)
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 72, prominent: true))
            // Re-register the default focus item when controls are revealed;
            // keep its identity when songs or playback modes change.
            .id(interaction.showsControls)
            .focused($focusedControl, equals: .play)
            .prefersDefaultFocus(requestedControlFocus == .play, in: focusScope)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            .disabled(!interaction.showsControls)

            Button {
                player.next()
                markInteraction()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(TVPlaybackButtonStyle(size: 60))
            .focused($focusedControl, equals: .next)
            .prefersDefaultFocus(requestedControlFocus == .next, in: focusScope)
            .accessibilityLabel("下一首")
            .disabled(!player.canGoNext || !interaction.showsControls)

            if player.source != .personalFM {
                Button {
                    player.cycleRepeat()
                    markInteraction()
                } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                }
                .buttonStyle(TVPlaybackButtonStyle(size: 54, active: player.repeatMode != .off))
                .focused($focusedControl, equals: .repeatMode)
                .prefersDefaultFocus(requestedControlFocus == .repeatMode, in: focusScope)
                .accessibilityLabel(repeatAccessibilityLabel)
                .disabled(!interaction.showsControls)
            }
        }
        .fixedSize()
        .padding(.horizontal, 28)
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
        .prefersDefaultFocus(requestedControlFocus == focus, in: focusScope)
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
            showControls(preferredFocus: .play)
        }
        markInteraction()
    }

    private func handleImmersiveSkip(_ direction: MoveCommandDirection) {
        guard !interaction.showsControls else { return }
        if direction == .left { player.previous(restartCurrent: false) }
        if direction == .right { player.next() }
        interaction.clearLyricSelection()
        markInteraction()
    }

    private func closeMoreActions() {
        isMorePresented = false
        markInteraction()
        Task { @MainActor in
            await Task.yield()
            requestControlFocus(.moreActions)
        }
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
        requestedControlFocus = target
        focusedControl = nil
        Task { @MainActor in
            await Task.yield()
            guard isActive, requestedControlFocus == target else { return }
            focusedControl = target
            resetFocus(in: focusScope)
        }
    }

    private func restoreControlsAfterNativeFocus(_ target: NowPlayingFocus) {
        guard isActive, player.currentTrack != nil, interaction.showsControls,
              interaction.panel != .queue, !isMorePresented, !isInfoPresented else { return }
        requestControlFocus(target)
    }

    @MainActor
    private func fulfillPendingPlaybackFocus() async {
        guard let trackID = pendingPlaybackFocusTrackID else { return }
        await Task.yield()
        guard !Task.isCancelled,
              isActive,
              player.currentTrack?.id == trackID,
              interaction.panel != .queue,
              !isInfoPresented else { return }
        pendingPlaybackFocusTrackID = nil
        requestControlFocus(.play)
    }

    private func showControls(preferredFocus: NowPlayingFocus? = nil) {
        interaction.showControls()
        focusedControl = nil
        guard let preferredFocus else {
            isTimelineFocusEnabled = true
            return
        }
        isTimelineFocusEnabled = false
        Task { @MainActor in
            defer { isTimelineFocusEnabled = true }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled,
                  isActive,
                  interaction.showsControls,
                  interaction.panel != .queue,
                  !isInfoPresented else { return }
            requestControlFocus(preferredFocus)
        }
    }

    private func requestQueueFocus(_ requestedTrackID: Int? = nil) {
        let tracks = player.playbackQueue
        let target = requestedTrackID ?? player.currentTrack?.id ?? tracks.first?.id
        guard let target, tracks.contains(where: { $0.id == target }) else {
            requestControlFocus(.queueMode)
            return
        }
        requestedControlFocus = .queue
        focusedControl = .queue
        modeFocusFallback = nil
        queueFocusGeneration &+= 1
        queueFocusRequest = PlaybackQueueFocusRequest(trackID: target, generation: queueFocusGeneration)
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

    private var intelligencePlaylistID: Int? {
        guard let track = player.currentTrack, player.source != .personalFM else { return nil }
        if case .intelligence(let playlistID) = player.source { return playlistID }
        guard !track.noCopyright else { return nil }
        return account.likedSongsPlaylist?.id
    }

    private func toggleIntelligence(from track: Track, playlistID: Int) {
        if player.isIntelligenceActive || player.isLoadingIntelligence {
            player.stopIntelligence()
        } else {
            player.startIntelligence(from: track, playlistID: playlistID)
        }
        markInteraction()
    }

    private func handlePlayerExit() {
        if isMorePresented { closeMoreActions(); return }
        if isInfoPresented {
            closeInfoPanel()
            return
        }
        guard interaction.handleBack(
            hasCurrentTrack: player.currentTrack != nil,
            allowsLyricsNavigation: hasNavigableLyrics
        ) == .handled else {
            onDismiss()
            return
        }
        if interaction.panel == .queue {
            requestQueueFocus()
        } else if interaction.showsControls {
            requestControlFocus(.queueMode)
        } else {
            requestControlFocus(.immersive)
        }
        markInteraction()
    }

    private func openDetail(_ route: AppRoute) {
        focusedControl = nil
        openRouteFromNowPlaying?(route)
    }

    @MainActor
    private func activatePlayerIfNeeded() async {
        guard isActive else { return }
        interaction.activate()
        // The presentation transition already animates entry; a second delayed
        // layout change made the page feel like it settled twice.
        expandsStage = interaction.panel != .artwork
        isInfoPresented = false
        isTimelineFocusEnabled = true
        focusedControl = nil
        requestedControlFocus = .play
        await Task.yield()
        guard !Task.isCancelled, isActive else { return }
        guard player.currentTrack != nil else {
            pendingPlaybackFocusTrackID = nil
            requestEmptyPlayerFocus()
            return
        }
        pendingPlaybackFocusTrackID = player.currentTrack?.id
        markInteraction()
        await expandStageIfNeeded()
    }

    @MainActor
    private func expandStageIfNeeded() async {
        guard !expandsStage,
              isActive,
              player.currentTrack != nil,
              interaction.panel != .artwork else { return }
        if reduceMotion {
            expandsStage = true
        } else {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
                expandsStage = true
            }
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
              interaction.showsControls,
              interaction.panel != .queue,
              !isInfoPresented,
              !isMorePresented,
              player.currentTrack != nil,
              player.isPlaying,
              focusedControl != .moreActions else { return }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled,
              isActive,
              interaction.showsControls,
              interaction.panel != .queue,
              !isInfoPresented,
              !isMorePresented,
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
            focusedControl = emptyPrimaryFocus
            resetFocus(in: focusScope)
        }
    }

    private func closeInfoPanel() {
        focusedControl = nil
        isInfoPresented = false
        markInteraction()
        Task { @MainActor in
            await Task.yield()
            guard interaction.showsControls else { return }
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
        HStack(alignment: .center, spacing: 30) {
            ArtworkView(url: track.artworkURL, cornerRadius: 16)
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.32), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if !track.artistNames.isEmpty {
                    Text(track.artistNames)
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Text(metadataSummary)
                        .lineLimit(1)
                    if let playbackBadge {
                        Text(playbackBadge)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white.opacity(0.82))
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                }
                .font(.system(size: 23, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.52))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                if let album {
                    Button {
                        openAlbum(album)
                    } label: {
                        Label("前往专辑", systemImage: "square.stack")
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .album)
                    .prefersDefaultFocus(preferredFocus == .album, in: focusScope)
                    .accessibilityLabel("前往专辑")
                }

                if artists.count == 1, let artist = artists.first {
                    Button {
                        openArtist(artist)
                    } label: {
                        Label("前往艺人", systemImage: "music.mic")
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .artist(artist.id))
                    .prefersDefaultFocus(preferredFocus == .artist(artist.id), in: focusScope)
                    .accessibilityLabel("前往艺人")
                } else if artists.count > 1, let firstArtist = artists.first {
                    Menu {
                        ForEach(artists) { artist in
                            Button(artist.name) {
                                openArtist(artist)
                            }
                        }
                    } label: {
                        Label("前往艺人", systemImage: "music.mic")
                    }
                    .buttonStyle(NowPlayingInfoDestinationButtonStyle())
                    .focused($focusedAction, equals: .artist(firstArtist.id))
                    .prefersDefaultFocus(preferredFocus == .artist(firstArtist.id), in: focusScope)
                    .accessibilityLabel("选择要前往的艺人")
                }
            }
            .focusSection()
        }
        .padding(.horizontal, 26)
        .frame(height: 180)
        .glassPanel(cornerRadius: 32)
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
        [track.album.name, DisplayFormatter.duration(duration)]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
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
        lyricTrack
            .frame(
                maxWidth: .infinity,
                minHeight: viewportHeight,
                maxHeight: viewportHeight,
                alignment: .topLeading
            )
    }

    private var lyricTrack: some View {
        let activeLyricIndex = player.activeLyricIndex
        let anchorIndex = validIndex(selectedIndex) ?? validIndex(activeLyricIndex) ?? 0
        let emphasizedIndex = validIndex(selectedIndex) ?? validIndex(activeLyricIndex) ?? anchorIndex

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: lyricRowSpacing) {
                    ForEach(lines.indices, id: \.self) { index in
                        let line = lines[index]
                        let opacity = primaryOpacity(for: index - emphasizedIndex)

                        lyricRow(
                            line,
                            selected: index == selectedIndex,
                            emphasized: index == emphasizedIndex,
                            primaryOpacity: opacity
                        )
                        .id(index)
                    }

                    Color.clear
                        .frame(height: viewportHeight)
                        .accessibilityHidden(true)
                }
            }
            .scrollDisabled(true)
            .allowsHitTesting(false)
            .frame(
                maxWidth: .infinity,
                minHeight: max(viewportHeight - lyricAnchorY, 1),
                maxHeight: max(viewportHeight - lyricAnchorY, 1),
                alignment: .topLeading
            )
            .padding(.top, lyricAnchorY)
            .frame(
                maxWidth: .infinity,
                minHeight: viewportHeight,
                maxHeight: viewportHeight,
                alignment: .topLeading
            )
            .mask(lyricViewportMask)
            .onAppear {
                scroll(to: anchorIndex, using: proxy, animated: false)
            }
            .onChange(of: anchorIndex) { _, newIndex in
                scroll(to: newIndex, using: proxy, animated: true)
            }
        }
    }

    private func lyricRow(
        _ line: LyricLine,
        selected: Bool,
        emphasized: Bool,
        primaryOpacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: lyricSupplementalSpacing) {
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
                    .font(.system(size: lyricTranslationFontSize, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(secondaryColor(primaryOpacity: primaryOpacity, emphasis: 0.78))
            } else if showsTranslatedLyrics,
                      let romaji = line.romaji, !romaji.isEmpty {
                Text(romaji)
                    .font(.system(size: lyricRomajiFontSize, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(secondaryColor(primaryOpacity: primaryOpacity, emphasis: 0.54))
            }
        }
        .padding(.horizontal, lyricHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.white.opacity(primaryOpacity))
        .scaleEffect(emphasized ? 1 : inactiveLyricScale, anchor: .leading)
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.56), value: emphasized)
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

    private var lyricAnchorY: CGFloat { 24 }
    private var lyricRowSpacing: CGFloat { 72 }
    private var lyricFontSize: CGFloat { 80 }
    private var lyricTranslationFontSize: CGFloat { 32 }
    private var lyricRomajiFontSize: CGFloat { 30 }
    private var lyricHorizontalPadding: CGFloat { 14 }
    private var lyricSelectionBadgeClearance: CGFloat { 92 }
    private var lyricSupplementalSpacing: CGFloat { 10 }
    private var inactiveLyricScale: CGFloat { 0.88 }

    private func scroll(to index: Int, using proxy: ScrollViewProxy, animated: Bool) {
        guard lines.indices.contains(index) else { return }
        if reduceMotion || !animated {
            proxy.scrollTo(index, anchor: .top)
        } else {
            withAnimation(.smooth(duration: 0.56)) {
                proxy.scrollTo(index, anchor: .top)
            }
        }
    }

    private func validIndex(_ index: Int?) -> Int? {
        guard let index, lines.indices.contains(index) else { return nil }
        return index
    }

    private func primaryOpacity(for distance: Int) -> Double {
        switch abs(distance) {
        case 0: 1
        case 1: 0.32
        case 2: 0.22
        case 3: 0.15
        default: 0.10
        }
    }

    private func secondaryColor(primaryOpacity: Double, emphasis: Double) -> Color {
        let opacity = primaryOpacity == 1
            ? emphasis
            : min(primaryOpacity, max(0.12, primaryOpacity * 0.82))
        return .white.opacity(opacity)
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

private struct NowPlayingMoreActionsPanel: View {
    @Environment(AccountStore.self) private var account
    @Namespace private var menuScope
    @State private var page = Page.actions
    @FocusState private var focusedItem: String?

    private enum Page { case actions, playlists, artists }
    let track: Track
    let isLiked: Bool
    let ownedPlaylists: [PlaylistSummary]
    let sourcePlaylistID: Int?
    let album: AlbumRef?
    let artists: [ArtistRef]
    let close: () -> Void
    let openDetail: (AppRoute) -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text(page == .playlists ? "添加到歌单" : (page == .artists ? "查看歌手" : "更多操作"))
                    .font(.system(size: 36, weight: .bold))
                Text(track.name).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                ScrollView {
                    VStack(spacing: 12) {
                        if page == .playlists {
                            ForEach(ownedPlaylists) { playlist in
                                item(playlist.name, id: "playlist-\(playlist.id)", symbol: "music.note.list") {
                                    Task { await account.add(track, to: playlist) }
                                    close()
                                }
                            }
                        } else if page == .artists {
                            ForEach(artists) { artist in
                                item(artist.name, id: "artist-\(artist.id)", symbol: "person") { openDetail(.artist(artist.id)) }
                            }
                        } else {
                            item(isLiked ? "取消喜欢" : "喜欢", id: "like", symbol: "star") {
                                Task { await account.toggleLike(track) }
                                close()
                            }
                            if !ownedPlaylists.isEmpty {
                                item("添加到歌单", id: "add-playlist", symbol: "text.badge.plus", submenu: true) {
                                    show(.playlists)
                                }
                                .onMoveCommand { if $0 == .right { show(.playlists) } }
                            }
                            if let album {
                                item("查看专辑《\(album.name)》", id: "album", symbol: "square.stack") { openDetail(.album(album.id)) }
                            }
                            if artists.count == 1, let artist = artists.first {
                                item("查看歌手“\(artist.name)”", id: "artist", symbol: "person") { openDetail(.artist(artist.id)) }
                            } else if artists.count > 1 {
                                item("查看歌手", id: "artists", symbol: "person", submenu: true) { show(.artists) }
                                    .onMoveCommand { if $0 == .right { show(.artists) } }
                            }
                            if let sourcePlaylistID,
                               let playlist = ownedPlaylists.first(where: { $0.id == sourcePlaylistID }) {
                                item("从《\(playlist.name)》中移除", id: "remove", symbol: "minus.circle") {
                                    Task { await account.remove(track, from: playlist) }
                                    close()
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                Text(page == .actions ? "按右键或确认键展开 · 返回键关闭" : "按左键或返回键返回")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(30)
            .frame(width: 680, height: 720)
            .glassPanel(cornerRadius: 30)
            .padding(.trailing, 76)
        }
        .focusScope(menuScope)
        .accessibilityIdentifier("now-playing-more-panel")
        .onExitCommand(perform: back)
        .onMoveCommand { if $0 == .left, page != .actions { back() } }
        .task { focusedItem = "like" }
    }

    private func item(_ title: String, id: String, symbol: String,
                      submenu: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol).frame(width: 32)
                Text(title).lineLimit(2)
                Spacer(minLength: 0)
                if submenu { Image(systemName: "chevron.right") }
            }
            .font(.system(size: 27, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        }
        .buttonStyle(TVCardButtonStyle(cornerRadius: 14, contentPadding: 18, focusedScale: 1.025))
        .focused($focusedItem, equals: id)
        .accessibilityIdentifier("player-menu-\(id)")
    }

    private func show(_ target: Page) {
        page = target
        Task { @MainActor in
            await Task.yield()
            focusedItem = target == .playlists ? ownedPlaylists.first.map { "playlist-\($0.id)" }
                : artists.first.map { "artist-\($0.id)" }
        }
    }

    private func back() {
        guard page != .actions else { close(); return }
        let target = page == .playlists ? "add-playlist" : "artists"
        page = .actions
        Task { @MainActor in
            await Task.yield()
            focusedItem = target
        }
    }
}

/// Borderless glyph that only lifts into a white disc while focused.
private struct NowPlayingGlyphButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 62
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(active ? TVTheme.accent : (isFocused ? Color.black : Color.white.opacity(0.92)))
            .background {
                Circle().fill(isFocused ? Color.white : Color.clear)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.08 : (configuration.isPressed ? 0.95 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.30 : 0), radius: isFocused ? 14 : 0, y: 7)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

private extension View {
    func nowPlayingControlGroup() -> some View {
        padding(8)
            .background(Color.white.opacity(0.11), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
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
            .labelStyle(.titleAndIcon)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 30)
            .frame(height: 70)
            .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.92))
            .background(Capsule().fill(isFocused ? Color.white : Color.white.opacity(0.13)))
            .overlay {
                Capsule().stroke(Color.white.opacity(isFocused ? 0.92 : 0.10), lineWidth: 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.32 : 0), radius: isFocused ? 16 : 0, y: 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}
