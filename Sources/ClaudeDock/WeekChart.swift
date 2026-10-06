import SwiftUI
import ClaudeDockCore

/// One org's week on the shared Mon–Sun axis: today's column, the "now" line, history,
/// the use-it-all and current-pace lines, the "would go unused" wedge, and the reset.
struct WeekChart: View {
    let chart: WeekChartModel
    let red: Bool
    let resetLabel: String?

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 0, y: 12, width: size.width, height: size.height - 34)
            let lineColor = red ? Palette.crit : Palette.accent
            func pt(_ p: ChartPoint) -> CGPoint { CGPoint(x: plot.minX + p.x * plot.width, y: plot.maxY - p.y * plot.height) }
            func path(_ points: [ChartPoint]) -> Path {
                var path = Path()
                guard let first = points.first else { return path }
                path.move(to: pt(first))
                points.dropFirst().forEach { path.addLine(to: pt($0)) }
                return path
            }
            func vertical(_ x: Double) -> Path {
                Path { $0.move(to: CGPoint(x: plot.minX + x * plot.width, y: plot.minY)); $0.addLine(to: CGPoint(x: plot.minX + x * plot.width, y: plot.maxY)) }
            }

            let todayX = plot.minX + chart.today.lowerBound * plot.width
            let todayWidth = (chart.today.upperBound - chart.today.lowerBound) * plot.width
            ctx.fill(Path(CGRect(x: todayX, y: plot.minY, width: todayWidth, height: plot.height)), with: .color(.primary.opacity(0.08)))
            let todayLabel = chart.resetLabelMeetsToday && resetLabel != nil ? "TODAY · ↺ \(resetLabel!)" : "TODAY"
            ctx.draw(Text(todayLabel).font(.system(size: 8.5, weight: .bold)).foregroundColor(.primary),
                     at: CGPoint(x: todayX + todayWidth / 2, y: 5))

            for day in chart.days.dropFirst() { ctx.stroke(vertical(day.start), with: .color(.primary.opacity(0.08)), lineWidth: 1) }
            ctx.stroke(path([ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 1)]), with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ctx.stroke(path([ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 0)]), with: .color(.primary.opacity(0.25)), lineWidth: 1)

            if chart.unused.count >= 3 {
                var wedge = path(chart.unused)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(Palette.warn.opacity(0.5)))
            }
            ctx.stroke(path(chart.past), with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ctx.stroke(path(chart.useItAll), with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ctx.stroke(path(chart.yourPace), with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4]))

            if let resetX = chart.resetX {
                ctx.stroke(vertical(resetX), with: .color(Palette.accent), lineWidth: 1.5)
                ctx.stroke(path(chart.nextWindow), with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let resetLabel, !chart.resetLabelMeetsToday {
                    ctx.draw(Text("↺ \(resetLabel)").font(.system(size: 8.5)).foregroundColor(.secondary),
                             at: CGPoint(x: plot.minX + resetX * plot.width, y: 5))
                }
            }

            ctx.stroke(vertical(chart.nowX), with: .color(.primary), lineWidth: 1.5)
            let dot = pt(ChartPoint(x: chart.nowX, y: chart.nowY))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(lineColor))
            let labelY = dot.y + 14 < plot.maxY ? dot.y + 12 : dot.y - 10
            ctx.draw(Text("now · \(Formatting.percent(chart.nowY * 100))").font(.system(size: 9.5, weight: .semibold)).foregroundColor(.primary),
                     at: CGPoint(x: chart.nowLabelOnLeft ? dot.x - 6 : dot.x + 6, y: labelY),
                     anchor: chart.nowLabelOnLeft ? .trailing : .leading)

            for day in chart.days {
                let isToday = chart.today.contains(day.center)
                ctx.draw(Text(day.name).font(.system(size: 9, weight: isToday ? .bold : .regular))
                            .foregroundColor(isToday ? .primary : .secondary),
                         at: CGPoint(x: plot.minX + day.center * plot.width, y: size.height - 8))
            }
        }
        .frame(height: 88)
    }
}

struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            key("so far") { Rectangle().fill(Palette.accent).frame(width: 14, height: 2) }
            key("use-it-all pace") { Line().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 14, height: 2) }
            key("your pace") { Line().stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4])).frame(width: 14, height: 2) }
            key("would go unused") { Rectangle().fill(Palette.warn.opacity(0.6)).frame(width: 12, height: 6) }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func key<S: View>(_ text: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 4) { swatch(); Text(text) }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}
