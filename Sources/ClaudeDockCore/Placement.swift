import CoreGraphics
import Foundation

/// How tall the widget should be to match the Dock bar.
public enum DockFit {
    /// The Liquid Glass Dock floats 6 pt above the screen edge and its bar is 8 pt shorter
    /// than the space macOS reserves for it (measured: 90 pt reserved, 82 pt bar, 48 pt icons).
    static let reservedOverBar = 8.0
    static let barOverIcons = 34.0
    static let defaultTileSize = 48.0

    /// The Dock bar's height: from the space it reserves at the bottom of the screen, or from
    /// its icon size when it auto-hides or sits on a side. Kept between 44 and 140 pt.
    public static func height(screen: CGRect, visible: CGRect, tileSize: Double?) -> Double {
        let reserved = visible.minY - screen.minY
        let bar = reserved > 20 ? reserved - reservedOverBar : (tileSize ?? defaultTileSize) + barOverIcons
        return min(max(bar, 44), 140)
    }

    /// How much to scale the widget's contents: with the Dock's icons (48 pt by default), so
    /// the rings sit in the widget the way the icons sit in the Dock, and a taller widget
    /// doesn't also grow wider and run under the Dock. Kept between 0.75 and 1.5.
    public static func contentScale(tileSize: Double?) -> Double {
        min(max((tileSize ?? defaultTileSize) / defaultTileSize, 0.75), 1.5)
    }

}

/// Where the owner dragged the widget, as distances from the screen's right and bottom edges
/// to the widget's right and bottom edges, so the spot survives a resize.
public struct WidgetOffset: Codable, Equatable, Sendable {
    public var right: Double
    public var bottom: Double

    public init(right: Double, bottom: Double) {
        self.right = right
        self.bottom = bottom
    }
}

public enum WidgetPlacement {
    /// The saved spot if there is one (pulled fully on screen), else the bottom-right corner:
    /// beside a bottom Dock at its height, or inside the visible frame for a side or hidden Dock.
    public static func origin(size: CGSize, screen: CGRect, visible: CGRect, saved: WidgetOffset?) -> CGPoint {
        let point: CGPoint
        if let saved {
            point = CGPoint(x: screen.maxX - saved.right - size.width, y: screen.minY + saved.bottom)
        } else {
            let dockAtBottom = visible.minY > screen.minY + 1
            point = CGPoint(x: visible.maxX - size.width - 12, y: dockAtBottom ? screen.minY + 6 : visible.minY + 12)
        }
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - size.width),
                       y: min(max(point.y, screen.minY), screen.maxY - size.height))
    }

    public static func offset(origin: CGPoint, size: CGSize, screen: CGRect) -> WidgetOffset {
        WidgetOffset(right: screen.maxX - (origin.x + size.width), bottom: origin.y - screen.minY)
    }

    /// The panel opens above the widget when it fits there (or there's more room above),
    /// otherwise below; right edges line up, it stays 8 pt inside the screen, and it shrinks
    /// to the room available.
    public static func panelFrame(panel: CGSize, widget: CGRect, visible: CGRect) -> CGRect {
        let above = visible.maxY - (widget.maxY + 8) - 8
        let below = (widget.minY - 8) - (visible.minY + 8)
        let x = min(max(widget.maxX - panel.width, visible.minX + 8), visible.maxX - panel.width - 8)
        if above >= panel.height || above >= below {
            return CGRect(x: x, y: widget.maxY + 8, width: panel.width, height: min(panel.height, above))
        }
        let height = min(panel.height, below)
        return CGRect(x: x, y: widget.minY - 8 - height, width: panel.width, height: height)
    }
}
