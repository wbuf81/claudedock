import Testing
@testable import ClaudeDockCore

@Suite struct EffectsTests {
    @Test func amountsScaleTheParticles() {
        #expect(EffectAmount.allCases.map(\.multiplier) == [0.5, 1, 1.8])
    }

    @Test func choicesAreSavedByName() {
        #expect(EffectStyle.allCases.map(\.rawValue) == ["sparks", "flow", "shimmer", "off"])
        #expect(EffectStyle(rawValue: "confetti") == nil)  // Settings falls back to the default
    }
}
