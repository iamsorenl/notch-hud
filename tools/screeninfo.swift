import AppKit
for s in NSScreen.screens {
  print("frame=\(s.frame) safeTop=\(s.safeAreaInsets.top) auxL=\(String(describing:s.auxiliaryTopLeftArea)) auxR=\(String(describing:s.auxiliaryTopRightArea))")
}
