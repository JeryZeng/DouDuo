import SwiftUI
import UIKit

/// 抖音表情包：displayName（"[微笑]"）→ UIImage。
/// 评论和弹幕里的 [微笑] 等标记共用官方表情图。
@MainActor
final class DYEmojiStore: ObservableObject {
    static let shared = DYEmojiStore()
    @Published private(set) var images: [String: UIImage] = [:]
    private var started = false

    func load(bridge: DouyinBridge) async {
        guard !started else { return }
        started = true
        let list = await bridge.emojiList()
        guard !list.isEmpty else { started = false; return }
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for e in list {
                guard let s = e.url, let u = URL(string: s) else { continue }
                group.addTask {
                    guard let (d, _) = try? await URLSession.shared.data(from: u),
                          let img = UIImage(data: d) else { return (e.displayName, nil) }
                    // 缩到正文行高大小（20pt）：Text 里内联图片不会自动缩放，原图直接塞会撑大整行
                    return (e.displayName, Self.scaled(img, toSide: 20))
                }
            }
            // Publish in batches: make early images usable without invalidating
            // the danmaku renderer separately for every completed download.
            var downloaded: [String: UIImage] = [:]
            for await (name, img) in group {
                if let img { downloaded[name] = img }
                if downloaded.count >= 16 {
                    images.merge(downloaded) { _, new in new }
                    downloaded.removeAll(keepingCapacity: true)
                }
            }
            if !downloaded.isEmpty { images.merge(downloaded) { _, new in new } }
        }
        if images.isEmpty { started = false }
    }

    /// 等比缩放到指定边长（pt），供 Text 内联使用
    nonisolated static func scaled(_ img: UIImage, toSide side: CGFloat) -> UIImage {
        let ratio = min(side / max(img.size.width, 1), side / max(img.size.height, 1))
        let size = CGSize(width: max(1, img.size.width * ratio), height: max(1, img.size.height * ratio))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 把 "好[微笑]的" 拼成带表情图的 Text
    func rich(_ s: String) -> Text {
        var out = Text("")
        for (text, image) in segments(s) {
            if let image { out = out + Text(Image(uiImage: image)).baselineOffset(-2) }
            else { out = out + Text(text) }
        }
        return out
    }

    /// The layer renderer measures and draws this same string, including the
    /// attachment widths, so emoji cannot overlap the next danmaku in a lane.
    func attributed(_ s: String, font: UIFont,
                    attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "")
        for (text, image) in segments(s) {
            if let image {
                let side = font.pointSize + 3
                let ratio = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2,
                                           width: size.width, height: size.height)
                let run = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                run.addAttributes(attributes, range: NSRange(location: 0, length: run.length))
                out.append(run)
            } else {
                out.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        return out
    }

    /// Only replace exact names present in the official list. Unknown, malformed
    /// or not-yet-downloaded names remain readable text.
    private func segments(_ s: String) -> [(String, UIImage?)] {
        var out: [(String, UIImage?)] = []
        var buf = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "[", let close = s[i...].firstIndex(of: "]"), s.distance(from: i, to: close) <= 14 {
                let name = String(s[i...close])
                if let img = images[name] {
                    if !buf.isEmpty { out.append((buf, nil)); buf = "" }
                    out.append((name, img))
                    i = s.index(after: close)
                    continue
                }
            }
            buf.append(s[i])
            i = s.index(after: i)
        }
        if !buf.isEmpty { out.append((buf, nil)) }
        return out
    }
}
