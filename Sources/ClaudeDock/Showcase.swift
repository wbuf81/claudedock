import AppKit
import SwiftUI
import ClaudeDockCore

/// `ClaudeDock --showcase DIR` draws the README's images from the Pokémon demo data: a desktop
/// scene, every widget state, the panel in dark and light, and a social-preview card. Nothing
/// from the real screen or account can end up in them.
@MainActor
enum Showcase {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 11, minute: 32))!
        let scenarios = DemoData.scenarios(now: now)
        let settings = Settings(defaults: UserDefaults(suiteName: "ClaudeDockShowcase")!)
        let history = dir.appendingPathComponent("showcase-history.jsonl")
        func model(_ scenario: DemoScenario) -> AppModel {
            let model = AppModel(settings: settings, store: HistoryStore(url: history))
            model.apply(scenario)
            model.widgetHeight = 82
            return model
        }
        let main = model(scenarios[0])

        write(DesktopScene(model: main, dark: true), size: CGSize(width: 1180, height: 820), scheme: .dark, to: dir, "hero-dark.png")
        write(DesktopScene(model: main, dark: false), size: CGSize(width: 1180, height: 820), scheme: .light, to: dir, "hero-light.png")
        write(StatesSheet(rows: zip(captions, scenarios).map { ($0, model($1)) }),
              size: CGSize(width: 1100, height: 760), scheme: .dark, to: dir, "states.png")
        for scheme in [ColorScheme.dark, .light] {
            let name = scheme == .dark ? "panel-dark.png" : "panel-light.png"
            write(PanelOnly(model: main, dark: scheme == .dark), size: CGSize(width: 520, height: 900), scheme: scheme, to: dir, name)
        }
        write(SocialCard(model: main), size: CGSize(width: 1280, height: 640), scheme: .dark, to: dir, "social-card.png")
        try? FileManager.default.removeItem(at: history)
        print("Showcase written to \(dir.path)")
    }

    /// One line per demo scenario, in `DemoData.scenarios` order.
    static let captions = [
        "Pikachu is green and pulsing: tokens would go unused. Charizard is nearly out.",
        "Pikachu's 5-hour window is busy, so move Claude Code to Charizard and leave room for the desktop app.",
        "Charizard's week resets first, so use it before it expires.",
        "Both are low: Charizard is back first.",
        "Pikachu is on pace (yellow) but down to its last 12%, so Charizard, whose week hasn't started (steady green), goes first.",
    ]

    private static func write<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, to dir: URL, _ name: String) {
        let framed = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.renderStyle, .showcase)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: dir.appendingPathComponent(name))
    }
}

private struct Wallpaper: View {
    var dark: Bool

    var body: some View {
        LinearGradient(
            colors: dark
                ? [Color(red: 0.14, green: 0.20, blue: 0.30), Color(red: 0.29, green: 0.27, blue: 0.40), Color(red: 0.66, green: 0.47, blue: 0.42)]
                : [Color(red: 0.62, green: 0.77, blue: 0.91), Color(red: 0.79, green: 0.71, blue: 0.89), Color(red: 0.95, green: 0.79, blue: 0.66)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A Dock-shaped bar of plain coloured tiles: no real app icons.
private struct FakeDock: View {
    private let tiles: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .yellow, .mint]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 82)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }
}

/// The bottom-right of a desktop: Dock, widget, and the panel opened above it.
private struct DesktopScene: View {
    @ObservedObject var model: AppModel
    var dark: Bool

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            FakeDock()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, -160)
                .padding(.bottom, 6)
            VStack(alignment: .trailing, spacing: 8) {
                PanelView(model: model, actions: .none)
                WidgetView(model: model, actions: .none)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 6)
        }
    }
}

private struct StatesSheet: View {
    var rows: [(String, AppModel)]

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 28) {
                        WidgetView(model: row.1, actions: .none).fixedSize()
                        Text(row.0)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(40)
        }
    }
}

private struct PanelOnly: View {
    @ObservedObject var model: AppModel
    var dark: Bool

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            PanelView(model: model, actions: .none).fixedSize()
        }
    }
}

private struct SocialCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(spacing: 30) {
                VStack(spacing: 10) {
                    Text("Claude Dock").font(.system(size: 84, weight: .bold)).foregroundStyle(.white)
                    Text("Your Claude plan usage, always in the corner of your screen")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                WidgetView(model: model, actions: .none).fixedSize().scaleEffect(1.5)
                    .padding(.top, 20)
            }
        }
    }
}
