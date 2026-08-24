import SwiftUI

private struct OpenNowPlayingKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct HandlesNavigationExitKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NavigationFocusRestorationKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct NavigationFocusRestorationRouteKey: EnvironmentKey {
    static let defaultValue: AppRoute? = nil
}

private struct RootTabActivationKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var openNowPlaying: (() -> Void)? {
        get { self[OpenNowPlayingKey.self] }
        set { self[OpenNowPlayingKey.self] = newValue }
    }

    var handlesNavigationExit: Bool {
        get { self[HandlesNavigationExitKey.self] }
        set { self[HandlesNavigationExitKey.self] = newValue }
    }

    var navigationFocusRestorationGeneration: Int {
        get { self[NavigationFocusRestorationKey.self] }
        set { self[NavigationFocusRestorationKey.self] = newValue }
    }

    var navigationFocusRestorationRoute: AppRoute? {
        get { self[NavigationFocusRestorationRouteKey.self] }
        set { self[NavigationFocusRestorationRouteKey.self] = newValue }
    }

    var rootTabActivationGeneration: Int {
        get { self[RootTabActivationKey.self] }
        set { self[RootTabActivationKey.self] = newValue }
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

private struct NavigationFocusRestorationState {
    var generation = 0
    var route: AppRoute?
}

private enum NowPlayingEntry: Equatable {
    case contextual
    case tabBar
}

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player
    @Environment(ToastCenter.self) private var toast
    @State private var selectedTab = RootTab.listenNow
    @State private var lastContentTab = RootTab.listenNow
    @State private var listenNowPath: [AppRoute] = []
    @State private var browsePath: [AppRoute] = []
    @State private var searchPath: [AppRoute] = []
    @State private var libraryPath: [AppRoute] = []
    @State private var browseSession = BrowseSession()
    @State private var searchSession = SearchSession()
    @State private var rootActivationGenerations: [RootTab: Int] = [:]
    @State private var navigationFocusRestorations: [RootTab: NavigationFocusRestorationState] = [:]
    @State private var isNowPlayingPresented = false
    @State private var nowPlayingEntry: NowPlayingEntry?

    var body: some View {
        ZStack {
            TVBackground()
            TabView(selection: $selectedTab) {
                tabNavigation(tab: .listenNow, path: $listenNowPath) {
                    HomeView()
                }
                .tag(RootTab.listenNow)
                .tabItem { Label("现在就听", systemImage: "play.circle.fill") }

                tabNavigation(tab: .browse, path: $browsePath) {
                    BrowseView(session: browseSession)
                }
                .tag(RootTab.browse)
                .tabItem { Label("浏览", systemImage: "square.grid.2x2.fill") }

                tabNavigation(tab: .search, path: $searchPath) {
                    SearchView(session: searchSession)
                }
                .tag(RootTab.search)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

                tabNavigation(tab: .library, path: $libraryPath) {
                    LibraryView()
                }
                .tag(RootTab.library)
                .tabItem { Label("资料库", systemImage: "music.note.list") }

                Color.clear
                    .tag(RootTab.nowPlaying)
                    .tabItem { Label("正在播放", systemImage: "music.note") }
            }
            .tint(TVTheme.accent)
            .disabled(isNowPlayingPresented)

            toastOverlay

            if isNowPlayingPresented {
                NowPlayingView(onClose: dismissNowPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(10)
            }
        }
        .environment(\.openNowPlaying, { presentNowPlaying() })
        .modifier(
            ConditionalExitCommand(
                isActive: selectedNavigationDepth > 0 && !isNowPlayingPresented,
                action: popSelectedNavigation
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isNowPlayingPresented)
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab != newTab { stopMVIfNeeded(in: oldTab) }
            if newTab == .nowPlaying {
                if oldTab != .nowPlaying {
                    lastContentTab = oldTab
                    if nowPlayingEntry == nil {
                        nowPlayingEntry = .tabBar
                    }
                }
                isNowPlayingPresented = true
            } else if oldTab != .nowPlaying {
                if oldTab != newTab {
                    resetRootPresentation(for: newTab)
                }
                lastContentTab = newTab
            }
        }
        .onPlayPauseCommand {
            player.togglePlayPause()
        }
        .task {
            await account.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.saveState()
            }
        }
    }

    private var selectedNavigationDepth: Int {
        switch selectedTab {
        case .listenNow: listenNowPath.count
        case .browse: browsePath.count
        case .search: searchPath.count
        case .library: libraryPath.count
        case .nowPlaying: 0
        }
    }

    private func stopMVIfNeeded(in tab: RootTab) {
        let route: AppRoute?
        switch tab {
        case .listenNow: route = listenNowPath.last
        case .browse: route = browsePath.last
        case .search: route = searchPath.last
        case .library: route = libraryPath.last
        case .nowPlaying: route = nil
        }
        if case .mv = route {
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

    private func presentNowPlaying() {
        guard !isNowPlayingPresented else { return }
        if selectedTab != .nowPlaying {
            lastContentTab = selectedTab
            nowPlayingEntry = .contextual
            selectedTab = .nowPlaying
        }
        isNowPlayingPresented = true
    }

    private func dismissNowPlaying() {
        guard isNowPlayingPresented else { return }
        let destination = lastContentTab
        let shouldResetDestination = nowPlayingEntry == .tabBar
        nowPlayingEntry = nil
        selectedTab = destination
        isNowPlayingPresented = false
        if shouldResetDestination {
            resetRootPresentation(for: destination)
        }
    }

    private func popSelectedNavigation() {
        let poppedRoute: AppRoute?
        switch selectedTab {
        case .listenNow:
            poppedRoute = listenNowPath.popLast()
        case .browse:
            poppedRoute = browsePath.popLast()
        case .search:
            poppedRoute = searchPath.popLast()
        case .library:
            poppedRoute = libraryPath.popLast()
        case .nowPlaying:
            poppedRoute = nil
        }
        guard let poppedRoute else { return }
        if case .mv = poppedRoute {
            MVPlaybackController.shared.stop()
        }
        requestNavigationFocusRestoration(poppedRoute, in: selectedTab)
    }

    private func tabNavigation<Content: View>(
        tab: RootTab,
        path: Binding<[AppRoute]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let restoration = navigationFocusRestorations[tab] ?? NavigationFocusRestorationState()
        return NavigationStack(path: path) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
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
                }
        }
        .environment(\.handlesNavigationExit, true)
        .environment(\.rootTabActivationGeneration, rootActivationGenerations[tab] ?? 0)
        .environment(\.navigationFocusRestorationGeneration, restoration.generation)
        .environment(\.navigationFocusRestorationRoute, restoration.route)
    }

    private func resetRootPresentation(for tab: RootTab) {
        guard tab.isContentTab else { return }
        rootActivationGenerations[tab, default: 0] &+= 1
        var restoration = navigationFocusRestorations[tab] ?? NavigationFocusRestorationState()
        restoration.route = nil
        navigationFocusRestorations[tab] = restoration
    }

    private func requestNavigationFocusRestoration(_ route: AppRoute, in tab: RootTab) {
        guard tab.isContentTab else { return }
        var restoration = navigationFocusRestorations[tab] ?? NavigationFocusRestorationState()
        restoration.route = route
        restoration.generation &+= 1
        navigationFocusRestorations[tab] = restoration
    }
}

private struct ConditionalExitCommand: ViewModifier {
    let isActive: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive { content.onExitCommand(perform: action) }
        else { content }
    }
}
