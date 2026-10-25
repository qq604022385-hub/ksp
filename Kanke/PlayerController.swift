import SwiftUI
import UIKit
import AVFAudio
import KSPlayer
import KankeCore

@MainActor
final class PlayerController: ObservableObject {
    let view = KankeVideoPlayerView(frame: .zero)
    let host = UIView()
    @Published var buffering = false
    @Published var error: String?
    @Published private(set) var isFullScreen = false
    private var progress: ((Double, Double) -> Void)?
    private var bridge: PlaybackDelegate?
    private var identity = UUID()
    private var lastSaved: Double = -10
    private var ended = false
    var onEnd: (() -> Void)?
    var onBack: (() -> Void)?
    var speed: Float = 1 {
        didSet { view.playerLayer?.player.playbackRate = speed }
    }

    init() {
        // Explicit FFmpeg engine, with no AVPlayer fallback.
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil
        KSOptions.isAutoPlay = true
        KSOptions.isSeekedAutoPlay = true
        KSOptions.isPipPopViewController = false
        host.backgroundColor = .black
        host.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        view.fullScreenChanged = { [weak self] active in self?.isFullScreen = active }
        view.backBlock = { [weak self] in self?.onBack?() }
    }

    func load(_ media: PlaybackResponse, resume: Double = 0, progress: @escaping (Double, Double) -> Void) {
        stop()
        self.progress = progress
        buffering = true; error = nil; ended = false; lastSaved = -10
        let delegate = PlaybackDelegate(owner: self, identity: identity)
        bridge = delegate; view.delegate = delegate
        view.resetPlayer()
        view.routeButton.isHidden = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let options = KSOptions()
        options.startPlayTime = resume.isFinite && resume > 3 ? resume : 0
        options.startPlayRate = speed
        options.appendHeader(media.headers)
        if let userAgent = media.headers["User-Agent"] { options.userAgent = userAgent }
        view.statusLabel.isHidden = true
        view.set(resource: KSPlayerResource(url: media.url, options: options, name: view.titleLabel.text ?? ""))
        view.isMaskShow = true
    }

    func navigation(title: String, sources: [VideoSource], source: Int, episode: Int,
                    onSource: @escaping (Int) -> Void, onEpisode: @escaping (Int) -> Void,
                    onNext: @escaping () -> Void) {
        view.titleLabel.text = title
        view.sourceButton.menu = UIMenu(title: "播放线路", children: sources.enumerated().map { index, item in
            UIAction(title: item.name, state: index == source ? .on : .off) { _ in onSource(index) }
        })
        let episodes = sources.indices.contains(source) ? sources[source].episodes : []
        view.episodeButton.menu = UIMenu(title: "选集", children: episodes.enumerated().map { index, item in
            UIAction(title: item.title, state: index == episode ? .on : .off) { _ in onEpisode(index) }
        })
        view.nextButton.isEnabled = episodes.indices.contains(episode + 1)
        view.next = onNext
    }

    fileprivate func receive(_ state: KSPlayerState, token: UUID) {
        guard identity == token else { return }
        buffering = state == .preparing || state == .buffering
        if state == .error { error = "播放失败，请重试或切换线路" }
        if state == .playedToTheEnd { finish(nil, token: token) }
    }
    fileprivate func time(_ position: Double, duration: Double, token: UUID) {
        guard identity == token, position.isFinite, position > 0 else { return }
        if abs(position - lastSaved) >= 10 {
            lastSaved = position
            progress?(position, duration.isFinite ? duration : 0)
        }
    }
    fileprivate func finish(_ message: String?, token: UUID) {
        guard identity == token else { return }
        buffering = false; saveProgress()
        if let message { error = message; return }
        guard !ended else { return }
        ended = true; onEnd?()
    }
    func saveProgress() {
        guard let player = view.playerLayer?.player else { return }
        let position = player.currentPlaybackTime, duration = player.duration
        if position.isFinite && position > 0 { progress?(position, duration.isFinite ? duration : 0) }
    }
    func stop() {
        saveProgress(); progress = nil; onEnd = nil
        identity = UUID(); view.delegate = nil; bridge = nil
        view.playerLayer?.delegate = nil
        view.playerLayer?.stop(); view.playerLayer = nil
        buffering = false
    }
    func showStatus(_ message: String) {
        view.statusLabel.text = message; view.statusLabel.isHidden = false
    }
    func close() {
        stop(); onBack = nil; view.next = nil
        view.sourceButton.menu = nil; view.episodeButton.menu = nil
    }
}

// Hop from the older delegate API to the main actor; ignore replaced streams.
private final class PlaybackDelegate: PlayerControllerDelegate {
    weak var owner: PlayerController?
    let identity: UUID
    init(owner: PlayerController, identity: UUID) { self.owner = owner; self.identity = identity }
    func playerController(state: KSPlayerState) {
        Task { @MainActor [weak owner, identity] in owner?.receive(state, token: identity) }
    }
    func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
        Task { @MainActor [weak owner, identity] in owner?.time(currentTime, duration: totalTime, token: identity) }
    }
    func playerController(finish error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor [weak owner, identity] in owner?.finish(message, token: identity) }
    }
    func playerController(maskShow: Bool) {}
    func playerController(action: PlayerButtonType) {}
    func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
    func playerController(seek: TimeInterval) {
        Task { @MainActor [weak owner] in owner?.saveProgress() }
    }
}

final class KankeVideoPlayerView: IOSVideoPlayerView {
    let statusLabel = UILabel()
    let sourceButton = UIButton(type: .system)
    let episodeButton = UIButton(type: .system)
    let nextButton = UIButton(type: .system)
    var next: (() -> Void)?
    var fullScreenChanged: ((Bool) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        for (button, title) in [(sourceButton, "线路"), (episodeButton, "选集"), (nextButton, "下一集")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13)
            button.tintColor = .white; button.accessibilityLabel = title
            toolBar.addArrangedSubview(button)
        }
        sourceButton.showsMenuAsPrimaryAction = true
        episodeButton.showsMenuAsPrimaryAction = true
        nextButton.addAction(UIAction { [weak self] _ in self?.next?() }, for: .touchUpInside)
        sourceButton.isHidden = true; episodeButton.isHidden = true; nextButton.isHidden = true
        toolBar.pipButton.isHidden = true
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isUserInteractionEnabled = false
        statusLabel.isHidden = true
        addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateUI(isFullScreen: Bool) {
        var responder: UIResponder? = next
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard responder is UIViewController else { return }
        fullScreenChanged?(isFullScreen)
        super.updateUI(isFullScreen: isFullScreen)
    }
    override func updateUI(isLandscape: Bool) {
        super.updateUI(isLandscape: isLandscape)
        sourceButton.isHidden = !isLandscape; episodeButton.isHidden = !isLandscape
        nextButton.isHidden = !isLandscape; toolBar.pipButton.isHidden = true
    }
}

@MainActor
struct NativePlayer: UIViewRepresentable {
    let controller: PlayerController
    func makeUIView(context: Context) -> UIView { controller.host }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
