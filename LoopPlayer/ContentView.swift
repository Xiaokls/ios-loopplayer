import Photos
import SwiftUI

/// 触发播放的请求
struct PlayRequest: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    let startIndex: Int
    let listLoop: Bool
}

struct ContentView: View {
    @StateObject private var selection = SelectionModel()
    @State private var albums: [AlbumItem] = []
    @State private var albumIndex = 0
    @State private var videos: [PHAsset] = []
    @State private var authDenied = false
    @State private var playRequest: PlayRequest?
    @State private var draggingId: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                grid
            }
            .padding(.bottom, 76) // 给底部栏留出空间

            bottomBar
        }
        .background(Color(white: 0.08))
        .onAppear(perform: bootstrap)
        .fullScreenCover(item: $playRequest) { req in
            PlayerView(model: PlayerModel(
                assets: req.assets,
                startIndex: req.startIndex,
                listLoop: req.listLoop
            ))
        }
    }

    // MARK: - 头部导航：居中相册下拉菜单

    private var header: some View {
        ZStack {
            Color(white: 0.12)
            Menu {
                ForEach(0..<albums.count, id: \.self) { i in
                    Button(albums[i].title) { selectAlbum(i) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(albums.isEmpty ? "相册" : albums[albumIndex].title)
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.primary)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
        }
        .frame(height: 52)
    }

    // MARK: - 视频网格

    private var grid: some View {
        GeometryReader { proxy in
            // 三等分栅格：1px 间距，单元格严格正方形
            let side = floor((proxy.size.width - 4) / 3)
            ScrollView {
                if authDenied {
                    Text("没有相册访问权限\n请到 设置 > 隐私 > 照片 中开启")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(videos, id: \.localIdentifier) { asset in
                            cell(asset, side: side)
                        }
                    }
                    .padding(1)
                }
            }
        }
    }

    private func cell(_ asset: PHAsset, side: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ThumbView(asset: asset)
                .frame(width: side, height: side)
                .clipped()

            // 右上角多选控件：选中为绿色实心圆（无对勾），44pt 点击区
            Button(action: { selection.toggle(asset) }) {
                Image(systemName: selection.contains(asset) ? "circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selection.contains(asset) ? .green : .white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .frame(width: side, height: side)
        .background(Color(white: 0.15))
        .contentShape(Rectangle())
        .onTapGesture { playSingle(asset) } // 单击直接播放该文件
    }

    // MARK: - 底部导航：左侧已选缩略图（可拖拽排序、可滚动），右侧固定播放按钮

    private var bottomBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selection.items, id: \.localIdentifier) { item in
                        ThumbView(asset: item)
                            .frame(width: 52, height: 52)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(white: 0.3), lineWidth: 1)
                            )
                            .onDrag {
                                draggingId = item.localIdentifier
                                return NSItemProvider(object: item.localIdentifier as NSString)
                            }
                            .onDrop(
                                of: ["public.text"],
                                delegate: ReorderDelegate(
                                    target: item,
                                    selection: selection,
                                    draggingId: $draggingId
                                )
                            )
                    }
                }
                .padding(.horizontal, 4)
            }

            Button(action: playSelection) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(selection.items.isEmpty ? Color(white: 0.35) : .green)
            }
            .disabled(selection.items.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background(Color(white: 0.12))
    }

    // MARK: - 行为

    private func playSingle(_ asset: PHAsset) {
        playRequest = PlayRequest(assets: [asset], startIndex: 0, listLoop: false)
    }

    private func playSelection() {
        guard !selection.items.isEmpty else { return }
        // 按缩略图条的顺序连播，最后一个播完回到第一个
        playRequest = PlayRequest(assets: selection.items, startIndex: 0, listLoop: true)
    }

    private func selectAlbum(_ i: Int) {
        guard i < albums.count else { return }
        albumIndex = i
        loadVideos()
    }

    private func loadVideos() {
        let album = albums[albumIndex]
        DispatchQueue.global(qos: .userInitiated).async {
            let list = PhotoLib.fetchVideos(in: album)
            DispatchQueue.main.async { videos = list }
        }
    }

    private func bootstrap() {
        guard albums.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                if status == .denied || status == .restricted {
                    authDenied = true
                    return
                }
                albums = PhotoLib.fetchAlbums()
                if !albums.isEmpty { loadVideos() } // 默认显示第一个相册（全部视频）
            }
        }
    }
}

/// 拖拽排序的落点代理
private struct ReorderDelegate: DropDelegate {
    let target: PHAsset
    let selection: SelectionModel
    @Binding var draggingId: String?

    func dropEntered(info: DropInfo) {
        guard let id = draggingId else { return }
        selection.move(draggedId: id, before: target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}
