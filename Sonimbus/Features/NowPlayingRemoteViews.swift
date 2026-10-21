import SwiftUI
import UIKit

struct PlaybackQueueFocusRequest: Equatable {
    let trackID: Int
    let generation: Int
}

/// A collection view keeps the focus engine's work proportional to visible cards,
/// even when the playback queue contains thousands of songs.
struct PlaybackQueueView: UIViewControllerRepresentable {
    let tracks: [Track]
    let currentID: Int?
    let focusRequest: PlaybackQueueFocusRequest?
    let onSelect: (Track) -> Void
    let onRemove: (Track) -> Void
    let onFocusReleased: () -> Void

    func makeUIViewController(context: Context) -> PlaybackQueueController {
        PlaybackQueueController()
    }

    func updateUIViewController(_ controller: PlaybackQueueController, context: Context) {
        controller.onSelect = onSelect
        controller.onRemove = onRemove
        controller.onFocusReleased = onFocusReleased
        controller.update(tracks: tracks, currentID: currentID, focusRequest: focusRequest)
        controller.view.isUserInteractionEnabled = context.environment.isEnabled
    }

    static func dismantleUIViewController(_ controller: PlaybackQueueController, coordinator: ()) {
        let released = controller.onFocusReleased
        DispatchQueue.main.async { released?() }
    }
}

final class PlaybackQueueController: UICollectionViewController {
    var onSelect: ((Track) -> Void)?
    var onRemove: ((Track) -> Void)?
    var onFocusReleased: (() -> Void)?
    private var tracks: [Track] = []
    private var currentID: Int?
    private var focusRequest: PlaybackQueueFocusRequest?
    private var pendingFocusIndex: IndexPath?
    private var focusedIndex: IndexPath?
    private var focusAttempts = 0

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 263, height: 380)
        layout.minimumLineSpacing = 30
        layout.sectionInset = UIEdgeInsets(top: 42, left: 34, bottom: 42, right: 34)
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.register(PlaybackQueueCell.self, forCellWithReuseIdentifier: "track")
        collectionView.accessibilityIdentifier = "playback-queue-collection"
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(showRemoval(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        collectionView.addGestureRecognizer(hold)
    }

    func update(tracks: [Track], currentID: Int?, focusRequest: PlaybackQueueFocusRequest?) {
        loadViewIfNeeded()
        let changed = self.tracks != tracks
        let currentChanged = self.currentID != currentID
        let focusedID = focusedIndex.flatMap { self.tracks.indices.contains($0.item) ? self.tracks[$0.item].id : nil }
        self.tracks = tracks
        self.currentID = currentID
        if changed {
            collectionView.reloadData()
            if let focusedID, let index = tracks.firstIndex(where: { $0.id == focusedID }) {
                focusedIndex = IndexPath(item: index, section: 0)
            } else if let previous = focusedIndex, !tracks.isEmpty {
                focusedIndex = IndexPath(item: min(previous.item, tracks.count - 1), section: 0)
            } else {
                focusedIndex = nil
            }
        } else if currentChanged {
            // Updating the playing marker must not reload or refocus the collection.
            for case let cell as PlaybackQueueCell in collectionView.visibleCells {
                guard let index = collectionView.indexPath(for: cell)?.item, tracks.indices.contains(index) else { continue }
                cell.configure(track: tracks[index], index: index, isCurrent: tracks[index].id == currentID)
            }
        }
        if let focusRequest, self.focusRequest != focusRequest {
            self.focusRequest = focusRequest
            focusAttempts = 0
            if let index = tracks.firstIndex(where: { $0.id == focusRequest.trackID }) {
                pendingFocusIndex = IndexPath(item: index, section: 0)
                DispatchQueue.main.async { [weak self] in self?.applyPendingFocus() }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyPendingFocus()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let index = pendingFocusIndex ?? focusedIndex,
           let cell = collectionView.cellForItem(at: index) { return [cell] }
        return [collectionView]
    }

    override func viewWillDisappear(_ animated: Bool) {
        pendingFocusIndex = nil
        super.viewWillDisappear(animated)
    }

    private func applyPendingFocus() {
        guard view.window != nil, let index = pendingFocusIndex, tracks.indices.contains(index.item) else { return }
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: index, at: .centeredHorizontally, animated: false)
        collectionView.layoutIfNeeded()
        guard let cell = collectionView.cellForItem(at: index) else { return }
        UIFocusSystem.focusSystem(for: view)?.requestFocusUpdate(to: cell)
        UIFocusSystem.focusSystem(for: view)?.updateFocusIfNeeded()
        if cell.isFocused {
            pendingFocusIndex = nil
        } else if focusAttempts < 4 {
            // SwiftUI may still be fading in this controller on the first layout.
            focusAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyPendingFocus()
            }
        }
    }

    override func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        pendingFocusIndex ?? focusedIndex
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        tracks.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "track", for: indexPath) as! PlaybackQueueCell
        let track = tracks[indexPath.item]
        cell.configure(track: track, index: indexPath.item, isCurrent: track.id == currentID)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(tracks[indexPath.item])
    }

    override func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        if let index = context.nextFocusedIndexPath { focusedIndex = index }
    }

    @objc private func showRemoval(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let index = focusedIndex,
              tracks.indices.contains(index.item), presentedViewController == nil else { return }
        let track = tracks[index.item]
        guard track.id != currentID else { return }
        let menu = UIAlertController(title: track.name, message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "从播放队列移除", style: .destructive) { [weak self] _ in self?.onRemove?(track) })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(menu, animated: true)
    }
}

private final class PlaybackQueueArtworkView: UIView {
    let imageView = UIImageView()
    let placeholder = UIImageView(image: UIImage(systemName: "music.note"))

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor(TVTheme.magenta).cgColor, UIColor.systemIndigo.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.cornerRadius = 20
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        placeholder.contentMode = .scaleAspectFit
        placeholder.tintColor = .white.withAlphaComponent(0.8)
        for view in [imageView, placeholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 55),
            placeholder.heightAnchor.constraint(equalToConstant: 65),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class PlaybackQueueCell: UICollectionViewCell {
    private let artwork = PlaybackQueueArtworkView()
    private var imageView: UIImageView { artwork.imageView }
    private var placeholder: UIImageView { artwork.placeholder }
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let positionLabel = UILabel()
    private var imageURL: URL?
    private var imageTask: Task<Void, Never>?
    private var isCurrent = false
    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
        artistLabel.font = .systemFont(ofSize: 21)
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        let stack = UIStackView(arrangedSubviews: [artwork, titleLabel, artistLabel, positionLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            artwork.heightAnchor.constraint(equalToConstant: 235),
        ])
        contentView.layer.cornerRadius = 28
        contentView.layer.borderColor = UIColor(TVTheme.accent).cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(track: Track, index: Int, isCurrent: Bool) {
        self.isCurrent = isCurrent
        titleLabel.text = track.name
        artistLabel.text = track.artistNames
        positionLabel.text = "\(index + 1)\(isCurrent ? " · 正在播放" : "")"
        accessibilityIdentifier = "queue-track-\(track.id)"
        accessibilityLabel = "\(index + 1) · \(track.name) · \(track.artistNames)\(isCurrent ? " · 正在播放" : "")"
        updateColors()
        loadImage(track.album.picUrl.flatMap { ArtworkURL.make($0, size: 480) })
    }

    private func updateColors() {
        contentView.backgroundColor = isFocused ? .white : .white.withAlphaComponent(isCurrent ? 0.12 : 0.055)
        contentView.layer.borderWidth = isCurrent ? 3 : 0
        let foreground: UIColor = isFocused ? .black : .white
        titleLabel.textColor = foreground
        artistLabel.textColor = foreground.withAlphaComponent(0.58)
        positionLabel.textColor = foreground.withAlphaComponent(0.54)
    }

    private func loadImage(_ url: URL?) {
        guard imageURL != url else { return }
        imageTask?.cancel()
        imageURL = url
        imageView.image = nil
        placeholder.isHidden = false
        guard let url else { return }
        if let cached = DecodedRemoteImageCache.shared.image(for: url) {
            imageView.image = cached
            placeholder.isHidden = true
            return
        }
        imageTask = Task { @MainActor [weak self] in
            guard let data = try? await RemoteImageRepository.shared.data(for: url), !Task.isCancelled else { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value
            guard !Task.isCancelled, let self, self.imageURL == url, let decoded else { return }
            DecodedRemoteImageCache.shared.insert(decoded, for: url)
            self.imageView.image = decoded
            self.placeholder.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageURL = nil
        imageView.image = nil
        placeholder.isHidden = false
        transform = .identity
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateColors()
            self.transform = self.isFocused && !UIAccessibility.isReduceMotionEnabled
                ? CGAffineTransform(scaleX: 1.055, y: 1.055) : .identity
        }
    }
}

/// Separates a short directional press from a hold, so revealing controls does
/// not steal focus before the long press can finish.
struct ImmersivePlaybackControl: UIViewRepresentable {
    let onSelect: () -> Void
    let onMove: (MoveCommandDirection) -> Void
    let onSkip: (MoveCommandDirection) -> Void
    let onFocusReleased: () -> Void

    func makeUIView(context: Context) -> ImmersiveRemoteControl { ImmersiveRemoteControl() }
    func updateUIView(_ view: ImmersiveRemoteControl, context: Context) {
        view.onSelect = onSelect
        view.onMove = onMove
        view.onSkip = onSkip
        view.onFocusReleased = onFocusReleased
        view.setInputEnabled(context.environment.isEnabled)
    }

    static func dismantleUIView(_ view: ImmersiveRemoteControl, coordinator: ()) {
        let released = view.onFocusReleased
        DispatchQueue.main.async { released?() }
    }
}

final class ImmersiveRemoteControl: UIControl {
    var onSelect: (() -> Void)?
    var onMove: ((MoveCommandDirection) -> Void)?
    var onSkip: ((MoveCommandDirection) -> Void)?
    var onFocusReleased: (() -> Void)?
    private var holdTask: Task<Void, Never>?
    private var heldDirection: MoveCommandDirection?
    private var didSkip = false
    override var canBecomeFocused: Bool { isEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isEnabled = false
        isHidden = true
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "播放中"
        accessibilityIdentifier = "immersive-playback-control"
        accessibilityHint = "点按显示控制，长按左键上一首，长按右键下一首"
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { cancelHold(); return }
        if isEnabled { requestInputFocus() }
    }

    func setInputEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        // A transparent UIKit overlay still occludes focus regions beneath it.
        // Hide it while inactive so the visible SwiftUI controls can take focus.
        isHidden = !enabled
        if enabled {
            requestInputFocus()
        } else {
            cancelHold()
            let released = onFocusReleased
            DispatchQueue.main.async { released?() }
        }
    }

    private func requestInputFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.isEnabled else { return }
            let focusSystem = UIFocusSystem.focusSystem(for: self)
            focusSystem?.requestFocusUpdate(to: self)
            focusSystem?.updateFocusIfNeeded()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = presses.filter { press in
            switch press.type {
            case .leftArrow, .rightArrow:
                guard heldDirection == nil else { return false }
                let direction: MoveCommandDirection = press.type == .leftArrow ? .left : .right
                heldDirection = direction
                didSkip = false
                holdTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                    guard let self, self.isFocused else { return }
                    self.didSkip = true
                    self.onSkip?(direction)
                }
                return false
            case .upArrow: onMove?(.up); return false
            case .downArrow: onMove?(.down); return false
            case .select: return false
            default: return true
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(Set(unhandled), with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = presses.filter { press in
            switch press.type {
            case .leftArrow, .rightArrow:
                let direction = heldDirection
                let skipped = didSkip
                cancelHold()
                if !skipped, let direction { onMove?(direction) }
                return false
            case .select: onSelect?(); return false
            case .upArrow, .downArrow: return false
            default: return true
            }
        }
        if !unhandled.isEmpty { super.pressesEnded(Set(unhandled), with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        cancelHold()
        super.pressesCancelled(presses, with: event)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if !isFocused {
            cancelHold()
            if context.previouslyFocusedView === self, !isEnabled {
                // SwiftUI can clear its binding when this native focus item is
                // released. Restore the control after that update, not before it.
                let released = onFocusReleased
                DispatchQueue.main.async { released?() }
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        heldDirection = nil
        didSkip = false
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard heldDirection == nil else { return }
        switch gesture.direction {
        case .left: onMove?(.left)
        case .right: onMove?(.right)
        case .up: onMove?(.up)
        case .down: onMove?(.down)
        default: break
        }
    }
}
