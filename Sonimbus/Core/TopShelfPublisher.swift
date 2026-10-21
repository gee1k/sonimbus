import TVServices

@MainActor
enum TopShelfPublisher {
    static func clear() {
        if TopShelfSnapshotStore.write(nil) { TVTopShelfContentProvider.topShelfContentDidChange() }
    }

    static func update(account: AccountStore, player: PlayerService) {
        guard let userID = account.profile?.userId, account.isLoggedIn else {
            clear()
            return
        }
        let playlists = account.playlists.sorted { $0.isLikedSongsList && !$1.isLikedSongsList }
        let snapshot = TopShelfSnapshot(
            accountID: userID,
            recentTracks: player.recentTracks.prefix(12).map {
                .init(id: $0.id, title: $0.name, imageURL: $0.artworkURL)
            },
            playlists: playlists.prefix(12).map {
                .init(id: $0.id, title: $0.isLikedSongsList ? "我喜欢的音乐" : $0.name, imageURL: $0.artworkURL)
            }
        )
        guard TopShelfSnapshotStore.read() != snapshot else { return }
        if TopShelfSnapshotStore.write(snapshot) { TVTopShelfContentProvider.topShelfContentDidChange() }
    }
}
