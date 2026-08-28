import Testing
@testable import SonimbusCore

private enum TestRoute: Hashable {
    case playlist(Int)
    case artist(Int)
}

@Test func ordinaryTabDepartureDiscardsItsNavigationAndFocusContext() {
    var state = RootTabPresentationState<TestRoute>()
    state.path = [.playlist(42)]
    state.requestNavigationFocusRestoration(.playlist(42))
    state.requestTrackFocusRestoration(7)

    let previousRootGeneration = state.rootActivationGeneration
    let previousNavigationGeneration = state.navigationFocusRestorationGeneration
    let previousTrackGeneration = state.trackFocusRestorationGeneration
    state.resetToRoot()

    #expect(state.path.isEmpty)
    #expect(state.rootActivationGeneration == previousRootGeneration + 1)
    #expect(state.navigationFocusRestorationGeneration == previousNavigationGeneration + 1)
    #expect(state.navigationFocusRestorationRoute == nil)
    #expect(state.trackFocusRestorationGeneration == previousTrackGeneration + 1)
    #expect(state.trackFocusRestorationID == nil)
}

@Test func contextualNowPlayingReturnPreservesTheDetailNavigationPath() {
    var state = RootTabPresentationState<TestRoute>()
    state.path = [.playlist(42), .artist(9)]

    state.requestTrackFocusRestoration(7)

    #expect(state.path == [.playlist(42), .artist(9)])
    #expect(state.trackFocusRestorationID == AnyHashable(7))
    #expect(state.navigationFocusRestorationRoute == nil)
}

@Test func navigationAndTrackRestorationRequestsCannotRemainActiveTogether() {
    var state = RootTabPresentationState<TestRoute>()

    state.requestTrackFocusRestoration(7)
    state.requestNavigationFocusRestoration(.playlist(42))
    #expect(state.navigationFocusRestorationRoute == .playlist(42))
    #expect(state.trackFocusRestorationID == nil)

    state.requestTrackFocusRestoration(9)
    #expect(state.navigationFocusRestorationRoute == nil)
    #expect(state.trackFocusRestorationID == AnyHashable(9))

    state.requestTrackFocusRestoration(nil)
    #expect(state.trackFocusRestorationID == nil)
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
