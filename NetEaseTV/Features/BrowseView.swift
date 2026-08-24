import SwiftUI

@Observable
final class BrowseSession {
    var playlists: [PlaylistSummary] = []
    var charts: [ToplistItem] = []
    var albums: [AlbumSummary] = []
    var artists: [ArtistSummary] = []
    var mvs: [MVSummary] = []
    var category = "全部"
    var order = "hot"
}

struct BrowseView: View {
    private enum Section: Hashable {
        case top
        case playlists
        case charts
        case mvs
        case albums
        case artists
    }

    private let fallbackCategories = ["全部", "华语", "欧美", "日语", "韩语", "粤语", "电子", "摇滚", "民谣", "说唱", "古典", "爵士"]

    @Bindable var session: BrowseSession
    let activationGeneration: Int

    @Environment(\.navigationFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.navigationFocusRestorationRoute) private var focusRestorationRoute

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = 0
    @State private var categories: [String] = []
    @State private var lastFocusedRoute: AppRoute?
    @FocusState private var focusedRoute: AppRoute?

    private var playlists: [PlaylistSummary] {
        get { session.playlists }
        nonmutating set { session.playlists = newValue }
    }

    private var charts: [ToplistItem] {
        get { session.charts }
        nonmutating set { session.charts = newValue }
    }

    private var albums: [AlbumSummary] {
        get { session.albums }
        nonmutating set { session.albums = newValue }
    }

    private var artists: [ArtistSummary] {
        get { session.artists }
        nonmutating set { session.artists = newValue }
    }

    private var mvs: [MVSummary] {
        get { session.mvs }
        nonmutating set { session.mvs = newValue }
    }

    private var category: String {
        get { session.category }
        nonmutating set { session.category = newValue }
    }

    private var order: String {
        get { session.order }
        nonmutating set { session.order = newValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 54) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("探索音乐世界")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("编辑精选、音乐视频、排行榜与最新发行")
                        .font(.title3)
                        .foregroundStyle(TVTheme.secondaryText)
                    HStack(spacing: 18) {
                        Menu {
                            ForEach(availableCategories, id: \.self) { item in
                                Button(item) { category = item }
                            }
                        } label: {
                            Label("分类 · \(category)", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .buttonStyle(TVPillButtonStyle())

                        Picker("排序", selection: $session.order) {
                            Text("热门").tag("hot")
                            Text("最新").tag("new")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 340)
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, TVTheme.horizontalPadding)
                .focusSection()

                if !playlists.isEmpty {
                    HorizontalShelf(title: "编辑精选") {
                        ForEach(playlists) { playlist in
                            PlaylistCard(playlist: playlist, width: 280)
                                .focused($focusedRoute, equals: .playlist(playlist.id))
                                .id(AppRoute.playlist(playlist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .playlist(playlist.id)
                                })
                        }
                    }
                    .id(Section.playlists)
                }

                if !charts.isEmpty {
                    HorizontalShelf(title: "排行榜", subtitle: "实时了解大家都在听什么") {
                        ForEach(charts) { chart in
                            ChartCard(chart: chart)
                                .focused($focusedRoute, equals: .playlist(chart.id))
                                .id(AppRoute.playlist(chart.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .playlist(chart.id)
                                })
                        }
                    }
                    .id(Section.charts)
                }

                if !mvs.isEmpty {
                    HorizontalShelf(title: "音乐视频", subtitle: "为大屏精选的网易云 MV") {
                        ForEach(mvs) { mv in
                            MVCard(mv: mv, queue: mvs)
                                .focused($focusedRoute, equals: .mv(mv.id))
                                .id(AppRoute.mv(mv.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .mv(mv.id)
                                })
                        }
                    }
                    .id(Section.mvs)
                }

                if !albums.isEmpty {
                    HorizontalShelf(title: "新专速递") {
                        ForEach(albums) { album in
                            AlbumCard(album: album)
                                .focused($focusedRoute, equals: .album(album.id))
                                .id(AppRoute.album(album.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .album(album.id)
                                })
                        }
                    }
                    .id(Section.albums)
                }

                if !artists.isEmpty {
                    HorizontalShelf(title: "热门歌手") {
                        ForEach(artists) { artist in
                            ArtistCard(artist: artist)
                                .focused($focusedRoute, equals: .artist(artist.id))
                                .id(AppRoute.artist(artist.id))
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastFocusedRoute = .artist(artist.id)
                                })
                        }
                    }
                    .id(Section.artists)
                }

                if isLoading {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 100)
                } else if let errorMessage, playlists.isEmpty {
                    LoadStateView(title: "浏览页暂时不可用", message: errorMessage) {
                        Task { await load() }
                    }
                    .frame(height: 420)
                }
                }
                .padding(.top, 44)
                .padding(.bottom, 70)
                // Include the top padding in the anchor so scrollTo resolves to offset zero.
                .id(Section.top)
            }
            .background(TVBackground(tint: .blue))
            .task(id: focusRestorationGeneration) {
                await restoreNavigationFocus(using: proxy)
            }
            .task(id: activationGeneration) {
                await resetForTabActivation(using: proxy)
            }
        }
        .task(id: "\(category)-\(order)") { await load() }
        .onChange(of: focusedRoute) { _, route in
            if let route { lastFocusedRoute = route }
        }
    }

    @MainActor
    private func resetForTabActivation(using proxy: ScrollViewProxy) async {
        guard activationGeneration > 0 else { return }
        focusedRoute = nil
        lastFocusedRoute = nil
        await Task.yield()
        guard !Task.isCancelled else { return }
        proxy.scrollTo(Section.top, anchor: .top)
    }

    private var availableCategories: [String] {
        categories.isEmpty ? fallbackCategories : categories
    }

    @MainActor
    private func restoreNavigationFocus(using proxy: ScrollViewProxy) async {
        guard let route = focusRestorationRoute ?? lastFocusedRoute else { return }
        focusedRoute = nil
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(section(for: route), anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        lastFocusedRoute = route
        focusedRoute = route
    }

    private func section(for route: AppRoute) -> Section {
        switch route {
        case .playlist(let id):
            return charts.contains(where: { $0.id == id }) ? .charts : .playlists
        case .mv:
            return .mvs
        case .album:
            return .albums
        case .artist:
            return .artists
        default:
            return .playlists
        }
    }

    @MainActor
    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedCategory = category
        let requestedOrder = order
        let cachedCharts = charts
        let cachedAlbums = albums
        let cachedArtists = artists
        let cachedMVs = mvs
        isLoading = true
        errorMessage = nil
        async let playlistRequest = try? NeteaseAPI.topPlaylists(
            category: requestedCategory,
            order: requestedOrder
        ).playlists
        async let categoryRequest = categories.isEmpty ? try? NeteaseAPI.playlistCategories() : nil
        async let chartRequest = cachedCharts.isEmpty ? try? NeteaseAPI.toplists() : cachedCharts
        async let albumRequest = cachedAlbums.isEmpty ? try? NeteaseAPI.newAlbums() : cachedAlbums
        async let artistRequest = cachedArtists.isEmpty ? try? NeteaseAPI.topArtists() : cachedArtists
        async let personalizedMVRequest = cachedMVs.isEmpty ? try? NeteaseAPI.personalizedMVs(limit: 12) : cachedMVs
        async let latestMVRequest = cachedMVs.isEmpty ? try? NeteaseAPI.latestMVs(limit: 24) : []
        let playlistResult = await playlistRequest ?? []
        let chartResult = await chartRequest ?? []
        let albumResult = await albumRequest ?? []
        let artistResult = await artistRequest ?? []
        let mvResult = mergedMVs(
            recommended: await personalizedMVRequest ?? [],
            latest: await latestMVRequest ?? []
        )
        let categoryResult = await categoryRequest ?? []
        guard generation == loadGeneration,
              !Task.isCancelled,
              requestedCategory == category,
              requestedOrder == order else { return }
        playlists = playlistResult
        charts = chartResult
        albums = albumResult
        artists = artistResult
        mvs = mvResult
        if !categoryResult.isEmpty {
            var seen = Set<String>()
            categories = (["全部"] + categoryResult.map(\.name))
                .filter { seen.insert($0).inserted }
        }
        if playlists.isEmpty && charts.isEmpty && albums.isEmpty && artists.isEmpty && mvs.isEmpty {
            errorMessage = "没有收到内容，请稍后重试"
        }
        isLoading = false
    }

    private func mergedMVs(recommended: [MVSummary], latest: [MVSummary]) -> [MVSummary] {
        var seen = Set<Int>()
        return (recommended + latest)
            .filter { seen.insert($0.id).inserted }
            .prefix(24)
            .map { $0 }
    }
}

private struct ChartCard: View {
    let chart: ToplistItem

    var body: some View {
        NavigationLink(value: AppRoute.playlist(chart.id)) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(url: chart.artworkURL)
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text(chart.name).font(.title3.bold()).lineLimit(1)
                    Text(chart.updateFrequency ?? "持续更新")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(22)
            }
            .frame(width: 285, height: 285)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(TVCardButtonStyle(cornerRadius: 24, contentPadding: 0))
    }
}
