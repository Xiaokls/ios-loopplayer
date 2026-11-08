import AVFoundation
import Photos

/// 播放队列模型。
/// listLoop = true：按队列顺序连播，最后一个播完自动回到第一个（多选播放）
/// listLoop = false：单文件无限循环（单击播放）
final class PlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var failed = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    /// 用户拖动进度条时暂停观察器覆盖 currentTime
    var isScrubbing = false

    let queue = AVQueuePlayer()

    private let assets: [PHAsset]
    private var index: Int
    let listLoop: Bool
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var stopped = false

    init(assets: [PHAsset], startIndex: Int, listLoop: Bool) {
        self.assets = assets
        self.index = startIndex
        self.listLoop = listLoop
        timeObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            guard let self = self else { return }
            if !self.isScrubbing { self.currentTime = CMTimeGetSeconds(t) }
            if let item = self.queue.currentItem {
                let d = CMTimeGetSeconds(item.duration)
                if d.isFinite && d > 0 { self.duration = d }
            }
        }
        loadCurrent()
    }

    deinit {
        queue.pause()
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        if let to = timeObserver { queue.removeTimeObserver(to) }
    }

    /// 退出播放页时调用：停止并释放队列，防止音频挂死
    func stop() {
        stopped = true
        queue.pause()
        reset()
    }

    /// 跳转到指定秒
    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration - 0.3, 0))
        queue.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    /// 相对当前进度快进/快退（左右滑动用）
    func seekRelative(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    /// 上滑切换下一条（仅单独播放模式）
    func next() { switchRelative(1) }

    /// 下滑切换上一条（仅单独播放模式）
    func previous() { switchRelative(-1) }

    private func switchRelative(_ delta: Int) {
        guard !listLoop, !stopped, assets.count > 1 else { return }
        index = (index + delta + assets.count) % assets.count
        loadCurrent()
    }

    func togglePlay() {
        if isPlaying {
            queue.pause()
        } else {
            queue.play()
        }
        isPlaying.toggle()
    }

    private func loadCurrent() {
        guard index >= 0, index < assets.count else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true   // iCloud 视频允许联网取流
        PHImageManager.default().requestAVAsset(forVideo: assets[index], options: options) { [weak self] avAsset, _, _ in
            DispatchQueue.main.async {
                guard let self = self, !self.stopped else { return }
                guard let avAsset = avAsset else {
                    self.failed = true
                    return
                }
                self.failed = false
                self.reset()

                let item = AVPlayerItem(asset: avAsset)
                if self.listLoop {
                    self.queue.insert(item, after: nil)
                    self.endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                    ) { [weak self] _ in
                        self?.advance()
                    }
                } else {
                    // 单曲无缝循环
                    self.looper = AVPlayerLooper(player: self.queue, templateItem: item)
                }
                self.queue.play()
                self.isPlaying = true
            }
        }
    }

    private func advance() {
        index = (index + 1) % assets.count
        loadCurrent()
    }

    private func reset() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        looper = nil
        queue.removeAllItems()
        currentTime = 0
        duration = 0
    }
}
