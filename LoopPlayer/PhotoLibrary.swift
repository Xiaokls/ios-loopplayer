import Photos
import UIKit
import SwiftUI

/// 相册条目。collection 为 nil 表示伪相册（「最近项目」或「已隐藏」）
struct AlbumItem {
    let title: String
    let collection: PHAssetCollection?
    /// true 表示「已隐藏」目录：只含隐藏资产；其余目录默认排除隐藏
    var includeHidden: Bool = false
}

enum PhotoLib {

    /// 只含视频的筛选选项，按拍摄时间倒序；includeHidden=true 时不过滤隐藏资产（用于智能相册集合内取视频）
    static func videoOptions(includeHidden: Bool = false) -> PHFetchOptions {
        let o = PHFetchOptions()
        if includeHidden {
            o.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        } else {
            o.predicate = NSPredicate(format: "mediaType = %d AND isHidden = 0", PHAssetMediaType.video.rawValue)
        }
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return o
    }

    /// 获取相册列表：最近项目 + 用户自建相册 + 个人收藏 + 已隐藏（列末）
    static func fetchAlbums() -> [AlbumItem] {
        var result: [AlbumItem] = []

        let recentsCount = PHAsset.fetchAssets(with: .video, options: videoOptions()).count
        if recentsCount > 0 {
            result.append(AlbumItem(title: "最近项目", collection: nil))
        }

        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { col, _, _ in
            let videos = PHAsset.fetchAssets(in: col, options: videoOptions())
            if videos.count > 0 {
                result.append(AlbumItem(title: col.localizedTitle ?? "未命名", collection: col))
            }
        }

        // 枚举全部智能相册，按标题识别「个人收藏」「已隐藏」
        // （公开 SDK 没有 smartAlbumHidden 成员，但隐藏相册确实以智能相册集合形式存在，可直接取其中的资产）
        var favoritesItem: AlbumItem?
        var hiddenItem: AlbumItem?
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smart.enumerateObjects { col, _, _ in
            let title = col.localizedTitle ?? ""
            let isHiddenAlbum = title.contains("隐藏") || title.localizedCaseInsensitiveContains("hidden")
            let isFavorites = !isHiddenAlbum
                && (title.contains("收藏") || title.localizedCaseInsensitiveContains("favorit"))
            guard isHiddenAlbum || isFavorites else { return }
            let videos = PHAsset.fetchAssets(in: col, options: videoOptions(includeHidden: true))
            guard videos.count > 0 else { return }
            // 系统返回的 localizedTitle 可能是英文（Hidden），统一用中文显示名
            let displayTitle = isHiddenAlbum ? "已隐藏" : "个人收藏"
            let item = AlbumItem(title: displayTitle, collection: col, includeHidden: true)
            if isHiddenAlbum { hiddenItem = item } else { favoritesItem = item }
        }

        if let fav = favoritesItem { result.append(fav) }
        if let hid = hiddenItem {
            result.append(hid)
        } else {
            // 兜底：枚举不到隐藏集合时仍常驻显示「已隐藏」（旧 isHidden 谓词伪相册）
            result.append(AlbumItem(title: "已隐藏", collection: nil, includeHidden: true))
        }
        return result
    }

    /// 获取某相册内全部视频资源
    static func fetchVideos(in album: AlbumItem) -> [PHAsset] {
        var assets: [PHAsset] = []
        let options = videoOptions(includeHidden: album.includeHidden)
        let result: PHFetchResult<PHAsset>
        if let col = album.collection {
            result = PHAsset.fetchAssets(in: col, options: options)
        } else {
            result = PHAsset.fetchAssets(with: .video, options: options)
        }
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// 异步取视频资源的第一条（用于封面）
    static func firstVideo(of album: AlbumItem, completion: @escaping (PHAsset?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let videos = fetchVideos(in: album)
            DispatchQueue.main.async { completion(videos.first) }
        }
    }
}

/// 相册/视频缩略图视图。fit=true 时按视频信箱方式显示（等比完整+上下黑边），用于播放页相邻页
struct ThumbView: View {
    let asset: PHAsset?
    var fit: Bool = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            fit ? Color.black : Color(white: 0.15)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard let asset = asset, image == nil else { return }
        let size = CGSize(width: 320, height: 320)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async { self.image = img }
            }
        }
    }
}
