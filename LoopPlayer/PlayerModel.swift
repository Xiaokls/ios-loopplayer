import AVFoundation
import Photos

/// 播放队列模型。
/// listLoop = true：按队列顺序连播，最后一个播完自动回到第一个（多选播放）
/// listLoop = false：单文件无限循环（单击播放）
final class PlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var failed = false

    let queue = AVQueuePlayer()

    private let assets: [PHAsset]
    private var index: Int
    private let listLoop: Bool
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?

    init(assets: [PHAsset], startIndex: Int, listLoop: Bool) {
        self.assets = assets
        self.index = startIndex
        self.listLoop = listLoop
        loadCurrent()
    }

    deinit {
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
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
                guard let self = self else { return }
                guard let avAsset = avAsset else {
                    self.failed = true
                    return
                }
                self.failed = false
                self.reset()

                let item = AVPlayerItem(asset: avAsset)
                if self.listLoop {
                    self.queue.insert([item], at: 0)
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
    }
}
