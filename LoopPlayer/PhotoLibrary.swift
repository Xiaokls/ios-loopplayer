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

    /// 只含视频的筛选选项，按拍摄时间倒序；hiddenOnly=true 时只取隐藏视频
    static func videoOptions(hiddenOnly: Bool = false) -> PHFetchOptions {
        let o = PHFetchOptions()
        if hiddenOnly {
            o.predicate = NSPredicate(format: "mediaType = %d AND isHidden = 1", PHAssetMediaType.video.rawValue)
        } else {
            o.predicate = NSPredicate(format: "mediaType = %d AND isHidden = 0", PHAssetMediaType.video.rawValue)
        }
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return o
    }

    /// 获取相册列表：最近项目 + 用户自建相册 + 已隐藏（独立目录，列末）
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

        // 「已隐藏」独立目录：Photos 框架没有隐藏相册集合，用 isHidden 谓词构造伪相册（始终显示）
        result.append(AlbumItem(title: "已隐藏", collection: nil, includeHidden: true))
        return result
    }

    /// 获取某相册内全部视频资源
    static func fetchVideos(in album: AlbumItem) -> [PHAsset] {
        var assets: [PHAsset] = []
        let options = videoOptions(hiddenOnly: album.includeHidden)
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

/// 相册/视频缩略图视图
struct ThumbView: View {
    let asset: PHAsset?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.15)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
