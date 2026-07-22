import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count == 3, let x = Double(a[1]), let y = Double(a[2]) else { print("need x y"); exit(1) }
let p = CGPoint(x: x, y: y)
for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
  let btn: CGMouseButton = .left
  if let ev = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: btn) { ev.post(tap: .cghidEventTap) }
  usleep(60000)
}
print("clicked \(x),\(y)")
