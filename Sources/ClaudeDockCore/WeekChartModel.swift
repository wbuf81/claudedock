import Foundation

/// A point on a week chart: x is the share of the Mon–Sun week (0...1), y is % used / 100.
public struct ChartPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Everything a week chart draws, in unit coordinates, so the view only scales and strokes.
public struct WeekChartModel: Equatable, Sendable {
    public var today: ClosedRange<Double>
    public var nowX: Double
    public var nowY: Double
    /// Window start (0%), this window's readings, and now.
    public var past: [ChartPoint]
    /// From now to 100% exactly at reset.
    public var useItAll: [ChartPoint]
    /// From now at the current pace (flat at 100% once it runs out).
    public var yourPace: [ChartPoint]
    /// Polygon between the two at reset: what would go unused. Empty when nothing would.
    public var unused: [ChartPoint]
    /// nil when the reset falls outside this week.
    public var resetX: Double?
    /// The next window at use-it-all pace, from the reset to Sunday night.
    public var nextWindow: [ChartPoint]
    public var days: [DayMark]
    /// The "↺ reset" label would overlap the TODAY label, so the two share one label.
    public var resetLabelMeetsToday = false
    /// Near the right edge the "now" label would run off the chart, so put it left of the dot.
    public var nowLabelOnLeft = false
    /// High in the chart the "now" label goes below the dot; low in the chart, above it, so it
    /// never runs into the axis.
    public var nowLabelBelow = false

    public static func make(axis: WeekAxis, now: Date, reading: Reading, forecast: WeekForecast?,
                            history: [Reading]) -> WeekChartModel {
        var past: [(Date, Double)] = []
        if let reset = reading.weekResetsAt {
            let start = reset.addingTimeInterval(-Pace.window)
            past.append((start, 0))
            past += history
                .filter { $0.org == reading.org && $0.weekResetsAt == reset && $0.time > start && $0.time < now }
                .sorted { $0.time < $1.time }
                .map { ($0.time, $0.week) }
        }
        past.append((now, reading.week))

        var model = WeekChartModel(today: axis.today(now), nowX: axis.x(now), nowY: reading.week / 100,
                                   past: clip(past, axis), useItAll: [], yourPace: [], unused: [],
                                   resetX: nil, nextWindow: [], days: axis.days)
        model.nowLabelOnLeft = model.nowX > 0.8
        model.nowLabelBelow = model.nowY >= 0.45
        guard let reset = reading.weekResetsAt, let forecast else { return model }

        let allLine = [(now, reading.week), (reset, 100.0)]
        var paceLine = [(now, reading.week)]
        if let out = forecast.runsOutAt {
            paceLine += [(out, 100), (reset, 100)]
        } else {
            paceLine.append((reset, forecast.forecastAtReset))
        }
        model.useItAll = clip(allLine, axis)
        model.yourPace = clip(paceLine, axis)

        if forecast.unused > 0.05 {
            let edge = min(reset, axis.end)
            model.unused = [(now, reading.week), (edge, value(paceLine, at: edge)), (edge, value(allLine, at: edge))]
                .map { point($0, axis) }
        }
        if axis.contains(reset) {
            model.resetX = axis.x(reset)
            let todayCenter = (model.today.lowerBound + model.today.upperBound) / 2
            model.resetLabelMeetsToday = abs(axis.x(reset) - todayCenter) < 0.15
            let nextAtEnd = axis.end.timeIntervalSince(reset) / Pace.window * 100
            model.nextWindow = [point((reset, 0), axis), point((axis.end, nextAtEnd), axis)]
        }
        return model
    }

    /// Keeps the part of a line inside the week, interpolating where it crosses the edges.
    static func clip(_ line: [(Date, Double)], _ axis: WeekAxis) -> [ChartPoint] {
        var kept: [(Date, Double)] = []
        for (i, p) in line.enumerated() {
            if p.0 < axis.start {
                if i + 1 < line.count, line[i + 1].0 > axis.start {
                    kept.append((axis.start, interpolate(p, line[i + 1], at: axis.start)))
                }
                continue
            }
            if p.0 > axis.end {
                if i > 0, line[i - 1].0 < axis.end {
                    kept.append((axis.end, interpolate(line[i - 1], p, at: axis.end)))
                }
                break
            }
            kept.append(p)
        }
        return kept.map { point($0, axis) }
    }

    static func value(_ line: [(Date, Double)], at date: Date) -> Double {
        for i in 1..<line.count where date <= line[i].0 {
            return interpolate(line[i - 1], line[i], at: date)
        }
        return line.last!.1
    }

    static func interpolate(_ a: (Date, Double), _ b: (Date, Double), at date: Date) -> Double {
        let span = b.0.timeIntervalSince(a.0)
        guard span > 0 else { return b.1 }
        return a.1 + (b.1 - a.1) * date.timeIntervalSince(a.0) / span
    }

    static func point(_ p: (Date, Double), _ axis: WeekAxis) -> ChartPoint {
        ChartPoint(x: axis.x(p.0), y: p.1 / 100)
    }
}
