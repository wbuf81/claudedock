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

    /// What the Dock shows, from its settings and the running apps: Finder, the pinned apps,
    /// a section of running apps that aren't pinned plus (with recents on) up to 3 recent
    /// ones, the pinned folders, and the Trash. Dividers come before the recent section and
    /// before the folders. Minimized windows can't be counted.
    public static func contents(pinned: [String], recent: [String], running: [String], folders: Int,
                                showRecents: Bool) -> (items: Int, dividers: Int) {
        let pinnedSet = Set(pinned).union(["com.apple.finder"])
        var section = running.filter { !pinnedSet.contains($0) }
        if showRecents { section += recent.filter { !pinnedSet.contains($0) }.prefix(3) }
        let middle = Set(section).count
        return (1 + pinned.count + middle + folders + 1, (middle > 0 ? 1 : 0) + 1)
    }

    /// The Dock's width at the bottom of the screen, estimated from how many items it holds
    /// (apps, folders, minimized windows, the Trash) and how many dividers split them, since
    /// macOS doesn't say: the Dock's window covers the whole screen. nil when the Dock hides
    /// or sits on a side.
    ///
    /// Measured on macOS 26 with a 90 pt reserved band: 68 pt per item, about 30 pt per
    /// divider and 15 pt of padding, so 21 items and 2 dividers made 1503.5 pt. Items scale
    /// with the band, like `height`.
    public static func estimatedWidth(items: Int, dividers: Int, screen: CGRect, visible: CGRect) -> Double? {
        let reserved = visible.minY - screen.minY
        guard reserved > 20 else { return nil }
        let item = reserved - 22
        return min(Double(items) * item + Double(dividers) * item * 0.445 + 15, screen.width)
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

/// The edges that stay put when the compact widget grows to its full size.
public struct GrowthAnchor: Equatable, Sendable {
    public enum Horizontal: Sendable { case left, right }
    public enum Vertical: Sendable { case bottom, top, center }

    public var horizontal: Horizontal
    public var vertical: Vertical

    public init(_ horizontal: Horizontal, _ vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// The side of the widget the crab perches on: the one facing the middle of the screen.
public enum CrabEdge: Equatable, Sendable { case top, bottom, left, right }

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

    /// The owner's size, shrunk only as far as needed for the widget (whose size at scale 1
    /// is `natural`) to fit inside the visible frame with 12 pt to spare on each side.
    public static func fittedScale(_ wanted: Double, natural: CGSize, visible: CGRect) -> Double {
        guard natural.width > 0, natural.height > 0 else { return wanted }
        return min(wanted, (visible.width - 24) / natural.width, (visible.height - 24) / natural.height)
    }
}

public enum WidgetPlacement {
    /// The widget's origin for a spot (nil means bottom right), pulled fully on screen. The
    /// bottom corners sit beside a bottom Dock at its height, or just above it when the Dock
    /// (`dockWidth` wide, centred) reaches the corner; everything else stays inside the
    /// visible frame, so menu bar and side Docks are never covered.
    public static func origin(size: CGSize, screen: CGRect, visible: CGRect, spot: WidgetSpot?,
                              dockWidth: Double? = nil) -> CGPoint {
        func bottom(atX x: Double) -> Double {
            guard visible.minY > screen.minY + 1 else { return visible.minY + 12 }
            guard let dockWidth else { return screen.minY + 6 }
            let besideDock = x >= screen.midX + dockWidth / 2 + 8 || x + size.width <= screen.midX - dockWidth / 2 - 8
            return besideDock ? screen.minY + 6 : visible.minY + 12
        }
        let point: CGPoint
        switch spot {
        case .free(let saved)?:
            point = CGPoint(x: screen.maxX - saved.right - size.width, y: screen.minY + saved.bottom)
        case .snapped(.bottomLeft)?:
            point = CGPoint(x: visible.minX + 12, y: bottom(atX: visible.minX + 12))
        case .snapped(.topRight)?:
            point = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12)
        case .snapped(.topLeft)?:
            point = CGPoint(x: visible.minX + 12, y: visible.maxY - size.height - 12)
        case .snapped(.rightMiddle)?:
            point = CGPoint(x: visible.maxX - size.width - 6, y: visible.midY - size.height / 2)
        case .snapped(.leftMiddle)?:
            point = CGPoint(x: visible.minX + 6, y: visible.midY - size.height / 2)
        case .snapped(.bottomRight)?, nil:
            point = CGPoint(x: visible.maxX - size.width - 12, y: bottom(atX: visible.maxX - size.width - 12))
        }
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - size.width),
                       y: min(max(point.y, screen.minY), screen.maxY - size.height))
    }

    /// The snap point a drop lands on: a corner when the widget is within 60 pt of where it
    /// would sit there, or a side when it's within 60 pt of that edge and near its middle.
    public static func snap(frame: CGRect, screen: CGRect, visible: CGRect, dockWidth: Double? = nil) -> SnapPoint? {
        for corner in [SnapPoint.bottomRight, .bottomLeft, .topRight, .topLeft] {
            let spot = origin(size: frame.size, screen: screen, visible: visible, spot: .snapped(corner), dockWidth: dockWidth)
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

    /// The compact widget grows toward the middle of the screen, so the part under the
    /// pointer stays under it: from its right edge in the right half and its left edge in
    /// the left half, from its bottom edge in the lower half and its top edge in the upper
    /// half. A strip snapped to the middle of a side grows from its vertical centre.
    public static func anchor(compact: CGRect, visible: CGRect, spot: WidgetSpot?) -> GrowthAnchor {
        let horizontal: GrowthAnchor.Horizontal = compact.midX >= visible.midX ? .right : .left
        if case .snapped(let point)? = spot, point == .rightMiddle || point == .leftMiddle {
            return GrowthAnchor(horizontal, .center)
        }
        return GrowthAnchor(horizontal, compact.midY < visible.midY ? .bottom : .top)
    }

    /// The full widget's frame: `size` grown out of the compact frame from its anchored
    /// edges, then kept inside the visible frame across, and between the bottom of the
    /// screen and the menu bar. It may cover a bottom Dock: while expanded it floats above it.
    public static func expandedFrame(compact: CGRect, size: CGSize, anchor: GrowthAnchor,
                                     screen: CGRect, visible: CGRect) -> CGRect {
        let x = anchor.horizontal == .right ? compact.maxX - size.width : compact.minX
        let y: Double
        switch anchor.vertical {
        case .bottom: y = compact.minY
        case .top: y = compact.maxY - size.height
        case .center: y = compact.midY - size.height / 2
        }
        return CGRect(x: min(max(x, visible.minX), visible.maxX - size.width),
                      y: min(max(y, screen.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    /// Above the widget in the lower half, below it in the upper half; beside a vertical
    /// strip, on its inner side.
    public static func crabEdge(anchor: GrowthAnchor, vertical: Bool) -> CrabEdge {
        if vertical { return anchor.horizontal == .right ? .left : .right }
        return anchor.vertical == .top ? .bottom : .top
    }

    /// The window's frame: the glass plus a clear band `depth` deep on the crab's side.
    public static func withCrabBand(_ glass: CGRect, edge: CrabEdge, depth: Double) -> CGRect {
        switch edge {
        case .top: CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: glass.height + depth)
        case .bottom: CGRect(x: glass.minX, y: glass.minY - depth, width: glass.width, height: glass.height + depth)
        case .left: CGRect(x: glass.minX - depth, y: glass.minY, width: glass.width + depth, height: glass.height)
        case .right: CGRect(x: glass.minX, y: glass.minY, width: glass.width + depth, height: glass.height)
        }
    }

    /// The compact frame that `full` grew out of from its anchored edges: where the widget is
    /// saved when the owner moves it while it's full size.
    public static func compactFrame(full: CGRect, size: CGSize, anchor: GrowthAnchor) -> CGRect {
        let x = anchor.horizontal == .right ? full.maxX - size.width : full.minX
        let y: Double
        switch anchor.vertical {
        case .bottom: y = full.minY
        case .top: y = full.maxY - size.height
        case .center: y = full.midY - size.height / 2
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
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
        // Clear of the widget and of the Dock's band (the Dock draws over other windows).
        let bottom = max(widget.maxY + 8, visible.minY + 8)
        let top = min(widget.minY - 8, visible.maxY - 8)
        let above = visible.maxY - 8 - bottom
        let below = top - (visible.minY + 8)
        let aligned = onLeft ? widget.minX : widget.maxX - panel.width
        let x = min(max(aligned, visible.minX + 8), visible.maxX - panel.width - 8)
        if above >= panel.height || above >= below {
            return CGRect(x: x, y: bottom, width: panel.width, height: min(panel.height, above))
        }
        let height = min(panel.height, below)
        return CGRect(x: x, y: top - height, width: panel.width, height: height)
    }
}
