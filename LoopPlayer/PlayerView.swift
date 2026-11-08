import AVFoundation
import SwiftUI

/// 播放页：头部 < 返回；单击屏幕暂停/播放；双指放大全屏、缩小退出全屏
struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.presentationMode) private var presentation
    @State private var fullscreen = false
    @State private var pinchValue: CGFloat = 1
    @State private var timelineVisible = false
    @State private var hideTimelineTask: DispatchWorkItem?
    /// 全屏状态变化回调（宿主控制器据此淡化 Home 小白条）
    var onFullscreenChanged: ((Bool) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.edgesIgnoringSafeArea(.all)

            VideoSurface(player: model.queue, fill: fullscreen)
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture { model.togglePlay() }
                .gesture(
                    MagnificationGesture()
                        .onChanged { pinchValue = $0 }
                        .onEnded { value in
                            if value > 1.15 {
                                fullscreen = true
                            } else if value < 0.85 {
                                fullscreen = false
                            }
                            pinchValue = 1
                            onFullscreenChanged?(fullscreen)
                        }
                )
                // 横滑=调进度（约每 10pt = 1 秒）；单独播放时竖滑=切换上/下一条（全屏下同样生效）
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onChanged { value in
                            if abs(value.translation.width) >= abs(value.translation.height) {
                                flashTimeline()
                            }
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if !model.listLoop && abs(dy) > abs(dx) {
                                if dy < -60 { model.next() } else if dy > 60 { model.previous() }
                            } else {
                                model.seekRelative(dx / 10.0)
                                flashTimeline()
                            }
                        }
                )

            if !fullscreen {
                header
            }

            VStack {
                Spacer()
                if !fullscreen || timelineVisible {
                    progressBar
                        .transition(.opacity)
                }
            }

            if model.failed {
                VStack(spacing: 8) {
                    Text("该视频暂时无法播放")
                        .font(.headline)
                    Text("可能存储在 iCloud 且当前网络不可用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(white: 0.15))
                .cornerRadius(12)
                .offset(y: 120)
            }
        }
        .onDisappear { model.stop() }
    }

    // MARK: - 全屏下滑动时临时显示时间轴，2 秒后自动隐藏

    private func flashTimeline() {
        guard fullscreen else { return }
        withAnimation(.easeInOut(duration: 0.2)) { timelineVisible = true }
        hideTimelineTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.3)) { timelineVisible = false }
        }
        hideTimelineTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 90)

            Button(action: { presentation.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 6)
            .padding(.top, 2)
        }
        .edgesIgnoringSafeArea(.top)
    }

    // MARK: - 底部进度条

    @ViewBuilder
    private var progressBar: some View {
        if model.duration > 0 {
            VStack(spacing: 2) {
                SlimSlider(
                    value: Binding(
                        get: { min(model.currentTime, model.duration) },
                        set: { newValue in
                            model.isScrubbing = true
                            model.currentTime = newValue
                        }
                    ),
                    range: 0...model.duration,
                    onCommit: {
                        model.seek(to: model.currentTime)
                        model.isScrubbing = false
                    }
                )
                HStack {
                    Text(timeString(model.currentTime))
                    Spacer()
                    Text(timeString(model.duration))
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 细进度条：12pt 圆点 thumb（约为系统 Slider 的一半），拖动即时更新
struct SlimSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let frac = span > 0 ? (value - range.lowerBound) / span : 0
            let x = min(max(frac, 0), 1) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.green)
                    .frame(width: x, height: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 1)
                    .offset(x: x - 6)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(max(v.location.x / max(width, 1), 0), 1)
                        value = range.lowerBound + f * span
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 24)
    }
}

/// AVPlayerLayer 视频显示面
struct VideoSurface: UIViewRepresentable {
    let player: AVQueuePlayer
    let fill: Bool

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// 播放页宿主控制器：全屏时声明自动隐藏 Home 小白条（系统会在交互期间淡化，底部上滑仍会唤回）
final class PlayerHostingController: UIHostingController<PlayerView> {
    var immersive = false {
        didSet {
            if oldValue != immersive { setNeedsUpdateOfHomeIndicatorAutoHidden() }
        }
    }
    override var prefersHomeIndicatorAutoHidden: Bool { immersive }
}

/// 替代 fullScreenCover：用 PlayerHostingController 呈现播放页，以便控制小白条
struct PlayerPresenter: UIViewControllerRepresentable {
    @Binding var request: PlayRequest?

    func makeUIViewController(context: Context) -> PlayerPresenterVC {
        PlayerPresenterVC()
    }

    func updateUIViewController(_ uiViewController: PlayerPresenterVC, context: Context) {
        uiViewController.sync(request: request)
    }
}

final class PlayerPresenterVC: UIViewController {
    private var hosted: PlayerHostingController?
    private var currentID: UUID?

    func sync(request: PlayRequest?) {
        guard let req = request, currentID != req.id else { return }
        currentID = req.id
        let model = PlayerModel(assets: req.assets, startIndex: req.startIndex, listLoop: req.listLoop)
        let view = PlayerView(model: model) { [weak self] immersive in
            self?.hosted?.immersive = immersive
        }
        if let host = hosted {
            host.rootView = view
            if host.presentingViewController == nil { present(host, animated: true) }
        } else {
            let host = PlayerHostingController(rootView: view)
            host.modalPresentationStyle = .fullScreen
            hosted = host
            present(host, animated: true)
        }
    }
}
