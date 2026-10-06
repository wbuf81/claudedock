import SwiftUI
import ClaudeDockCore

/// The always-on corner widget: one block per org, plus a switch tab when there's advice.
/// As tall as the Dock bar, with contents scaled to the Dock's icon size.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        let k = model.widgetScale
        HStack(spacing: 0) {
            if let advice = model.advice {
                VStack(spacing: 1 * k) {
                    Text("⇄").font(.system(size: 14 * k)).foregroundStyle(Palette.warn)
                    Text("\(advice.target.name)\nfirst")
                        .font(.system(size: 9.5 * k, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 9 * k)
                .frame(maxHeight: .infinity)
                .background(Palette.warn.opacity(0.16))
                Divider()
            }
            if model.orgs.isEmpty {
                Text(model.signedIn ? "Loading usage…" : "Sign in to claude.ai")
                    .font(.system(size: 11 * k, weight: .semibold))
                    .padding(.horizontal, 16 * k)
            }
            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                if index > 0 { Divider() }
                OrgBlock(model: model, org: org, k: k)
            }
        }
        .frame(height: model.widgetHeight)
        .hud(radius: model.widgetHeight * 0.27, glass: true)
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() })
        .onTapGesture(perform: actions.tap)
        .contextMenu {
            Button("Refresh now", action: actions.refresh)
            Button("Hide for 1 hour", action: actions.hide)
            Button("Snap back to corner", action: actions.snapBack)
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
    let k: CGFloat

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        let red = light == .red
        HStack(spacing: 12 * k) {
            WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0,
                     color: red ? Palette.crit : Palette.accent, size: 48 * k)
            VStack(alignment: .leading, spacing: 5 * k) {
                HStack(spacing: 6 * k) {
                    Text(org.name).font(.system(size: 13 * k, weight: .semibold)).lineLimit(1)
                    StoplightDot(light: light, size: 9 * k)
                }
                UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                         color: Palette.accent, height: 6 * k)
                Text(reading.map { Copy.widgetSubline($0, now: model.now, formatting: model.formatting) }
                     ?? "no reading yet")
                .font(.system(size: 11 * k, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineLimit(1)
            }
            .frame(width: 150 * k, alignment: .leading)
        }
        .padding(.leading, 14 * k)
        .padding(.trailing, 16 * k)
        .frame(maxHeight: .infinity)
    }
}
