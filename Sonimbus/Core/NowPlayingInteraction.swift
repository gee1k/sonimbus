enum NowPlayingPanel: Equatable {
    case artwork
    case lyrics
    case queue
}

enum NowPlayingChromeMode: Equatable {
    case controls
    case ambient
    case lyricsNavigation
}

enum NowPlayingBackAction: Equatable {
    case handled
    case deferToSystem
}

enum NowPlayingPresentationSource: Equatable {
    case contextual
    case tabBar
}

struct RootTabPresentationState<Route: Hashable> {
    var path: [Route] = []
    private(set) var rootActivationGeneration = 0

    mutating func resetToRoot() {
        path.removeAll()
        rootActivationGeneration &+= 1
    }
}

struct NavigationReturnContext<Tab: Hashable, Route: Hashable, Focus: Hashable>: Equatable {
    let tab: Tab
    let parentPath: [Route]
    let focus: Focus

    func matches(tab: Tab, parentPath: [Route]) -> Bool {
        self.tab == tab && self.parentPath == parentPath
    }

    func shouldDiscard(when tab: Tab, popsToDepth depth: Int) -> Bool {
        self.tab == tab && parentPath.count >= depth
    }
}

enum PlaybackOriginAction: Hashable {
    case play
    case shuffle
    case intelligence
}

enum PlaybackCollectionOrigin: Hashable {
    case playlist(Int)
    case intelligence(Int)
    case album(Int)
    case artist(Int)
    case daily
    case newSongs
    case recent
    case cloud
    case search
    case personalFM
    case none
}

enum PlaybackOriginSurface: Hashable {
    case collection(PlaybackCollectionOrigin)
    case homeRecent
    case homeNewSongs
    case homePersonalFM
    case searchResults
    case recentHistory
    case cloud

    var accessibilityID: String {
        switch self {
        case .collection(let origin): "collection-\(origin.accessibilityID)"
        case .homeRecent: "home-recent"
        case .homeNewSongs: "home-new-songs"
        case .homePersonalFM: "home-personal-fm"
        case .searchResults: "search-results"
        case .recentHistory: "recent-history"
        case .cloud: "cloud"
        }
    }
}

private extension PlaybackCollectionOrigin {
    var accessibilityID: String {
        switch self {
        case .playlist(let id): "playlist-\(id)"
        case .intelligence(let id): "intelligence-\(id)"
        case .album(let id): "album-\(id)"
        case .artist(let id): "artist-\(id)"
        case .daily: "daily"
        case .newSongs: "new-songs"
        case .recent: "recent"
        case .cloud: "cloud"
        case .search: "search"
        case .personalFM: "personal-fm"
        case .none: "none"
        }
    }
}

enum PlaybackOriginFocus: Hashable {
    case track(PlaybackOriginSurface, trackID: Int, occurrence: Int)
    case action(PlaybackOriginSurface, PlaybackOriginAction)

    var surface: PlaybackOriginSurface {
        switch self {
        case .track(let surface, _, _), .action(let surface, _): surface
        }
    }
}

struct NowPlayingPresentationState: Equatable {
    private(set) var source: NowPlayingPresentationSource?

    var isPresented: Bool { source != nil }

    @discardableResult
    mutating func present(from source: NowPlayingPresentationSource) -> Bool {
        guard self.source == nil else { return false }
        self.source = source
        return true
    }

    mutating func dismiss() -> NowPlayingPresentationSource? {
        let dismissedSource = source
        source = nil
        return dismissedSource
    }
}

struct NowPlayingInteractionState: Equatable {
    private(set) var panel: NowPlayingPanel = .lyrics
    private(set) var chromeMode: NowPlayingChromeMode = .controls
    private(set) var selectedLyricIndex: Int?
    private var panelBeforeQueue: NowPlayingPanel = .lyrics

    var showsControls: Bool { chromeMode == .controls }

    mutating func activate() {
        if panel == .queue {
            panel = panelBeforeQueue
        }
        chromeMode = .controls
        selectedLyricIndex = nil
    }

    mutating func showControls() {
        chromeMode = .controls
        selectedLyricIndex = nil
    }

    mutating func hideControlsForIdle() {
        guard panel != .queue else { return }
        chromeMode = .ambient
        selectedLyricIndex = nil
    }

    mutating func toggleLyrics() {
        panel = panel == .lyrics ? .artwork : .lyrics
        panelBeforeQueue = panel
        showControls()
    }

    mutating func toggleQueue() {
        if panel == .queue {
            panel = panelBeforeQueue
        } else {
            panelBeforeQueue = panel
            panel = .queue
        }
        showControls()
    }

    mutating func moveLyricSelection(
        direction: Int,
        activeIndex: Int?,
        lineCount: Int
    ) {
        guard panel == .lyrics, lineCount > 0, direction != 0 else { return }
        chromeMode = .lyricsNavigation
        let startingIndex = selectedLyricIndex ?? activeIndex ?? 0
        selectedLyricIndex = min(max(startingIndex + direction, 0), lineCount - 1)
    }

    mutating func clearLyricSelection() {
        selectedLyricIndex = nil
    }

    mutating func handleBack(
        hasCurrentTrack: Bool = true,
        allowsLyricsNavigation: Bool = true
    ) -> NowPlayingBackAction {
        guard hasCurrentTrack else { return .deferToSystem }
        if panel == .queue {
            panel = panelBeforeQueue
            showControls()
            return .handled
        }
        if chromeMode == .controls {
            chromeMode = panel == .lyrics && allowsLyricsNavigation ? .lyricsNavigation : .ambient
            selectedLyricIndex = nil
            return .handled
        }
        if selectedLyricIndex != nil {
            selectedLyricIndex = nil
            return .handled
        }
        return .deferToSystem
    }
}
