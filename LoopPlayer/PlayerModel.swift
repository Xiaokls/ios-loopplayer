import AVFoundation
import Photos

/// 播放队列模型。
/// listLoop = true：多选连播。AVQueuePlayer 滑动窗口预取（始终保持 2 个就绪条目入队），
/// 播完自动无缝衔接下一条，列表末尾回到开头无限循环。
/// listLoop = false：单文件无限循环（单击播放），上下滑切换相邻条目。
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
    private var timeObserver: Any?
    private var stopped = false

    // 连播预取状态（insertCursor 为已入队绝对计数，跨圈循环）
    private var readyItems: [Int: AVPlayerItem] = [:]
    private var inFlight: Set<Int> = []
    private var insertCursor = 0
    private var generation = 0

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
            if self.listLoop { self.fillQueue() }
        }
        if listLoop && assets.count > 1 {
            startList()
        } else {
            loadCurrent()
        }
    }

    deinit {
        queue.pause()
        if let to = timeObserver { queue.removeTimeObserver(to) }
    }

    /// 退出播放页时调用：停止并释放队列，防止音频挂死
    func stop() {
        stopped = true
        generation += 1
        readyItems.removeAll()
        inFlight.removeAll()
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

    /// 单独播放模式下相邻条目的资源（供竖滑跟手时露出封面预览）
    func adjacent(_ delta: Int) -> PHAsset? {
        guard !listLoop, assets.count > 1 else { return nil }
        return assets[(index + delta + assets.count) % assets.count]
    }

    func togglePlay() {
        if isPlaying {
            queue.pause()
        } else {
            queue.play()
        }
        isPlaying.toggle()
    }

    // MARK: - 连播：滑动窗口预取

    private func startList() {
        generation += 1
        readyItems.removeAll()
        inFlight.removeAll()
        insertCursor = 0
        failed = false
        fillQueue()
        queue.play()
        isPlaying = true
    }

    /// 保持队列里始终有 2 个就绪条目；播完的条目由 AVQueuePlayer 自动移除并无缝接上
    private func fillQueue() {
        guard !stopped, listLoop, assets.count > 1 else { return }
        while queue.items().count < 2 {
            let key = insertCursor
            if let item = readyItems.removeValue(forKey: key) {
                queue.insert(item, after: nil)
                insertCursor += 1
            } else {
                prefetch(key: key)
                break
            }
        }
    }

    private func prefetch(key: Int) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let asset = assets[key % assets.count]
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true   // iCloud 视频允许联网取流
        let gen = generation
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
            DispatchQueue.main.async {
                guard let self = self, !self.stopped, self.generation == gen else { return }
                self.inFlight.remove(key)
                guard let avAsset = avAsset else {
                    self.failed = true
                    return
                }
                self.readyItems[key] = AVPlayerItem(asset: avAsset)
                self.fillQueue()
            }
        }
    }

    // MARK: - 单曲循环

    private func loadCurrent() {
        guard index >= 0, index < assets.count else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
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
                self.looper = AVPlayerLooper(player: self.queue, templateItem: item)
                self.queue.play()
                self.isPlaying = true
            }
        }
    }

    private func reset() {
        looper = nil
        queue.removeAllItems()
        currentTime = 0
        duration = 0
    }
}
