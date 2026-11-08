import AVFoundation
import Photos

/// 播放队列模型。
/// listLoop = true：多选连播。滑动窗口预取（保持 3 个就绪条目入队，条目 readyToPlay 才入队），
/// 播完自动无缝衔接；时间轴合并为整个列表的总进度，列表末尾回到开头无限循环。
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
    private var itemAssetIdx: [ObjectIdentifier: Int] = [:]
    private var currentAssetIdx = 0
    private var currentItemObs: NSKeyValueObservation?

    // 时间轴合并：每段起始偏移与列表总时长
    private(set) var segStart: [Double] = []
    private(set) var totalDuration: Double = 0
    private var pendingLocalSeek: Double?

    init(assets: [PHAsset], startIndex: Int, listLoop: Bool) {
        self.assets = assets
        self.index = startIndex
        self.listLoop = listLoop
        if listLoop {
            var acc = 0.0
            for a in assets {
                segStart.append(acc)
                acc += max(a.duration, 0)
            }
            totalDuration = acc
        }
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
            currentItemObs = queue.observe(\.currentItem, options: [.old, .new]) { [weak self] q, c in
                guard let self = self else { return }
                if let old = c.oldValue {
                    self.itemAssetIdx.removeValue(forKey: ObjectIdentifier(old))
                }
                if let item = q.currentItem,
                   let idx = self.itemAssetIdx[ObjectIdentifier(item)] {
                    self.currentAssetIdx = idx
                    self.currentTime = 0
                }
            }
            startList()
        } else {
            loadCurrent()
        }
    }

    deinit {
        queue.pause()
        if let to = timeObserver { queue.removeTimeObserver(to) }
        currentItemObs?.invalidate()
    }

    /// 退出播放页时调用：停止并释放队列，防止音频挂死
    func stop() {
        stopped = true
        generation += 1
        readyItems.removeAll()
        inFlight.removeAll()
        pendingLocalSeek = nil
        queue.pause()
        reset()
    }

    // MARK: - 时间轴

    /// 进度条当前值：连播模式=列表全局位置，单播=当前条目位置
    var sliderValue: Double {
        if listLoop {
            return min(globalTime, max(totalDuration, 0))
        }
        return min(currentTime, max(duration, 0))
    }

    /// 进度条总时长：连播模式=列表总时长
    var sliderTotal: Double {
        listLoop ? totalDuration : duration
    }

    private var globalTime: Double {
        let base = currentAssetIdx < segStart.count ? segStart[currentAssetIdx] : 0
        return base + currentTime
    }

    /// 拖动进度条过程中更新显示值
    func setSlider(_ v: Double) {
        if listLoop {
            let base = currentAssetIdx < segStart.count ? segStart[currentAssetIdx] : 0
            currentTime = max(0, v - base)
        } else {
            currentTime = v
        }
    }

    /// 松手提交
    func commitScrub() {
        if listLoop {
            seekGlobal(sliderValue)
        } else {
            seek(to: currentTime)
        }
    }

    /// 跳转到列表全局秒（连播模式）：重建队列从目标条目开始
    func seekGlobal(_ t: Double) {
        guard listLoop, !segStart.isEmpty, !stopped else { return }
        let clamped = min(max(t, 0), max(totalDuration - 0.3, 0))
        var idx = 0
        for (i, s) in segStart.enumerated() where s <= clamped { idx = i }
        let local = clamped - segStart[idx]

        generation += 1
        readyItems.removeAll()
        inFlight.removeAll()
        queue.removeAllItems()
        insertCursor = idx
        currentAssetIdx = idx
        currentTime = local
        pendingLocalSeek = local
        fillQueue()
        queue.play()
        isPlaying = true
    }

    /// 跳转到指定秒（当前条目内）
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
        currentAssetIdx = 0
        failed = false
        fillQueue()
        queue.play()
        isPlaying = true
    }

    /// 保持队列里始终有 3 个就绪条目；播完的条目由 AVQueuePlayer 自动移除并无缝接上
    private func fillQueue() {
        guard !stopped, listLoop, assets.count > 1 else { return }
        while queue.items().count < 3 {
            let key = insertCursor
            if let item = readyItems.removeValue(forKey: key) {
                itemAssetIdx[ObjectIdentifier(item)] = key % assets.count
                queue.insert(item, after: nil)
                insertCursor += 1
                // 重建队列后首条入队：跳到目标位置
                if let local = pendingLocalSeek {
                    queue.seek(to: CMTime(seconds: local, preferredTimescale: 600))
                    pendingLocalSeek = nil
                }
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
                guard let avAsset = avAsset else {
                    self.inFlight.remove(key)
                    self.failed = true
                    return
                }
                self.publish(item: AVPlayerItem(asset: avAsset), key: key, gen: gen)
            }
        }
    }

    /// 条目 readyToPlay 后才进入就绪池，避免切换瞬间队列停顿造成顿挫
    private func publish(item: AVPlayerItem, key: Int, gen: Int) {
        let finish: (AVPlayerItem?) -> Void = { [weak self] ready in
            guard let self = self, !self.stopped, self.generation == gen else { return }
            self.inFlight.remove(key)
            if let ready = ready {
                self.readyItems[key] = ready
                self.fillQueue()
            } else {
                self.failed = true
            }
        }
        switch item.status {
        case .readyToPlay:
            finish(item)
        case .failed:
            finish(nil)
        default:
            var token: NSKeyValueObservation?
            token = item.observe(\.status, options: [.new]) { it, _ in
                if it.status == .readyToPlay {
                    token?.invalidate()
                    finish(it)
                } else if it.status == .failed {
                    token?.invalidate()
                    finish(nil)
                }
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
