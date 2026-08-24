import AVFoundation
import MediaPlayer
import Observation
import os.log
import UIKit

enum PlaySource: Codable, Equatable {
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

    var sourceID: Int {
        switch self {
        case .playlist(let id), .intelligence(let id), .album(let id), .artist(let id): id
        default: 0
        }
    }

    var playlistID: Int? {
        guard case .playlist(let id) = self else { return nil }
        return id
    }
}

@MainActor
@Observable
final class PlayerService {
    static let shared = PlayerService()
    private static let log = Logger(subsystem: "com.gee1k.neteasetv", category: "Player")

    private(set) var queue: [Track] = []
    private(set) var recentTracks: [Track] = []
    private(set) var currentTrack: Track?
    private(set) var currentIndex = -1
    private(set) var source: PlaySource = .none
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var isLoadingPersonalFM = false
    private(set) var duration: TimeInterval = 0
    private(set) var lyrics: ParsedLyrics?
    private(set) var isLoadingLyrics = false
    private(set) var lyricsErrorMessage: String?
    private(set) var servedQuality: String?
    private(set) var alternativeSource: String?
    private(set) var isTrial = false
    private(set) var shuffleEnabled = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var preferredQuality: AudioQuality = .lossless
    private(set) var showsTranslatedLyrics = true
    private(set) var enablesAlternativeSources = true
    var progress: TimeInterval = 0
    var isScrubbing = false

    var activeLyricIndex: Int? { lyrics?.activeIndex(at: progress) }
    var canGoPrevious: Bool { currentTrack != nil && source != .personalFM }
    var canGoNext: Bool {
        guard currentTrack != nil else { return false }
        if source == .personalFM { return true }
        return PlaybackQueuePolicy.nextIndex(
            after: currentIndex,
            count: activeQueue.count,
            repeatMode: repeatMode
        ) != nil
    }
    var playbackQueue: [Track] {
        if source == .personalFM {
            return currentTrack.map { [$0] } ?? []
        }
        return activeQueue
    }

    private let engine = AVPlayer()
    private var shuffledQueue: [Track] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var resolveGeneration = 0
    private var lyricsGeneration = 0
    private var fmGeneration = 0
    private var playRequestGeneration = 0
    private var fmUpcoming: [Track] = []
    private var fmPrefetchTask: Task<Void, Never>?
    private var scrobbled = false
    private var consecutiveFailures = 0
    private var wasPlayingBeforeInterruption = false
    private var isResolvingURL = false
    private var didReachEnd = false
    private var attemptedAlternativeSources = Set<String>()

    private var activeQueue: [Track] { shuffleEnabled ? shuffledQueue : queue }

    private init() {
        engine.actionAtItemEnd = .pause
        repeatMode = UserDefaults.standard.string(forKey: "player.repeat")
            .flatMap(RepeatMode.init(rawValue:)) ?? .off
        shuffleEnabled = UserDefaults.standard.bool(forKey: "player.shuffle")
        preferredQuality = UserDefaults.standard.string(forKey: "player.quality")
            .flatMap(AudioQuality.init(rawValue:)) ?? .lossless
        showsTranslatedLyrics = UserDefaults.standard.object(forKey: "lyrics.showTranslations") as? Bool ?? true
        enablesAlternativeSources = UserDefaults.standard.object(forKey: "player.alternativeSources") as? Bool ?? true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.log.error("Audio session setup failed: \(error.localizedDescription)")
        }

        timeObserver = engine.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing, time.seconds.isFinite else { return }
                self.progress = max(0, time.seconds)
                self.updateNowPlayingProgress()
                let threshold = min(30, max(5, self.duration / 2))
                if !self.scrobbled, self.progress >= threshold {
                    self.scrobbleIfNeeded(completed: false)
                }
            }
        }

        statusObservation = engine.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = self.isResolvingURL
                    || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleAudioInterruption(notification) }
        }

        configureRemoteCommands()
        restoreState()
    }

    func play(_ tracks: [Track], source: PlaySource, startingAt track: Track? = nil) {
        let uniqueTracks = PlaybackQueuePolicy.deduplicated(visibleTracks(tracks))
        guard !uniqueTracks.isEmpty else { return }
        consecutiveFailures = 0
        queue = uniqueTracks
        self.source = source
        let first = track.flatMap { requested in
            uniqueTracks.first(where: { $0.id == requested.id })
        } ?? uniqueTracks[0]
        if shuffleEnabled {
            shuffledQueue = [first] + uniqueTracks.filter { $0.id != first.id }.shuffled()
            currentIndex = 0
        } else {
            currentIndex = uniqueTracks.firstIndex(where: { $0.id == first.id }) ?? 0
        }
        start(activeQueue[currentIndex])
    }

    func playShuffled(_ tracks: [Track], source: PlaySource) {
        let uniqueTracks = PlaybackQueuePolicy.deduplicated(visibleTracks(tracks))
        guard let startingTrack = uniqueTracks.randomElement() else { return }
        if !shuffleEnabled {
            shuffleEnabled = true
            UserDefaults.standard.set(true, forKey: "player.shuffle")
        }
        play(uniqueTracks, source: source, startingAt: startingTrack)
    }

    func playTrack(_ track: Track, source: PlaySource = .none) {
        guard isTrackVisible(track) else {
            ToastCenter.shared.show("请先在设置中开启歌曲解锁")
            return
        }
        consecutiveFailures = 0
        if let index = activeQueue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = index
            start(track)
        } else {
            play([track], source: source)
        }
    }

    func playNext(_ track: Track) {
        guard isTrackVisible(track) else {
            ToastCenter.shared.show("请先在设置中开启歌曲解锁")
            return
        }
        guard let currentTrack else {
            play([track], source: .none)
            return
        }
        guard currentTrack.id != track.id else {
            ToastCenter.shared.show("这首歌正在播放")
            return
        }

        if shuffleEnabled {
            if !queue.contains(where: { $0.id == track.id }) { queue.append(track) }
            shuffledQueue.removeAll { $0.id == track.id }
            let index = shuffledQueue.firstIndex(where: { $0.id == currentTrack.id }) ?? currentIndex
            shuffledQueue.insert(track, at: min(index + 1, shuffledQueue.count))
            currentIndex = index
        } else {
            queue.removeAll { $0.id == track.id }
            let index = queue.firstIndex(where: { $0.id == currentTrack.id }) ?? currentIndex
            queue.insert(track, at: min(index + 1, queue.count))
            currentIndex = index
        }
        persistState()
        ToastCenter.shared.show("《\(track.name)》将在下一首播放")
    }

    func addToQueue(_ track: Track) {
        guard isTrackVisible(track) else {
            ToastCenter.shared.show("请先在设置中开启歌曲解锁")
            return
        }
        guard currentTrack != nil else {
            play([track], source: .none)
            return
        }
        guard !queue.contains(where: { $0.id == track.id }) else {
            ToastCenter.shared.show("《\(track.name)》已在播放队列中")
            return
        }
        queue.append(track)
        if shuffleEnabled { shuffledQueue.append(track) }
        persistState()
        ToastCenter.shared.show("《\(track.name)》已添加到队列末尾")
    }

    func removeFromQueue(_ track: Track) {
        guard let currentTrack, currentTrack.id != track.id else {
            ToastCenter.shared.show("正在播放的歌曲不能从队列移除")
            return
        }
        let previousCount = queue.count
        queue.removeAll { $0.id == track.id }
        shuffledQueue.removeAll { $0.id == track.id }
        guard queue.count != previousCount else { return }
        currentIndex = activeQueue.firstIndex(where: { $0.id == currentTrack.id }) ?? 0
        persistState()
        ToastCenter.shared.show("已从播放队列移除《\(track.name)》")
    }

    func clearRecentTracks() {
        recentTracks = []
        persistState()
    }

    func clearForAccountChange() {
        resolveGeneration += 1
        lyricsGeneration += 1
        fmGeneration += 1
        playRequestGeneration += 1
        fmPrefetchTask?.cancel()
        fmPrefetchTask = nil
        itemStatusObservation = nil
        engine.pause()
        engine.replaceCurrentItem(with: nil)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        queue = []
        shuffledQueue = []
        fmUpcoming = []
        recentTracks = []
        currentTrack = nil
        currentIndex = -1
        source = .none
        isPlaying = false
        isBuffering = false
        isLoadingPersonalFM = false
        duration = 0
        progress = 0
        lyrics = nil
        isLoadingLyrics = false
        lyricsErrorMessage = nil
        servedQuality = nil
        alternativeSource = nil
        isTrial = false
        attemptedAlternativeSources.removeAll()
        isResolvingURL = false
        didReachEnd = false
        scrobbled = false
        consecutiveFailures = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        persistState()
    }

    func startPersonalFM() {
        ToastCenter.shared.show("正在为你挑选私人 FM…")
        consecutiveFailures = 0
        resolveGeneration += 1
        lyricsGeneration += 1
        fmGeneration += 1
        playRequestGeneration += 1
        fmPrefetchTask?.cancel()
        fmPrefetchTask = nil
        itemStatusObservation = nil
        let generation = fmGeneration

        engine.pause()
        engine.replaceCurrentItem(with: nil)
        source = .personalFM
        queue = []
        shuffledQueue = []
        fmUpcoming = []
        currentTrack = nil
        currentIndex = -1
        progress = 0
        duration = 0
        lyrics = nil
        isLoadingLyrics = false
        lyricsErrorMessage = nil
        servedQuality = nil
        alternativeSource = nil
        isTrial = false
        attemptedAlternativeSources.removeAll()
        isPlaying = false
        isResolvingURL = false
        isBuffering = true
        isLoadingPersonalFM = true
        didReachEnd = false
        updateNowPlayingMetadata()
        persistState()

        Task { await advanceFM(generation: generation, showsError: true) }
    }

    func startIntelligence(
        from track: Track,
        playlistID: Int,
        onStarted: (() -> Void)? = nil
    ) {
        playRequestGeneration += 1
        let requestGeneration = playRequestGeneration
        ToastCenter.shared.show("正在生成心动歌单…")
        Task {
            do {
                let generated = try await NeteaseAPI.intelligenceList(
                    songID: track.id,
                    playlistID: playlistID
                )
                guard requestGeneration == playRequestGeneration else { return }
                var seen = Set<Int>()
                let tracks = generated.filter { seen.insert($0.id).inserted }
                guard !tracks.isEmpty else {
                    ToastCenter.shared.show("暂时没有生成可播放的心动歌曲")
                    return
                }
                play(tracks, source: .intelligence(playlistID))
                onStarted?()
                ToastCenter.shared.show("已开启心动模式")
            } catch {
                guard requestGeneration == playRequestGeneration else { return }
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    func dislikeCurrentFM() {
        guard source == .personalFM, let track = currentTrack else { return }
        let generation = fmGeneration
        Task {
            await advanceFM(generation: generation, showsError: true)
            try? await NeteaseAPI.fmTrash(id: track.id)
            ToastCenter.shared.show("已减少推荐《\(track.name)》")
        }
    }

    func togglePlayPause() {
        guard let track = currentTrack else { return }
        if isBuffering {
            pause()
            return
        }
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else if engine.currentItem == nil || didReachEnd {
            start(track, at: didReachEnd ? 0 : progress)
        } else {
            engine.play()
            isPlaying = true
        }
        updateNowPlayingProgress()
    }

    func pause() {
        if isResolvingURL {
            resolveGeneration += 1
            isResolvingURL = false
            isBuffering = false
        }
        engine.pause()
        isPlaying = false
        isBuffering = false
        updateNowPlayingProgress()
        persistState()
    }

    func next() {
        consecutiveFailures = 0
        advanceToNext(userInitiated: true)
    }

    private func advanceToNext(userInitiated: Bool) {
        if source == .personalFM {
            let generation = fmGeneration
            Task { await advanceFM(generation: generation, showsError: userInitiated) }
            return
        }
        guard !activeQueue.isEmpty else { return }
        guard let nextIndex = PlaybackQueuePolicy.nextIndex(
            after: currentIndex,
            count: activeQueue.count,
            repeatMode: repeatMode
        ) else {
            if userInitiated {
                ToastCenter.shared.show("已经是队列末尾")
            } else {
                engine.pause()
                isPlaying = false
                isBuffering = false
                didReachEnd = true
                updateNowPlayingProgress()
                persistState()
            }
            return
        }
        currentIndex = nextIndex
        start(activeQueue[nextIndex])
    }

    func previous() {
        guard source != .personalFM else { return }
        consecutiveFailures = 0
        if progress > 4 {
            seek(to: 0)
            return
        }
        guard !activeQueue.isEmpty else { return }
        var previousIndex = currentIndex - 1
        if previousIndex < 0 {
            guard repeatMode == .all else {
                seek(to: 0)
                return
            }
            previousIndex = activeQueue.count - 1
        }
        currentIndex = previousIndex
        start(activeQueue[previousIndex])
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(0, seconds), max(duration, 0))
        progress = target
        if target <= 0 || target < max(duration - 0.5, 0) {
            didReachEnd = false
        }
        engine.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlayingProgress()
        persistState()
    }

    func seek(by delta: TimeInterval) {
        seek(to: progress + delta)
    }

    func toggleShuffle() {
        guard source != .personalFM else { return }
        shuffleEnabled.toggle()
        UserDefaults.standard.set(shuffleEnabled, forKey: "player.shuffle")
        guard let track = currentTrack else { return }
        if shuffleEnabled {
            shuffledQueue = [track] + queue.filter { $0.id != track.id }.shuffled()
            currentIndex = 0
        } else {
            currentIndex = queue.firstIndex(where: { $0.id == track.id }) ?? 0
        }
        persistState()
    }

    func cycleRepeat() {
        guard source != .personalFM else { return }
        repeatMode = repeatMode.next
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "player.repeat")
        persistState()
    }

    func setPreferredQuality(_ quality: AudioQuality) {
        preferredQuality = quality
        UserDefaults.standard.set(quality.rawValue, forKey: "player.quality")
        ToastCenter.shared.show("音质已设为\(quality.displayName)，下一首生效")
    }

    func setShowsTranslatedLyrics(_ shows: Bool) {
        showsTranslatedLyrics = shows
        UserDefaults.standard.set(shows, forKey: "lyrics.showTranslations")
    }

    func setEnablesAlternativeSources(_ enabled: Bool) {
        enablesAlternativeSources = enabled
        UserDefaults.standard.set(enabled, forKey: "player.alternativeSources")
        if !enabled {
            pruneUnavailableTracksFromQueue()
        }
        ToastCenter.shared.show(
            enabled ? "已开启歌曲解锁" : "已关闭歌曲解锁，后续不再尝试第三方音源"
        )
    }

    func visibleTracks(_ tracks: [Track]) -> [Track] {
        SongUnlockPolicy.visibleTracks(tracks, isEnabled: enablesAlternativeSources)
    }

    private func isTrackVisible(_ track: Track) -> Bool {
        enablesAlternativeSources || !track.isPlaybackUnavailable
    }

    private func pruneUnavailableTracksFromQueue() {
        let currentID = currentTrack?.id
        let shouldKeep: (Track) -> Bool = { track in
            track.id == currentID || !track.isPlaybackUnavailable
        }
        queue = queue.filter(shouldKeep)
        shuffledQueue = shuffledQueue.filter(shouldKeep)
        fmUpcoming = fmUpcoming.filter { !$0.isPlaybackUnavailable }
        guard source != .personalFM else {
            persistState()
            return
        }
        if let currentID {
            currentIndex = activeQueue.firstIndex(where: { $0.id == currentID }) ?? 0
        } else {
            currentIndex = -1
        }
        persistState()
    }

    func retryLyrics() {
        guard let track = currentTrack, !isLoadingLyrics else { return }
        lyrics = nil
        isLoadingLyrics = true
        lyricsErrorMessage = nil
        lyricsGeneration += 1
        let generation = lyricsGeneration
        Task { await loadLyrics(track, generation: generation) }
    }

    func saveState() {
        scrobbleIfNeeded(completed: false)
        persistState()
    }

    private func start(_ track: Track, at position: TimeInterval = 0) {
        playRequestGeneration += 1
        if source != .personalFM {
            fmGeneration += 1
            fmUpcoming = []
            fmPrefetchTask?.cancel()
            fmPrefetchTask = nil
            isLoadingPersonalFM = false
        }
        scrobbleIfNeeded(completed: false)
        itemStatusObservation = nil
        engine.pause()
        engine.replaceCurrentItem(with: nil)
        currentTrack = track
        progress = min(max(0, position), max(track.duration, 0))
        duration = track.duration
        lyrics = nil
        isLoadingLyrics = true
        lyricsErrorMessage = nil
        servedQuality = nil
        alternativeSource = nil
        isTrial = false
        attemptedAlternativeSources.removeAll()
        didReachEnd = false
        scrobbled = false
        isPlaying = false
        isResolvingURL = true
        isBuffering = true
        resolveGeneration += 1
        let playbackGeneration = resolveGeneration
        lyricsGeneration += 1
        let lyricGeneration = lyricsGeneration
        updateNowPlayingMetadata()
        persistState()

        Task { await resolveAndPlay(track, generation: playbackGeneration, startingAt: progress) }
        Task { await loadLyrics(track, generation: lyricGeneration) }
    }

    private func resolveAndPlay(_ track: Track, generation: Int, startingAt position: TimeInterval) async {
        var result: SongURLData?
        var receivedResponse = false
        var requestError: Error?
        for quality in preferredQuality.fallbackLevels {
            do {
                let candidate = try await NeteaseAPI.songURLs(ids: [track.id], level: quality.rawValue).first
                receivedResponse = true
                result = candidate
                if candidate?.url != nil { break }
            } catch {
                requestError = error
                // Lower qualities use the same endpoint. Retrying every level after
                // a transport/API failure only multiplies the timeout; quality
                // fallback remains active for successful responses with no URL.
                break
            }
        }
        var url = result?.url.flatMap {
            URL(string: $0.replacingOccurrences(of: "http://", with: "https://"))
        }
        guard generation == resolveGeneration else { return }
        var resolvedAlternative: UnblockService.Resolved?
        if enablesAlternativeSources, url == nil || result?.freeTrialInfo != nil {
            resolvedAlternative = await UnblockService.resolve(
                track,
                excludingSources: attemptedAlternativeSources
            )
            if enablesAlternativeSources, let resolvedAlternative {
                attemptedAlternativeSources.insert(resolvedAlternative.source)
                url = resolvedAlternative.url
            } else {
                resolvedAlternative = nil
            }
        }
        guard generation == resolveGeneration else { return }
        guard let url else {
            if !receivedResponse, requestError != nil {
                isPlaying = false
                isResolvingURL = false
                isBuffering = false
                ToastCenter.shared.show("暂时无法连接播放服务，请稍后重试")
                return
            }
            handleUnavailableTrack(track)
            return
        }

        consecutiveFailures = 0
        recordRecent(track)
        persistState()
        alternativeSource = resolvedAlternative?.source
        servedQuality = resolvedAlternative == nil ? result?.level : nil
        isTrial = resolvedAlternative == nil && result?.freeTrialInfo != nil
        if resolvedAlternative != nil {
            duration = track.duration
        } else if let milliseconds = result?.time, milliseconds > 0 {
            duration = TimeInterval(milliseconds) / 1_000
        }

        await beginPlayback(
            url: url,
            track: track,
            generation: generation,
            startingAt: position
        )
    }

    private func beginPlayback(
        url: URL,
        track: Track,
        generation: Int,
        startingAt position: TimeInterval
    ) async {
        guard generation == resolveGeneration,
              currentTrack?.id == track.id else { return }
        let item = AVPlayerItem(url: url)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnded() }
        }
        engine.replaceCurrentItem(with: item)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.handleFailedItem(item, track: track, generation: generation)
            }
        }
        if position > 0 {
            await engine.seek(
                to: CMTime(seconds: min(position, duration), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        engine.play()
        isPlaying = true
        isResolvingURL = false
        isBuffering = engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlayingMetadata()
    }

    private func handleFailedItem(_ item: AVPlayerItem, track: Track, generation: Int) {
        guard generation == resolveGeneration,
              engine.currentItem === item,
              currentTrack?.id == track.id else { return }
        itemStatusObservation = nil
        engine.pause()
        engine.replaceCurrentItem(with: nil)
        resolveGeneration += 1
        let retryGeneration = resolveGeneration
        guard enablesAlternativeSources else {
            handleUnavailableTrack(track)
            return
        }
        isPlaying = false
        isResolvingURL = true
        isBuffering = true
        ToastCenter.shared.show(
            alternativeSource == nil
                ? "原播放地址不可用，正在尝试补全音源…"
                : "当前补全音源不可用，正在尝试其他来源…"
        )
        Task {
            await retryWithAlternativeSource(
                track,
                generation: retryGeneration,
                startingAt: progress
            )
        }
    }

    private func retryWithAlternativeSource(
        _ track: Track,
        generation: Int,
        startingAt position: TimeInterval
    ) async {
        let resolved = await UnblockService.resolve(
            track,
            excludingSources: attemptedAlternativeSources
        )
        guard generation == resolveGeneration,
              currentTrack?.id == track.id else { return }
        guard enablesAlternativeSources else {
            handleUnavailableTrack(track)
            return
        }
        guard let resolved else {
            handleUnavailableTrack(track)
            return
        }
        consecutiveFailures = 0
        attemptedAlternativeSources.insert(resolved.source)
        alternativeSource = resolved.source
        servedQuality = nil
        isTrial = false
        recordRecent(track)
        persistState()
        await beginPlayback(
            url: resolved.url,
            track: track,
            generation: generation,
            startingAt: position
        )
    }

    private func handleUnavailableTrack(_ track: Track) {
        isPlaying = false
        isResolvingURL = false
        isBuffering = false
        consecutiveFailures += 1
        let canTryNext = consecutiveFailures < 5 && (
            source == .personalFM
                || currentIndex + 1 < activeQueue.count
                || (repeatMode == .all && activeQueue.count > 1)
        )
        ToastCenter.shared.show(
            canTryNext
                ? "《\(track.name)》暂时无法播放，正在尝试下一首"
                : "《\(track.name)》暂时无法播放，可能受版权、会员或网络限制"
        )
        if canTryNext { advanceToNext(userInitiated: false) }
    }

    private func loadLyrics(_ track: Track, generation: Int) async {
        do {
            let response = try await NeteaseAPI.lyrics(id: track.id)
            guard generation == lyricsGeneration else { return }
            lyrics = LyricsParser.parse(response)
            isLoadingLyrics = false
            lyricsErrorMessage = nil
        } catch {
            guard generation == lyricsGeneration else { return }
            lyrics = nil
            isLoadingLyrics = false
            lyricsErrorMessage = "歌词暂时无法载入"
        }
    }

    private func handleEnded() {
        scrobbleIfNeeded(completed: true)
        if repeatMode == .one, source != .personalFM {
            scrobbled = false
            seek(to: 0)
            engine.play()
            isPlaying = true
        } else {
            advanceToNext(userInitiated: false)
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            engine.pause()
            isPlaying = false
            updateNowPlayingProgress()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard wasPlayingBeforeInterruption, options.contains(.shouldResume) else { return }
            wasPlayingBeforeInterruption = false
            try? AVAudioSession.sharedInstance().setActive(true)
            engine.play()
            isPlaying = true
            updateNowPlayingProgress()
        @unknown default:
            break
        }
    }

    private func advanceFM(generation: Int, showsError: Bool) async {
        guard generation == fmGeneration, source == .personalFM else { return }
        if fmUpcoming.isEmpty, let fmPrefetchTask {
            await fmPrefetchTask.value
        }
        guard generation == fmGeneration, source == .personalFM else { return }
        if fmUpcoming.isEmpty {
            do {
                let tracks = try await NeteaseAPI.personalFM()
                guard generation == fmGeneration, source == .personalFM else { return }
                var seen = Set<Int>()
                fmUpcoming = tracks.filter { seen.insert($0.id).inserted }
            } catch {
                guard generation == fmGeneration, source == .personalFM else { return }
                isLoadingPersonalFM = false
                isBuffering = false
                if showsError { ToastCenter.shared.show("私人 FM 暂时不可用") }
                return
            }
        }
        guard generation == fmGeneration, source == .personalFM else { return }
        guard !fmUpcoming.isEmpty else {
            isLoadingPersonalFM = false
            isBuffering = false
            if showsError { ToastCenter.shared.show("私人 FM 暂时没有新推荐") }
            return
        }
        let track = fmUpcoming.removeFirst()
        isLoadingPersonalFM = false
        start(track)
        if fmUpcoming.count < 2, fmPrefetchTask == nil {
            fmPrefetchTask = Task { [weak self] in
                defer {
                    if self?.fmGeneration == generation {
                        self?.fmPrefetchTask = nil
                    }
                }
                guard let self,
                      let more = try? await NeteaseAPI.personalFM(),
                      !Task.isCancelled,
                      generation == self.fmGeneration,
                      self.source == .personalFM else { return }
                var existingIDs = Set(fmUpcoming.map(\.id))
                if let currentID = currentTrack?.id { existingIDs.insert(currentID) }
                fmUpcoming.append(contentsOf: more.filter { existingIDs.insert($0.id).inserted })
            }
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingMetadata() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let url = track.artworkURL else { return }
        Task.detached {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard self.currentTrack?.id == track.id else { return }
                var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                currentInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
            }
        }
    }

    private func updateNowPlayingProgress() {
        guard currentTrack != nil else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private struct PersistedState: Codable {
        let queue: [Track]
        let shuffledQueue: [Track]?
        let recentTracks: [Track]?
        let currentID: Int?
        let source: PlaySource
        let repeatMode: RepeatMode
        let shuffle: Bool
        let progress: TimeInterval?
        let reachedEnd: Bool?
    }

    private func persistState() {
        let persistedQueue: [Track]
        if source == .personalFM {
            persistedQueue = currentTrack.map { [$0] } ?? []
        } else {
            persistedQueue = queue
        }
        let state = PersistedState(
            queue: Array(persistedQueue.prefix(1_000)),
            shuffledQueue: shuffleEnabled ? Array(shuffledQueue.prefix(1_000)) : nil,
            recentTracks: Array(recentTracks.prefix(40)),
            currentID: currentTrack?.id,
            source: source,
            repeatMode: repeatMode,
            shuffle: shuffleEnabled,
            progress: progress,
            reachedEnd: didReachEnd
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.stateFileURL, options: .atomic)
    }

    private func restoreState() {
        guard let data = try? Data(contentsOf: Self.stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        recentTracks = Array(PlaybackQueuePolicy.deduplicated(state.recentTracks ?? []).prefix(40))
        guard !state.queue.isEmpty else { return }
        queue = PlaybackQueuePolicy.deduplicated(visibleTracks(state.queue))
        guard !queue.isEmpty else { return }
        source = state.source
        repeatMode = state.repeatMode
        shuffleEnabled = state.shuffle
        if shuffleEnabled {
            let restoredShuffle = state.shuffledQueue ?? []
            shuffledQueue = restoredShuffle.count == queue.count
                && Set(restoredShuffle.map(\.id)) == Set(queue.map(\.id))
                ? restoredShuffle
                : queue.shuffled()
        }
        guard let currentID = state.currentID,
              let index = activeQueue.firstIndex(where: { $0.id == currentID }) else { return }
        currentIndex = index
        currentTrack = activeQueue[index]
        duration = activeQueue[index].duration
        progress = min(max(0, state.progress ?? 0), duration)
        didReachEnd = state.reachedEnd ?? false
        isLoadingLyrics = true
        lyricsErrorMessage = nil
        updateNowPlayingMetadata()
        Task { await loadLyrics(activeQueue[index], generation: lyricsGeneration) }
    }

    private func recordRecent(_ track: Track) {
        recentTracks.removeAll { $0.id == track.id }
        recentTracks.insert(track, at: 0)
        if recentTracks.count > 40 {
            recentTracks.removeLast(recentTracks.count - 40)
        }
    }

    private func scrobbleIfNeeded(completed: Bool) {
        guard let track = currentTrack, !scrobbled, progress > 1 else { return }
        scrobbled = true
        let seconds = completed ? Int(duration) : Int(progress)
        let sourceID = source.sourceID
        Task.detached {
            await NeteaseAPI.scrobble(trackID: track.id, sourceID: sourceID, seconds: seconds)
        }
    }

    private static var stateFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetEaseTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("player-state.json")
    }
}
