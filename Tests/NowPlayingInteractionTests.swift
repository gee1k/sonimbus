import Testing
@testable import SonimbusCore

private enum TestTab: Hashable {
    case listenNow
    case browse
}

private enum TestRoute: Hashable {
    case daily
    case album(Int)
}

@Test func rootTabResetClearsOnlyItsOwnPathAndAdvancesGeneration() {
    var state = RootTabPresentationState<TestRoute>()
    state.path = [.daily, .album(7)]

    state.resetToRoot()

    #expect(state.path.isEmpty)
    #expect(state.rootActivationGeneration == 1)
}

@Test func navigationReturnContextRequiresTheSameTabAndExactParentPath() {
    let source = PlaybackOriginFocus.track(.homeRecent, trackID: 42, occurrence: 0)
    let context = NavigationReturnContext(
        tab: TestTab.listenNow,
        parentPath: [TestRoute.daily],
        focus: source
    )

    #expect(context.matches(tab: .listenNow, parentPath: [.daily]))
    #expect(!context.matches(tab: .browse, parentPath: [.daily]))
    #expect(!context.matches(tab: .listenNow, parentPath: [.album(7)]))
    #expect(context.shouldDiscard(when: .listenNow, popsToDepth: 1))
    #expect(!context.shouldDiscard(when: .browse, popsToDepth: 0))
}

@Test func contextualAndTabBarPresentationsRemainDistinct() {
    var presentation = NowPlayingPresentationState()

    presentation.present(from: .contextual)
    #expect(presentation.isPresented)
    #expect(presentation.dismiss() == .contextual)
    #expect(!presentation.isPresented)

    presentation.present(from: .tabBar)
    #expect(presentation.dismiss() == .tabBar)
}

@Test func tabBarDismissalAllowsAnImmediateDeliberateReentry() {
    var presentation = NowPlayingPresentationState()

    let initialPresentation = presentation.present(from: .tabBar)
    #expect(initialPresentation)
    #expect(presentation.dismiss() == .tabBar)
    let deliberateTabRequest = presentation.present(from: .tabBar)
    #expect(deliberateTabRequest)
}

@Test func playbackOriginUsesStableOccurrenceInsteadOfMutableListPosition() {
    let original = PlaybackOriginFocus.track(.homeRecent, trackID: 42, occurrence: 0)
    let sameTrackAfterReordering = PlaybackOriginFocus.track(
        .homeRecent,
        trackID: 42,
        occurrence: 0
    )
    let duplicateOccurrence = PlaybackOriginFocus.track(.homeRecent, trackID: 42, occurrence: 1)
    let otherShelf = PlaybackOriginFocus.track(.homeNewSongs, trackID: 42, occurrence: 0)

    #expect(original == sameTrackAfterReordering)
    #expect(original != duplicateOccurrence)
    #expect(original != otherShelf)
}

@Test func repeatedActivationDoesNotReplaceTheOriginalPresentationSource() {
    var presentation = NowPlayingPresentationState()

    presentation.present(from: .contextual)
    presentation.present(from: .tabBar)
    #expect(presentation.source == .contextual)
}

@Test func queueBackRestoresThePreviousPanelBeforeLeavingNowPlaying() {
    var state = NowPlayingInteractionState()

    state.toggleQueue()
    #expect(state.panel == .queue)
    #expect(state.handleBack() == .handled)
    #expect(state.panel == .lyrics)
    #expect(state.showsControls)
}

@Test func closingQueueDoesNotDiscardAnExplicitlyHiddenLyricsPanel() {
    var state = NowPlayingInteractionState()

    state.toggleLyrics()
    #expect(state.panel == .artwork)
    state.toggleQueue()
    state.toggleQueue()

    #expect(state.panel == .artwork)
}

@Test func backHidesControlsBeforeDeferringToTheTabHierarchy() {
    var state = NowPlayingInteractionState()

    #expect(state.handleBack() == .handled)
    #expect(state.chromeMode == .lyricsNavigation)
    #expect(state.handleBack() == .deferToSystem)
}

@Test func lyricNavigationConsumesBackOnlyWhileASelectionIsActive() {
    var state = NowPlayingInteractionState()

    _ = state.handleBack()
    state.moveLyricSelection(direction: 1, activeIndex: 4, lineCount: 12)
    #expect(state.selectedLyricIndex == 5)
    #expect(state.handleBack() == .handled)
    #expect(state.selectedLyricIndex == nil)
    #expect(state.handleBack() == .deferToSystem)
}

@Test func idleChromeNeverTakesFocusAwayFromTheQueue() {
    var state = NowPlayingInteractionState()

    state.toggleQueue()
    state.hideControlsForIdle()

    #expect(state.panel == .queue)
    #expect(state.showsControls)
}

@Test func activatingNowPlayingClosesTheTransientQueuePanel() {
    var state = NowPlayingInteractionState()

    state.toggleLyrics()
    state.toggleQueue()
    state.activate()

    #expect(state.panel == .artwork)
    #expect(state.showsControls)
}

@Test func backUsesAmbientModeWhenTheCurrentSongHasNoNavigableLyrics() {
    var state = NowPlayingInteractionState()

    #expect(state.handleBack(allowsLyricsNavigation: false) == .handled)
    #expect(state.chromeMode == .ambient)
    #expect(state.handleBack(allowsLyricsNavigation: false) == .deferToSystem)
}

@Test func emptyPlayerBackImmediatelyReturnsToThePresentingTab() {
    var state = NowPlayingInteractionState()

    #expect(state.handleBack(hasCurrentTrack: false) == .deferToSystem)
    #expect(state.chromeMode == .controls)
}
