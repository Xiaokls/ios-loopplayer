import AVFoundation
import SwiftUI

/// 播放页：头部 < 返回；单击屏幕暂停/播放；双指放大全屏、缩小退出全屏
struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.presentationMode) private var presentation
    @State private var fullscreen = false
    @State private var pinchValue: CGFloat = 1

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
                        }
                )

            header

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
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 90)

            Button(action: { presentation.wrappedValue.dismiss() }) {
                Text("<")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 8)
            .padding(.top, 2)
        }
        .edgesIgnoringSafeArea(.top)
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
