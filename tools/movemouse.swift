import CoreGraphics
import Foundation
// Post a REAL mouseMoved event (moves cursor AND notifies monitors). Args: x y (top-left global)
let a = CommandLine.arguments
guard a.count == 3, let x = Double(a[1]), let y = Double(a[2]) else { print("need x y"); exit(1) }
let p = CGPoint(x: x, y: y)
if let ev = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) {
  ev.post(tap: .cghidEventTap)
}
print("moved to \(x),\(y)")
