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
    ///
    /// The icons are measured from the bar macOS actually reserves, like `height`: the icon
    /// size setting can say 64 while macOS shrinks a full Dock's icons to fit the screen.
    /// The setting is only used when the Dock auto-hides or sits on a side.
    public static func contentScale(screen: CGRect, visible: CGRect, tileSize: Double?) -> Double {
        let reserved = visible.minY - screen.minY
        let icons = reserved > 20 ? reserved - reservedOverBar - barOverIcons : (tileSize ?? defaultTileSize)
        return min(max(icons / defaultTileSize, 0.75), 1.5)
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

/// The six places the widget snaps to.
public enum SnapPoint: String, Codable, CaseIterable, Sendable {
    case bottomRight, bottomLeft, topRight, topLeft, rightMiddle, leftMiddle
}

/// Where the owner put the widget: snapped to one of the six points, or dropped anywhere.
public enum WidgetSpot: Codable, Equatable, Sendable {
    case snapped(SnapPoint)
    case free(WidgetOffset)
}

public enum LayoutChoice: String, Codable, CaseIterable, Sendable {
    case automatic, horizontal, vertical
}

public enum WidgetLayout {
    /// Automatic is vertical on the left and right edges, like a side Dock, and horizontal
    /// everywhere else.
    public static func isVertical(spot: WidgetSpot?, choice: LayoutChoice) -> Bool {
        switch choice {
        case .horizontal: return false
        case .vertical: return true
        case .automatic:
            guard case .snapped(let point)? = spot else { return false }
            return point == .rightMiddle || point == .leftMiddle
        }
    }

    /// The owner's size setting, as a multiple of the Dock-matched size.
    public static func clampSize(_ scale: Double) -> Double { min(max(scale, 0.6), 2) }
}

public enum WidgetPlacement {
    /// The widget's origin for a spot (nil means bottom right), pulled fully on screen. The
    /// bottom corners sit beside a bottom Dock at its height; everything else stays inside
    /// the visible frame, so menu bar and side Docks are never covered.
    public static func origin(size: CGSize, screen: CGRect, visible: CGRect, spot: WidgetSpot?) -> CGPoint {
        let dockAtBottom = visible.minY > screen.minY + 1
        let bottom = dockAtBottom ? screen.minY + 6 : visible.minY + 12
        let point: CGPoint
        switch spot {
        case .free(let saved)?:
            point = CGPoint(x: screen.maxX - saved.right - size.width, y: screen.minY + saved.bottom)
        case .snapped(.bottomLeft)?:
            point = CGPoint(x: visible.minX + 12, y: bottom)
        case .snapped(.topRight)?:
            point = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12)
        case .snapped(.topLeft)?:
            point = CGPoint(x: visible.minX + 12, y: visible.maxY - size.height - 12)
        case .snapped(.rightMiddle)?:
            point = CGPoint(x: visible.maxX - size.width - 6, y: visible.midY - size.height / 2)
        case .snapped(.leftMiddle)?:
            point = CGPoint(x: visible.minX + 6, y: visible.midY - size.height / 2)
        case .snapped(.bottomRight)?, nil:
            point = CGPoint(x: visible.maxX - size.width - 12, y: bottom)
        }
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - size.width),
                       y: min(max(point.y, screen.minY), screen.maxY - size.height))
    }

    /// The snap point a drop lands on: a corner when the widget is within 60 pt of where it
    /// would sit there, or a side when it's within 60 pt of that edge and near its middle.
    public static func snap(frame: CGRect, screen: CGRect, visible: CGRect) -> SnapPoint? {
        for corner in [SnapPoint.bottomRight, .bottomLeft, .topRight, .topLeft] {
            let spot = origin(size: frame.size, screen: screen, visible: visible, spot: .snapped(corner))
            if hypot(spot.x - frame.minX, spot.y - frame.minY) <= 60 { return corner }
        }
        for side in [SnapPoint.rightMiddle, .leftMiddle] {
            let spot = origin(size: frame.size, screen: screen, visible: visible, spot: .snapped(side))
            if abs(spot.x - frame.minX) <= 60, abs(frame.midY - visible.midY) <= visible.height * 0.25 { return side }
        }
        return nil
    }

    public static func offset(origin: CGPoint, size: CGSize, screen: CGRect) -> WidgetOffset {
        WidgetOffset(right: screen.maxX - (origin.x + size.width), bottom: origin.y - screen.minY)
    }

    /// The panel opens toward the middle of the screen. Beside a vertical widget on a side;
    /// otherwise above it when it fits there (or there's more room above), else below, lined
    /// up with the widget's outer edge. It stays 8 pt inside the screen and shrinks to fit.
    public static func panelFrame(panel: CGSize, widget: CGRect, visible: CGRect) -> CGRect {
        let onLeft = widget.midX < visible.midX
        if widget.height > widget.width {
            let height = min(panel.height, visible.height - 16)
            let x = onLeft ? widget.maxX + 8 : widget.minX - 8 - panel.width
            let y = min(max(widget.midY - height / 2, visible.minY + 8), visible.maxY - height - 8)
            return CGRect(x: x, y: y, width: panel.width, height: height)
        }
        let above = visible.maxY - (widget.maxY + 8) - 8
        let below = (widget.minY - 8) - (visible.minY + 8)
        let aligned = onLeft ? widget.minX : widget.maxX - panel.width
        let x = min(max(aligned, visible.minX + 8), visible.maxX - panel.width - 8)
        if above >= panel.height || above >= below {
            return CGRect(x: x, y: widget.maxY + 8, width: panel.width, height: min(panel.height, above))
        }
        let height = min(panel.height, below)
        return CGRect(x: x, y: widget.minY - 8 - height, width: panel.width, height: height)
    }
}
