import Foundation

/// Current-video preloading and opening the panel share one first-page request.
/// Keep this cache on the bridge so account reloads discard pending results too.
@MainActor
final class DYCommentFirstPageCache {
    typealias Page = (items: [DYComment], cursor: Int, hasMore: Bool, total: Int)
    private struct Slot {
        let token: UUID
        let created: Date
        let task: Task<Page, Error>
        var completed: Page?
    }
    private var slots: [String: Slot] = [:]
    private var order: [String] = []
    private let limit = 20

    /// 面板首帧同步读取已预加载的评论，避免先弹空面板、再插入文字。
    func snapshot(_ id: String) -> Page? {
        guard let slot = slots[id], Date().timeIntervalSince(slot.created) < 300 else { return nil }
        return slot.completed
    }

    func page(_ id: String, load: @escaping @MainActor () async throws -> Page) async throws -> Page {
        if let slot = slots[id], Date().timeIntervalSince(slot.created) < 300 {
            order.removeAll { $0 == id }; order.append(id)
            return try await slot.task.value
        }
        let token = UUID()
        let task = Task { @MainActor in try await load() }
        slots[id] = Slot(token: token, created: Date(), task: task)
        order.removeAll { $0 == id }; order.append(id)
        while order.count > limit { slots[order.removeFirst()] = nil }
        do {
            let page = try await task.value
            // 切换账号或缓存被淘汰后，旧请求不得补回已完成的数据。
            if slots[id]?.token == token { slots[id]?.completed = page }
            return page
        } catch {
            if slots[id]?.token == token {
                slots[id] = nil
                order.removeAll { $0 == id }
            }
            throw error
        }
    }

    func clear() {
        for slot in slots.values { slot.task.cancel() }
        slots.removeAll()
        order.removeAll()
    }
}
