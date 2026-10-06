import CoreGraphics
import Foundation
import Testing
@testable import ClaudeDockCore

/// Sweeps the placement maths across the Macs, Docks, sizes and org counts other people
/// will have, checking what must never happen: a widget off screen or under the menu bar or
/// a side Dock or a bottom Dock, a panel off screen or on top of the widget.
@Suite struct MatrixTests {
    struct Display {
        var name: String
        var size: CGSize
        var menuBar: Double
    }

    enum DockSide: CaseIterable { case bottom, left, right, hidden }

    static let displays = [
        Display(name: "13-inch MacBook Air", size: CGSize(width: 1470, height: 956), menuBar: 25),
        Display(name: "14-inch MacBook Pro", size: CGSize(width: 1512, height: 982), menuBar: 33),
        Display(name: "16-inch MacBook Pro", size: CGSize(width: 1728, height: 1117), menuBar: 33),
        Display(name: "1080p display", size: CGSize(width: 1920, height: 1080), menuBar: 25),
        Display(name: "1440p display", size: CGSize(width: 2560, height: 1440), menuBar: 25),
        Display(name: "4K display", size: CGSize(width: 3840, height: 2160), menuBar: 25),
    ]
    static let tileSizes: [Double] = [32, 48, 64, 80]
    static let sizeScales: [Double] = [0.6, 0.8, 1, 1.25, 1.5, 2]
    /// Items in the Dock (apps, folders, minimized windows, the Trash), from sparse to crowded.
    static let dockItems = [8, 16, 24, 40]

    /// The visible frame macOS reports: minus the menu bar, and minus the Dock's reserved
    /// band (icon size + 42 pt, as measured) on whichever side it sits.
    static func visible(_ display: Display, _ side: DockSide, tile: Double) -> CGRect {
        let w = display.size.width, h = display.size.height, menu = display.menuBar, band = tile + 42
        switch side {
        case .bottom: return CGRect(x: 0, y: band, width: w, height: h - band - menu)
        case .left: return CGRect(x: band, y: 0, width: w - band, height: h - menu)
        case .right: return CGRect(x: 0, y: 0, width: w - band, height: h - menu)
        case .hidden: return CGRect(x: 0, y: 0, width: w, height: h - menu)
        }
    }

    /// The widget's size at a given owner scale, mirroring WidgetView: about 248.5 pt per
    /// org plus a 66 pt switch tab across, as tall as the Dock bar; or a 104 pt strip with
    /// about 146 pt per org.
    static func widgetSize(orgs: Int, vertical: Bool, screen: CGRect, visible: CGRect, tile: Double, scale: Double) -> CGSize {
        let k = DockFit.contentScale(screen: screen, visible: visible, tileSize: tile) * scale
        if vertical { return CGSize(width: 104 * k, height: Double(orgs) * 146 * k + 50 * k) }
        let height = DockFit.height(screen: screen, visible: visible, tileSize: tile) * scale
        return CGSize(width: (Double(orgs) * 248.5 + 66) * k, height: height)
    }

    /// The panel's height: header and status line, plus about 330 pt per org.
    static func panelSize(orgs: Int) -> CGSize { CGSize(width: 372, height: 60 + Double(orgs) * 330) }

    @Test func everyCombinationStaysOnScreenAndClear() {
        var problems: [String] = []
        for display in Self.displays {
            let screen = CGRect(origin: .zero, size: display.size)
            for side in DockSide.allCases {
                for tile in Self.tileSizes {
                    let visible = Self.visible(display, side, tile: tile)
                    for items in Self.dockItems {
                    let dockWidth = DockFit.estimatedWidth(items: items, dividers: 2, screen: screen, visible: visible)
                    let dock = dockWidth.map { CGRect(x: screen.midX - $0 / 2, y: screen.minY, width: $0, height: visible.minY - screen.minY) }
                    for orgs in 1...3 {
                        for spot in [nil] + SnapPoint.allCases.map({ WidgetSpot.snapped($0) }) {
                            let vertical = WidgetLayout.isVertical(spot: spot, choice: .automatic)
                            for wanted in Self.sizeScales {
                                let natural = Self.widgetSize(orgs: orgs, vertical: vertical, screen: screen,
                                                              visible: visible, tile: tile, scale: 1)
                                let scale = WidgetLayout.fittedScale(wanted, natural: natural, visible: visible)
                                let size = Self.widgetSize(orgs: orgs, vertical: vertical, screen: screen,
                                                           visible: visible, tile: tile, scale: scale)
                                let origin = WidgetPlacement.origin(size: size, screen: screen, visible: visible, spot: spot,
                                                                    dockWidth: dockWidth)
                                let widget = CGRect(origin: origin, size: size)
                                let label = "\(display.name), Dock \(side) \(Int(tile)) pt with \(items) items, \(orgs) org(s), \(spot.map { "\($0)" } ?? "default"), size \(wanted)"

                                if widget.minX < visible.minX - 0.5 || widget.maxX > visible.maxX + 0.5 {
                                    problems.append("\(label): widget under a side Dock or off screen \(widget)")
                                }
                                if widget.maxY > visible.maxY + 0.5 { problems.append("\(label): widget under the menu bar \(widget)") }
                                if widget.minY < screen.minY - 0.5 { problems.append("\(label): widget below the screen \(widget)") }
                                if let dock, widget.insetBy(dx: 1, dy: 1).intersects(dock) {
                                    problems.append("\(label): widget under the Dock \(widget) vs \(dock)")
                                }

                                let panel = WidgetPlacement.panelFrame(panel: Self.panelSize(orgs: orgs), widget: widget, visible: visible)
                                if panel.minX < visible.minX + 7.5 || panel.maxX > visible.maxX - 7.5
                                    || panel.minY < visible.minY + 7.5 || panel.maxY > visible.maxY - 7.5 {
                                    problems.append("\(label): panel off screen \(panel)")
                                }
                                if panel.insetBy(dx: 1, dy: 1).intersects(widget) {
                                    problems.append("\(label): panel covers the widget \(panel) vs \(widget)")
                                }
                                if panel.height < 240 { problems.append("\(label): panel squeezed to \(Int(panel.height)) pt") }
                            }
                        }
                    }
                    }
                }
            }
        }
        // One example of each kind of problem, with how often it happens.
        var kinds: [String: (count: Int, example: String)] = [:]
        for problem in problems {
            let kind = problem.components(separatedBy: ": ").dropFirst().first?.components(separatedBy: " (").first ?? problem
            kinds[kind, default: (0, problem)].count += 1
        }
        let summary = kinds.sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count)× \($0.key)\n    e.g. \($0.value.example)" }
            .joined(separator: "\n")
        #expect(problems.count == 0, "\(problems.count) problems:\n\(summary)")
    }

    @Test func fittedScaleOnlyShrinksWhatWouldNotFit() {
        let visible = CGRect(x: 0, y: 0, width: 1470, height: 931)
        #expect(WidgetLayout.fittedScale(1.5, natural: CGSize(width: 500, height: 82), visible: visible) == 1.5)
        #expect(WidgetLayout.fittedScale(2, natural: CGSize(width: 811, height: 82), visible: visible) == (1470.0 - 24) / 811)
        #expect(WidgetLayout.fittedScale(2, natural: CGSize(width: 104, height: 500), visible: visible) == (931.0 - 24) / 500)
    }
}
