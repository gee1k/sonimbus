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

struct NowPlayingPresentationState: Equatable {
    private(set) var source: NowPlayingPresentationSource?

    var isPresented: Bool { source != nil }

    mutating func present(from source: NowPlayingPresentationSource) {
        guard self.source == nil else { return }
        self.source = source
    }

    mutating func dismiss() -> NowPlayingPresentationSource? {
        defer { source = nil }
        return source
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

    mutating func handleBack(allowsLyricsNavigation: Bool = true) -> NowPlayingBackAction {
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
