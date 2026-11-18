#!/usr/bin/env python3
"""Exercise production flick arbitration and double-tap target geometry; no UI or account."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DouDuo/DYCommentImageZoom.swift').read_text()
policy = source[source.index('enum DYCommentImageGesturePolicy'):source.index('/// UIScrollView keeps')]
checks = r'''
func check(_ ok: Bool, _ name: String) {
    precondition(ok, name)
    print("PASS " + name)
}
func dismiss(_ dx: CGFloat, _ dy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> Bool {
    DYCommentImageGesturePolicy.dismisses(translation: CGPoint(x: dx, y: dy), velocity: CGPoint(x: vx, y: vy))
}
check(dismiss(5, 60, 30, 1000), "quick downward flick exits")
check(!dismiss(0, 240, 0, 150), "long slow inspection drag stays open")
check(!dismiss(200, 30, 1300, 100), "horizontal page gesture stays open")
check(!dismiss(0, -100, 0, -1100), "upward flick stays open")
check(!dismiss(0, 10, 0, 1000), "tiny fast movement stays open")
check(!dismiss(80, 60, 800, 1000), "mostly horizontal travel stays open")
check(!dismiss(0, 60, 1200, 1000), "horizontal release velocity cannot dismiss")
check(!dismiss(0, 60, 0, -1000), "down then up release stays open")
for viewport in [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669)] {
    for point in [CGPoint(x: 30, y: 40), CGPoint(x: 230, y: 500), CGPoint(x: 900, y: 200)] {
        let rect = DYCommentImageGesturePolicy.zoomRect(viewport: viewport, around: point, scale: 3)
        check(abs(rect.midX - point.x) < 0.001 && abs(rect.midY - point.y) < 0.001,
              "double tap anchors its own position")
        check(abs(rect.width * 3 - viewport.width) < 0.001 && abs(rect.height * 3 - viewport.height) < 0.001,
              "double tap requests three-times magnification")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='douduo-image-gestures-') as d:
    script = Path(d) / 'main.swift'
    script.write_text('import Foundation\nimport CoreGraphics\n' + policy + checks)
    subprocess.run(['swift', str(script)], check=True)
