#!/usr/bin/env python3
"""Exercise production panel progress and release decisions without launching a UI."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'DouDuo/DouyinDuoLayout.swift').read_text()
policy = source[source.index('enum DYPanelDismissMotion'):source.index('struct DYSheetDragActions')]
checks = r'''
func check(_ ok: Bool, _ name: String) {
    precondition(ok, name)
    print("PASS " + name)
}
let travel: CGFloat = 400
let translations: [CGFloat] = [0, 80, 160, 200, 160, 80, 0, -40]
let expected: [CGFloat] = [0, 0.2, 0.4, 0.5, 0.4, 0.2, 0, 0]
let actual = translations.map { DYPanelDismissMotion.progress(translation: $0, travel: travel) }
check(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.001 },
      "right swipe follows the finger and reversing left restores the panel immediately")
check(DYPanelDismissMotion.progress(translation: 900, travel: travel) == 1,
      "overshoot stops at fully dismissed")
check(DYPanelDismissMotion.progress(translation: 80, travel: 0) == 0,
      "zero-sized panel never divides by zero")
for extent: CGFloat in [320, 466, 620, 951] {
    check(!DYPanelDismissMotion.closes(translation: extent * 0.3, velocity: 0, travel: extent),
          "short slow release springs back for each panel size")
    check(DYPanelDismissMotion.closes(translation: extent * 0.5, velocity: 0, travel: extent),
          "past-halfway release dismisses for each panel size")
    check(!DYPanelDismissMotion.closes(translation: extent * 0.6, velocity: -800, travel: extent),
          "fast reversal reopens even after crossing the distance threshold")
}
check(DYPanelDismissMotion.closes(translation: 25, velocity: 900, travel: 620),
      "short fast flick dismisses without dragging halfway")
check(!DYPanelDismissMotion.closes(translation: 25, velocity: 150, travel: 620),
      "same short distance at low speed stays open")
check(!DYPanelDismissMotion.closes(translation: 5, velocity: 1200, travel: 620),
      "tiny accidental movement cannot fling the panel away")
check(!DYPanelDismissMotion.closes(translation: -60, velocity: 1200, travel: 620),
      "leftward or upward displacement cannot dismiss")
'''
with tempfile.TemporaryDirectory(prefix='douduo-comment-panel-') as temporary:
    script = Path(temporary) / 'main.swift'
    script.write_text('import Foundation\nimport CoreGraphics\n' + policy + checks)
    subprocess.run(['swift', str(script)], check=True)
