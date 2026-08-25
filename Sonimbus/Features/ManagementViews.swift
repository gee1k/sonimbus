import SwiftUI

private enum CloudUploadFocus: Hashable {
    case source
}

struct CloudUploadView: View {
    @Environment(\.dismiss) private var dismiss

    let onCompleted: () -> Void

    @State private var source = ""
    @State private var songName = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var isUploading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: CloudUploadFocus?

    var body: some View {
        ZStack {
            TVBackground(tint: TVTheme.magenta)
            ScrollView {
                VStack(spacing: 30) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 90, weight: .semibold))
                        .foregroundStyle(TVTheme.accent)

                    VStack(spacing: 8) {
                        Text("上传到音乐云盘")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("在手机键盘中粘贴可直接下载的 HTTPS 音频链接。")
                            .font(.title3)
                            .foregroundStyle(TVTheme.secondaryText)
                    }

                    formField("音频链接", text: $source)
                        .focused($focusedField, equals: .source)
                    formField("歌曲名（可留空）", text: $songName)
                    HStack(spacing: 22) {
                        formField("歌手（可留空）", text: $artist, width: 439)
                        formField("专辑（可留空）", text: $album, width: 439)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(TVTheme.amber)
                            .frame(maxWidth: 900, alignment: .leading)
                    }

                    HStack(spacing: 20) {
                        Button("取消") { dismiss() }
                            .buttonStyle(TVPillButtonStyle())
                            .disabled(isUploading)
                        Button {
                            Task { await upload() }
                        } label: {
                            if isUploading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在下载并上传")
                                }
                            } else {
                                Label("开始上传", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: true))
                        .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                    }

                    Text("链接只用于本次传输；音频会直接从来源下载并上传到你的网易云账号。")
                        .font(.caption)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                .frame(maxWidth: 1_050)
                .padding(.vertical, 54)
            }
        }
        .onExitCommand {
            if !isUploading { dismiss() }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            focusedField = .source
        }
    }

    private func formField(
        _ title: String,
        text: Binding<String>,
        width: CGFloat = 900
    ) -> some View {
        TextField(title, text: text)
            .font(.title3)
            .frame(width: width)
    }

    @MainActor
    private func upload() async {
        let raw = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else {
            errorMessage = MediaTransferError.invalidHTTPSURL.localizedDescription
            return
        }
        isUploading = true
        errorMessage = nil
        do {
            try await MediaTransferService.uploadCloudTrack(
                CloudUploadRequest(
                    sourceURL: url,
                    songName: songName,
                    artist: artist,
                    album: album
                )
            )
            ToastCenter.shared.show("歌曲已上传到音乐云盘")
            onCompleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }
}

struct CloudMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    let item: CloudSongItem
    let onCompleted: () -> Void

    @State private var query: String
    @State private var results: [Track] = []
    @State private var isSearching = false
    @State private var matchingID: Int?
    @State private var errorMessage: String?

    init(item: CloudSongItem, onCompleted: @escaping () -> Void) {
        self.item = item
        self.onCompleted = onCompleted
        let initial = [item.songName, item.artist]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        _query = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("匹配云盘歌曲")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("为《\(item.songName ?? "云盘歌曲")》选择正确的网易云曲目资料")
                        .font(.headline)
                        .foregroundStyle(TVTheme.secondaryText)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(TVPillButtonStyle())
            }
            .padding(.horizontal, TVTheme.horizontalPadding)
            .padding(.top, 38)

            HStack(spacing: 18) {
                TextField("搜索歌曲或歌手", text: $query)
                    .font(.title3)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await search() }
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .buttonStyle(TVPillButtonStyle(prominent: true))
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal, TVTheme.horizontalPadding)

            Group {
                if isSearching {
                    LoadStateView(title: "正在搜索可匹配歌曲")
                } else if let errorMessage {
                    LoadStateView(title: "匹配搜索失败", message: errorMessage) {
                        Task { await search() }
                    }
                } else if results.isEmpty {
                    EmptyStateView(
                        title: "搜索后选择正确曲目",
                        message: "匹配只会更新云盘歌曲资料，不会删除你的音频文件。",
                        symbol: "link"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(results) { track in
                                Button {
                                    Task { await match(track) }
                                } label: {
                                    HStack(spacing: 18) {
                                        ArtworkView(url: track.artworkURL, cornerRadius: 10)
                                            .frame(width: 66, height: 66)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(track.name)
                                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                            Text("\(track.artistNames) · \(track.album.name)")
                                                .font(.system(size: 21, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if matchingID == track.id {
                                            ProgressView()
                                        } else {
                                            Label("选择", systemImage: "link")
                                                .font(.headline)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(height: 88)
                                }
                                .buttonStyle(TrackRowButtonStyle())
                                .disabled(matchingID != nil)
                            }
                        }
                        .padding(.horizontal, TVTheme.horizontalPadding)
                        .padding(.bottom, 70)
                    }
                }
            }
        }
        .background(TVBackground(tint: .purple))
        .onExitCommand {
            if matchingID == nil { dismiss() }
        }
    }

    @MainActor
    private func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            results = try await NeteaseAPI.search(keyword, type: .songs, limit: 20).songs ?? []
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    @MainActor
    private func match(_ track: Track) async {
        guard let userID = account.profile?.userId else { return }
        matchingID = track.id
        do {
            try await NeteaseAPI.matchCloudSong(
                userID: userID,
                cloudSongID: item.songId,
                targetSongID: track.id
            )
            ToastCenter.shared.show("已匹配为《\(track.name)》")
            onCompleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        matchingID = nil
    }
}

struct PlaylistEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    let detail: PlaylistDetail

    @State private var name: String
    @State private var description: String
    @State private var coverSource = ""
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(detail: PlaylistDetail) {
        self.detail = detail
        _name = State(initialValue: detail.name)
        _description = State(initialValue: detail.description ?? "")
    }

    var body: some View {
        ZStack {
            TVBackground(tint: .indigo)
            ScrollView {
                VStack(spacing: 30) {
                    ArtworkView(url: detail.artworkURL, cornerRadius: 30, symbol: "music.note.list")
                        .frame(width: 230, height: 230)

                    VStack(spacing: 8) {
                        Text("编辑歌单资料")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("标题和描述会立即同步；封面可粘贴 HTTPS 图片链接替换。")
                            .font(.title3)
                            .foregroundStyle(TVTheme.secondaryText)
                    }

                    TextField("歌单名称", text: $name)
                        .font(.title3)
                        .frame(width: 900)
                    TextField("歌单描述", text: $description, axis: .vertical)
                        .font(.title3)
                        .lineLimit(2...4)
                        .frame(width: 900)
                    TextField("新封面 HTTPS 链接（不修改可留空）", text: $coverSource)
                        .font(.title3)
                        .frame(width: 900)

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(TVTheme.amber)
                            .frame(width: 900, alignment: .leading)
                    }

                    HStack(spacing: 20) {
                        Button("取消") { dismiss() }
                            .buttonStyle(TVPillButtonStyle())
                            .disabled(isSaving)
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在保存")
                                }
                            } else {
                                Label("保存更改", systemImage: "checkmark")
                            }
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: true))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                }
                .padding(.vertical, 48)
            }
        }
        .onExitCommand {
            if !isSaving { dismiss() }
        }
    }

    @MainActor
    private func save() async {
        let rawCover = coverSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let coverURL: URL?
        if rawCover.isEmpty {
            coverURL = nil
        } else if let parsed = URL(string: rawCover), parsed.scheme?.lowercased() == "https" {
            coverURL = parsed
        } else {
            validationMessage = "封面必须是有效的 HTTPS 图片链接"
            return
        }
        isSaving = true
        validationMessage = nil
        if await account.updatePlaylist(
            id: detail.id,
            name: name,
            description: description,
            coverURL: coverURL
        ) {
            dismiss()
        }
        isSaving = false
    }
}
