import XCTest

final class NavigationRegressionUITests: XCTestCase {
    private let homeTrackIDs = [
        3_417_910_003,
        3_420_799_859,
        3_424_349_862,
        1_974_443_812,
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        guard testRun?.failureCount ?? 0 > 0 else { return }
        let app = XCUIApplication()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "player-interaction-failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "player-interaction-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testRecentShelfReorderKeepsUniqueCardsAndRestoresExactSource() throws {
        let app = launchFixture()
        let sourceID = homeCardID(surface: "home-recent", trackID: homeTrackIDs[3])
        let source = app.buttons[sourceID].firstMatch

        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(source, in: app, timeout: 8))
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        dismissNowPlaying(in: app)

        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(source, timeout: 5))

        let visibleCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'track-card-home-recent-'")
        ).allElementsBoundByIndex.filter(\.exists)
        let labels = visibleCards.map(\.label)
        XCTAssertGreaterThanOrEqual(labels.count, 4)
        XCTAssertEqual(Set(labels).count, labels.count, "最近播放重排后出现了重复卡片")

        for trackID in homeTrackIDs {
            XCTAssertTrue(
                app.buttons[homeCardID(surface: "home-recent", trackID: trackID)]
                    .firstMatch.exists
            )
        }
    }

    func testSameTrackOnTwoHomeShelvesReturnsToTheRecentShelf() throws {
        let app = launchFixture(duplicatesAcrossShelves: true)
        let trackID = homeTrackIDs[0]
        let recent = app.buttons[homeCardID(surface: "home-recent", trackID: trackID)].firstMatch
        let recommendations = app.buttons[
            homeCardID(surface: "home-new-songs", trackID: trackID)
        ].firstMatch

        XCTAssertTrue(recent.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(recent, in: app, timeout: 8))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(recommendations.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(recommendations, timeout: 5))
        XCTAssertEqual(recent.label, recommendations.label)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(waitForFocus(recent, timeout: 5))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        dismissNowPlaying(in: app)

        XCTAssertTrue(waitForFocus(recent, timeout: 5))
        XCTAssertFalse(recommendations.hasFocus)
    }

    func testNewSongsReturnRestoresExactCardAfterRecentShelfReorder() throws {
        let app = launchFixture(duplicatesAcrossShelves: true)
        let trackID = homeTrackIDs[2]
        let recent = app.buttons[homeCardID(surface: "home-recent", trackID: trackID)]
            .firstMatch
        let recommendation = app.buttons[
            homeCardID(surface: "home-new-songs", trackID: trackID)
        ].firstMatch

        XCTAssertTrue(recent.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(recent, in: app, timeout: 8))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(recommendation, timeout: 5))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        dismissNowPlaying(in: app)

        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(recommendation, timeout: 5))
    }

    func testAlbumOpenedFromNowPlayingUnwindsToNowPlayingThenOriginalHomeCard() throws {
        let app = launchFixture()
        let homeTrackID = homeTrackIDs[2]
        let sourceID = homeCardID(surface: "home-recent", trackID: homeTrackID)
        let source = app.buttons[sourceID].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(source, in: app, timeout: 8))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))

        let info = app.buttons["查看歌曲信息"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 4))
        // The more-actions Menu between transport and info hides its focus from XCUI.
        XCTAssertTrue(pressUntilFocused(info, direction: .left, attempts: 10))
        XCUIRemote.shared.press(.select)

        let albumAction = app.buttons["前往专辑"].firstMatch
        XCTAssertTrue(albumAction.waitForExistence(timeout: 4))
        XCTAssertTrue(waitForFocus(albumAction, timeout: 4))
        XCUIRemote.shared.press(.select)

        let albumPage = app.descendants(matching: .any)["album-detail-22002"].firstMatch
        XCTAssertTrue(albumPage.waitForExistence(timeout: 5))
        XCTAssertFalse(nowPlayingPage(in: app).exists)
        XCTAssertFalse(app.buttons["现在就听"].firstMatch.exists)
        let playAction = app.buttons["播放"].firstMatch
        XCTAssertTrue(playAction.waitForExistence(timeout: 4))
        XCTAssertTrue(
            waitForFocus(playAction, timeout: 4),
            "集合详情页进入后应默认聚焦播放操作"
        )

        let albumTrack = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'track-row-collection-album-22002-'"
            )
        ).firstMatch
        XCTAssertTrue(albumTrack.waitForExistence(timeout: 5))
        XCTAssertTrue(focus(albumTrack, in: app, timeout: 8))
        let albumTrackID = albumTrack.identifier

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        dismissNowPlaying(in: app)

        XCTAssertTrue(albumPage.waitForExistence(timeout: 5))
        let restoredAlbumTrack = app.buttons[albumTrackID].firstMatch
        XCTAssertTrue(restoredAlbumTrack.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(restoredAlbumTrack, timeout: 5))
        XCTAssertFalse(source.exists)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            nowPlayingPage(in: app).waitForExistence(timeout: 5),
            "从播放页进入的专辑返回时应回到播放页"
        )
        dismissNowPlaying(in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(source, timeout: 5))
        XCTAssertFalse(albumPage.exists)
    }

    func testBackClosesQueueThenControlsThenNowPlaying() throws {
        let app = launchFixture()
        let source = app.buttons[
            homeCardID(surface: "home-recent", trackID: homeTrackIDs[1])
        ].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(source, in: app, timeout: 8))
        XCUIRemote.shared.press(.select)

        let page = nowPlayingPage(in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let queue = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '播放队列'")
        ).firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 4))
        XCTAssertTrue(focus(queue, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)

        let queuePanel = app.descendants(matching: .any)["now-playing-queue-panel"]
            .firstMatch
        XCTAssertTrue(queuePanel.waitForExistence(timeout: 4))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(page.exists, "第一次返回只能关闭播放队列")
        XCTAssertTrue(queuePanel.waitForNonExistence(timeout: 4))

        let info = app.buttons["查看歌曲信息"].firstMatch
        XCTAssertTrue(info.exists && info.isEnabled)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(page.exists, "第二次返回只能隐藏控制层")
        XCTAssertTrue(waitUntil(timeout: 4) { !info.isEnabled })

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(page.waitForNonExistence(timeout: 5), "第三次返回才允许关闭播放页")
        XCTAssertTrue(waitForFocus(source, timeout: 5))
    }

    func testTabBarNowPlayingCanDismissAndImmediatelyReenter() throws {
        let app = launchFixture()
        let libraryTab = app.buttons["资料库"].firstMatch
        let nowPlayingTab = app.buttons["正在播放"].firstMatch
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 8))
        XCTAssertTrue(nowPlayingTab.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(libraryTab, in: app, timeout: 6))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))

        dismissNowPlaying(in: app)
        XCTAssertTrue(nowPlayingPage(in: app).waitForNonExistence(timeout: 3))
        sleep(2)
        XCTAssertFalse(nowPlayingPage(in: app).exists, "关闭后不应被 Tab 选择状态立即重开")
        XCTAssertTrue(waitForFocus(libraryTab, timeout: 4))

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
    }

    func testOrdinaryTabSwitchResetsHomeScrollAndFocusToRoot() throws {
        let app = launchFixture()
        let source = app.buttons[
            homeCardID(surface: "home-recent", trackID: homeTrackIDs[2])
        ].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(source, in: app, timeout: 8))

        XCUIRemote.shared.press(.menu)
        let listenNow = app.buttons["现在就听"].firstMatch
        XCTAssertTrue(waitForFocus(listenNow, timeout: 4))

        let browse = app.buttons["浏览"].firstMatch
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(browse, timeout: 4))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(listenNow, timeout: 4))
        XCTAssertFalse(source.hasFocus, "普通 Tab 切换不应恢复到离开前的歌曲卡片")

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitUntil(timeout: 4) {
            let focused = focusedButton(in: app)
            return focused.exists && !focused.identifier.hasPrefix("track-card-")
        })
    }

    func testSearchRecentQueriesUseNativeHorizontalFocus() throws {
        let app = launchFixture(searchFixture: true)
        let search = app.buttons["搜索"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(search, in: app, timeout: 6))

        let suggestion = app.buttons["试试搜索：周杰伦"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(
            pressUntilFocused(suggestion, direction: .down, attempts: 10),
            "搜索页应能沿原生向下焦点路径到达搜索建议"
        )
        XCUIRemote.shared.press(.down)

        let firstRecent = app.buttons["林俊杰"].firstMatch
        let secondRecent = app.buttons["五月天"].firstMatch
        let clearRecent = app.buttons["清除"].firstMatch
        XCTAssertTrue(firstRecent.waitForExistence(timeout: 4))
        XCTAssertTrue(
            waitForFocus(firstRecent, timeout: 2)
                || waitForFocus(secondRecent, timeout: 2)
                || waitForFocus(clearRecent, timeout: 2)
        )
        if clearRecent.hasFocus {
            XCUIRemote.shared.press(.left)
        }
        XCTAssertTrue(firstRecent.hasFocus || secondRecent.hasFocus)
        if firstRecent.hasFocus {
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(waitForFocus(secondRecent, timeout: 4))
        } else {
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(waitForFocus(firstRecent, timeout: 4))
        }
    }

    func testBrowseMVReturnRestoresCardButOrdinaryTabSwitchDoesNot() throws {
        let app = launchFixture()
        let browse = app.buttons["浏览"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 8))
        XCTAssertTrue(focus(browse, in: app, timeout: 6))
        XCTAssertTrue(focusFirstButton(withPrefix: "mv-card-", in: app, timeout: 25))

        let source = focusedButton(in: app)
        let sourceID = source.identifier
        XCTAssertTrue(sourceID.hasPrefix("mv-card-"))
        XCUIRemote.shared.press(.select)

        let detail = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'mv-detail-'")
        ).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 12))
        XCTAssertFalse(browse.exists)
        let videoStage = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'mv-video-stage-'")
        ).firstMatch
        XCTAssertTrue(videoStage.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForFocus(videoStage, timeout: 5),
            "MV 详情页进入后应默认聚焦视频舞台"
        )

        XCUIRemote.shared.press(.menu)
        let restoredSource = app.buttons[sourceID].firstMatch
        XCTAssertTrue(restoredSource.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(restoredSource, timeout: 5))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(browse, timeout: 5))
        let search = app.buttons["搜索"].firstMatch
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(search, timeout: 5))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(browse, timeout: 5))
        XCTAssertEqual(focusedButton(in: app).label, browse.label)
    }

    func testLargePlaylistRespondsAndRestoresScrolledRow() {
        let app = XCUIApplication()
        app.launchEnvironment["SONIMBUS_UI_PLAYBACK_FIXTURE"] = "1"
        app.launchEnvironment["SONIMBUS_UI_LARGE_PLAYLIST"] = "1"
        app.launch()
        let first = app.buttons["track-row-collection-playlist-9000000-9000001-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let play = app.buttons["播放"].firstMatch
        XCTAssertTrue(focus(play, in: app, timeout: 5))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(first, timeout: 3), "进入 3000 首歌的列表不应阻塞主线程")
        for _ in 0..<35 { XCUIRemote.shared.press(.down) }
        let row = app.buttons["track-row-collection-playlist-9000000-9000036-0"].firstMatch
        XCTAssertTrue(waitForFocus(row, timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        dismissNowPlaying(in: app)
        XCTAssertTrue(waitForFocus(row, timeout: 5), "返回时应恢复选中的歌曲")
        XCUIRemote.shared.press(.down)
        let next = app.buttons["track-row-collection-playlist-9000000-9000037-0"].firstMatch
        XCTAssertTrue(waitForFocus(next, timeout: 3))
        // The last page must remain reachable without creating thousands of focus regions.
        for _ in 0..<37 { XCUIRemote.shared.press(.up) }
        XCTAssertTrue(focus(play, in: app, timeout: 5))
        // SwiftUI Menu's outer accessibility button does not expose the native
        // menu control's focus. Verify the menu opens using the remote instead.
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["第 1 页 · 1–500 首"].firstMatch.waitForExistence(timeout: 3))
        for _ in 0..<5 { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.select)
        let lastPageFirst = app.buttons["track-row-collection-playlist-9000000-9002501-0"].firstMatch
        XCTAssertTrue(lastPageFirst.waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
    }

    func testLargePlaybackQueueMovesContinuouslyAndKeepsSelectedTrackFocused() {
        let app = XCUIApplication()
        app.launchEnvironment["SONIMBUS_UI_PLAYBACK_FIXTURE"] = "1"
        app.launchEnvironment["SONIMBUS_UI_LARGE_PLAYLIST"] = "1"
        app.launch()
        let play = app.buttons["播放"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(play, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        let queue = app.buttons["显示播放队列"].firstMatch
        XCTAssertTrue(focus(queue, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)
        let first = app.descendants(matching: .any)["queue-track-9000001"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(first, timeout: 3))
        for _ in 0..<30 { XCUIRemote.shared.press(.right) }
        let selected = app.descendants(matching: .any)["queue-track-9000031"].firstMatch
        XCTAssertTrue(waitForFocus(selected, timeout: 3), "3000 首队列连续移动不应阻塞焦点")
        let queueScreenshot = XCTAttachment(screenshot: app.screenshot())
        queueScreenshot.name = "large-playback-queue"
        queueScreenshot.lifetime = .keepAlways
        add(queueScreenshot)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(selected, timeout: 3), "播放选中歌曲后焦点应停在该卡片")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(app.descendants(matching: .any)["queue-track-9000032"].firstMatch, timeout: 3))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(selected, timeout: 3))
        XCUIRemote.shared.press(.menu)
        // Inspect the restored focus immediately, before the six-second idle
        // timer hides controls while XCTest snapshots the large source list.
        XCTAssertTrue(waitForFocus(queue, timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(selected, timeout: 3), "重新进入队列应直接到达正在播放的歌曲")
    }

    func testIntelligenceTogglesWithoutChangingTrackOrLosingFocus() {
        let app = launchFixture(playerActions: true)
        let source = app.buttons[homeCardID(surface: "home-recent", trackID: homeTrackIDs[1])].firstMatch
        XCTAssertTrue(focus(source, in: app, timeout: 8))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        let title = app.staticTexts["now-playing-track-title"].firstMatch
        let originalTitle = title.label
        let start = app.buttons["从这首开启心动模式"].firstMatch
        XCTAssertTrue(focus(start, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)
        let stop = app.buttons["退出心动模式"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 4))
        XCTAssertTrue(waitForFocus(stop, timeout: 2))
        XCTAssertEqual(title.label, originalTitle)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(start.waitForExistence(timeout: 2), "退出不应等待网络加载整个歌单")
        XCTAssertTrue(waitForFocus(start, timeout: 2))
        XCTAssertEqual(title.label, originalTitle)
        let next = app.buttons["下一首"].firstMatch
        XCTAssertTrue(focus(next, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil(timeout: 3) { title.label == "颜如玉 2.0" }, "退出后应恢复进入前的播放顺序")
        XCTAssertTrue(waitForFocus(next, timeout: 2))
    }

    func testAddToPlaylistOpensWithRightAndReturnsWithLeft() {
        let app = launchFixture(playerActions: true)
        let source = app.buttons[homeCardID(surface: "home-recent", trackID: homeTrackIDs[0])].firstMatch
        XCTAssertTrue(focus(source, in: app, timeout: 8))
        XCUIRemote.shared.press(.select)
        let more = app.buttons["更多操作"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(focus(more, in: app, timeout: 6))
        XCUIRemote.shared.press(.select)
        let add = app.buttons["player-menu-add-playlist"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        XCTAssertTrue(focus(add, in: app, timeout: 5))
        XCUIRemote.shared.press(.right)
        let playlist = app.buttons["player-menu-playlist-71002"].firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(playlist, timeout: 3))
        let menuScreenshot = XCTAttachment(screenshot: app.screenshot())
        menuScreenshot.name = "add-to-playlist-menu"
        menuScreenshot.lifetime = .keepAlways
        self.add(menuScreenshot)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(add, timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(playlist, timeout: 3), "确认键也应能打开子菜单")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(add, timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(more, timeout: 3))
    }

    func testImmersiveLongPressSkipsOnceWithoutShowingControls() {
        let app = launchFixture()
        let source = app.buttons[homeCardID(surface: "home-recent", trackID: homeTrackIDs[1])].firstMatch
        XCTAssertTrue(focus(source, in: app, timeout: 8))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 5))
        let title = app.staticTexts["now-playing-track-title"].firstMatch
        let originalTitle = title.label
        XCUIRemote.shared.press(.menu)
        let immersive = app.descendants(matching: .any)["immersive-playback-control"].firstMatch
        XCTAssertTrue(immersive.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(immersive, timeout: 3))
        XCUIRemote.shared.press(.right, forDuration: 0.9)
        XCTAssertTrue(waitUntil(timeout: 3) { title.label == "颜如玉 2.0" })
        XCTAssertTrue(waitForFocus(immersive, timeout: 2))
        XCTAssertFalse(app.buttons["查看歌曲信息"].firstMatch.isEnabled)
        XCUIRemote.shared.press(.left, forDuration: 0.9)
        XCTAssertTrue(waitUntil(timeout: 3) { title.label == originalTitle })
        XCTAssertTrue(waitForFocus(immersive, timeout: 2))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(app.buttons["暂停"].firstMatch, timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForFocus(app.buttons["播放"].firstMatch, timeout: 3), "唤回控制栏后的第一次确认应直接暂停")
    }

    private func launchFixture(
        duplicatesAcrossShelves: Bool = false,
        searchFixture: Bool = false,
        playerActions: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SONIMBUS_UI_PLAYBACK_FIXTURE"] = "1"
        if playerActions { app.launchEnvironment["SONIMBUS_UI_PLAYER_ACTIONS"] = "1" }
        if duplicatesAcrossShelves {
            app.launchEnvironment["SONIMBUS_UI_DUPLICATE_TRACK"] = "1"
        }
        if searchFixture {
            app.launchEnvironment["SONIMBUS_UI_SEARCH_FIXTURE"] = "1"
        }
        app.launch()
        addTeardownBlock { [weak self, weak app] in
            guard let self, let app, self.testRun?.failureCount ?? 0 > 0 else { return }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(self.name)-failure"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        let listenNow = app.buttons["现在就听"].firstMatch
        XCTAssertTrue(listenNow.waitForExistence(timeout: 8))
        if !listenNow.hasFocus {
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(
                waitForFocus(listenNow, timeout: 4),
                "每条遥控器路径开始前都应先回到当前根 Tab"
            )
        }
        let browse = app.buttons["浏览"].firstMatch
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(browse, timeout: 4))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(
            waitForFocus(listenNow, timeout: 4),
            "普通 Tab 往返后应从现在就听根焦点重新开始"
        )
        return app
    }

    private func homeCardID(surface: String, trackID: Int) -> String {
        "track-card-\(surface)-\(trackID)-0"
    }

    private func nowPlayingPage(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["now-playing-page"].firstMatch
    }

    private func focusFirstButton(
        withPrefix prefix: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let focused = focusedButton(in: app)
            if focused.identifier.hasPrefix(prefix) { return true }
            XCUIRemote.shared.press(.down)
            usleep(350_000)
        }
        return focusedButton(in: app).identifier.hasPrefix(prefix)
    }

    private func focusedButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func dismissNowPlaying(in app: XCUIApplication) {
        let page = nowPlayingPage(in: app)
        for _ in 0..<4 where page.exists {
            XCUIRemote.shared.press(.menu)
            if page.waitForNonExistence(timeout: 1.5) { return }
        }
        XCTAssertFalse(page.exists, "播放页未按返回层级关闭")
    }

    private func focus(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.hasFocus { return true }

            let current = app.buttons.matching(NSPredicate(format: "hasFocus == true"))
                .firstMatch
            guard element.exists else {
                usleep(100_000)
                continue
            }
            guard current.exists else {
                XCUIRemote.shared.press(.down)
                usleep(300_000)
                continue
            }

            let currentFrame = current.frame
            let targetFrame = element.frame
            guard !currentFrame.isEmpty, !targetFrame.isEmpty else {
                XCUIRemote.shared.press(.down)
                usleep(200_000)
                continue
            }

            let horizontal = targetFrame.midX - currentFrame.midX
            let vertical = targetFrame.midY - currentFrame.midY
            if abs(vertical) > 40 {
                XCUIRemote.shared.press(vertical > 0 ? .down : .up)
            } else if abs(horizontal) > 20 {
                XCUIRemote.shared.press(horizontal > 0 ? .right : .left)
            } else {
                XCUIRemote.shared.press(.down)
            }
            usleep(250_000)
        }
        return element.exists && element.hasFocus
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func pressUntilFocused(
        _ element: XCUIElement,
        direction: XCUIRemote.Button,
        attempts: Int
    ) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.hasFocus { return true }
            XCUIRemote.shared.press(direction)
            usleep(300_000)
        }
        return element.exists && element.hasFocus
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }
}
