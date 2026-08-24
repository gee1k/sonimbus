import SwiftUI

struct LibraryView: View {
    @Environment(\.navigationFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.navigationFocusRestorationRoute) private var focusRestorationRoute
    @Environment(AccountStore.self) private var account
    @State private var showLogin = false
    @State private var isRefreshing = false
    @State private var showLogoutConfirmation = false
    @State private var showCreatePlaylist = false
    @State private var playlistPendingDeletion: PlaylistSummary?
    @State private var lastFocusedRoute: AppRoute?
    @FocusState private var focusedRoute: AppRoute?

    private var otherPlaylists: [PlaylistSummary] {
        guard let likedID = account.likedSongsPlaylist?.id else { return account.playlists }
        return account.playlists.filter { $0.id != likedID }
    }

    var body: some View {
        Group {
            if account.isLoggedIn {
                loggedInView
            } else if account.isBootstrapping {
                LoadStateView(title: "正在同步资料库")
                    .background(TVBackground(tint: .indigo))
            } else if account.hasAuthenticationCookie {
                accountSyncFailedView
            } else {
                loggedOutView
            }
        }
        .fullScreenCover(isPresented: $showLogin) { LoginView() }
        .fullScreenCover(isPresented: $showCreatePlaylist) { CreatePlaylistView() }
        .onChange(of: focusedRoute) { _, route in
            if let route { lastFocusedRoute = route }
        }
        .alert("退出网易云音乐？", isPresented: $showLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                Task { await account.logout() }
            }
        } message: {
            Text("本机保存的登录凭证会被移除，之后可以随时重新扫码登录。")
        }
        .alert(
            "删除歌单？",
            isPresented: Binding(
                get: { playlistPendingDeletion != nil },
                set: { if !$0 { playlistPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { playlistPendingDeletion = nil }
            Button("删除", role: .destructive) {
                guard let playlist = playlistPendingDeletion else { return }
                playlistPendingDeletion = nil
                Task { await account.deletePlaylist(playlist) }
            }
        } message: {
            Text("《\(playlistPendingDeletion?.name ?? "这个歌单")》会从网易云音乐账号中永久删除，此操作无法撤销。")
        }
    }

    private var loggedInView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                profileHeader
                if let liked = account.likedSongsPlaylist {
                    NavigationLink(value: AppRoute.playlist(liked.id)) {
                        HStack(spacing: 30) {
                            ZStack {
                                LinearGradient(colors: [TVTheme.magenta, TVTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 72, weight: .bold))
                            }
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("我喜欢的音乐").font(.system(size: 32, weight: .bold))
                                Text("\(liked.trackCount) 首歌曲")
                                    .font(.headline)
                                    .opacity(0.62)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.title2)
                        }
                        .padding(30)
                    }
                    .buttonStyle(TVCardButtonStyle(cornerRadius: 32, contentPadding: 0, focusedScale: 1.018))
                    .padding(.horizontal, TVTheme.horizontalPadding)
                    .focused($focusedRoute, equals: .playlist(liked.id))
                    .id(AppRoute.playlist(liked.id))
                    .simultaneousGesture(TapGesture().onEnded {
                        lastFocusedRoute = .playlist(liked.id)
                    })
                }

                HStack(spacing: 30) {
                    NavigationLink(value: AppRoute.recents) {
                        LibraryShortcutCard(
                            title: "最近播放",
                            subtitle: "网易云账号中的听歌记录",
                            symbol: "clock.fill",
                            colors: [.indigo, .blue]
                        )
                    }
                    .buttonStyle(TVHeroButtonStyle())
                    .focused($focusedRoute, equals: .recents)
                    .id(AppRoute.recents)
                    .simultaneousGesture(TapGesture().onEnded { lastFocusedRoute = .recents })

                    NavigationLink(value: AppRoute.cloud) {
                        LibraryShortcutCard(
                            title: "音乐云盘",
                            subtitle: "播放你上传到云盘的歌曲",
                            symbol: "icloud.fill",
                            colors: [TVTheme.magenta, .purple]
                        )
                    }
                    .buttonStyle(TVHeroButtonStyle())
                    .focused($focusedRoute, equals: .cloud)
                    .id(AppRoute.cloud)
                    .simultaneousGesture(TapGesture().onEnded { lastFocusedRoute = .cloud })
                }
                .padding(.horizontal, TVTheme.horizontalPadding)
                .focusSection()

                if !account.likedAlbums.isEmpty {
                    HorizontalShelf(title: "收藏的专辑") {
                        ForEach(account.likedAlbums) { album in
                            AlbumCard(album: album)
                                .focused($focusedRoute, equals: .album(album.id))
                                .id(AppRoute.album(album.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .album(album.id)
                                })
                        }
                    }
                }

                if !account.likedArtists.isEmpty {
                    HorizontalShelf(title: "关注的歌手") {
                        ForEach(account.likedArtists) { artist in
                            ArtistCard(artist: artist)
                                .focused($focusedRoute, equals: .artist(artist.id))
                                .id(AppRoute.artist(artist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .artist(artist.id)
                                })
                        }
                    }
                }

                if otherPlaylists.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(title: "我的歌单", subtitle: "创建与收藏的全部歌单")
                        EmptyStateView(
                            title: "还没有其他歌单",
                            message: "你创建或收藏的歌单会出现在这里。",
                            symbol: "music.note.list"
                        )
                        .frame(height: 210)
                    }
                } else {
                    HorizontalShelf(title: "我的歌单", subtitle: "创建与收藏的全部歌单") {
                        ForEach(otherPlaylists) { playlist in
                            PlaylistCard(playlist: playlist)
                                .focused($focusedRoute, equals: .playlist(playlist.id))
                                .id(AppRoute.playlist(playlist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .playlist(playlist.id)
                                })
                                .contextMenu {
                                    if account.ownsPlaylist(id: playlist.id) {
                                        Button("删除歌单", role: .destructive) {
                                            playlistPendingDeletion = playlist
                                        }
                                    }
                                }
                        }
                    }
                }
                }
                .padding(.top, 42)
                .padding(.bottom, 80)
            }
            .background(TVBackground(tint: .indigo))
            .task(id: focusRestorationGeneration) {
                await restoreNavigationFocus(using: proxy)
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 26) {
            ArtworkView(
                url: account.profile?.avatarUrl.flatMap { ArtworkURL.make($0, size: 240) },
                cornerRadius: 55,
                symbol: "person.fill"
            )
            .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(account.profile?.nickname ?? "网易云用户")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                MembershipStatusBadge(label: account.membershipLabel, isVIP: account.isVIP)
                if let signature = account.profile?.signature, !signature.isEmpty {
                    Text(signature)
                        .font(.system(size: 21, weight: .regular, design: .rounded))
                        .foregroundStyle(TVTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                showCreatePlaylist = true
            } label: {
                Label("新建歌单", systemImage: "plus")
            }
            .buttonStyle(TVPillButtonStyle())
            NavigationLink(value: AppRoute.settings) {
                Label("设置", systemImage: "gearshape.fill")
            }
            .buttonStyle(TVPillButtonStyle())
            .focused($focusedRoute, equals: .settings)
            .id(AppRoute.settings)
            .simultaneousGesture(TapGesture().onEnded { lastFocusedRoute = .settings })
            Button {
                Task {
                    isRefreshing = true
                    await account.refreshLibrary(showFeedback: true)
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("刷新中")
                    }
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(TVPillButtonStyle())
            .disabled(isRefreshing)
            Button("退出登录", role: .destructive) {
                showLogoutConfirmation = true
            }
            .buttonStyle(TVPillButtonStyle(destructive: true))
        }
        .padding(.horizontal, TVTheme.horizontalPadding)
        .focusSection()
    }

    @MainActor
    private func restoreNavigationFocus(using proxy: ScrollViewProxy) async {
        guard let route = focusRestorationRoute ?? lastFocusedRoute else { return }
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(route, anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        lastFocusedRoute = route
        focusedRoute = route
    }

    private var loggedOutView: some View {
        ZStack {
            TVBackground(tint: .indigo)
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(TVTheme.accent.opacity(0.16))
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 94, weight: .medium))
                        .foregroundStyle(TVTheme.accent)
                }
                .frame(width: 180, height: 180)
                Text("让音乐回到你的客厅")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("扫码登录后，歌单、收藏和每日推荐会自动同步。")
                    .font(.title3)
                    .foregroundStyle(TVTheme.secondaryText)
                Button("扫码登录") { showLogin = true }
                    .buttonStyle(TVPillButtonStyle(prominent: true))
            }
        }
    }

    private var accountSyncFailedView: some View {
        ZStack {
            TVBackground(tint: .indigo)
            VStack(spacing: 26) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 92, weight: .medium))
                    .foregroundStyle(TVTheme.amber)
                Text("登录状态暂时无法同步")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text(account.bootstrapError ?? "登录凭证仍保存在这台 Apple TV 上，不需要重新扫码。")
                    .font(.title3)
                    .foregroundStyle(TVTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 780)
                HStack(spacing: 18) {
                    Button {
                        Task { await account.bootstrap() }
                    } label: {
                        Label("重试同步", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(TVPillButtonStyle(prominent: true))

                    Button("重新扫码") { showLogin = true }
                        .buttonStyle(TVPillButtonStyle())
                }
            }
        }
    }
}

private struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    @State private var name = ""
    @State private var isPrivate = false
    @State private var isCreating = false

    var body: some View {
        ZStack {
            TVBackground(tint: .indigo)
            VStack(spacing: 34) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [TVTheme.magenta, TVTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note.list")
                        .font(.system(size: 92, weight: .semibold))
                }
                .frame(width: 220, height: 220)

                VStack(spacing: 9) {
                    Text("新建歌单")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("创建后会立即同步到你的网易云音乐账号。")
                        .font(.title3)
                        .foregroundStyle(TVTheme.secondaryText)
                }

                TextField("输入歌单名称", text: $name)
                    .font(.title2)
                    .frame(width: 780)

                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("隐私歌单")
                            .font(.headline)
                        Text("只有你自己可以查看。")
                            .font(.caption)
                            .foregroundStyle(TVTheme.secondaryText)
                    }
                    Spacer()
                    Toggle("隐私歌单", isOn: $isPrivate)
                        .labelsHidden()
                }
                .padding(24)
                .frame(width: 780)
                .glassPanel(cornerRadius: 24)

                HStack(spacing: 20) {
                    Button("取消") { dismiss() }
                        .buttonStyle(TVPillButtonStyle())
                    Button {
                        Task {
                            isCreating = true
                            if await account.createPlaylist(name: name, isPrivate: isPrivate) {
                                dismiss()
                            }
                            isCreating = false
                        }
                    } label: {
                        if isCreating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("创建中")
                            }
                        } else {
                            Label("创建", systemImage: "plus")
                        }
                    }
                    .buttonStyle(TVPillButtonStyle(prominent: true))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
        .onExitCommand { dismiss() }
    }
}

private struct LibraryShortcutCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190)
            .overlay(alignment: .trailing) {
                Image(systemName: symbol)
                    .font(.system(size: 92, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.24))
                    .padding(.trailing, 42)
            }
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.76))
                }
                .padding(34)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

struct RecentPlaysView: View {
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    @State private var records: [PlayRecordItem] = []
    @State private var weekOnly = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    private var visibleRecords: [PlayRecordItem] {
        let visibleIDs = Set(player.visibleTracks(records.map(\.song)).map(\.id))
        return records.filter { visibleIDs.contains($0.song.id) }
    }

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近播放")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("与网易云音乐账号同步的听歌记录")
                        .font(.headline)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                Spacer()
                Picker("时间范围", selection: $weekOnly) {
                    Text("最近一周").tag(true)
                    Text("所有时间").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                Button {
                    player.play(visibleRecords.map(\.song), source: .recent)
                    openNowPlaying?()
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                }
                .buttonStyle(TVPillButtonStyle(prominent: true))
                .disabled(visibleRecords.isEmpty)

            }
            .padding(.horizontal, TVTheme.horizontalPadding)
            .padding(.top, 38)
            .focusSection()

            content
        }
        .background(TVBackground(tint: .indigo))
        .task(id: weekOnly) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadStateView(title: "正在同步播放记录")
        } else if let errorMessage {
            LoadStateView(title: "无法载入播放记录", message: errorMessage) {
                Task { await load() }
            }
        } else if visibleRecords.isEmpty {
            EmptyStateView(
                title: records.isEmpty ? "还没有播放记录" : "没有可显示的歌曲",
                message: records.isEmpty
                    ? "完整播放一段音乐后会出现在这里。"
                    : "歌曲解锁已关闭，暂不可用歌曲已隐藏。",
                symbol: "clock"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(visibleRecords.enumerated()), id: \.element.song.id) { index, record in
                        TrackRow(
                            track: record.song,
                            index: index,
                            tracks: visibleRecords.map(\.song),
                            source: .recent
                        )
                    }
                }
                .padding(.horizontal, TVTheme.horizontalPadding)
                .padding(.bottom, 80)
            }
        }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedWeekOnly = weekOnly
        guard let userID = account.profile?.userId else {
            isLoading = false
            records = []
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await NeteaseAPI.playRecords(userID: userID, week: requestedWeekOnly)
            guard generation == loadGeneration,
                  !Task.isCancelled,
                  requestedWeekOnly == weekOnly,
                  account.profile?.userId == userID else { return }
            records = result
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }
}

struct CloudMusicView: View {
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    @State private var response: NeteaseAPI.CloudResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0
    @State private var showUpload = false
    @State private var matchingItem: CloudSongItem?
    @State private var itemPendingDeletion: CloudSongItem?
    @State private var isDeleting = false

    private var items: [CloudSongItem] { response?.data ?? [] }
    private var tracks: [Track] { items.compactMap(\.playableTrack) }

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("音乐云盘")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(storageDescription)
                        .font(.headline)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                Spacer()
                Button {
                    showUpload = true
                } label: {
                    Label("上传音乐", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(TVPillButtonStyle())
                Button {
                    player.play(tracks, source: .cloud)
                    openNowPlaying?()
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                }
                .buttonStyle(TVPillButtonStyle(prominent: true))
                .disabled(tracks.isEmpty)

            }
            .padding(.horizontal, TVTheme.horizontalPadding)
            .padding(.top, 38)
            .focusSection()

            content
        }
        .background(TVBackground(tint: TVTheme.magenta))
        .task { await load() }
        .fullScreenCover(isPresented: $showUpload) {
            CloudUploadView {
                Task { await load() }
            }
        }
        .fullScreenCover(item: $matchingItem) { item in
            CloudMatchView(item: item) {
                Task { await load() }
            }
        }
        .alert(
            "从音乐云盘删除？",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { itemPendingDeletion = nil }
            Button("删除", role: .destructive) {
                guard let item = itemPendingDeletion else { return }
                itemPendingDeletion = nil
                Task { await delete(item) }
            }
        } message: {
            Text("《\(itemPendingDeletion?.songName ?? "这首歌曲")》会从你的网易云音乐云盘中永久删除。")
        }
    }

    private var storageDescription: String {
        guard let size = response?.size, let maxSize = response?.maxSize, maxSize > 0 else {
            return "播放你上传到网易云音乐的歌曲"
        }
        let used = String(format: "%.1f", Double(size) / 1_073_741_824)
        let total = String(format: "%.0f", Double(maxSize) / 1_073_741_824)
        return "已使用 \(used) GB / \(total) GB"
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadStateView(title: "正在同步音乐云盘")
        } else if let errorMessage {
            LoadStateView(title: "无法载入音乐云盘", message: errorMessage) {
                Task { await load() }
            }
        } else if tracks.isEmpty {
            EmptyStateView(
                title: "云盘还没有歌曲",
                message: "在网易云音乐客户端上传的音乐会出现在这里。",
                symbol: "icloud"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if let track = item.playableTrack {
                            TrackRow(
                                track: track,
                                index: index,
                                tracks: tracks,
                                source: .cloud,
                                cloudMatchAction: { matchingItem = item },
                                cloudDeleteAction: { itemPendingDeletion = item }
                            )
                        }
                    }
                }
                .padding(.horizontal, TVTheme.horizontalPadding)
                .padding(.bottom, 80)
            }
        }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let result = try await NeteaseAPI.cloudSongs()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            response = result
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
    }

    @MainActor
    private func delete(_ item: CloudSongItem) async {
        guard account.isLoggedIn, !isDeleting else { return }
        isDeleting = true
        do {
            try await NeteaseAPI.deleteCloudSong(id: item.songId)
            ToastCenter.shared.show("已从音乐云盘删除《\(item.songName ?? "歌曲")》")
            await load()
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
        isDeleting = false
    }
}

struct PlaybackSettingsView: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("播放设置")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text("根据账号权限选择音质，不可用时会逐级回落到可播放音质。")
                        .font(.title3)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("首选音质")
                    .font(.title2.bold())
                Picker(
                    "首选音质",
                    selection: Binding(
                        get: { player.preferredQuality },
                        set: { player.setPreferredQuality($0) }
                    )
                ) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            PlaybackSettingsToggle(
                title: "歌词翻译与罗马音",
                description: "关闭后播放页只保留原文歌词。",
                isOn: Binding(
                    get: { player.showsTranslatedLyrics },
                    set: { player.setShowsTranslatedLyrics($0) }
                )
            )

            PlaybackSettingsToggle(
                title: "歌曲解锁",
                description: "开启后显示不可用歌曲，并尝试波点补全；关闭后不访问第三方服务。",
                isOn: Binding(
                    get: { player.enablesAlternativeSources },
                    set: { player.setEnablesAlternativeSources($0) }
                )
            )

            Spacer()
        }
        .padding(.horizontal, 150)
        .padding(.top, 90)
        .background(TVBackground(tint: .purple))
    }
}

private struct PlaybackSettingsToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                Text(description)
                    .font(.headline)
                    .foregroundStyle(TVTheme.secondaryText)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .glassPanel(cornerRadius: 28)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}
