import Testing
@testable import NetEaseTVCore

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
