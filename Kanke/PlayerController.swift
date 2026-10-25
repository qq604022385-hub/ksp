import SwiftUI
import AVKit
import KankeCore

@MainActor
final class PlayerController: ObservableObject {
    let player = AVPlayer()
    @Published var buffering = false
    @Published var error: String?
    private var status: NSKeyValueObservation?
    private var timeToken: Any?
    private var endToken: NSObjectProtocol?
    private var failureToken: NSObjectProtocol?
    private var progress: ((Double, Double) -> Void)?
    private var identity = UUID()
    var onEnd: (() -> Void)?
    var speed: Float = 1

    func load(_ media: PlaybackResponse, resume: Double = 0, progress: @escaping (Double, Double) -> Void) {
        stop()
        self.progress = progress
        let token = UUID(); identity = token
        error = nil; buffering = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // Forward service-specified media headers. Device/CDN behavior is verified separately.
        var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": media.headers]
        if let agent = media.headers["User-Agent"] { options[AVURLAssetHTTPUserAgentKey] = agent }
        let asset = AVURLAsset(url: media.url, options: options)
        let item = AVPlayerItem(asset: asset)
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        status = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.identity == token else { return }
                if item.status == .failed {
                    self.buffering = false
                    self.error = item.error?.localizedDescription ?? "播放失败，请尝试其他线路"
                } else if item.status == .readyToPlay {
                    self.buffering = false
                    if resume > 3 && resume.isFinite {
                        self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.identity == token else { return }
                                self.player.playImmediately(atRate: self.speed)
                            }
                        }
                    } else { self.player.playImmediately(atRate: self.speed) }
                }
            }
        }
        timeToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProgress() }
        }
        endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProgress(); self?.onEnd?() }
        }
        failureToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in self?.error = message ?? "视频连接中断，请重试或切换线路" }
        }
    }
    func saveProgress() {
        let seconds = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        if seconds.isFinite && seconds > 0 { progress?(seconds, duration.isFinite ? duration : 0) }
    }
    func stop() {
        saveProgress(); progress = nil
        onEnd = nil
        identity = UUID(); player.pause(); status = nil
        if let timeToken { player.removeTimeObserver(timeToken); self.timeToken = nil }
        if let endToken { NotificationCenter.default.removeObserver(endToken); self.endToken = nil }
        if let failureToken { NotificationCenter.default.removeObserver(failureToken); self.failureToken = nil }
        player.replaceCurrentItem(with: nil)
        buffering = false
    }
}

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
