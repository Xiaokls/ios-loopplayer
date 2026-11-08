import Foundation
import Photos

/// 多选状态：按选择顺序保存，支持拖拽调整顺序
final class SelectionModel: ObservableObject {
    @Published var items: [PHAsset] = []

    func contains(_ asset: PHAsset) -> Bool {
        items.contains { $0.localIdentifier == asset.localIdentifier }
    }

    func toggle(_ asset: PHAsset) {
        if let idx = items.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            items.remove(at: idx)
        } else {
            items.append(asset)
        }
    }

    /// 把 draggedId 对应的资源移动到 target 所在的槽位：
    /// 从左往右拖落到 target 之后，从右往左拖落到 target 之前（两项互换也能成功）
    func move(draggedId: String, to target: PHAsset) {
        guard let from = items.firstIndex(where: { $0.localIdentifier == draggedId }) else { return }
        guard let slot = items.firstIndex(where: { $0.localIdentifier == target.localIdentifier }),
              from != slot else { return }
        let dragged = items.remove(at: from)
        items.insert(dragged, at: min(slot, items.count))
    }

    func remove(_ asset: PHAsset) {
        items.removeAll { $0.localIdentifier == asset.localIdentifier }
    }

    func clear() { items.removeAll() }
}
