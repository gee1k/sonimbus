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

    func testAlbumOpenedFromNowPlayingUnwindsToAlbumThenOriginalHomeCard() throws {
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
        XCTAssertTrue(focus(info, in: app, timeout: 5))
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

    func testLivePlaybackAdvancesPausesAndReturnsToHome() throws {
        guard ProcessInfo.processInfo.environment["SONIMBUS_LIVE_UI"] == "1" else {
            throw XCTSkip("Enable SONIMBUS_LIVE_UI for network playback acceptance")
        }
        let app = XCUIApplication()
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track-card-home-new-songs-'")).firstMatch
        XCTAssertTrue(app.buttons["现在就听"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(focusFirstButton(withPrefix: "track-card-home-new-songs-", in: app, timeout: 35))
        XCTAssertTrue(card.exists)
        XCTAssertTrue(focus(card, in: app, timeout: 15))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 10))
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label == '播放进度' AND value CONTAINS '/' ")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30))
        let advances = NSPredicate { _, _ in
            guard let value = progress.value as? String,
                  let elapsed = value.components(separatedBy: " / ").first else { return false }
            return elapsed != "0:00" && elapsed != "00:00"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advances, object: nil)], timeout: 40), .completed)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["播放"].firstMatch.waitForExistence(timeout: 5))
        let paused = progress.value as? String
        let changesWhilePaused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (progress.value as? String) != paused }, object: nil
        )
        changesWhilePaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changesWhilePaused], timeout: 3), .completed)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 5))
        let resumed = NSPredicate { _, _ in (progress.value as? String) != paused }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: nil)], timeout: 10), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "live-playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dismissNowPlaying(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(card, timeout: 5))
    }

    func testAuthenticatedRecentPlaysLikesAndPersonalFM() throws {
        guard ProcessInfo.processInfo.environment["SONIMBUS_AUTH_UI"] == "1" else {
            throw XCTSkip("Requires an explicitly signed-in simulator account")
        }
        let app = XCUIApplication()
        app.launch()
        let library = app.buttons["资料库"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        XCTAssertTrue(focus(library, in: app, timeout: 10))
        let likedLibrary = app.buttons.matching(NSPredicate(format: "label CONTAINS '我喜欢的音乐'")).firstMatch
        XCTAssertTrue(likedLibrary.waitForExistence(timeout: 30), "Signed-in library must finish loading")
        let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS '最近播放'")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(recent, in: app, timeout: 12))
        XCUIRemote.shared.press(.select)
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track-row-recent-history-'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 25), "Account recent-song endpoint must return tracks")
        let rowID = firstRow.identifier
        let recentShot = XCTAttachment(screenshot: app.screenshot())
        recentShot.name = "authenticated-recent-plays"
        recentShot.lifetime = .keepAlways
        add(recentShot)
        XCTAssertTrue(focus(firstRow, in: app, timeout: 12))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 10))
        let originalLiked = app.buttons["取消喜欢"].firstMatch.exists
        let initialLabel = originalLiked ? "取消喜欢" : "喜欢"
        let oppositeLabel = originalLiked ? "喜欢" : "取消喜欢"
        var needsRestore = false
        addTeardownBlock {
            guard needsRestore, app.state == .runningForeground else { return }
            let restore = app.buttons[oppositeLabel].firstMatch
            if restore.exists, self.focus(restore, in: app, timeout: 8) {
                XCUIRemote.shared.press(.select)
                XCTAssertTrue(app.buttons[initialLabel].firstMatch.waitForExistence(timeout: 10), "Restore original like state")
            }
        }
        let favorite = app.buttons[initialLabel].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(favorite, in: app, timeout: 10))
        needsRestore = true
        XCUIRemote.shared.press(.select)
        let changedMessage = originalLiked ? "已取消喜欢" : "已添加到喜欢的音乐"
        XCTAssertTrue(app.staticTexts[changedMessage].firstMatch.waitForExistence(timeout: 15), "Like write must be acknowledged by server")
        func reloadAccountAndOpenCurrentTrack() {
            app.terminate()
            app.launch()
            XCTAssertTrue(library.waitForExistence(timeout: 15))
            XCTAssertTrue(focus(library, in: app, timeout: 10))
            XCTAssertTrue(likedLibrary.waitForExistence(timeout: 30))
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 10))
        }
        reloadAccountAndOpenCurrentTrack()
        let restore = app.buttons[oppositeLabel].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "Server like state must survive account reload")
        XCTAssertTrue(focus(restore, in: app, timeout: 10))
        XCUIRemote.shared.press(.select)
        let restoredMessage = originalLiked ? "已添加到喜欢的音乐" : "已取消喜欢"
        XCTAssertTrue(app.staticTexts[restoredMessage].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons[initialLabel].firstMatch.exists)
        needsRestore = false
        reloadAccountAndOpenCurrentTrack()
        XCTAssertTrue(app.buttons[initialLabel].firstMatch.waitForExistence(timeout: 10), "Restored server state must survive account reload")
        dismissNowPlaying(in: app)
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(recent, in: app, timeout: 12))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons[rowID].firstMatch.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        let home = app.buttons["现在就听"].firstMatch
        XCTAssertTrue(focus(home, in: app, timeout: 12))
        let fm = app.buttons["home-personal-fm"].firstMatch
        XCTAssertTrue(fm.waitForExistence(timeout: 10))
        XCTAssertTrue(focus(fm, in: app, timeout: 10))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 10))
        let fmDislike = app.buttons["减少类似推荐并播放下一首"].firstMatch
        XCTAssertTrue(fmDislike.waitForExistence(timeout: 30), "Personal FM must return a playable track")
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label == '播放进度' AND value CONTAINS '/' ")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        let advances = NSPredicate { _, _ in
            guard let value = progress.value as? String,
                  let elapsed = value.components(separatedBy: " / ").first else { return false }
            return elapsed != "0:00" && elapsed != "00:00"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advances, object: nil)], timeout: 30), .completed)
        let fmShot = XCTAttachment(screenshot: app.screenshot())
        fmShot.name = "authenticated-personal-fm"
        fmShot.lifetime = .keepAlways
        add(fmShot)
        let next = app.buttons["下一首"].firstMatch
        XCTAssertTrue(focus(next, in: app, timeout: 10))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(fmDislike.waitForExistence(timeout: 20))
        XCUIRemote.shared.press(.playPause)
    }

    func testAuthenticatedRecentPlayReportingSurvivesRelaunch() throws {
        guard ProcessInfo.processInfo.environment["SONIMBUS_AUTH_UI"] == "1" else {
            throw XCTSkip("Requires an explicitly signed-in simulator account")
        }
        let app = XCUIApplication()
        func openAccountRecents() {
            app.launch()
            let library = app.buttons["资料库"].firstMatch
            XCTAssertTrue(library.waitForExistence(timeout: 15))
            XCTAssertTrue(focus(library, in: app, timeout: 10))
            let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS '最近播放'")).firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 30))
            XCTAssertTrue(focus(recent, in: app, timeout: 12))
            XCUIRemote.shared.press(.select)
        }
        openAccountRecents()
        XCTAssertTrue(waitUntil(timeout: 20) {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track-row-recent-history-'")).count >= 2
        })
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track-row-recent-history-'")).element(boundBy: 1)
        let selectedID = row.identifier
        XCTAssertTrue(focus(row, in: app, timeout: 12))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(nowPlayingPage(in: app).waitForExistence(timeout: 10))
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label == '播放进度' AND value CONTAINS '/' ")).firstMatch
        let played = NSPredicate { _, _ in
            guard let value = progress.value as? String,
                  let elapsed = value.components(separatedBy: " / ").first else { return false }
            let parts = elapsed.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 6
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: played, object: nil)], timeout: 45), .completed)
        XCUIRemote.shared.press(.playPause)
        app.terminate()
        openAccountRecents()
        let newest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'track-row-recent-history-'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 25))
        XCTAssertEqual(newest.identifier, selectedID, "Recently played song must move to the top after a fresh server read")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "server-recent-order-after-relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchFixture(
        duplicatesAcrossShelves: Bool = false,
        searchFixture: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SONIMBUS_UI_PLAYBACK_FIXTURE"] = "1"
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

            let current = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
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
