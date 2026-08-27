import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    static let shared = AccountStore()
    private static let lastUserIDKey = "auth.lastUserID"

    private(set) var profile: UserProfile?
    private(set) var membership: VIPMembership?
    private(set) var playlists: [PlaylistSummary] = []
    private(set) var likedAlbums: [AlbumSummary] = []
    private(set) var likedArtists: [ArtistSummary] = []
    private(set) var likedSongIDs: Set<Int> = []
    private(set) var playlistRevision = 0
    private(set) var isBootstrapping = false
    private(set) var hasBootstrapped = false
    private(set) var bootstrapError: String?
    private var refreshCookieTask: Task<Void, Never>?
    private var accountGeneration = 0
    private var libraryRefreshGeneration = 0
    private var pendingSongLikeIDs = Set<Int>()
    private var pendingAlbumSubscriptionIDs = Set<Int>()
    private var pendingArtistSubscriptionIDs = Set<Int>()
    private var pendingPlaylistSubscriptionIDs = Set<Int>()

    var hasAuthenticationCookie: Bool { NeteaseClient.shared.isLoggedIn }
    var isLoggedIn: Bool { hasAuthenticationCookie && profile != nil }
    var isVIP: Bool {
        (profile?.vipType ?? 0) > 0 || (membership?.redVipLevel ?? 0) > 0
    }
    var membershipLabel: String {
        guard isVIP else { return "普通用户" }
        guard let level = membership?.redVipLevel, level > 0 else { return "黑胶 VIP" }
        return "黑胶 VIP · Lv.\(level)"
    }
    var likedSongsPlaylist: PlaylistSummary? {
        playlists.first(where: \.isLikedSongsList)
    }
    var ownedPlaylists: [PlaylistSummary] {
        guard let userID = profile?.userId else { return [] }
        return playlists.filter { $0.creator?.userId == userID && !$0.isLikedSongsList }
    }

    private init() {}

    @discardableResult
    func bootstrap() async -> Bool {
        guard !isBootstrapping else { return isLoggedIn }
        isBootstrapping = true
        defer {
            isBootstrapping = false
            hasBootstrapped = true
        }
        guard hasAuthenticationCookie else {
            let hadPersistedAccount = UserDefaults.standard.object(forKey: Self.lastUserIDKey) != nil
            if profile != nil || hadPersistedAccount { clearAccountData() }
            bootstrapError = nil
            return false
        }
        let bootstrapGeneration = accountGeneration
        do {
            guard let fetchedProfile = try await NeteaseAPI.account() else {
                guard bootstrapGeneration == accountGeneration else { return false }
                bootstrapError = "账号资料暂时没有返回，登录凭证仍已保留，请稍后重试"
                return false
            }
            guard bootstrapGeneration == accountGeneration, hasAuthenticationCookie else { return false }
            if profile?.userId != fetchedProfile.userId {
                accountGeneration &+= 1
                libraryRefreshGeneration &+= 1
            }
            let previousUserID = UserDefaults.standard.object(forKey: Self.lastUserIDKey) as? Int
            if let previousUserID, previousUserID != fetchedProfile.userId {
                PlayerService.shared.clearForAccountChange()
            }
            UserDefaults.standard.set(fetchedProfile.userId, forKey: Self.lastUserIDKey)
            profile = fetchedProfile
            bootstrapError = nil
            let activeAccountGeneration = accountGeneration
            await refreshLibrary()
            guard activeAccountGeneration == accountGeneration, isLoggedIn else { return false }
            refreshCookieOncePerDay()
            return isLoggedIn && activeAccountGeneration == accountGeneration
        } catch NeteaseAPIError.needLogin {
            guard bootstrapGeneration == accountGeneration else { return false }
            NeteaseClient.shared.clearAuthentication()
            clearAccountData()
            bootstrapError = nil
            return false
        } catch {
            if bootstrapGeneration == accountGeneration {
                bootstrapError = error.localizedDescription
            }
            return false
        }
    }

    func refreshLibrary(showFeedback: Bool = false) async {
        guard let userID = profile?.userId else { return }
        libraryRefreshGeneration &+= 1
        let refreshGeneration = libraryRefreshGeneration
        let refreshAccountGeneration = accountGeneration
        async let playlistRequest = try? NeteaseAPI.userPlaylists(userID: userID)
        async let likedRequest = try? NeteaseAPI.likedSongIDs(userID: userID)
        async let albumRequest = try? NeteaseAPI.likedAlbums()
        async let artistRequest = try? NeteaseAPI.likedArtists()
        async let membershipRequest = fetchMembership(userID: userID)
        let (playlistResult, likedResult, albumResult, artistResult, membershipResult) = await (
            playlistRequest,
            likedRequest,
            albumRequest,
            artistRequest,
            membershipRequest
        )
        guard refreshGeneration == libraryRefreshGeneration,
              refreshAccountGeneration == accountGeneration,
              profile?.userId == userID else { return }
        if let playlistResult { playlists = playlistResult }
        if let likedResult { likedSongIDs = Set(likedResult) }
        if let albumResult { likedAlbums = albumResult }
        if let artistResult { likedArtists = artistResult }
        if membershipResult.succeeded { membership = membershipResult.value }
        guard showFeedback else { return }
        let completed = [
            playlistResult != nil,
            likedResult != nil,
            albumResult != nil,
            artistResult != nil,
            membershipResult.succeeded,
        ]
            .filter { $0 }.count
        if completed == 0 {
            ToastCenter.shared.show("资料库刷新失败，请稍后重试")
        } else if completed < 5 {
            ToastCenter.shared.show("资料库仅同步了部分内容")
        } else {
            ToastCenter.shared.show("资料库已刷新")
        }
    }

    func isLiked(_ track: Track) -> Bool {
        likedSongIDs.contains(track.id)
    }

    func isAlbumLiked(_ album: AlbumSummary) -> Bool {
        likedAlbums.contains(where: { $0.id == album.id })
    }

    func isArtistLiked(_ artist: ArtistSummary) -> Bool {
        likedArtists.contains(where: { $0.id == artist.id })
    }

    func containsPlaylist(id: Int) -> Bool {
        playlists.contains(where: { $0.id == id })
    }

    func ownsPlaylist(id: Int) -> Bool {
        ownedPlaylists.contains(where: { $0.id == id })
    }

    func toggleLike(_ track: Track) async {
        guard isLoggedIn else {
            ToastCenter.shared.show("登录后即可收藏歌曲")
            return
        }
        let generation = accountGeneration
        guard pendingSongLikeIDs.insert(track.id).inserted else { return }
        defer {
            if generation == accountGeneration { pendingSongLikeIDs.remove(track.id) }
        }
        invalidatePendingLibraryRefresh()
        let shouldLike = !likedSongIDs.contains(track.id)
        if shouldLike { likedSongIDs.insert(track.id) } else { likedSongIDs.remove(track.id) }
        adjustLikedSongsCount(by: shouldLike ? 1 : -1)
        do {
            try await NeteaseAPI.likeSong(id: track.id, like: shouldLike)
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(shouldLike ? "已添加到喜欢的音乐" : "已取消喜欢")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            if shouldLike { likedSongIDs.remove(track.id) } else { likedSongIDs.insert(track.id) }
            adjustLikedSongsCount(by: shouldLike ? -1 : 1)
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func toggleAlbum(_ album: AlbumSummary) async {
        guard isLoggedIn else {
            ToastCenter.shared.show("登录后即可收藏专辑")
            return
        }
        let generation = accountGeneration
        guard pendingAlbumSubscriptionIDs.insert(album.id).inserted else { return }
        defer {
            if generation == accountGeneration { pendingAlbumSubscriptionIDs.remove(album.id) }
        }
        invalidatePendingLibraryRefresh()
        let shouldLike = !isAlbumLiked(album)
        if shouldLike { likedAlbums.insert(album, at: 0) }
        else { likedAlbums.removeAll { $0.id == album.id } }
        do {
            try await NeteaseAPI.subscribeAlbum(id: album.id, subscribe: shouldLike)
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(shouldLike ? "已收藏《\(album.name)》" : "已取消收藏《\(album.name)》")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            if shouldLike { likedAlbums.removeAll { $0.id == album.id } }
            else { likedAlbums.insert(album, at: 0) }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func toggleArtist(_ artist: ArtistSummary) async {
        guard isLoggedIn else {
            ToastCenter.shared.show("登录后即可关注歌手")
            return
        }
        let generation = accountGeneration
        guard pendingArtistSubscriptionIDs.insert(artist.id).inserted else { return }
        defer {
            if generation == accountGeneration { pendingArtistSubscriptionIDs.remove(artist.id) }
        }
        invalidatePendingLibraryRefresh()
        let shouldLike = !isArtistLiked(artist)
        if shouldLike { likedArtists.insert(artist, at: 0) }
        else { likedArtists.removeAll { $0.id == artist.id } }
        do {
            try await NeteaseAPI.subscribeArtist(id: artist.id, subscribe: shouldLike)
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(shouldLike ? "已关注\(artist.name)" : "已取消关注\(artist.name)")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            if shouldLike { likedArtists.removeAll { $0.id == artist.id } }
            else { likedArtists.insert(artist, at: 0) }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func togglePlaylistSubscription(id: Int, name: String) async {
        guard isLoggedIn else {
            ToastCenter.shared.show("登录后即可收藏歌单")
            return
        }
        let generation = accountGeneration
        guard pendingPlaylistSubscriptionIDs.insert(id).inserted else { return }
        defer {
            if generation == accountGeneration { pendingPlaylistSubscriptionIDs.remove(id) }
        }
        invalidatePendingLibraryRefresh()
        let shouldSubscribe = !containsPlaylist(id: id)
        do {
            try await NeteaseAPI.subscribePlaylist(id: id, subscribe: shouldSubscribe)
            guard generation == accountGeneration, isLoggedIn else { return }
            await refreshLibrary()
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(shouldSubscribe ? "已收藏歌单《\(name)》" : "已取消收藏歌单《\(name)》")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func createPlaylist(name: String, isPrivate: Bool) async -> Bool {
        guard isLoggedIn else {
            ToastCenter.shared.show("登录后即可创建歌单")
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            ToastCenter.shared.show("请输入歌单名称")
            return false
        }
        invalidatePendingLibraryRefresh()
        let generation = accountGeneration
        do {
            _ = try await NeteaseAPI.createPlaylist(name: trimmed, isPrivate: isPrivate)
            guard generation == accountGeneration, isLoggedIn else { return false }
            await refreshLibrary()
            guard generation == accountGeneration, isLoggedIn else { return false }
            playlistRevision += 1
            ToastCenter.shared.show("已创建歌单《\(trimmed)》")
            return true
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return false }
            ToastCenter.shared.show(error.localizedDescription)
            return false
        }
    }

    func deletePlaylist(_ playlist: PlaylistSummary) async {
        guard ownsPlaylist(id: playlist.id) else { return }
        invalidatePendingLibraryRefresh()
        let generation = accountGeneration
        do {
            try await NeteaseAPI.deletePlaylist(id: playlist.id)
            guard generation == accountGeneration, isLoggedIn else { return }
            playlists.removeAll { $0.id == playlist.id }
            playlistRevision += 1
            ToastCenter.shared.show("已删除歌单《\(playlist.name)》")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func updatePlaylist(
        id: Int,
        name: String,
        description: String,
        coverURL: URL?
    ) async -> Bool {
        guard ownsPlaylist(id: id) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            ToastCenter.shared.show("歌单名称不能为空")
            return false
        }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        invalidatePendingLibraryRefresh()
        let generation = accountGeneration
        var savedPart = false
        do {
            try await NeteaseAPI.updatePlaylistName(id: id, name: trimmedName)
            savedPart = true
            try await NeteaseAPI.updatePlaylistDescription(id: id, description: trimmedDescription)
            if let coverURL {
                try await MediaTransferService.updatePlaylistCover(
                    playlistID: id,
                    sourceURL: coverURL
                )
            }
            guard generation == accountGeneration, isLoggedIn else { return false }
            await refreshLibrary()
            guard generation == accountGeneration, isLoggedIn else { return false }
            playlistRevision &+= 1
            ToastCenter.shared.show("歌单资料已更新")
            return true
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return false }
            if savedPart {
                await refreshLibrary()
                playlistRevision &+= 1
                ToastCenter.shared.show("部分资料已保存：\(error.localizedDescription)")
            } else {
                ToastCenter.shared.show(error.localizedDescription)
            }
            return false
        }
    }

    func add(_ track: Track, to playlist: PlaylistSummary) async {
        guard ownsPlaylist(id: playlist.id) else { return }
        invalidatePendingLibraryRefresh()
        let generation = accountGeneration
        do {
            try await NeteaseAPI.playlistTracks(operation: "add", playlistID: playlist.id, trackIDs: [track.id])
            guard generation == accountGeneration, isLoggedIn else { return }
            await refreshLibrary()
            guard generation == accountGeneration, isLoggedIn else { return }
            playlistRevision += 1
            ToastCenter.shared.show("已添加到《\(playlist.name)》")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func remove(_ track: Track, from playlist: PlaylistSummary) async {
        guard ownsPlaylist(id: playlist.id) else { return }
        invalidatePendingLibraryRefresh()
        let generation = accountGeneration
        do {
            try await NeteaseAPI.playlistTracks(operation: "del", playlistID: playlist.id, trackIDs: [track.id])
            guard generation == accountGeneration, isLoggedIn else { return }
            await refreshLibrary()
            guard generation == accountGeneration, isLoggedIn else { return }
            playlistRevision += 1
            ToastCenter.shared.show("已从《\(playlist.name)》移除")
        } catch {
            guard generation == accountGeneration, isLoggedIn else { return }
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func logout() async {
        refreshCookieTask?.cancel()
        refreshCookieTask = nil
        await NeteaseAPI.logout()
        NeteaseClient.shared.clearAuthentication()
        clearAccountData()
        bootstrapError = nil
    }

    private func clearAccountData() {
        refreshCookieTask?.cancel()
        refreshCookieTask = nil
        accountGeneration &+= 1
        libraryRefreshGeneration &+= 1
        PlayerService.shared.clearForAccountChange()
        profile = nil
        membership = nil
        playlists = []
        likedAlbums = []
        likedArtists = []
        likedSongIDs = []
        pendingSongLikeIDs = []
        pendingAlbumSubscriptionIDs = []
        pendingArtistSubscriptionIDs = []
        pendingPlaylistSubscriptionIDs = []
        playlistRevision = 0
        UserDefaults.standard.removeObject(forKey: Self.lastUserIDKey)
    }

    private func invalidatePendingLibraryRefresh() {
        libraryRefreshGeneration &+= 1
    }

    private func fetchMembership(userID: Int) async -> (succeeded: Bool, value: VIPMembership?) {
        do {
            return (true, try await NeteaseAPI.vipInfo(userID: userID))
        } catch {
            return (false, nil)
        }
    }

    private func adjustLikedSongsCount(by delta: Int) {
        guard let index = playlists.firstIndex(where: \.isLikedSongsList) else { return }
        let playlist = playlists[index]
        playlists[index] = playlist.replacingTrackCount(with: playlist.trackCount + delta)
    }

    private func refreshCookieOncePerDay() {
        let key = "auth.lastRefresh"
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) < today,
              refreshCookieTask == nil else { return }
        refreshCookieTask = Task { [weak self] in
            defer { self?.refreshCookieTask = nil }
            do {
                try await NeteaseAPI.refreshLogin()
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(today, forKey: key)
            } catch {
                // Keep the old timestamp so the next launch can retry.
            }
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String) {
        current = ToastMessage(text: text)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}
