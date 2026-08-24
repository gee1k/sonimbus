import SwiftUI

private struct OpenNowPlayingKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct NavigationFocusRestorationKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct NavigationFocusRestorationRouteKey: EnvironmentKey {
    static let defaultValue: AppRoute? = nil
}

extension EnvironmentValues {
    var openNowPlaying: (() -> Void)? {
        get { self[OpenNowPlayingKey.self] }
        set { self[OpenNowPlayingKey.self] = newValue }
    }

    var navigationFocusRestorationGeneration: Int {
        get { self[NavigationFocusRestorationKey.self] }
        set { self[NavigationFocusRestorationKey.self] = newValue }
    }

    var navigationFocusRestorationRoute: AppRoute? {
        get { self[NavigationFocusRestorationRouteKey.self] }
        set { self[NavigationFocusRestorationRouteKey.self] = newValue }
    }
}

private enum RootTab: Hashable {
    case listenNow
    case browse
    case search
    case library
    case nowPlaying
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
    @State private var isNowPlayingPresented = false
    @State private var navigationFocusRestorationGeneration = 0
    @State private var navigationFocusRestorationRoute: AppRoute?

    var body: some View {
        ZStack {
            TVBackground()
            TabView(selection: $selectedTab) {
                tabNavigation(path: $listenNowPath) {
                    HomeView()
                }
                .tag(RootTab.listenNow)
                .tabItem { Label("现在就听", systemImage: "play.circle.fill") }

                tabNavigation(path: $browsePath) {
                    BrowseView(session: browseSession)
                }
                .tag(RootTab.browse)
                .tabItem { Label("浏览", systemImage: "square.grid.2x2.fill") }

                tabNavigation(path: $searchPath) {
                    SearchView(session: searchSession)
                }
                .tag(RootTab.search)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

                tabNavigation(path: $libraryPath) {
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
        .environment(\.navigationFocusRestorationGeneration, navigationFocusRestorationGeneration)
        .environment(\.navigationFocusRestorationRoute, navigationFocusRestorationRoute)
        .modifier(
            ConditionalExitCommand(
                isActive: selectedNavigationDepth > 0 && !isNowPlayingPresented,
                action: popSelectedNavigation
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isNowPlayingPresented)
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .nowPlaying {
                if oldTab != .nowPlaying { lastContentTab = oldTab }
                isNowPlayingPresented = true
            } else if oldTab != .nowPlaying {
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
            selectedTab = .nowPlaying
        }
        isNowPlayingPresented = true
    }

    private func dismissNowPlaying() {
        guard isNowPlayingPresented else { return }
        selectedTab = lastContentTab
        isNowPlayingPresented = false
    }

    private func popSelectedNavigation() {
        var didPop = false
        switch selectedTab {
        case .listenNow:
            if !listenNowPath.isEmpty {
                navigationFocusRestorationRoute = listenNowPath.removeLast()
                didPop = true
            }
        case .browse:
            if !browsePath.isEmpty {
                navigationFocusRestorationRoute = browsePath.removeLast()
                didPop = true
            }
        case .search:
            if !searchPath.isEmpty {
                navigationFocusRestorationRoute = searchPath.removeLast()
                didPop = true
            }
        case .library:
            if !libraryPath.isEmpty {
                navigationFocusRestorationRoute = libraryPath.removeLast()
                didPop = true
            }
        case .nowPlaying:
            break
        }
        if didPop { navigationFocusRestorationGeneration &+= 1 }
    }

    private func tabNavigation<Content: View>(
        path: Binding<[AppRoute]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    Group {
                        switch route {
                        case .playlist(let id): PlaylistDetailView(playlistID: id)
                        case .album(let id): AlbumDetailView(albumID: id)
                        case .artist(let id): ArtistDetailView(artistID: id)
                        case .dailySongs: DailySongsView()
                        case .recents: RecentPlaysView()
                        case .cloud: CloudMusicView()
                        case .settings: PlaybackSettingsView()
                        }
                    }
                }
        }
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
