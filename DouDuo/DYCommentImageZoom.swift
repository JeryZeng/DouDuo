import SwiftUI
import UIKit

enum DYCommentImageGesturePolicy {
    /// A deliberate downward flick dismisses; slow inspection drags and
    /// horizontal page changes never do, even when the image is zoomed.
    static func dismisses(translation: CGPoint, velocity: CGPoint) -> Bool {
        translation.y > 20 && translation.y > abs(translation.x) * 1.2
            && velocity.y > 750 && velocity.y > abs(velocity.x) * 1.2
    }

    static func zoomRect(viewport: CGSize, around point: CGPoint, scale: CGFloat) -> CGRect {
        let size = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// UIScrollView keeps the pinch anchor and provides native panning/deceleration.
struct DYCommentZoomImage: View {
    let source: DYCommentImage
    let onDismiss: () -> Void
    @State private var image: UIImage?
    @State private var failed = false

    init(source: DYCommentImage, onDismiss: @escaping () -> Void) {
        self.source = source
        self.onDismiss = onDismiss
        _image = State(initialValue: URL(string: source.full).flatMap { ImageCache.shared.memoryCached($0) })
    }

    var body: some View {
        ZStack {
            if image == nil {
                if failed { Text("图片加载失败").foregroundStyle(.secondary) }
                else { ProgressView() }
            }
            DYCommentZoomSurface(image: image, onDismiss: onDismiss)
        }
        .task(id: source.full) {
            guard image == nil else { return }
            guard let url = URL(string: source.full) else { failed = true; return }
            let loaded = await ImageCache.shared.load(url)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
        .accessibilityLabel("评论图片")
        .accessibilityHint("双指缩放，双击放大或缩小，快速下滑关闭")
        .accessibilityAction(.escape, onDismiss)
    }
}

private struct DYCommentZoomSurface: UIViewRepresentable {
    let image: UIImage?
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> DYCommentZoomScrollView { DYCommentZoomScrollView(frame: .zero) }
    func updateUIView(_ view: DYCommentZoomScrollView, context: Context) {
        view.onDismiss = onDismiss
        view.setImage(image)
    }
}

private final class DYCommentZoomScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let picture = UIImageView()
    private var fittedViewport: CGSize = .zero
    private var closing = false
    var onDismiss: (() -> Void)?
    private lazy var downwardPan = UIPanGestureRecognizer(target: self, action: #selector(flicked(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        picture.contentMode = .scaleAspectFit
        addSubview(picture)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        downwardPan.maximumNumberOfTouches = 1
        downwardPan.delegate = self
        downwardPan.cancelsTouchesInView = false
        addGestureRecognizer(downwardPan)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(_ image: UIImage?) {
        guard picture.image !== image else { return }
        picture.image = image
        fittedViewport = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = picture.image, bounds.width > 0, bounds.height > 0 else { return }
        let resetsViewport = fittedViewport != bounds.size
        if resetsViewport {
            fittedViewport = bounds.size
            setZoomScale(minimumZoomScale, animated: false)
            let ratio = min(bounds.width / max(image.size.width, 1), bounds.height / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            picture.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centerPicture()
        if resetsViewport { contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top) }
    }

    private func centerPicture() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != insets { contentInset = insets }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture.image == nil ? nil : picture }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPicture() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= minimumZoomScale + 0.01 {
            centerPicture()
            setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
        }
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        guard picture.image != nil else { return }
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: picture)
            guard picture.bounds.contains(point) else { return }
            let rect = DYCommentImageGesturePolicy.zoomRect(viewport: bounds.size,
                                                            around: point, scale: 3)
            zoom(to: rect, animated: true)
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === downwardPan {
            let velocity = downwardPan.velocity(in: self)
            return !closing && !isZooming && velocity.y > 0 && velocity.y > abs(velocity.x) * 1.2
        }
        // At fit size there is nothing to pan: let the enclosing pager own
        // horizontal drags. Once zoomed, the scroll view owns detail panning.
        if gestureRecognizer === panGestureRecognizer && zoomScale <= minimumZoomScale + 0.01 { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === downwardPan && other === panGestureRecognizer)
            || (other === downwardPan && gestureRecognizer === panGestureRecognizer)
    }

    @objc private func flicked(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended, !closing, !isZooming,
              DYCommentImageGesturePolicy.dismisses(translation: pan.translation(in: window),
                                                    velocity: pan.velocity(in: window)) else { return }
        closing = true
        onDismiss?()
    }
}
