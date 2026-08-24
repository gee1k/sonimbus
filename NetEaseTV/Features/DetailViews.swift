import SwiftUI

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
                    metadata: "热门歌曲 · \(response.hotSongs.count) 首 · \(albums.count) 张专辑",
                    tracks: response.hotSongs,
                    source: .artist(response.artist.id),
                    circularArtwork: true,
                    collectionActionTitle: account.isArtistLiked(response.artist) ? "取消关注" : "关注歌手",
                    collectionActionSymbol: account.isArtistLiked(response.artist) ? "minus" : "plus",
                    collectionAction: account.isLoggedIn ? {
                        Task { await account.toggleArtist(response.artist) }
                    } : nil,
                    relatedAlbums: albums,
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
        async let similarRequest = try? NeteaseAPI.similarArtists(id: artistID)
        do {
            let detail = try await NeteaseAPI.artist(id: artistID)
            let albumResult = (await albumRequest)?.hotAlbums ?? []
            let artistResult = await similarRequest ?? []
            guard generation == loadGeneration, !Task.isCancelled else { return }
            albums = albumResult
            similarArtists = artistResult
            response = detail
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
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
