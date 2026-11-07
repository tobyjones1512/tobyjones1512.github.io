import Foundation

// A parametric equaliser for the backing tracks: up to eight bands, each a cut, shelf, bell or notch with its own
// frequency, gain and width, plus an output level. Played through AVAudioUnitEQ; the curve drawn in the editor is
// worked out here from the same settings (RBJ biquad formulas), so what you see is close to what you hear.

nonisolated struct EQBand: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case lowCut = "Low Cut", lowShelf = "Low Shelf", bell = "Bell", notch = "Notch", highShelf = "High Shelf", highCut = "High Cut"
        var id: String { rawValue }
        /// Cuts and notches only take a frequency (and a notch its width); they have no gain to set.
        var hasGain: Bool { self == .lowShelf || self == .bell || self == .highShelf }
        var hasWidth: Bool { self == .bell || self == .notch }
    }

    var id = UUID()
    var kind: Kind
    var frequency: Double   // Hz, 20 to 20,000
    var gain = 0.0          // dB, -24 to +24
    var q = 1.0             // width: higher is narrower, 0.1 to 10
    var on = true

    /// The width in octaves, as AVAudioUnitEQ takes it.
    var octaves: Double { 2 / log(2) * asinh(1 / (2 * q)) }

    /// The band's effect in decibels at `f` (a biquad's magnitude response).
    func response(at f: Double, sampleRate: Double = 48_000) -> Double {
        guard on else { return 0 }
        let w0 = 2 * .pi * min(frequency, sampleRate * 0.49) / sampleRate
        let c = cos(w0), s = sin(w0), a = pow(10, gain / 40)
        let alpha = s / (2 * (kind.hasWidth ? q : 0.707))
        let r = 2 * sqrt(a) * alpha
        let (b0, b1, b2, a0, a1, a2): (Double, Double, Double, Double, Double, Double)
        switch kind {
        case .bell: (b0, b1, b2, a0, a1, a2) = (1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
        case .notch: (b0, b1, b2, a0, a1, a2) = (1, -2 * c, 1, 1 + alpha, -2 * c, 1 - alpha)
        case .lowCut: (b0, b1, b2, a0, a1, a2) = ((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
        case .highCut: (b0, b1, b2, a0, a1, a2) = ((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
        case .lowShelf:
            (b0, b1, b2) = (a * ((a + 1) - (a - 1) * c + r), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - r))
            (a0, a1, a2) = ((a + 1) + (a - 1) * c + r, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - r)
        case .highShelf:
            (b0, b1, b2) = (a * ((a + 1) + (a - 1) * c + r), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - r))
            (a0, a1, a2) = ((a + 1) - (a - 1) * c + r, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - r)
        }
        let w = 2 * .pi * f / sampleRate
        func power(_ x0: Double, _ x1: Double, _ x2: Double) -> Double {
            let re = x0 + x1 * cos(w) + x2 * cos(2 * w), im = x1 * sin(w) + x2 * sin(2 * w)
            return re * re + im * im
        }
        return 10 * log10(max(power(b0, b1, b2), 1e-12) / max(power(a0, a1, a2), 1e-12))
    }
}

nonisolated struct TrackEQ: Codable, Hashable {
    static let maxBands = 8
    var on = true
    var bands: [EQBand]
    var outputGain = 0.0   // dB, -12 to +12

    /// The whole curve in decibels at `f`, output level included.
    func response(at f: Double) -> Double { bands.reduce(outputGain) { $0 + $1.response(at: f) } }

    /// Nothing changed from straight through: not worth saving.
    var isFlat: Bool { outputGain == 0 && bands.allSatisfy { !$0.on || ($0.kind.hasGain && $0.gain == 0) } }

    static let flat = TrackEQ(bands: [
        EQBand(kind: .lowCut, frequency: 30, on: false),
        EQBand(kind: .lowShelf, frequency: 100),
        EQBand(kind: .bell, frequency: 300),
        EQBand(kind: .bell, frequency: 1_000),
        EQBand(kind: .bell, frequency: 3_000),
        EQBand(kind: .highShelf, frequency: 8_000),
        EQBand(kind: .highCut, frequency: 18_000, on: false),
    ])

    /// Starting points, each a change from flat.
    static let presets: [(name: String, eq: TrackEQ)] = [
        ("Flat", flat),
        (String(localized: "Bass Boost"), flat.with(1) { $0.gain = 6 }),
        (String(localized: "Less Bass"), flat.with(0) { $0.frequency = 120; $0.on = true }),
        ("Warm", flat.with(1) { $0.frequency = 200; $0.gain = 3 }.with(5) { $0.gain = -3 }),
        ("Bright", flat.with(5) { $0.gain = 5 }),
        (String(localized: "Vocal Presence"), flat.with(4) { $0.gain = 4 }),
        (String(localized: "Quieter Vocals"), flat.with(3) { $0.frequency = 1_500; $0.gain = -8; $0.q = 0.7 }.with(4) { $0.gain = -4 }),
        (String(localized: "Room for Bass Players"), flat.with(1) { $0.frequency = 120; $0.gain = -8 }),
        ("Telephone", flat.with(0) { $0.frequency = 400; $0.on = true }.with(6) { $0.frequency = 3_000; $0.on = true }),
    ]

    func with(_ band: Int, _ change: (inout EQBand) -> Void) -> TrackEQ {
        var copy = self
        change(&copy.bands[band])
        return copy
    }
}
