import SwiftUI
import ClaudeDockCore

/// The always-on widget: one block per org, plus a switch tab when there's advice. A
/// horizontal bar as tall as the Dock, or a narrow vertical strip on the left and right
/// edges. Contents scale with the Dock's icon size and the owner's size setting.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        Group {
            if model.vertical { strip } else { bar }
        }
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() })
        .simultaneousGesture(MagnificationGesture()
            .onChanged { actions.pinch($0, false) }
            .onEnded { actions.pinch($0, true) })
        .onTapGesture(perform: actions.tap)
        .contextMenu { menu }
    }

    private var k: CGFloat { model.widgetScale }

    private var bar: some View {
        HStack(spacing: 0) {
            if let advice = model.advice {
                switchTab(advice)
                    .padding(.horizontal, 9 * k)
                    .frame(maxHeight: .infinity)
                    .background(Palette.warn.opacity(0.16))
                Divider()
            }
            if model.orgs.isEmpty { placeholder.padding(.horizontal, 16 * k) }
            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                if index > 0 { Divider().padding(.vertical, 16 * k) }
                OrgBlock(model: model, org: org, k: k, vertical: false)
            }
        }
        .frame(height: model.widgetHeight)
        .hud(radius: model.widgetHeight * 0.27, glass: true)
    }

    private var strip: some View {
        VStack(spacing: 0) {
            if let advice = model.advice {
                switchTab(advice)
                    .padding(.vertical, 8 * k)
                    .frame(maxWidth: .infinity)
                    .background(Palette.warn.opacity(0.16))
            }
            if model.orgs.isEmpty { placeholder.padding(.vertical, 16 * k) }
            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                if index > 0 { Divider().padding(.horizontal, 24 * k) }
                OrgBlock(model: model, org: org, k: k, vertical: true)
            }
        }
        .frame(width: 104 * k)
        .hud(radius: 22 * k, glass: true)
    }

    private func switchTab(_ advice: Advice) -> some View {
        VStack(spacing: 1 * k) {
            Text("⇄").font(.system(size: 14 * k)).foregroundStyle(Palette.warn)
            Text("\(advice.target.name)\nfirst")
                .font(.system(size: 9.5 * k, weight: .semibold))
                .multilineTextAlignment(.center)
        }
    }

    private var placeholder: some View {
        Text(placeholderText)
            .font(.system(size: 11 * k, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: 160 * k)
    }

    private var placeholderText: String {
        if !model.signedIn { return "Sign in to claude.ai" }
        if let problem = model.refreshProblem { return "Can't read usage:\n\(problem.short)" }
        return "Loading usage…"
    }

    @ViewBuilder
    private var menu: some View {
        let settings = model.settings
        Button("Refresh now", action: actions.refresh)
        Menu("Position") {
            ForEach(SnapPoint.allCases, id: \.self) { point in
                check(Self.title(point), settings.widgetSpot == .snapped(point)
                      || (point == .bottomRight && settings.widgetSpot == nil)) { actions.place(point) }
            }
        }
        Menu("Layout") {
            check("Automatic (vertical on the sides)", settings.layoutChoice == .automatic) { actions.layout(.automatic) }
            check("Horizontal", settings.layoutChoice == .horizontal) { actions.layout(.horizontal) }
            check("Vertical", settings.layoutChoice == .vertical) { actions.layout(.vertical) }
        }
        Menu("Size") {
            ForEach(Self.sizes, id: \.1) { name, scale in
                check(name, abs(settings.sizeScale - scale) < 0.01) { actions.size(scale) }
            }
        }
        Button("Hide for 1 hour", action: actions.hide)
        Button("Settings…", action: actions.settings)
        Button(model.signedIn ? "Sign out" : "Sign in…", action: actions.signInOut)
        Divider()
        Button("Quit Claude Dock", action: actions.quit)
    }

    private func check(_ title: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    static let sizes: [(String, Double)] = [("Small", 0.8), ("Match Dock", 1), ("Large", 1.25), ("Extra large", 1.5)]

    static func title(_ point: SnapPoint) -> String {
        switch point {
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        case .rightMiddle: "Right side"
        case .leftMiddle: "Left side"
        }
    }
}

/// One org: week ring, name and stoplight dot, 5-hour bar, caption. Side by side in the
/// horizontal bar; stacked and centred in the vertical strip.
private struct OrgBlock: View {
    @ObservedObject var model: AppModel
    let org: Org
    let k: CGFloat
    let vertical: Bool

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        let ring = WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0,
                            color: light == .red ? Palette.crit : Palette.accent, size: 48 * k)
        let name = HStack(spacing: 6 * k) {
            Text(org.name)
                .font(.system(size: max(13 * k, 11), weight: .semibold))
                .lineLimit(vertical ? 2 : 1)
                .multilineTextAlignment(vertical ? .center : .leading)
                .minimumScaleFactor(0.75)
            StoplightDot(light: light, size: 9 * k)
        }
        let bar = UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                           color: Palette.accent, height: 6 * k)
        let caption = reading.map { Copy.widgetSubline($0, now: model.now, formatting: model.formatting) }
            ?? model.orgProblems[org.id]?.short ?? "no reading yet"

        if vertical {
            VStack(spacing: 6 * k) {
                ring
                name
                bar.frame(width: 72 * k)
                Text(caption.replacingOccurrences(of: " · ", with: "\n"))
                    .font(.system(size: max(11 * k, 10), weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1 * k)
            }
            .padding(.horizontal, 8 * k)
            .padding(.vertical, 14 * k)
        } else {
            HStack(spacing: 14 * k) {
                ring
                VStack(alignment: .leading, spacing: 6 * k) {
                    name
                    bar
                    Text(caption)
                        .font(.system(size: max(11 * k, 10), weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(width: 150 * k, alignment: .leading)
            }
            .padding(.horizontal, 18 * k)
            .frame(maxHeight: .infinity)
        }
    }
}
