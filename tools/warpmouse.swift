import CoreGraphics
import AppKit
// Usage: warpmouse <x> <y>  (top-left origin, global points)
let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else { print("need x y"); exit(1) }
CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
CGAssociateMouseAndMouseCursorPosition(1)
print("warped to \(x),\(y)")
