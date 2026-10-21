import SwiftUI

private struct OpenNowPlayingKey: EnvironmentKey {
    static let defaultValue: ((PlaybackOriginFocus) -> Void)? = nil
}

private struct OpenRouteFromNowPlayingKey: EnvironmentKey {
    static let defaultValue: ((AppRoute) -> Void)? = nil
}

private struct RootTabActivationKey: EnvironmentKey {
    static let defaultValue = 0
}

struct PlaybackFocusRestorationRequest: Equatable {
    let origin: PlaybackOriginFocus
    let generation: Int
}

private struct PlaybackFocusRestorationRequestKey: EnvironmentKey {
    static let defaultValue: PlaybackFocusRestorationRequest? = nil
}

private struct CompletePlaybackFocusRestorationKey: EnvironmentKey {
    static let defaultValue: ((PlaybackFocusRestorationRequest) -> Void)? = nil
}

extension EnvironmentValues {
    var openNowPlaying: ((PlaybackOriginFocus) -> Void)? {
        get { self[OpenNowPlayingKey.self] }
        set { self[OpenNowPlayingKey.self] = newValue }
    }

    var openRouteFromNowPlaying: ((AppRoute) -> Void)? {
        get { self[OpenRouteFromNowPlayingKey.self] }
        set { self[OpenRouteFromNowPlayingKey.self] = newValue }
    }

    var rootTabActivationGeneration: Int {
        get { self[RootTabActivationKey.self] }
        set { self[RootTabActivationKey.self] = newValue }
    }

    var playbackFocusRestorationRequest: PlaybackFocusRestorationRequest? {
        get { self[PlaybackFocusRestorationRequestKey.self] }
        set { self[PlaybackFocusRestorationRequestKey.self] = newValue }
    }

    var completePlaybackFocusRestoration: ((PlaybackFocusRestorationRequest) -> Void)? {
        get { self[CompletePlaybackFocusRestorationKey.self] }
        set { self[CompletePlaybackFocusRestorationKey.self] = newValue }
    }
}

private enum RootTab: Hashable {
    case listenNow
    case browse
    case search
    case library
    case nowPlaying

    var isContentTab: Bool { self != .nowPlaying }
}

enum RootContentAnchor: Hashable {
    case top
}

private struct NowPlayingReturnTarget: Hashable {
    let source: NowPlayingPresentationSource
    let origin: PlaybackOriginFocus?
}

/// A detail opened from Now Playing unwinds back to Now Playing, like Apple Music.
private typealias NowPlayingReturn = NavigationReturnContext<
    RootTab,
    AppRoute,
    NowPlayingReturnTarget
>

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccountStore.self) private var account
    @Environment(ContentStore.self) private var content
    @Environment(PlayerService.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var pendingTopShelfLink: TopShelfLink?
    @State private var topShelfTask: Task<Void, Never>?
    @State private var selectedTab = RootTab.listenNow
    @State private var tabPresentations: [RootTab: RootTabPresentationState<AppRoute>] = [:]
    @State private var browseSession = BrowseSession()
    @State private var searchSession = SearchSession()
    @State private var lastContentTab = RootTab.listenNow
    @State private var nowPlayingPresentation = NowPlayingPresentationState()
    @State private var nowPlayingActivationGeneration = 0
    @State private var nowPlayingOriginFocus: PlaybackOriginFocus?
    @State private var nowPlayingReturnStack: [NowPlayingReturn] = []
    @State private var focusRestorationGeneration = 0
    @State private var focusRestorationTab: RootTab?
    @State private var focusRestorationRequest: PlaybackFocusRestorationRequest?

    var body: some View {
        let navigationTab = activeNavigationTab

        ZStack {
            NavigationStack(path: pathBinding(for: navigationTab)) {
                ZStack {
                    TVBackground()
                    rootTabs.id(account.identityRevision)
                }
                .navigationDestination(for: AppRoute.self, destination: routeDestination)
            }
            .environment(
                \.playbackFocusRestorationRequest,
                focusRestorationTab == navigationTab ? focusRestorationRequest : nil
            )
            .environment(\.completePlaybackFocusRestoration, completeFocusRestoration)
            .disabled(nowPlayingPresentation.isPresented)
            .accessibilityHidden(nowPlayingPresentation.isPresented)

            toastOverlay

            if nowPlayingPresentation.isPresented {
                NowPlayingView(
                    isActive: true,
                    activationGeneration: nowPlayingActivationGeneration,
                    onDismiss: dismissNowPlaying
                )
                .environment(\.openRouteFromNowPlaying, openRouteFromNowPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(nowPlayingTransition)
                .zIndex(10)
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.42),
            value: nowPlayingPresentation.isPresented
        )
        .environment(\.openNowPlaying, presentContextualNowPlaying)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .onPlayPauseCommand {
            player.togglePlayPause()
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["SONIMBUS_UI_LARGE_PLAYLIST"] == "1" {
                appendRouteIfNeeded(.playlist(9_000_000), in: .listenNow)
                return
            }
#endif
            await account.bootstrap()
            TopShelfPublisher.update(account: account, player: player)
            openPendingTopShelfLink()
        }
        .onOpenURL { url in
            guard let link = TopShelfLink(url: url) else { return }
            pendingTopShelfLink = link
            openPendingTopShelfLink()
        }
        .onChange(of: account.isBootstrapping) { _, busy in
            if !busy { openPendingTopShelfLink() }
        }
        .onChange(of: account.isSwitchingAccount) { _, busy in
            if !busy { openPendingTopShelfLink() }
        }
        .onChange(of: account.playlists) { _, _ in
            TopShelfPublisher.update(account: account, player: player)
        }
        .onChange(of: player.recentTracks) { _, _ in
            TopShelfPublisher.update(account: account, player: player)
        }
        .onChange(of: account.identityRevision) { _, _ in
            topShelfTask?.cancel()
            content.removeAll()
            MVPlaybackController.shared.stop()
            tabPresentations = [:]
            browseSession = BrowseSession()
            searchSession = SearchSession()
            nowPlayingReturnStack = []
            focusRestorationRequest = nil
            focusRestorationTab = nil
            nowPlayingOriginFocus = nil
            _ = nowPlayingPresentation.dismiss()
            selectedTab = .library
            lastContentTab = .library
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.saveState()
                account.saveCurrentAccount()
                TopShelfPublisher.update(account: account, player: player)
            }
        }
    }

    private func openPendingTopShelfLink() {
        guard account.hasBootstrapped, !account.isBootstrapping,
              !account.isSwitchingAccount, let link = pendingTopShelfLink else { return }
        pendingTopShelfLink = nil
        topShelfTask?.cancel()
        guard account.isLoggedIn, account.profile?.userId == link.accountID else {
            selectedTab = .library
            lastContentTab = .library
            toast.show("请先切换到此内容所属的账号")
            return
        }
        let revision = account.identityRevision
        _ = nowPlayingPresentation.dismiss()
        MVPlaybackController.shared.stop()
        selectedTab = .library
        lastContentTab = .library
        resetRootPresentation(for: .library)
        if link.kind == .playlist && link.action == .display {
            appendRouteIfNeeded(.playlist(link.id), in: .library)
            return
        }
        toast.show("正在载入播放内容…")
        topShelfTask = Task { @MainActor in
            do {
                let tracks: [Track]
                let source: PlaySource
                switch link.kind {
                case .playlist:
                    tracks = try await NeteaseAPI.playlist(id: link.id).playlist.tracks
                    source = .playlist(link.id)
                case .track:
                    tracks = try await NeteaseAPI.songDetails(ids: [link.id]).songs
                    source = .recent
                }
                guard !Task.isCancelled, account.identityRevision == revision,
                      account.profile?.userId == link.accountID else { return }
                guard !player.visibleTracks(tracks).isEmpty else {
                    toast.show("此内容暂时无法播放")
                    return
                }
                player.play(tracks, source: source)
                _ = presentNowPlaying(from: .tabBar)
            } catch is CancellationError {
                return
            } catch {
                guard account.identityRevision == revision else { return }
                toast.show(error.localizedDescription)
            }
        }
    }

    private var activeNavigationTab: RootTab {
        selectedTab.isContentTab ? selectedTab : lastContentTab
    }

    private var rootTabs: some View {
        TabView(selection: rootTabSelection) {
            rootContent(tab: .listenNow) { HomeView() }
                .tag(RootTab.listenNow)
                .tabItem { Label("现在就听", systemImage: "play.circle.fill") }

            rootContent(tab: .browse) { BrowseView(session: browseSession) }
                .tag(RootTab.browse)
                .tabItem { Label("浏览", systemImage: "square.grid.2x2.fill") }

            rootContent(tab: .search) { SearchView(session: searchSession) }
                .tag(RootTab.search)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            rootContent(tab: .library) { LibraryView() }
                .tag(RootTab.library)
                .tabItem { Label("资料库", systemImage: "music.note.list") }

            Color.clear
                .tag(RootTab.nowPlaying)
                .tabItem { Label("正在播放", systemImage: "music.note") }
        }
        .tint(TVTheme.accent)
    }

    private var rootTabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { requestedTab in
                guard requestedTab != selectedTab else { return }
                if requestedTab == .nowPlaying {
                    let contentTab = activeNavigationTab
                    guard contentTab.isContentTab else { return }
                    stopMVIfNeeded(in: contentTab)
                    lastContentTab = contentTab
                    guard presentNowPlaying(from: .tabBar) else { return }
                    selectedTab = .nowPlaying
                    return
                }

                let outgoingTab = activeNavigationTab
                stopMVIfNeeded(in: outgoingTab)
                resetRootPresentation(for: outgoingTab)
                selectedTab = requestedTab
                lastContentTab = requestedTab
            }
        )
    }

    private func rootContent<Content: View>(
        tab: RootTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .environment(
                \.rootTabActivationGeneration,
                presentationState(for: tab).rootActivationGeneration
            )
    }

    private func stopMVIfNeeded(in tab: RootTab) {
        if case .mv = presentationState(for: tab).path.last {
            MVPlaybackController.shared.stop()
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

    private var nowPlayingTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.04)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }

    private func presentContextualNowPlaying(from origin: PlaybackOriginFocus) {
        guard selectedTab.isContentTab else { return }
        if nowPlayingPresentation.isPresented {
            nowPlayingActivationGeneration &+= 1
            return
        }
        nowPlayingOriginFocus = origin
        stopMVIfNeeded(in: selectedTab)
        _ = presentNowPlaying(from: .contextual)
    }

    @discardableResult
    private func presentNowPlaying(from source: NowPlayingPresentationSource) -> Bool {
        guard nowPlayingPresentation.present(from: source) else { return false }
        nowPlayingActivationGeneration &+= 1
        return true
    }

    private func dismissNowPlaying() {
        guard let source = nowPlayingPresentation.source else { return }
        let destinationTab = source == .contextual ? selectedTab : lastContentTab
        let origin = source == .contextual ? nowPlayingOriginFocus : nil

        nowPlayingOriginFocus = nil
        _ = nowPlayingPresentation.dismiss()

        if source == .tabBar {
            resetRootPresentation(for: destinationTab)
            selectedTab = destinationTab
            lastContentTab = destinationTab
            return
        }

        guard let origin else { return }
        Task { @MainActor in
            await Task.yield()
            guard !nowPlayingPresentation.isPresented,
                  selectedTab == destinationTab else { return }
            requestFocusRestoration(origin, in: destinationTab)
        }
    }

    private func openRouteFromNowPlaying(_ route: AppRoute) {
        guard let source = nowPlayingPresentation.source else {
            appendRouteIfNeeded(route, in: activeNavigationTab)
            return
        }

        let destinationTab = source == .tabBar ? lastContentTab : selectedTab
        guard destinationTab.isContentTab else { return }
        var parentPath = presentationState(for: destinationTab).path
        if parentPath.last == route {
            parentPath.removeLast()
        }
        let origin = source == .contextual ? nowPlayingOriginFocus : nil

        if source == .tabBar {
            selectedTab = destinationTab
            lastContentTab = destinationTab
        }
        nowPlayingOriginFocus = nil
        _ = nowPlayingPresentation.dismiss()

        // The playback origin is restored when Now Playing itself is dismissed later.
        nowPlayingReturnStack.append(
            NowPlayingReturn(
                tab: destinationTab,
                parentPath: parentPath,
                focus: NowPlayingReturnTarget(source: source, origin: origin)
            )
        )
        appendRouteIfNeeded(route, in: destinationTab)
    }

    private func returnToNowPlaying(_ target: NowPlayingReturnTarget, in tab: RootTab) {
        Task { @MainActor in
            await Task.yield()
            guard !nowPlayingPresentation.isPresented,
                  activeNavigationTab == tab else { return }
            nowPlayingOriginFocus = target.origin
            if target.source == .tabBar {
                lastContentTab = tab
                selectedTab = .nowPlaying
            }
            presentNowPlaying(from: target.source)
        }
    }

    private func requestFocusRestoration(_ origin: PlaybackOriginFocus, in tab: RootTab) {
        focusRestorationGeneration &+= 1
        focusRestorationTab = tab
        focusRestorationRequest = PlaybackFocusRestorationRequest(
            origin: origin,
            generation: focusRestorationGeneration
        )
    }

    private func completeFocusRestoration(_ request: PlaybackFocusRestorationRequest) {
        guard focusRestorationRequest == request else { return }
        focusRestorationRequest = nil
        focusRestorationTab = nil
    }

    private func handleNavigationPathChange(
        in tab: RootTab,
        from oldPath: [AppRoute],
        to newPath: [AppRoute]
    ) {
        guard newPath.count < oldPath.count else { return }
        if case .mv = oldPath.last {
            MVPlaybackController.shared.stop()
        }

        let nowPlayingReturn = nowPlayingReturnStack.last {
            $0.matches(tab: tab, parentPath: newPath)
        }
        nowPlayingReturnStack.removeAll {
            $0.shouldDiscard(when: tab, popsToDepth: newPath.count)
        }
        if let nowPlayingReturn {
            returnToNowPlaying(nowPlayingReturn.focus, in: tab)
        }
    }

    private func presentationState(for tab: RootTab) -> RootTabPresentationState<AppRoute> {
        tabPresentations[tab] ?? RootTabPresentationState()
    }

    private func pathBinding(for tab: RootTab) -> Binding<[AppRoute]> {
        Binding(
            get: { presentationState(for: tab).path },
            set: { newPath in
                let oldPath = presentationState(for: tab).path
                var presentation = presentationState(for: tab)
                presentation.path = newPath
                tabPresentations[tab] = presentation
                handleNavigationPathChange(in: tab, from: oldPath, to: newPath)
            }
        )
    }

    private func resetRootPresentation(for tab: RootTab) {
        guard tab.isContentTab else { return }
        var presentation = presentationState(for: tab)
        presentation.resetToRoot()
        tabPresentations[tab] = presentation
        nowPlayingReturnStack.removeAll { $0.tab == tab }
        if focusRestorationTab == tab {
            focusRestorationRequest = nil
            focusRestorationTab = nil
        }
    }

    private func appendRouteIfNeeded(_ route: AppRoute, in tab: RootTab) {
        var presentation = presentationState(for: tab)
        guard presentation.path.last != route else { return }
        presentation.path.append(route)
        tabPresentations[tab] = presentation
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .playlist(let id):
#if DEBUG
            if id == 9_000_000 && ProcessInfo.processInfo.environment["SONIMBUS_UI_LARGE_PLAYLIST"] == "1" {
                LargePlaylistRegressionFixture()
            } else {
                PlaylistDetailView(playlistID: id)
            }
#else
            PlaylistDetailView(playlistID: id)
#endif
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
