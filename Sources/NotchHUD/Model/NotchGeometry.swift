import CoreGraphics

enum NotchGeometry {
    /// The physical notch cutout rect from a screen's auxiliary areas.
    /// Returns nil when there is no notch (no valid aux gap).
    static func notchRect(
        auxLeftMaxX: CGFloat?,
        auxRightMinX: CGFloat?,
        frameMaxY: CGFloat,
        safeTop: CGFloat
    ) -> CGRect? {
        guard
            let auxLeftMaxX,
            let auxRightMinX,
            auxRightMinX > auxLeftMaxX
        else {
            return nil
        }

        return CGRect(
            x: auxLeftMaxX,
            y: frameMaxY - safeTop,
            width: auxRightMinX - auxLeftMaxX,
            height: safeTop
        )
    }

    /// Widened trigger zone covering the visible peek beside the cutout.
    static func hitRect(
        from notchRect: CGRect,
        sideMargin: CGFloat,
        bottomExtra: CGFloat
    ) -> CGRect {
        CGRect(
            x: notchRect.minX - sideMargin,
            y: notchRect.minY - bottomExtra,
            width: notchRect.width + (sideMargin * 2),
            height: notchRect.height + bottomExtra
        )
    }

    /// Fallback centered rect when there is no notch.
    static func fallbackRect(
        frameMidX: CGFloat,
        frameMaxY: CGFloat,
        visibleMaxY: CGFloat,
        width: CGFloat
    ) -> CGRect {
        let height = max(frameMaxY - visibleMaxY, 32)
        return CGRect(
            x: frameMidX - (width / 2),
            y: frameMaxY - height,
            width: width,
            height: height
        )
    }

    /// Expanded-content hit region (for keeping the panel open while the pointer is over it).
    static func expandedContentRect(
        frameMidX: CGFloat,
        frameMaxY: CGFloat,
        notchHeight: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let totalHeight = height + notchHeight
        return CGRect(
            x: frameMidX - (width / 2),
            y: frameMaxY - totalHeight,
            width: width,
            height: totalHeight
        )
    }
}
