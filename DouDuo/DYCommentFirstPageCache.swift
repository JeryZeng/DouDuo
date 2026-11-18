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
    }
    private var slots: [String: Slot] = [:]
    private var order: [String] = []
    private let limit = 20

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
            return try await task.value
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
