import SwiftUI

private struct OpenNowPlayingKey: EnvironmentKey {
    static let defaultValue: ((AnyHashable?) -> Void)? = nil
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

private struct NowPlayingFocusRestorationGenerationKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct NowPlayingFocusRestorationIDKey: EnvironmentKey {
    static let defaultValue: AnyHashable? = nil
}

extension EnvironmentValues {
    var openNowPlaying: ((AnyHashable?) -> Void)? {
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

    var nowPlayingFocusRestorationGeneration: Int {
        get { self[NowPlayingFocusRestorationGenerationKey.self] }
        set { self[NowPlayingFocusRestorationGenerationKey.self] = newValue }
    }

    var nowPlayingFocusRestorationID: AnyHashable? {
        get { self[NowPlayingFocusRestorationIDKey.self] }
        set { self[NowPlayingFocusRestorationIDKey.self] = newValue }
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

private struct TrackFocusRestorationState {
    var generation = 0
    var trackID: AnyHashable?
}

enum RootContentAnchor: Hashable {
    case top
}

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccountStore.self) private var account
    @Environment(PlayerService.self) private var player
    @Environment(ToastCenter.self) private var toast
    @State private var selectedTab = RootTab.listenNow
    @State private var listenNowPath: [AppRoute] = []
    @State private var browsePath: [AppRoute] = []
    @State private var searchPath: [AppRoute] = []
    @State private var libraryPath: [AppRoute] = []
    @State private var browseSession = BrowseSession()
    @State private var searchSession = SearchSession()
    @State private var rootActivationGenerations: [RootTab: Int] = [:]
    @State private var navigationFocusRestorations: [RootTab: NavigationFocusRestorationState] = [:]
    @State private var trackFocusRestorations: [RootTab: TrackFocusRestorationState] = [:]
    @State private var lastContentTab = RootTab.listenNow
    @State private var contextualReturnFocusID: AnyHashable?
    @State private var nowPlayingPresentation = NowPlayingPresentationState()
    @State private var nowPlayingActivationGeneration = 0

    var body: some View {
        ZStack {
            TVBackground()
            TabView(selection: rootTabSelection) {
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
            .disabled(nowPlayingPresentation.isPresented)

            toastOverlay

            if nowPlayingPresentation.isPresented {
                NowPlayingView(
                    isActive: true,
                    activationGeneration: nowPlayingActivationGeneration,
                    onDismiss: dismissNowPlaying
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(10)
            }
        }
        .environment(\.openNowPlaying, presentContextualNowPlaying)
        .modifier(
            ConditionalExitCommand(
                isActive: selectedNavigationDepth > 0 && !nowPlayingPresentation.isPresented,
                action: popSelectedNavigation
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast.current)
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

    private var rootTabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { requestedTab in
                guard requestedTab != selectedTab else { return }
                if requestedTab == .nowPlaying {
                    let contentTab = selectedTab
                    guard contentTab.isContentTab else { return }
                    stopMVIfNeeded(in: contentTab)
                    lastContentTab = contentTab
                    presentNowPlaying(from: .tabBar)
                    selectedTab = .nowPlaying
                    return
                }

                stopMVIfNeeded(in: selectedTab)
                selectedTab = requestedTab
                lastContentTab = requestedTab
                resetRootPresentation(for: requestedTab)
            }
        )
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

    private func presentContextualNowPlaying(returningTo focusID: AnyHashable?) {
        if nowPlayingPresentation.isPresented {
            nowPlayingActivationGeneration &+= 1
            return
        }
        contextualReturnFocusID = focusID
        stopMVIfNeeded(in: selectedTab)
        presentNowPlaying(from: .contextual)
    }

    private func presentNowPlaying(from source: NowPlayingPresentationSource) {
        nowPlayingPresentation.present(from: source)
        nowPlayingActivationGeneration &+= 1
    }

    private func dismissNowPlaying() {
        guard let source = nowPlayingPresentation.source else { return }
        if source == .contextual {
            _ = nowPlayingPresentation.dismiss()
            let destination = selectedTab
            let focusID = contextualReturnFocusID
            contextualReturnFocusID = nil
            Task { @MainActor in
                await Task.yield()
                requestTrackFocusRestoration(focusID, in: destination)
            }
        } else {
            let destination = lastContentTab
            selectedTab = destination
            _ = nowPlayingPresentation.dismiss()
            Task { @MainActor in
                await Task.yield()
                guard !nowPlayingPresentation.isPresented,
                      selectedTab == destination else { return }
                resetRootPresentation(for: destination)
            }
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
        let trackRestoration = trackFocusRestorations[tab] ?? TrackFocusRestorationState()
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
        .environment(\.nowPlayingFocusRestorationGeneration, trackRestoration.generation)
        .environment(\.nowPlayingFocusRestorationID, trackRestoration.trackID)
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

    private func requestTrackFocusRestoration(_ trackID: AnyHashable?, in tab: RootTab) {
        guard tab.isContentTab, let trackID else { return }
        var restoration = trackFocusRestorations[tab] ?? TrackFocusRestorationState()
        restoration.trackID = trackID
        restoration.generation &+= 1
        trackFocusRestorations[tab] = restoration
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
