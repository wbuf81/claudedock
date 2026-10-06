import SwiftUI
import ClaudeDockCore

/// The panel that opens above the widget: switch advice, then each org's week in detail.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI usage · week of \(model.formatting.weekStartLabel(WeekAxis(containing: model.now).start))")
                Spacer()
                Text(updatedText)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            if !model.statusLine.isEmpty { statusLine }

            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                Divider().padding(.top, 10)
                OrgSection(model: model, org: org, showLegend: index == 0).padding(.top, 10)
            }

            if !model.signedIn {
                Button("Sign in to claude.ai", action: actions.signInOut).padding(.top, 10)
            }
        }
        .padding(14)
        .frame(width: 372)
        .hud(radius: 14)
    }

    private var updatedText: String {
        guard let last = model.lastUpdated else { return model.signedIn ? "loading…" : "signed out" }
        let time = model.formatting.dayTime(last, now: model.now)
        return model.isStale ? "as of \(time)" : "\(time) · live"
    }

    private var statusLine: some View {
        let switching = model.advice != nil
        return HStack(alignment: .top, spacing: 7) {
            Text(switching ? "⇄" : "✓").foregroundStyle(switching ? Palette.warn : Palette.accent)
            Text(model.statusLine).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(switching ? Palette.warn.opacity(0.16) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct OrgSection: View {
    @ObservedObject var model: AppModel
    let org: Org
    let showLegend: Bool

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(org.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                StoplightDot(light: light)
                Text(model.role(of: org) == .primary ? "Desktop app + Claude Code" : "Extra Claude Code")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                Spacer(minLength: 4)
                if model.claudeCodeOrg == org.id {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        Text("Claude Code is here")
                    }
                    .font(.system(size: 10))
                    .fixedSize()
                }
            }
            if let reading {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Formatting.percent(reading.week)) used").font(.system(size: 20, weight: .bold))
                    Text(Copy.weekLine(reading, forecast: forecast, now: model.now, formatting: model.formatting))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                WeekChart(
                    chart: WeekChartModel.make(axis: WeekAxis(containing: model.now), now: model.now, reading: reading,
                                               forecast: forecast, history: model.history),
                    red: light == .red,
                    resetLabel: reading.weekResetsAt.map { model.formatting.dayTime($0, now: model.now) })
                if showLegend { ChartLegend() }
                TodayBox(today: Copy.today(reading, forecast: forecast, now: model.now,
                                           formatting: model.formatting, model.settings.thresholds))
                ForEach(reading.scoped.keys.sorted(), id: \.self) { name in
                    let used = reading.scoped[name] ?? 0
                    BarRow(label: name, used: used, tick: forecast?.elapsedFraction,
                           detail: "\(Formatting.percent(used)) used · this week")
                }
                BarRow(label: "5 hours", used: reading.session, tick: reading.sessionElapsedFraction(now: model.now),
                       detail: reading.sessionResetsAt.map {
                           "\(Formatting.percent(reading.session)) used · till \(model.formatting.dayTime($0, now: model.now))"
                       } ?? "not started")
            } else {
                Text("No reading yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TodayBox: View {
    var today: Copy.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("TODAY  ").font(.system(size: 9.5, weight: .heavy)) + Text(today.main)).font(.system(size: 11.5))
            if let warning = today.warning {
                (Text("▲ ").foregroundColor(Palette.warn) + Text(warning)).font(.system(size: 11))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BarRow: View {
    var label: String
    var used: Double
    var tick: Double?
    var detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            UsageBar(used: used, tick: tick, color: Palette.accent)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 128, alignment: .trailing)
        }
        .padding(.top, 2)
    }
}
