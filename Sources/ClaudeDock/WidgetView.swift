import SwiftUI
import ClaudeDockCore

/// The always-on corner widget, Dock height: one block per org, plus a switch tab when
/// there's advice.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        HStack(spacing: 0) {
            if let advice = model.advice {
                VStack(spacing: 1) {
                    Text("⇄").font(.system(size: 14)).foregroundStyle(Palette.warn)
                    Text("\(advice.target.name)\nfirst")
                        .font(.system(size: 9.5, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity)
                .background(Palette.warn.opacity(0.16))
                Divider()
            }
            if model.orgs.isEmpty {
                Text(model.signedIn ? "Loading usage…" : "Sign in to claude.ai")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 16)
            }
            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                if index > 0 { Divider() }
                OrgBlock(model: model, org: org)
            }
        }
        .frame(height: 60)
        .hud(radius: 16)
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.tap)
        .contextMenu {
            Button("Refresh now", action: actions.refresh)
            Button("Hide for 1 hour", action: actions.hide)
            Button("Settings…", action: actions.settings)
            Button(model.signedIn ? "Sign out" : "Sign in…", action: actions.signInOut)
            Divider()
            Button("Quit Claude Dock", action: actions.quit)
        }
    }
}

private struct OrgBlock: View {
    @ObservedObject var model: AppModel
    let org: Org

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        let red = light == .red
        HStack(spacing: 8) {
            WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0,
                     color: red ? Palette.crit : Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(org.name).font(.system(size: 11, weight: .semibold))
                    StoplightDot(light: light)
                }
                UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                         color: Palette.accent, off: reading?.sessionResetsAt == nil)
                Text(reading.map {
                    Copy.widgetSubline($0, light: light, forecast: forecast, now: model.now,
                                       formatting: model.formatting, model.settings.thresholds)
                } ?? "no reading yet")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(width: 134, alignment: .leading)
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(maxHeight: .infinity)
        .background(red ? Palette.crit.opacity(0.18) : Color.clear)
    }
}
