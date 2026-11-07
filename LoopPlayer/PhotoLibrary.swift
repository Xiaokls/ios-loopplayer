import Photos
import UIKit
import SwiftUI

/// 相册条目。collection 为 nil 表示伪相册「全部视频」
struct AlbumItem {
    let title: String
    let collection: PHAssetCollection?
}

enum PhotoLib {

    /// 只含视频的筛选选项，按拍摄时间倒序
    static func videoOptions() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return o
    }

    /// 获取相册列表：全部视频 + 用户自建相册（仅含有视频的）
    static func fetchAlbums() -> [AlbumItem] {
        var result: [AlbumItem] = []

        let allCount = PHAsset.fetchAssets(with: .video, options: nil).count
        if allCount > 0 {
            result.append(AlbumItem(title: "全部视频", collection: nil))
        }

        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { col, _, _ in
            let videos = PHAsset.fetchAssets(in: col, options: videoOptions())
            if videos.count > 0 {
                result.append(AlbumItem(title: col.localizedTitle ?? "未命名", collection: col))
            }
        }
        return result
    }

    /// 获取某相册内全部视频资源
    static func fetchVideos(in album: AlbumItem) -> [PHAsset] {
        var assets: [PHAsset] = []
        let result: PHFetchResult<PHAsset>
        if let col = album.collection {
            result = PHAsset.fetchAssets(in: col, options: videoOptions())
        } else {
            result = PHAsset.fetchAssets(with: .video, options: videoOptions())
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
