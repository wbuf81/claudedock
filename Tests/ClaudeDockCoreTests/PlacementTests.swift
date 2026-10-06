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
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: nil)
                == CGPoint(x: 1978, y: 6))
    }

    @Test func sideOrHiddenDockStaysInsideTheVisibleFrame() {
        let rightDock = CGRect(x: 0, y: 0, width: 2470, height: 1440)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: rightDock, spot: nil)
                == CGPoint(x: 1888, y: 12))
    }

    @Test func savedSpotIsKeptFromTheBottomRight() {
        let saved = WidgetOffset(right: 100, bottom: 400)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(saved))
                == CGPoint(x: 1890, y: 400))
        // A bigger widget grows left and up from the same bottom-right anchor.
        let bigger = CGSize(width: 700, height: 100)
        #expect(WidgetPlacement.origin(size: bigger, screen: screen, visible: visibleWithDock, spot: .free(saved))
                == CGPoint(x: 1760, y: 400))
    }

    @Test func savedSpotIsPulledBackOnScreen() {
        let offScreen = WidgetOffset(right: -300, bottom: 5000)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(offScreen))
                == CGPoint(x: 1990, y: 1358))
    }

    @Test func offsetRoundTrips() {
        let origin = CGPoint(x: 1200, y: 300)
        let offset = WidgetPlacement.offset(origin: origin, size: size, screen: screen)
        #expect(offset == WidgetOffset(right: 790, bottom: 300))
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(offset)) == origin)
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

    @Test func linesUpLeftEdgesOnTheLeftHalf() {
        let widget = CGRect(x: 12, y: 6, width: 300, height: 82)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: visibleWithDock).minX == 12)
    }

    @Test func opensBesideAVerticalWidgetOnTheRight() {
        let strip = CGRect(x: 2450, y: 600, width: 104, height: 300)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: strip, visible: visibleWithDock)
                == CGRect(x: 2070, y: 400, width: 372, height: 700))
    }

    @Test func opensBesideAVerticalWidgetOnTheLeft() {
        let strip = CGRect(x: 6, y: 600, width: 104, height: 300)
        #expect(WidgetPlacement.panelFrame(panel: panel, widget: strip, visible: visibleWithDock).minX == 118)
    }

    @Test func shrinksWhenThereIsNotEnoughRoom() {
        let short = CGRect(x: 0, y: 90, width: 2560, height: 600)
        let widget = CGRect(x: 1978, y: 6, width: 570, height: 82)
        let frame = WidgetPlacement.panelFrame(panel: panel, widget: widget, visible: short)
        #expect(frame.minY == 96 && frame.maxY == 682)
    }
}


@Suite struct SnapPointTests {
    let wide = CGSize(width: 481, height: 82)
    let tall = CGSize(width: 104, height: 300)

    func origin(_ point: SnapPoint, _ size: CGSize) -> CGPoint {
        WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .snapped(point))
    }

    @Test func cornersSitBesideTheDockOrInsideTheScreen() {
        #expect(origin(.bottomRight, wide) == CGPoint(x: 2067, y: 6))
        #expect(origin(.bottomLeft, wide) == CGPoint(x: 12, y: 6))
        #expect(origin(.topRight, wide) == CGPoint(x: 2067, y: 1346))
        #expect(origin(.topLeft, wide) == CGPoint(x: 12, y: 1346))
    }

    @Test func edgesCentreTheWidgetVertically() {
        #expect(origin(.rightMiddle, tall) == CGPoint(x: 2450, y: 615))
        #expect(origin(.leftMiddle, tall) == CGPoint(x: 6, y: 615))
    }

    @Test func noSpotMeansBottomRight() {
        #expect(WidgetPlacement.origin(size: wide, screen: screen, visible: visibleWithDock, spot: nil) == CGPoint(x: 2067, y: 6))
    }

    @Test func dropsNearASnapPointSnap() {
        func drop(_ frame: CGRect) -> SnapPoint? { WidgetPlacement.snap(frame: frame, screen: screen, visible: visibleWithDock) }
        #expect(drop(CGRect(x: 40, y: 30, width: 481, height: 82)) == .bottomLeft)
        #expect(drop(CGRect(x: 2040, y: 1320, width: 481, height: 82)) == .topRight)
        #expect(drop(CGRect(x: 2420, y: 700, width: 104, height: 300)) == .rightMiddle)
        #expect(drop(CGRect(x: 30, y: 500, width: 481, height: 82)) == .leftMiddle)
        #expect(drop(CGRect(x: 1000, y: 600, width: 481, height: 82)) == nil)
    }

    @Test func sideEdgesAreVerticalUnlessOverridden() {
        #expect(WidgetLayout.isVertical(spot: .snapped(.rightMiddle), choice: .automatic))
        #expect(WidgetLayout.isVertical(spot: .snapped(.leftMiddle), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: .snapped(.bottomLeft), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: .free(WidgetOffset(right: 0, bottom: 0)), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: nil, choice: .automatic))
        #expect(WidgetLayout.isVertical(spot: .snapped(.bottomRight), choice: .vertical))
        #expect(!WidgetLayout.isVertical(spot: .snapped(.rightMiddle), choice: .horizontal))
    }

    @Test func sizesStayBetween60And200Percent() {
        #expect(WidgetLayout.clampSize(0.3) == 0.6)
        #expect(WidgetLayout.clampSize(1.25) == 1.25)
        #expect(WidgetLayout.clampSize(3) == 2)
    }

    @Test func spotsSurviveSaving() throws {
        for spot in [WidgetSpot.snapped(.leftMiddle), .free(WidgetOffset(right: 12, bottom: 40))] {
            let data = try JSONEncoder().encode(spot)
            #expect(try JSONDecoder().decode(WidgetSpot.self, from: data) == spot)
        }
    }
}
