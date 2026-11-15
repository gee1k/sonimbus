import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let snapshot = TopShelfSnapshotStore.read() else {
            completionHandler(nil)
            return
        }
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
        for (title, kind, entries) in [
            ("最近播放", TopShelfLink.Kind.track, snapshot.recentTracks),
            ("我的歌单", TopShelfLink.Kind.playlist, snapshot.playlists),
        ] {
            let items = entries.prefix(12).compactMap { entry -> TVTopShelfSectionedItem? in
                guard let imageURL = entry.imageURL else { return nil }
                let item = TVTopShelfSectionedItem(identifier: "\(snapshot.accountID)-\(kind.rawValue)-\(entry.id)")
                item.title = entry.title
                item.imageShape = .square
                item.setImageURL(imageURL, for: .screenScale1x)
                item.setImageURL(imageURL, for: .screenScale2x)
                let display = TopShelfLink(kind: kind, id: entry.id, accountID: snapshot.accountID,
                                           action: kind == .track ? .play : .display)
                let play = TopShelfLink(kind: kind, id: entry.id, accountID: snapshot.accountID, action: .play)
                item.displayAction = TVTopShelfAction(url: display.url)
                item.playAction = TVTopShelfAction(url: play.url)
                return item
            }
            if !items.isEmpty {
                let section = TVTopShelfItemCollection(items: items)
                section.title = title
                sections.append(section)
            }
        }
        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }
}
