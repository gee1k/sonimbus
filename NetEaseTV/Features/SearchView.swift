import SwiftUI

@Observable
final class SearchSession {
    var query = ""
    var scope = NeteaseAPI.SearchType.songs
    var result: NeteaseAPI.SearchResult?
    var songCatalogArtist: ArtistSummary?
    var songCatalogHasMore = false
}

private enum SearchFocus: Hashable {
    case suggested
    case recent(String)
    case clearRecent
}

struct SearchView: View {
    @Environment(\.navigationFocusRestorationGeneration) private var focusRestorationGeneration
    @Environment(\.navigationFocusRestorationRoute) private var focusRestorationRoute
    @Environment(PlayerService.self) private var player

    @Bindable var session: SearchSession

    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var recentQueries: [String] = []
    @State private var suggestedQuery: String?
    @State private var searchGeneration = 0
    @State private var pendingResultFocusID: Int?
    @State private var lastFocusedResultID: Int?
    @FocusState private var focusedSearchControl: SearchFocus?
    @FocusState private var focusedResultID: Int?

    private var query: String {
        get { session.query }
        nonmutating set { session.query = newValue }
    }

    private var scope: NeteaseAPI.SearchType {
        get { session.scope }
        nonmutating set { session.scope = newValue }
    }

    private var result: NeteaseAPI.SearchResult? {
        get { session.result }
        nonmutating set { session.result = newValue }
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 20) {
                TextField("搜索歌曲、歌单、专辑、歌手或 MV", text: $session.query)
                    .font(.title2)
                    .onSubmit { Task { await search() } }
                Picker("类型", selection: $session.scope) {
                    Text("歌曲").tag(NeteaseAPI.SearchType.songs)
                    Text("歌单").tag(NeteaseAPI.SearchType.playlists)
                    Text("专辑").tag(NeteaseAPI.SearchType.albums)
                    Text("歌手").tag(NeteaseAPI.SearchType.artists)
                    Text("MV").tag(NeteaseAPI.SearchType.mvs)
                }
                .pickerStyle(.segmented)
                .onChange(of: scope) { _, _ in
                    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await search() }
                }
            }
            .padding(.horizontal, TVTheme.horizontalPadding)
            .padding(.top, 35)
            .focusSection()

            Group {
                if isSearching {
                    LoadStateView(title: "正在搜索")
                } else if let errorMessage {
                    LoadStateView(title: "搜索失败", message: errorMessage) {
                        Task { await search() }
                    }
                } else if let result {
                    results(result)
                } else {
                    suggestions
                }
            }
        }
        .background(TVBackground(tint: TVTheme.magenta))
        .onAppear { loadRecentQueries() }
        .task { await loadSuggestedQuery() }
        .onChange(of: focusedResultID) { _, id in
            if let id { lastFocusedResultID = id }
        }
        .onChange(of: query) { _, value in
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            searchGeneration += 1
            isSearching = false
            isLoadingMore = false
            errorMessage = nil
            result = nil
            session.songCatalogArtist = nil
            session.songCatalogHasMore = false
        }
        .task(id: focusRestorationGeneration) { await restoreNavigationFocus() }
    }

    @ViewBuilder
    private func results(_ result: NeteaseAPI.SearchResult) -> some View {
        switch scope {
        case .songs:
            let tracks = result.songs ?? []
            if tracks.isEmpty {
                noResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            if let artist = session.songCatalogArtist {
                                catalogHeader(artist)
                            }
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                TrackRow(track: track, index: index, tracks: tracks, source: .search)
                                    .id(track.id)
                                    .focused($focusedResultID, equals: track.id)
                            }
                            if hasMore(result) { loadMoreButton }
                        }
                        .padding(.horizontal, TVTheme.horizontalPadding)
                        .padding(.bottom, 70)
                    }
                    .task(id: pendingResultFocusID) {
                        await focusPendingResult(using: proxy)
                    }
                }
            }
        case .playlists:
            cardGrid(items: result.playlists ?? [], hasMore: hasMore(result)) { PlaylistCard(playlist: $0) }
        case .albums:
            cardGrid(items: result.albums ?? [], hasMore: hasMore(result)) { AlbumCard(album: $0) }
        case .artists:
            cardGrid(items: result.artists ?? [], hasMore: hasMore(result)) { ArtistCard(artist: $0) }
        case .mvs:
            let videos = result.mvs ?? []
            cardGrid(items: videos, hasMore: hasMore(result), columnCount: 4) {
                MVCard(mv: $0, width: 350, queue: videos)
            }
        }
    }

    private func catalogHeader(_ artist: ArtistSummary) -> some View {
        HStack(spacing: 20) {
            ArtworkView(url: artist.artworkURL, cornerRadius: 14)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(artist.name)的完整曲库")
                    .font(.title3.bold())
                Text("含网易云暂不可播放曲目；播放时会自动尝试补全音源。")
                    .font(.callout)
                    .foregroundStyle(TVTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func cardGrid<Item: Identifiable, Card: View>(
        items: [Item],
        hasMore: Bool,
        columnCount: Int = 5,
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View where Item.ID == Int {
        Group {
            if items.isEmpty {
                noResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 36) {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 34),
                                    count: columnCount
                                ),
                                spacing: 42
                            ) {
                                ForEach(items) { item in
                                    card(item)
                                        .id(item.id)
                                        .focused($focusedResultID, equals: item.id)
                                        .simultaneousGesture(TapGesture().onEnded {
                                            lastFocusedResultID = item.id
                                        })
                                }
                            }
                            if hasMore { loadMoreButton }
                        }
                        .padding(.horizontal, TVTheme.horizontalPadding)
                        .padding(.bottom, 70)
                    }
                    .task(id: pendingResultFocusID) {
                        await focusPendingResult(using: proxy)
                    }
                }
            }
        }
    }

    private var noResults: some View {
        EmptyStateView(
            title: "没有找到相关内容",
            message: "换一个关键词或搜索类型试试。",
            symbol: "magnifyingglass"
        )
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            if isLoadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("载入中")
                }
            } else {
                Label("载入更多", systemImage: "chevron.down")
            }
        }
        .buttonStyle(TVPillButtonStyle())
        .disabled(isLoadingMore)
        .padding(.vertical, 18)
    }

    private var suggestions: some View {
        VStack(spacing: 28) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 82))
                .foregroundStyle(
                    LinearGradient(colors: [TVTheme.accent, TVTheme.magenta], startPoint: .top, endPoint: .bottom)
                )
            Text("想听什么？").font(.system(size: 42, weight: .bold, design: .rounded))
            Text("输入歌名、歌手、专辑、歌单或 MV 名称，然后按下遥控器确认键。")
                .font(.title3)
                .foregroundStyle(TVTheme.secondaryText)
            if let suggestedQuery, !suggestedQuery.isEmpty {
                Button {
                    query = suggestedQuery
                    Task { await search() }
                } label: {
                    Label("试试搜索：\(suggestedQuery)", systemImage: "sparkles")
                }
                .buttonStyle(TVPillButtonStyle())
                .focused($focusedSearchControl, equals: .suggested)
                .onMoveCommand { direction in
                    if direction == .down, let first = recentQueries.first {
                        focusedSearchControl = .recent(first)
                    }
                }
            }
            if !recentQueries.isEmpty {
                VStack(spacing: 16) {
                    HStack {
                        Text("最近搜索")
                            .font(.headline)
                        Spacer()
                        Button("清除") {
                            recentQueries = []
                            saveRecentQueries()
                        }
                        .buttonStyle(TVPillButtonStyle())
                        .focused($focusedSearchControl, equals: .clearRecent)
                        .onMoveCommand { direction in
                            if direction == .up, suggestedQuery != nil {
                                focusedSearchControl = .suggested
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(recentQueries.prefix(8), id: \.self) { keyword in
                                Button(keyword) {
                                    query = keyword
                                    Task { await search() }
                                }
                                .buttonStyle(TVPillButtonStyle())
                                .focused($focusedSearchControl, equals: .recent(keyword))
                                .onMoveCommand { direction in
                                    if direction == .up, suggestedQuery != nil {
                                        focusedSearchControl = .suggested
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .scrollClipDisabled()
                }
                .frame(maxWidth: 1_260)
                .padding(.top, 16)
                .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func restoreNavigationFocus() async {
        let routeID: Int? = switch focusRestorationRoute {
        case .playlist(let id), .album(let id), .artist(let id), .mv(let id): id
        default: nil
        }
        guard let id = routeID ?? lastFocusedResultID else { return }
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        focusedResultID = nil
        lastFocusedResultID = id
        pendingResultFocusID = id
    }

    @MainActor
    private func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let requestedScope = scope
        isSearching = true
        isLoadingMore = false
        focusedResultID = nil
        pendingResultFocusID = nil
        errorMessage = nil
        session.songCatalogArtist = nil
        session.songCatalogHasMore = false
        do {
            var response: NeteaseAPI.SearchResult
            var matchedCatalogArtist: ArtistSummary?
            var matchedCatalogHasMore = false
            if requestedScope == .songs {
                async let regularSearch = NeteaseAPI.search(keyword, type: .songs)
                async let artistSearch = NeteaseAPI.search(keyword, type: .artists, limit: 10)
                response = try await regularSearch
                if let artistResult = try? await artistSearch,
                   let artist = exactArtist(in: artistResult.artists ?? [], matching: keyword),
                   let catalog = try? await NeteaseAPI.artistSongs(id: artist.id),
                   !catalog.songs.isEmpty {
                    response = replacingSongs(
                        in: response,
                        with: catalog.songs,
                        total: artist.musicSize
                    )
                    matchedCatalogArtist = artist
                    matchedCatalogHasMore = catalog.hasMore
                }
            } else {
                response = try await NeteaseAPI.search(keyword, type: requestedScope)
            }
            guard generation == searchGeneration else { return }
            guard requestedScope == scope,
                  keyword == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                isSearching = false
                return
            }
            session.songCatalogArtist = matchedCatalogArtist
            session.songCatalogHasMore = matchedCatalogHasMore
            result = response
            recordRecentQuery(keyword)
        } catch {
            guard generation == searchGeneration else { return }
            guard requestedScope == scope else {
                isSearching = false
                return
            }
            result = nil
            errorMessage = error.localizedDescription
        }
        if generation == searchGeneration { isSearching = false }
    }

    @MainActor
    private func loadMore() async {
        guard let current = result else { return }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, hasMore(current) else { return }
        let generation = searchGeneration
        let requestedScope = scope
        isLoadingMore = true
        defer {
            if generation == searchGeneration { isLoadingMore = false }
        }
        do {
            let next: NeteaseAPI.SearchResult
            var catalogHasMore: Bool?
            if requestedScope == .songs, let artist = session.songCatalogArtist {
                let page = try await NeteaseAPI.artistSongs(
                    id: artist.id,
                    offset: current.songs?.count ?? 0
                )
                next = replacingSongs(
                    in: current,
                    with: page.songs,
                    total: artist.musicSize
                )
                catalogHasMore = page.hasMore
            } else {
                next = try await NeteaseAPI.search(
                    keyword,
                    type: requestedScope,
                    offset: resultItemCount(current)
                )
            }
            guard generation == searchGeneration,
                  requestedScope == scope,
                  keyword == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let firstNewID = firstNewResultID(current, with: next)
            focusedResultID = nil
            result = merged(current, with: next)
            if let catalogHasMore { session.songCatalogHasMore = catalogHasMore }
            pendingResultFocusID = firstNewID
        } catch {
            guard generation == searchGeneration,
                  requestedScope == scope else { return }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    private func hasMore(_ value: NeteaseAPI.SearchResult) -> Bool {
        if scope == .songs, session.songCatalogArtist != nil {
            return session.songCatalogHasMore
        }
        let count = resultItemCount(value)
        guard count > 0 else { return false }
        if let total = resultTotalCount(value) { return count < total }
        return count.isMultiple(of: 40)
    }

    private func resultItemCount(_ value: NeteaseAPI.SearchResult) -> Int {
        switch scope {
        case .songs: value.songs?.count ?? 0
        case .playlists: value.playlists?.count ?? 0
        case .albums: value.albums?.count ?? 0
        case .artists: value.artists?.count ?? 0
        case .mvs: value.mvs?.count ?? 0
        }
    }

    private func resultTotalCount(_ value: NeteaseAPI.SearchResult) -> Int? {
        switch scope {
        case .songs: value.songCount
        case .playlists: value.playlistCount
        case .albums: value.albumCount
        case .artists: value.artistCount
        case .mvs: value.mvCount
        }
    }

    private func firstNewResultID(
        _ current: NeteaseAPI.SearchResult,
        with next: NeteaseAPI.SearchResult
    ) -> Int? {
        switch scope {
        case .songs:
            let existing = Set((current.songs ?? []).map(\.id))
            return next.songs?.first(where: { !existing.contains($0.id) })?.id
        case .playlists:
            let existing = Set((current.playlists ?? []).map(\.id))
            return next.playlists?.first(where: { !existing.contains($0.id) })?.id
        case .albums:
            let existing = Set((current.albums ?? []).map(\.id))
            return next.albums?.first(where: { !existing.contains($0.id) })?.id
        case .artists:
            let existing = Set((current.artists ?? []).map(\.id))
            return next.artists?.first(where: { !existing.contains($0.id) })?.id
        case .mvs:
            let existing = Set((current.mvs ?? []).map(\.id))
            return next.mvs?.first(where: { !existing.contains($0.id) })?.id
        }
    }

    private func merged(
        _ current: NeteaseAPI.SearchResult,
        with next: NeteaseAPI.SearchResult
    ) -> NeteaseAPI.SearchResult {
        NeteaseAPI.SearchResult(
            songs: unique((current.songs ?? []) + (next.songs ?? [])),
            albums: unique((current.albums ?? []) + (next.albums ?? [])),
            artists: unique((current.artists ?? []) + (next.artists ?? [])),
            playlists: unique((current.playlists ?? []) + (next.playlists ?? [])),
            mvs: unique((current.mvs ?? []) + (next.mvs ?? [])),
            songCount: next.songCount ?? current.songCount,
            albumCount: next.albumCount ?? current.albumCount,
            artistCount: next.artistCount ?? current.artistCount,
            playlistCount: next.playlistCount ?? current.playlistCount,
            mvCount: next.mvCount ?? current.mvCount
        )
    }

    private func replacingSongs(
        in result: NeteaseAPI.SearchResult,
        with songs: [Track],
        total: Int?
    ) -> NeteaseAPI.SearchResult {
        NeteaseAPI.SearchResult(
            songs: songs,
            albums: result.albums,
            artists: result.artists,
            playlists: result.playlists,
            mvs: result.mvs,
            songCount: total ?? songs.count,
            albumCount: result.albumCount,
            artistCount: result.artistCount,
            playlistCount: result.playlistCount,
            mvCount: result.mvCount
        )
    }

    private func exactArtist(in artists: [ArtistSummary], matching keyword: String) -> ArtistSummary? {
        let term = normalizedSearchTerm(keyword)
        return artists.first { artist in
            normalizedSearchTerm(artist.name) == term
                || artist.alias.contains { normalizedSearchTerm($0) == term }
        }
    }

    private func normalizedSearchTerm(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .filter { !$0.isWhitespace }
    }

    private func unique<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
        var seen = Set<Item.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    @MainActor
    private func focusPendingResult(using proxy: ScrollViewProxy) async {
        guard let id = pendingResultFocusID else { return }
        await Task.yield()
        proxy.scrollTo(id, anchor: .center)
        try? await Task.sleep(for: .milliseconds(160))
        guard pendingResultFocusID == id else { return }
        focusedResultID = id
        pendingResultFocusID = nil
    }

    private func loadRecentQueries() {
        guard let data = UserDefaults.standard.data(forKey: "search.recentQueries"),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return }
        recentQueries = values
    }

    @MainActor
    private func loadSuggestedQuery() async {
        guard suggestedQuery == nil else { return }
        suggestedQuery = try? await NeteaseAPI.searchDefaultKeyword()
    }

    private func recordRecentQuery(_ keyword: String) {
        recentQueries.removeAll { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }
        recentQueries.insert(keyword, at: 0)
        recentQueries = Array(recentQueries.prefix(8))
        saveRecentQueries()
    }

    private func saveRecentQueries() {
        guard let data = try? JSONEncoder().encode(recentQueries) else { return }
        UserDefaults.standard.set(data, forKey: "search.recentQueries")
    }
}
