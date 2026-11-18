#!/usr/bin/env python3
"""Check production centered video geometry across outer, inner and split viewports."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "DouDuo/DYVideoFit.swift").read_text()
checks = r'''
let viewports = [CGSize(width: 466, height: 678), CGSize(width: 669, height: 951),
                 CGSize(width: 430, height: 800), CGSize(width: 951, height: 669),
                 CGSize(width: 390, height: 360)]
for viewport in viewports {
    for aspect in [0.25, 0.4, 9.0 / 16, 1.0, 16.0 / 9, 2.39] {
        for fill in [false, true] {
            let frame = DYVideoFit.contentFrame(container: viewport, videoAspect: aspect, fillWidth: fill)
            precondition(abs(frame.midX - viewport.width / 2) < 0.001)
            precondition(abs(frame.midY - viewport.height / 2) < 0.001)
            precondition(frame.minX >= -0.001 && frame.minY >= -0.001)
            precondition(frame.maxX <= viewport.width + 0.001 && frame.maxY <= viewport.height + 0.001)
            let mode = DYVideoFit.presentation(fillWidth: fill, videoAspect: aspect,
                                              screenAspect: viewport.width / viewport.height)
            if mode == .aspectFit {
                precondition(abs(frame.width / frame.height - aspect) < 0.001)
            } else {
                precondition(frame == CGRect(origin: .zero, size: viewport))
            }
        }
    }
}
let narrow = DYVideoFit.contentFrame(container: viewports[0], videoAspect: 0.25, fillWidth: false)
precondition(narrow.minX > 0)
precondition(abs(narrow.minX - (viewports[0].width - narrow.maxX)) < 0.001)
print("PASS tall videos retain equal side margins; fill/fit masks stay centered across viewports")

let outer = CGRect(x: 0, y: 0, width: 466, height: 678)
for bounds: ClosedRange<CGFloat> in [0...382, 84...466, 20...382] {
    for aspect in [0.25, 9.0 / 16, 1.0, 16.0 / 9] {
        let fitted = DYVideoFit.contentSize(container: outer.size, videoAspect: aspect, fillWidth: false)
        let placement = DYVideoFit.chromePlacement(viewport: outer, fitted: fitted,
                                                  horizontalBounds: bounds, fillWidth: false)
        let center = outer.midX + placement.offset.width
        let width = fitted.width * placement.scale
        precondition(abs(center - (bounds.lowerBound + bounds.upperBound) / 2) < 0.001)
        precondition(center - width / 2 >= bounds.lowerBound - 0.001)
        precondition(center + width / 2 <= bounds.upperBound + 0.001)
        precondition(fitted.height * placement.scale <= outer.height + 0.001)
        precondition(placement.scale > 0 && placement.scale <= 1)
        let fill = DYVideoFit.chromePlacement(viewport: outer, fitted: fitted,
                                             horizontalBounds: bounds, fillWidth: true)
        precondition(fill.scale == 1 && fill.offset == .zero)
        let noChrome = DYVideoFit.chromePlacement(viewport: outer, fitted: fitted,
                                                 horizontalBounds: nil, fillWidth: false)
        precondition(noChrome.scale == 1 && noChrome.offset == .zero)
    }
}
let insetViewport = CGRect(x: 20, y: 80, width: 362, height: 598)
let insetFit = DYVideoFit.contentSize(container: insetViewport.size, videoAspect: 9.0 / 16, fillWidth: false)
let alreadyInset = DYVideoFit.chromePlacement(viewport: insetViewport, fitted: insetFit,
                                             horizontalBounds: 20...382, fillWidth: false)
precondition(alreadyInset.scale == 1 && alreadyInset.offset == .zero)
let invalid = DYVideoFit.chromePlacement(viewport: outer, fitted: .zero,
                                        horizontalBounds: 0...382, fillWidth: false)
precondition(invalid.scale == 1 && invalid.offset == .zero)
print("PASS complete image fits beside either rail; fill and already-inset players keep their geometry")
'''
with tempfile.TemporaryDirectory(prefix="douduo-video-alignment-") as temporary:
    script = Path(temporary) / "main.swift"
    script.write_text(source + "\n" + checks)
    subprocess.run(["swift", str(script)], check=True)

layout = (root / "DouDuo/DouyinDuoLayout.swift").read_text()
app = (root / "DouDuo/DouDuoApp.swift").read_text()
assert ".onHingeChange" in layout and "context.hinge?.status == .closed" in layout
assert ".modifier(DYHingeStateRoot())" in app
print("PASS shared hinge state remains at app root")
