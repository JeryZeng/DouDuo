#!/usr/bin/env python3
"""Run the production first-page cache against a local transport, without an account."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = r'''import Foundation
struct DYComment { let id: String }
enum Failure: Error { case rejected }
@main struct Tests {
    @MainActor static func main() async throws {
        var calls = 0
        let cache = DYCommentFirstPageCache()
        func result(_ id: String) -> DYCommentFirstPageCache.Page {
            ([DYComment(id: id)], 20, true, 100)
        }
        func check(_ value: Bool, _ label: String) {
            guard value else { fatalError(label) }
            print("PASS " + label)
        }
        check(cache.snapshot("video") == nil, "未完成预加载时不伪造首帧评论")
        async let preload = cache.page("video") {
            calls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return result("first")
        }
        async let panel = cache.page("video") {
            calls += 1
            return result("duplicate")
        }
        let (a, b) = try await (preload, panel)
        check(calls == 1 && a.items.first?.id == b.items.first?.id,
              "opening during preload shares the pending request")
        let initial = cache.snapshot("video")
        check(initial?.items.first?.id == a.items.first?.id && initial?.cursor == 20 && initial?.total == 100,
              "打开面板可同步读取首帧评论和分页信息，无需再等异步任务")
        let again = try await cache.page("video") { calls += 1; return result("duplicate") }
        check(calls == 1 && again.cursor == 20 && again.hasMore && again.total == 100,
              "completed first page and pagination metadata are reused")
        do { _ = try await cache.page("failure") { throw Failure.rejected } } catch {}
        check(cache.snapshot("failure") == nil, "失败请求不提供首帧快照")
        let retry = try await cache.page("failure") { result("retry") }
        check(retry.items.first?.id == "retry", "preload failure permits a foreground retry")
        _ = try await cache.page("empty") { ([], 0, false, 0) }
        let empty = try await cache.page("empty") { fatalError("empty page refetched") }
        check(empty.items.isEmpty && !empty.hasMore, "empty first page is a cached success")
        cache.clear()
        check(cache.snapshot("video") == nil, "切换账号立即清除首帧快照")
        let refreshed = try await cache.page("video") { calls += 1; return result("new account") }
        check(calls == 2 && refreshed.items.first?.id == "new account", "account reload discards cached pages")
        for i in 0..<21 { _ = try await cache.page("bounded-\(i)") { result("\(i)") } }
        let evicted = try await cache.page("bounded-0") { result("evicted") }
        check(evicted.items.first?.id == "evicted", "cache evicts beyond twenty videos")
        check(cache.snapshot("bounded-1") == nil, "淘汰缓存时同步移除首帧快照")
        let old = Task { @MainActor in
            try await cache.page("switch") {
                try? await Task.sleep(nanoseconds: 50_000_000)
                return result("old")
            }
        }
        await Task.yield()
        cache.clear()
        _ = try await cache.page("switch") { result("fresh") }
        _ = try await old.value
        check(cache.snapshot("switch")?.items.first?.id == "fresh", "旧账号迟到结果不能覆盖新账号首帧")
        let fresh = try await cache.page("switch") { fatalError("fresh result lost") }
        check(fresh.items.first?.id == "fresh", "late old-account result cannot repopulate the cache")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="douduo-comment-preload-") as d:
    d = Path(d)
    (d / "Harness.swift").write_text(harness)
    subprocess.run(["swiftc", "-parse-as-library", str(root / "DouDuo/DYCommentFirstPageCache.swift"),
                    str(d / "Harness.swift"), "-o", str(d / "verify")], check=True)
    subprocess.run([str(d / "verify")], check=True)
