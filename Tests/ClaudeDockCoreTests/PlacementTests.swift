import CoreGraphics
import Foundation
import Testing
@testable import ClaudeDockCore

/// A 2560×1440 display with the Dock at the bottom, reserving 90 pt (measured on a real Mac:
/// 48 pt icons, the Liquid Glass bar 82 pt tall floating 6 pt above the edge).
let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let visibleWithDock = CGRect(x: 0, y: 90, width: 2560, height: 1350)

@Suite struct DockFitTests {
    @Test func matchesTheDockBarFromItsReservedSpace() {
        #expect(DockFit.height(screen: screen, visible: visibleWithDock, tileSize: nil) == 82)
        let biggerDock = CGRect(x: 0, y: 106, width: 2560, height: 1334)
        #expect(DockFit.height(screen: screen, visible: biggerDock, tileSize: 64) == 98)
    }

    @Test func autoHiddenOrSideDockUsesTheIconSize() {
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: nil) == 82)
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: 64) == 98)
        let leftDock = CGRect(x: 90, y: 0, width: 2470, height: 1440)
        #expect(DockFit.height(screen: screen, visible: leftDock, tileSize: 32) == 66)
    }

    // The widget's contents track the Dock's icons (48 pt by default), not the bar, so a
    // taller widget doesn't also grow wider and run under the Dock.
    @Test func contentsScaleWithTheIconSize() {
        #expect(DockFit.contentScale(tileSize: nil) == 1)
        #expect(DockFit.contentScale(tileSize: 64) == 64.0 / 48)
        #expect(DockFit.contentScale(tileSize: 16) == 0.75)
        #expect(DockFit.contentScale(tileSize: 128) == 1.5)
    }

    @Test func staysReadableAndSane() {
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: 16) == 50)
        #expect(DockFit.height(screen: screen, visible: CGRect(x: 0, y: 400, width: 2560, height: 1040), tileSize: nil) == 140)
    }
}

@Suite struct WidgetPlacementTests {
    let size = CGSize(width: 570, height: 82)

    @Test func defaultsToTheCornerBesideTheDock() {
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, saved: nil)
                == CGPoint(x: 1978, y: 6))
    }

    @Test func sideOrHiddenDockStaysInsideTheVisibleFrame() {
        let rightDock = CGRect(x: 0, y: 0, width: 2470, height: 1440)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: rightDock, saved: nil)
                == CGPoint(x: 1888, y: 12))
    }

    @Test func savedSpotIsKeptFromTheBottomRight() {
        let saved = WidgetOffset(right: 100, bottom: 400)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, saved: saved)
                == CGPoint(x: 1890, y: 400))
        // A bigger widget grows left and up from the same bottom-right anchor.
        let bigger = CGSize(width: 700, height: 100)
        #expect(WidgetPlacement.origin(size: bigger, screen: screen, visible: visibleWithDock, saved: saved)
                == CGPoint(x: 1760, y: 400))
    }

    @Test func savedSpotIsPulledBackOnScreen() {
        let offScreen = WidgetOffset(right: -300, bottom: 5000)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, saved: offScreen)
                == CGPoint(x: 1990, y: 1358))
    }

    @Test func offsetRoundTrips() {
        let origin = CGPoint(x: 1200, y: 300)
        let offset = WidgetPlacement.offset(origin: origin, size: size, screen: screen)
        #expect(offset == WidgetOffset(right: 790, bottom: 300))
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, saved: offset) == origin)
    }
}

@Suite struct PanelPlacementTests {
    let panel = CGSize(width: 372, height: 700)

    @Test func opensAboveAWidgetAtTheBottom() {
        let widget = CGRect(x: 1978, y: 6, width: 570, height: 82)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: visibleWithDock)
                == CGRect(x: 2176, y: 96, width: 372, height: 700))
    }

    @Test func opensBelowAWidgetNearTheTop() {
        let widget = CGRect(x: 1000, y: 1300, width: 570, height: 82)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: visibleWithDock)
                == CGRect(x: 1198, y: 592, width: 372, height: 700))
    }

    @Test func staysInsideTheScreenEdges() {
        let widget = CGRect(x: 10, y: 6, width: 300, height: 82)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: visibleWithDock).minX == 8)
    }

    @Test func shrinksWhenThereIsNotEnoughRoom() {
        let short = CGRect(x: 0, y: 90, width: 2560, height: 600)
        let widget = CGRect(x: 1978, y: 6, width: 570, height: 82)
        let frame = WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: short)
        #expect(frame.minY == 96 && frame.maxY == 682)
    }
}

