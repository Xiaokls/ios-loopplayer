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

    /// 把 draggedId 对应的资源移动到 target 之前
    func move(draggedId: String, before target: PHAsset) {
        guard let from = items.firstIndex(where: { $0.localIdentifier == draggedId }) else { return }
        guard items[from].localIdentifier != target.localIdentifier else { return }
        let dragged = items.remove(at: from)
        guard let to = items.firstIndex(where: { $0.localIdentifier == target.localIdentifier }) else {
            items.insert(dragged, at: min(from, items.count))
            return
        }
        items.insert(dragged, at: to)
    }

    func clear() { items.removeAll() }
}
