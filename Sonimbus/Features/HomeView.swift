import SwiftUI

struct HomeView: View {
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(\.navigationFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.navigationFocusRestorationRoute) private var focusRestorationRoute
    @Environment(\.rootTabActivationGeneration) private var rootTabActivationGeneration
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player

    @State private var playlists: [PlaylistSummary] = []
    @State private var newSongs: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showLogin = false
    @State private var loadGeneration = 0
    @State private var lastFocusedRoute: AppRoute?
    @FocusState private var focusedRoute: AppRoute?
    @FocusState private var focusedTrackID: AnyHashable?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                header
                hero

                if !visibleRecentTracks.isEmpty {
                    HorizontalShelf(title: "最近播放", subtitle: "继续你刚才的音乐") {
                        ForEach(visibleRecentTracks.prefix(12)) { track in
                            TrackCard(
                                track: track,
                                tracks: visibleRecentTracks,
                                source: .recent,
                                focusBinding: $focusedTrackID
                            )
                        }
                    }
                }

                if !visibleNewSongs.isEmpty {
                    HorizontalShelf(title: "为你推荐的新歌", subtitle: "根据你的口味持续更新") {
                        ForEach(visibleNewSongs) { track in
                            TrackCard(
                                track: track,
                                tracks: visibleNewSongs,
                                source: .newSongs,
                                focusBinding: $focusedTrackID
                            )
                        }
                    }
                }

                if !playlists.isEmpty {
                    HorizontalShelf(title: account.isLoggedIn ? "专属推荐" : "热门推荐") {
                        ForEach(playlists) { playlist in
                            PlaylistCard(playlist: playlist)
                                .focused($focusedRoute, equals: .playlist(playlist.id))
                                .id(AppRoute.playlist(playlist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .playlist(playlist.id)
                                })
                        }
                    }
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                } else if let errorMessage, playlists.isEmpty {
                    LoadStateView(title: "现在无法载入推荐", message: errorMessage) {
                        Task { await load() }
                    }
                    .frame(height: 420)
                }
                }
                .padding(.top, 42)
                .padding(.bottom, 70)
                .id(RootContentAnchor.top)
            }
            .background(TVBackground(tint: .purple))
            .task(id: focusRestorationGeneration) {
                await restoreNavigationFocus(using: proxy)
            }
            .onChange(of: rootTabActivationGeneration) { _, generation in
                Task { await resetRootPresentation(for: generation, using: proxy) }
            }
        }
        .fullScreenCover(isPresented: $showLogin) { LoginView() }
        .task(id: account.profile?.userId) { await load() }
        .onChange(of: focusedRoute) { _, route in
            if let route { lastFocusedRoute = route }
        }
        .onChange(of: rootTabActivationGeneration) { _, _ in
            focusedRoute = nil
            focusedTrackID = nil
            lastFocusedRoute = nil
        }
    }

    private var visibleRecentTracks: [Track] {
        player.visibleTracks(player.recentTracks)
    }

    private var visibleNewSongs: [Track] {
        player.visibleTracks(newSongs)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text(account.isLoggedIn ? "你的音乐，继续播放。" : "无需登录也可以先逛逛。")
                    .font(.title3)
                    .foregroundStyle(TVTheme.secondaryText)
            }
            Spacer()
            if let profile = account.profile {
                HStack(spacing: 16) {
                    ArtworkView(url: profile.avatarUrl.flatMap { ArtworkURL.make($0, size: 180) }, cornerRadius: 34, symbol: "person.fill")
                        .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.nickname)
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        MembershipStatusBadge(label: account.membershipLabel, isVIP: account.isVIP, compact: true)
                    }
                }
            } else if account.hasAuthenticationCookie {
                Button {
                    Task { await account.bootstrap() }
                } label: {
                    if account.isBootstrapping {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("同步中")
                        }
                    } else {
                        Label("重试同步", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(TVPillButtonStyle(prominent: true))
                .disabled(account.isBootstrapping)
            } else {
                Button("登录") { showLogin = true }
                    .buttonStyle(TVPillButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, TVTheme.horizontalPadding)
        .focusSection()
    }

    private var hero: some View {
        HStack(spacing: 30) {
            if account.isLoggedIn {
                NavigationLink(value: AppRoute.dailySongs) {
                    dailySongsTile
                }
                .buttonStyle(TVHeroButtonStyle())
                .frame(maxWidth: .infinity)
                .focused($focusedRoute, equals: .dailySongs)
                .id(AppRoute.dailySongs)
                .simultaneousGesture(TapGesture().onEnded { lastFocusedRoute = .dailySongs })
            } else {
                Button {
                    showLogin = true
                } label: {
                    dailySongsTile
                }
                .buttonStyle(TVHeroButtonStyle())
                .frame(maxWidth: .infinity)
            }

            Button {
                if account.isLoggedIn {
                    player.startPersonalFM()
                    openNowPlaying?(nil)
                } else {
                    showLogin = true
                }
            } label: {
                FeatureTile(
                    title: "私人 FM",
                    subtitle: "不间断的个性漫游",
                    symbol: "dot.radiowaves.left.and.right",
                    colors: [Color.indigo, Color.blue]
                )
            }
            .buttonStyle(TVHeroButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TVTheme.horizontalPadding)
        .focusSection()
    }

    private var dailySongsTile: some View {
        FeatureTile(
            title: "每日歌曲推荐",
            subtitle: account.isLoggedIn ? "每一天，30 首懂你的歌" : "登录后解锁专属推荐",
            symbol: "sparkles",
            colors: [TVTheme.accent, TVTheme.magenta]
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let prefix = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好"
        return account.profile.map { "\(prefix)，\($0.nickname)" } ?? prefix
    }

    @MainActor
    private func restoreNavigationFocus(using proxy: ScrollViewProxy) async {
        guard let route = focusRestorationRoute else { return }
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

    @MainActor
    private func resetRootPresentation(
        for generation: Int,
        using proxy: ScrollViewProxy
    ) async {
        guard generation > 0 else { return }
        await Task.yield()
        guard !Task.isCancelled,
              generation == rootTabActivationGeneration else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(RootContentAnchor.top, anchor: .top)
        }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedUserID = account.profile?.userId
        let requestedLoggedIn = account.isLoggedIn
        isLoading = true
        errorMessage = nil
        async let personalized = try? NeteaseAPI.personalizedPlaylists()
        async let recommended = requestedLoggedIn ? try? NeteaseAPI.recommendedPlaylists() : nil
        async let songs = try? NeteaseAPI.newSongs()
        let fallback = await personalized ?? []
        let recommendedResult = await recommended ?? []
        let songResult = await songs ?? []
        guard generation == loadGeneration,
              !Task.isCancelled,
              requestedUserID == account.profile?.userId,
              requestedLoggedIn == account.isLoggedIn else { return }
        playlists = recommendedResult.isEmpty ? fallback : recommendedResult
        newSongs = songResult
        if playlists.isEmpty && newSongs.isEmpty { errorMessage = "请检查网络连接后重试" }
        isLoading = false
    }
}

private struct FeatureTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 440, height: 440)
                    .offset(x: 110, y: -185)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 112, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(.top, 38)
                    .padding(.trailing, 44)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1)
                }
                .padding(42)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}
